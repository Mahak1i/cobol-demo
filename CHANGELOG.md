# Changelog

All notable changes to the LS loan-servicing batch (`LOANCALC` / `PAYCALC`).
Change IDs match the maintenance log in each program header and the
`LS0142` tags in columns 73-80 of every changed source line.

---

## [LS0142] 2026-10-28: PAYCALC payment precision defects

**Programs changed:** `PAYCALC` only (`src/PAYCALC.cbl`).
The pre-fix source is kept as `src/before/PAYCALC.cbl` for audit.
**Not changed:** `LOANCALC`, all copybooks, the call interface (`PAYPARM`),
and the record layouts. `LOANCALC` calls `PAYCALC` dynamically, so promoting
the new load module needs no relink of the driver.

### Symptoms reported

* Level monthly payments were slightly wrong, usually by a few cents and
  sometimes by more than a dollar. The shortfall built up over the term and
  came out in a much larger **final payment**: a 30-year mortgage ended with a
  1,734.56 final installment instead of 1,580.55.
* Every schedule still ran down to 0.00. The final-payment adjustment
  (LS0098) absorbed the error, so balance reconciliation never failed and
  the defect went unnoticed for years.
* A 950,000,000.00 commercial loan was rejected as "payment does not
  cover interest" (reason E6).
* A one-month bridge loan whose real payment is 1,009,999,999.99, too
  large for the `PIC S9(9)V99` payment field, was **accepted** with a
  payment of 9,999,999.00 and no warning.

### How it was diagnosed

1. **An independent answer key.** `tools/amort_reference.py` re-implements
   the business rules in Python with `decimal.Decimal` at 50 significant
   digits and shares no code with the COBOL. It produced
   `tests/expected/EXPECTED-RESULTS.txt`.
2. **An edge-case test deck** (`data/LOANS.DAT`) covering zero interest, a
   1-month term, 360-month terms, very large and very small principals, a
   very low and a very high rate, and records that must be rejected.
3. **A row-by-row comparison** (`tools/compare_results.py`) of every
   schedule row, total and status. Result: **10 of 14 cases failed**
   (`logs/before-run.log`).
4. **A hand trace** of the intermediate fields for the failing loans. The
   trace (below) reproduced the wrong COBOL payments to the cent, which
   proved the cause was in PAYCALC's working storage and not in LOANCALC.
5. **Fault isolation** (`scripts/fault_isolation.sh`). Each fix was
   applied to the old source on its own and the deck was re-run. **No
   single fix makes the deck pass.** There were four independent defects
   (`logs/fault-isolation.log`):

   | Variant of the pre-fix PAYCALC | Cases passing |
   |---|---|
   | as found                         | 4 / 14 |
   | FIX-1 only                       | 4 / 14 |
   | FIX-2 only                       | 5 / 14 |
   | FIX-3 only                       | 4 / 14 |
   | FIX-1 + FIX-2 + FIX-3            | 13 / 14 |
   | all four fixes (released source) | **14 / 14** |

### Hand trace: what the pre-fix fields actually held

| Loan | Field | Pre-fix value | Correct value |
|---|---|---|---|
| MTG0000001 250,000.00 @ 6.5% / 360 | `WS-MONTHLY-RATE`  `V9(6)` | 0.005416 | 0.0054166666… |
|  | `WS-GROWTH-FACTOR` `9(3)V9(6)` | 6.990129 | 6.9917979738… |
|  | `WS-PAYMENT-WORK`  `S9(7)V99` | 9,464.63 | 9,468.0597… |
|  | **payment** | **1,580.03** | **1,580.17** |
| MTG0000008 200,000.00 @ 0.01% / 360 | `WS-MONTHLY-RATE` | 0.000008 (**4% low**) | 0.0000083333… |
|  | **payment** | **554.78** | **556.39** |
| COM0000009 15,000.00 @ 29.99% / 360 | `WS-GROWTH-FACTOR` | **231.339321** | **7,233.0327…** |
| COM0000006 950,000,000.00 @ 5.75% / 360 | `WS-PAYMENT-WORK` | **5,434,012.36** | **25,443,628.19…** |
|  | **payment** | 1,184,367.85, then rejected E6 | **5,543,942.14** |
| COM0000011 999,999,999.99 @ 12% / 1 | **payment** | **9,999,999.00** | 1,009,999,999.99, too big for the field, so reject |

### Root causes and fixes

#### FIX-1: intermediate field too small (`WS-PAYMENT-WORK`)

**Cause.** The numerator `P × r × (1+r)^n` was stored in `PIC S9(7)V99`.
That picture was copied from the original principal field, from back when
the largest loan was 9,999,999.99. It failed in two ways:

* **High-order truncation.** A 950-million loan's numerator is about
  25 million, which needs 8 integer digits. COBOL dropped the leading digit
  without any message, because there was no `ON SIZE ERROR`:
  25,443,628.19 became 5,434,012.36.
* **Low-order truncation.** Only 2 decimals were kept before the value was
  divided by the small number `(1+r)^n − 1`, and the division magnified the
  lost digits. For a 1.00 loan the numerator 0.0082 became **0.00**, so the
  payment came out as 0.00.

**Fix.** `PIC S9(15)V9(16) COMP-3`: 14 integer digits cover the worst
case accepted by validation (about 4.3E13), and 16 decimals carry full
precision into the divide. The 31 digits are the Enterprise COBOL maximum
under `ARITH(EXTEND)`, which the compile JCL now documents.

#### FIX-2: missing `ROUNDED`

**Cause.** Without `ROUNDED`, COBOL **truncates**. Both payment `COMPUTE`s
(the amortized one and the zero-rate `P / n` one) cut the result off at the
cent, so an exact payment of 2,933.758… would bill as 2,933.75, and
10,000.00 / 36 = 277.7777… did bill as 277.77. The borrower was under-billed every month and the whole shortfall
landed on the final payment (278.05 instead of 277.70).

**Fix.** `COMPUTE … ROUNDED` on both payment statements. Rounding to cents
now happens **once**, at the very end. Every intermediate keeps its full
precision instead.

#### FIX-3: `(1 + r) ** n` losing digits

**Cause.** Two fields were too narrow:

* `WS-MONTHLY-RATE PIC V9(6)` truncated `r`. At 6.5% that is a 0.012%
  error, small but raised to the 360th power. At a 0.01% promotional rate
  it is **4%**: 0.0000083333 became 0.000008.
* `WS-GROWTH-FACTOR PIC 9(3)V9(6)` kept 6 decimals and only **3 integer
  digits**. At 29.99% over 360 months the factor is 7,233.03, and it was
  stored as **231.34** with the thousands digit gone. The formula
  `r·F/(F−1)` is forgiving when F is large, so the payment moved by only
  1.56. But on a loan that is almost all interest, the principal portion
  went from 0.05 to 1.61, and the schedule paid off in 221 months instead
  of 358, under-collecting **50,948.60** of interest.

**Fix.** `r` is now `PIC S9V9(18)` and `(1+r)^n` is now `PIC S9(7)V9(24)`
(7 integer digits cover 1.03^480 ≈ 1.43 million). Both are computed with
`ROUNDED`. The extra decimals on `(1+r)^n` matter because at very low
rates `(1+r)^n − 1` is tiny (about 1.7E-7 at 0.0001% over 2 months), and
dividing by it magnifies any error. With 18 decimals, rounding the factor
could still move a 999-million payment by 0.003, which is enough to flip a
cent. With 24 decimals the worst case is 3E-9.

#### FIX-4: no `ON SIZE ERROR`

**Cause.** Nothing in PAYCALC checked for overflow, so every truncation
above was silent. The worst case was a payment of 1,009,999,999.99 being
stored in `PIC S9(9)V99` as 9,999,999.00 and passed back as valid.

**Fix.** Every `COMPUTE` has `ON SIZE ERROR` → `9000-SIZE-ERROR`, which
sets return code **20** and a message. On any error the payment is forced
to zero, never a truncated value. LOANCALC already mapped RC 20 to reject
reason E5, so the loan is now rejected and listed on the report.

### Design notes

* **Interest per period** is computed in LOANCALC as
  `BALANCE × ANNUAL-RATE / 1200 ROUNDED` in a single `COMPUTE`, never from
  a pre-rounded monthly rate. That way no rounded intermediate can bias
  the half-cent decision (unchanged by this fix, but it explains why the
  defect was confined to PAYCALC).
* **Precision budget.** The payment must round to the right cent for
  every input that validation accepts (P ≤ 999,999,999.99, rate ≤ 36%,
  term ≤ 480). The unrounded payment is now accurate to better than 1E-8
  across that domain: about 5E-10 from `r`, 3E-9 from `(1+r)^n` and 6E-10
  from the 16-decimal numerator. The bound was derived first and then
  checked by brute force (see Verification).

### Verification

| Check | Result | Evidence |
|---|---|---|
| Standard deck, fixed PAYCALC | **14 / 14 pass**, every schedule row identical to the reference | `logs/after-run.log` |
| Standard deck, pre-fix PAYCALC | 4 / 14 pass | `logs/before-run.log` |
| Fault isolation | four independent root causes, all needed | `logs/fault-isolation.log` |
| Random deck, 2,000 loans (seed 19980314), about 218,000 schedule rows | fixed **2,000 / 2,000**; pre-fix 514 / 2,000 | `logs/stress-run.log` |
| Missing input dataset | controlled RC 16 with paragraph and FILE STATUS 35 | `logs/file-status-test.log` |

Additional runs, not committed as logs:
`scripts/stress_test.sh 1 20000`, `… 2 20000` and `… 3 20000` (60,000
loans) all pass. So does a 432-loan grid of the extremes: principals 0.01
to 999,999,999.99 × rates 0% to 36% × terms 1 to 480.

---

## [LS0098] 2011-02-09: early payoff and final-payment adjustment

* The last installment is now `balance + interest`, so every loan ends at
  exactly 0.00.
* If rounding makes the level payment retire the loan before its term
  ends, the schedule stops at payoff (`<- PAID OFF EARLY` on the report).

## [LS0057] 2003-07-22: zero-rate promotional loans

* PAYCALC: when `r = 0`, the payment is `P / n`, which avoids dividing by
  `(1+r)^n − 1 = 0`.

## [ORIG] 1998-03-14: initial release

* LOANCALC batch driver, PAYCALC payment subprogram, LOANREC / AMORTREC /
  PAYPARM copybooks.
