# LS Loan Servicing: COBOL Amortization Batch

A small but complete **loan-servicing batch system** written in classic
mainframe COBOL style (fixed format, Enterprise COBOL idioms, JCL), with a
GnuCOBOL build so it compiles and runs on Linux.

The centrepiece is a **precision-defect investigation**. A "before" version
of the payment subprogram contains realistic legacy bugs. It is checked
against an independent Python `decimal.Decimal` model, the bugs are
isolated one by one, and the fixed version is proven correct to the cent:
on the edge-case deck, on 2,000 random loans, and on a grid of the input
extremes.

> The scenario (system name, change numbers, maintenance-log history and
> programmer initials) is fictional, written to read like a real
> maintenance assignment. All code, data, tests and logs are real and
> reproducible.

---

## At a glance

| | |
|---|---|
| **Programs** | `LOANCALC` (batch driver, ~970 lines), `PAYCALC` (called payment subprogram) |
| **Copybooks** | `LOANREC` (input record), `AMORTREC` (output record), `PAYPARM` (CALL interface, shared by caller and callee) |
| **Files** | `LOANIN` fixed 80-byte input → `AMORTOUT` fixed 80-byte H/D/T output + `LOANRPT` 132-column report |
| **Debugging case** | Change **LS0142**: four independent precision defects in `PAYCALC` ([CHANGELOG.md](CHANGELOG.md)) |
| **Before fix** | 4 / 14 edge cases correct, 514 / 2,000 random loans correct ([log](logs/before-run.log)) |
| **After fix** | **14 / 14** and **2,000 / 2,000**, every schedule row matching to the cent ([log](logs/after-run.log)) |

---

## Architecture

```
                 //STEP010 EXEC PGM=LOANCALC
                 +--------------------------------------------------------+
  LOANIN         |  LOANCALC  (batch driver)                              |
  LOANREC  ----> |   1000-INITIALIZE     open files, prime read           |
  80-byte FB     |   2000-PROCESS-LOAN   per record:                      |
                 |     2100-VALIDATE-LOAN    EVALUATE edits -> E0..E4     |
                 |     2200-CALCULATE-PAYMENT                             |
                 |        CALL 'PAYCALC' USING WS-PC-PARMS  -----------+  |
                 |        amortization guard              -> E6       |  |
                 |     2300-BUILD-SCHEDULE                            |  |
                 |        2320-PROCESS-PERIOD  (VARYING ... UNTIL     |  |
                 |          FINAL-PERIOD)  interest/principal/balance |  |
                 |     2900-REJECT-LOAN                               |  |
                 |   7000-7600 report writer (page breaks, headings)  |  |
                 |   8000/8100 I/O with FILE STATUS checks            |  |
                 |   9000-TERMINATE  control totals, RC 0/4           |  |
                 |   9900-ABEND      diagnostics, RC 16               |  |
                 +----------------------------------------------------|---+
                       |                    |                         v
                       v                    v          +---------------------------+
                  AMORTOUT              LOANRPT        | PAYCALC  (subprogram)     |
                  AMORTREC              132-col        |  LINKAGE: COPY PAYPARM    |
                  H / D / T records     print report   |  1000-VALIDATE-INPUT      |
                                                       |  2000-CALCULATE-PAYMENT   |
                                                       |  9000-SIZE-ERROR  -> RC 20|
                                                       +---------------------------+
```

`LOANCALC` calls `PAYCALC` **dynamically** (`CALL WS-PAYCALC-PGM`). The
fixed and the pre-fix `PAYCALC` are therefore separate load modules, and
the same unchanged `LOANCALC` runs against either one. On z/OS the
`STEPLIB` decides which is used; under GnuCOBOL it is `COB_LIBRARY_PATH`.
That is exactly how the before/after comparison is run.

### Business rules

| Rule | Implementation |
|---|---|
| Monthly rate | `r = annual% / 1200` (`PIC S9V9(18) COMP-3`, ROUNDED) |
| Level payment | `P·r·(1+r)^n / ((1+r)^n − 1)`, rounded half-up to the cent **once** |
| Zero interest | `P / n`, ROUNDED |
| Period interest | `balance × annual% / 1200`, ROUNDED, computed in one COMPUTE (no pre-rounded rate) |
| Final payment | last period pays `balance + interest`, so the balance ends at **exactly 0.00** |
| Early payoff | if rounding lets the level payment retire the loan early, the schedule stops at payoff |
| Rejects | E0 blank ID · E1 principal non-numeric/zero · E2 rate non-numeric/>36% · E3 term not 1–480 · E4 bad date · E5 payment too large for `S9(9)V99` (PAYCALC RC 20) · E6 payment ≤ first-month interest |
| Return code | 0 clean · 4 rejects present · 16 I/O error / overflow (controlled abend) |

### Record layouts (copybooks)

* **`LOANREC`**: loan ID, borrower, `PRINCIPAL 9(9)V99`,
  `ANNUAL-RATE 9(2)V9(4)` (e.g. `065000` = 6.5%), `TERM-MONTHS 9(3)`,
  first due `YYYYMM`, loan type with 88-levels. Zoned decimal with implied
  decimal points.
* **`AMORTREC`**: one record type byte with three `REDEFINES` views:
  `H` header (terms, payment, OK/RJ and reason), `D` detail (one per
  period), `T` trailer (totals). Amounts are
  `S9(11)V99 SIGN LEADING SEPARATE`, so the file is readable in ISPF
  browse and by non-COBOL consumers.
* **`PAYPARM`**: the CALL interface in `COMP-3`, with 88-level return
  codes. **Both** programs `COPY` it, so the layout can never drift.

All three use the `:TAG:` convention, for example
`COPY LOANREC REPLACING ==:TAG:== BY ==IN==.`, so one layout serves an
FD, working storage or linkage with the right prefix (`IN-`, `OUT-`,
`WS-PC-`, `LK-`).

---

## COBOL skills demonstrated

| Skill | Where |
|---|---|
| Copybooks shared between programs, `COPY … REPLACING` with `:TAG:` | `copybooks/*.cpy`; `PAYPARM` used by both LOANCALC (WS) and PAYCALC (LINKAGE) |
| Packed decimal (`COMP-3`) and zoned decimal with implied decimals | `PAYPARM`, all LOANCALC work areas (`COMP-3`); `LOANREC` (`9(9)V99`, `9(2)V9(4)`) |
| Precision engineering: wide intermediates, `ROUNDED`, `ON SIZE ERROR` | `PAYCALC` working storage sizing comments and `2000-CALCULATE-PAYMENT`; LOANCALC `2320-PROCESS-PERIOD` |
| Structured paragraphs, `PERFORM … VARYING … UNTIL`, `EVALUATE TRUE`, 88-levels | throughout; e.g. `2100-VALIDATE-LOAN`, `2320-PROCESS-PERIOD`, `7400-PRINT-DETAIL-LINE` |
| FILE STATUS checked after every OPEN / READ / WRITE / CLOSE | `1100-OPEN-FILES`, `8000-READ-LOAN-RECORD`, `8100-WRITE-AMORT-RECORD`, `7000-PRINT-LINE`, `9100-CLOSE-FILES` |
| CALLed subprogram with LINKAGE SECTION, return-code contract | `PAYCALC`; `LOANCALC 2200-CALCULATE-PAYMENT` |
| `REDEFINES` for multi-format records, `SIGN LEADING SEPARATE` | `AMORTREC` |
| Print report: headings, page breaks, continuation headings, edited PICs, control totals | `7000`–`7600` paragraphs |
| Controlled abend with diagnostics and return codes | `9900-ABEND` |
| Classic conventions: `WS-`/`LK-`/`IN-`/`OUT-`/`RPT-` prefixes, numbered paragraphs, fixed columns (7 = indicator, 8–72 = code, **73–80 = change tag**) | every source; `LS0142` tags mark each changed line in `src/PAYCALC.cbl` |
| Portable source: one source for z/OS and GnuCOBOL via `>>IF GNUCOBOL IS DEFINED` | `LOANCALC` `SELECT` clauses and page-eject handling |
| JCL: compile/link with `IGYWCL`, `ARITH(EXTEND)`, `COND`, rerunnable delete step, DCBs | `jcl/LOANCMPL.jcl`, `jcl/LOANRUN.jcl` |

---

## The debugging showcase (LS0142)

[`CHANGELOG.md`](CHANGELOG.md) has the full write-up in plain language.
In short:

| # | Defect in `src/before/PAYCALC.cbl` | Effect | Fix in `src/PAYCALC.cbl` |
|---|---|---|---|
| 1 | Intermediate `P·r·(1+r)^n` in `PIC S9(7)V99` | 950M loan: 25,443,628.19 silently became 5,434,012.36; a 1.00 loan's numerator became 0.00 | `PIC S9(15)V9(16) COMP-3` |
| 2 | Missing `ROUNDED` on the payment | Truncation: 277.7777 → 277.77; shortfall dumped on the final payment | `COMPUTE … ROUNDED` (rounding happens once, at the end) |
| 3 | `r` in `V9(6)`, `(1+r)^n` in `9(3)V9(6)` | 0.01% rate cut 4%; at 29.99%/360 the factor 7,233.03 became 231.34 and the loan "paid off" 137 months early | `S9V9(18)` and `S9(7)V9(24)`, ROUNDED |
| 4 | No `ON SIZE ERROR` | 1,009,999,999.99 payment accepted as 9,999,999.00 | `ON SIZE ERROR` → RC 20 → loan rejected E5 |

Why it survived in production: the final-payment adjustment still drove
every schedule to 0.00, so balance reconciliation always passed.

How it was proven:

1. **Independent answer key.** `tools/amort_reference.py` (Python
   `Decimal`, 50 digits, no shared code) → `tests/expected/EXPECTED-RESULTS.txt`.
2. **Edge-case deck** (`data/LOANS.DAT`): standard 30-year, 15-year, auto,
   zero-interest, 1-month term, 950-million principal, 1.00 principal,
   0.01% rate, 29.99% over 360 months (early payoff), half-cent
   sensitivity, oversize payment, 0.36 total principal, and two invalid
   records.
3. **Row-by-row verification** (`tools/compare_results.py`): status,
   payment, every D record (date, payment, interest, principal, balance),
   trailer totals, plus internal footing checks.
4. **Fault isolation** (`scripts/fault_isolation.sh`): each fix applied
   alone to the old source. No single fix is enough
   ([log](logs/fault-isolation.log)).
5. **Stress** (`scripts/stress_test.sh`): seeded random deck across the
   whole domain ([log](logs/stress-run.log)).

Every changed line in the fixed source carries a comment and the tag in
columns 73–80:

```cobol
      * LS0142 FIX-3: (1+R)**N WAS 9(3)V9(6) - LOST ITS HIGH-ORDER
      *               DIGITS ABOVE 999 (LONG TERMS / HIGH RATES) AND
      *               ALL BUT 6 DECIMALS.  NOW 7 INTEGER + 24 DECIMALS.
           05  WS-GROWTH-FACTOR        PIC S9(7)V9(24)    COMP-3.       LS0142
```

`diff src/before/PAYCALC.cbl src/PAYCALC.cbl` shows the complete change.

---

## Build and run (GnuCOBOL)

Prerequisites: GnuCOBOL 3.x (`cobc`), GNU make, Python 3.8+ (standard
library only).

```bash
sudo apt-get install gnucobol        # Debian/Ubuntu; brew install gnucobol on macOS

make                 # build LOANCALC + both PAYCALC versions (clean, -Wall)
make test            # before/after regression -> logs/before-run.log, logs/after-run.log
make run             # run the batch with the fixed PAYCALC -> output/after/
make run-before      # same input, pre-fix PAYCALC        -> output/before/
scripts/fault_isolation.sh           # which fix repairs which case
scripts/stress_test.sh [seed] [n]    # random-deck regression (default 2,000 loans)
make expected        # regenerate the answer key from the Python model
```

`make test` exits 0 only if the fixed version passes every case.

`scripts/run_batch.sh` is the GnuCOBOL stand-in for the run JCL. It maps
each DDNAME to a file through an environment variable
(`DD_LOANIN`, `DD_AMORTOUT`, `DD_LOANRPT`) and sets `COB_LIBRARY_PATH` as
the STEPLIB:

```
//LOANRUN  STEP010 EXEC PGM=LOANCALC   PAYCALC=after
//STEPLIB  DD build/after
//LOANIN   DD data/LOANS.DAT
...
LOANCALC - REJECTED COM0000011 E5 PAYMENT EXCEEDS FIELD CAPACITY
LOANCALC - REJECTED BAD0000013 E3 TERM MUST BE 001 - 480 MONTHS
LOANCALC - REJECTED BAD0000014 E1 PRINCIPAL IS NOT NUMERIC
LOANCALC - RECORDS READ    : +0000014
LOANCALC - LOANS ACCEPTED  : +0000011
LOANCALC - LOANS REJECTED  : +0000003
STEP010 LOANCALC ENDED - COND CODE 0004
```

### On z/OS

* `jcl/LOANCMPL.jcl` compiles and link-edits both programs with `IGYWCL`.
  **`ARITH(EXTEND)` is required**, because `PAYCALC` uses fields of up to
  31 digits.
* `jcl/LOANRUN.jcl` holds a rerunnable IEFBR14 delete step, then
  `LOANCALC` with `LOANIN`, `AMORTOUT` (FB/80) and `LOANRPT` (FBA/133,
  where 132 print columns + the ASA byte).
* `GNUCOBOL` is not defined there, so the `>>IF GNUCOBOL` blocks compile
  out and the files are ordinary QSAM fixed-block datasets.

---

## Sample output

From [`samples/LOANRPT.TXT`](samples/LOANRPT.TXT) (fixed run):

```
LOAN ID: PER0000007   BORROWER: DIALLO, AMINATA                  TYPE: PERSONAL
PRINCIPAL:           1.00   RATE:  9.0000%   TERM:  12 MONTHS   1ST DUE 2026-12   MONTHLY PAYMENT:            0.09

    PMT       DUE                 PAYMENT              INTEREST             PRINCIPAL               BALANCE
    ---     -------   -------------------   -------------------   -------------------   -------------------
      1     2026-12                 0.09                  0.01                  0.08                  0.92
      ...
     11     2027-10                 0.09                  0.00                  0.09                  0.06
     12     2027-11                 0.06                  0.00                  0.06                  0.00    <- FINAL (ADJUSTED)

    LOAN TOTALS                     1.05                  0.05                  1.00                  0.00     12 PAYMENTS
```

```
    357     2056-09               374.93                 14.94                359.99                237.70
    358     2056-10               243.64                  5.94                237.70                  0.00    <- PAID OFF EARLY
```

From [`samples/AMORTOUT.DAT`](samples/AMORTOUT.DAT) (header, first detail, trailer):

```
HMTG0000001+0000025000000065000360+0000000158017OK
DMTG0000001001202701+0000000158017+0000000135417+0000000022600+0000024977400
TMTG0000001360+0000000158055+0000056886158+0000031886158+0000000000000
```

---

## Repository layout

```
cobol-loan-servicing/
├── src/
│   ├── LOANCALC.cbl          batch driver
│   ├── PAYCALC.cbl           payment subprogram - FIXED (LS0142 tags in cols 73-80)
│   └── before/PAYCALC.cbl    payment subprogram - PRE-FIX, kept for the investigation
├── copybooks/                LOANREC.cpy  AMORTREC.cpy  PAYPARM.cpy
├── jcl/                      LOANCMPL.jcl (compile/link)  LOANRUN.jcl (run)
├── data/LOANS.DAT            edge-case test deck (fixed 80-byte records)
├── tests/expected/           answer key generated by the Python model
├── tools/
│   ├── amort_reference.py    independent Decimal reference model
│   ├── compare_results.py    row-by-row verifier
│   └── gen_stress_deck.py    seeded random deck generator
├── scripts/                  run_batch.sh  run_tests.sh  fault_isolation.sh  stress_test.sh
├── logs/                     before/after, fault isolation, stress, FILE STATUS test
├── samples/                  report and AMORTOUT from the fixed run
├── Makefile
├── CHANGELOG.md              root causes and fixes for LS0142
└── README.md
```
