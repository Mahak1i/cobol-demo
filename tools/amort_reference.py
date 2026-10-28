#!/usr/bin/env python3
"""Independent reference model for the LOANCALC amortization batch.

This script re-implements the loan-servicing business rules in Python using
decimal.Decimal at 50 significant digits.  It shares NO code with the COBOL
programs; it only reads the same fixed-width input file.  Its output is the
"answer key" that the COBOL results are compared against.

Business rules (identical to the COBOL specification in README.md):

  r        = annual rate (percent) / 1200, kept exact
  payment  = P * r / (1 - (1 + r) ** -n), rounded half-up to cents
             (P / n when r = 0)
  interest = balance * annual rate / 1200, rounded half-up to cents, per period
  final    = in the last period (or as soon as the level payment would
             overpay) the borrower pays balance + interest, so the loan
             ends at exactly 0.00

Usage:
  amort_reference.py generate LOANS.DAT EXPECTED.txt   write the answer key
  amort_reference.py show LOANS.DAT LOAN-ID            print one schedule
"""

import sys
from decimal import Decimal, ROUND_HALF_UP, getcontext

getcontext().prec = 50

CENT = Decimal("0.01")
MAX_PAYMENT = Decimal("999999999.99")   # PIC S9(9)V99 payment field capacity

# Plain-English description of what each test record exercises.
CASE_NOTES = {
    "MTG0000001": "Standard 30-yr mortgage, 360 months",
    "MTG0000002": "15-yr mortgage, fractional rate",
    "AUT0000003": "60-month auto loan",
    "PER0000004": "Zero-interest loan (P / n path)",
    "PER0000005": "1-month term (payment = P * (1+r))",
    "COM0000006": "Very large principal (950,000,000.00)",
    "PER0000007": "Very small principal (1.00)",
    "MTG0000008": "Very low rate (0.01%), 360 months",
    "COM0000009": "High rate (29.99%), 360 months",
    "AUT0000010": "Half-cent rounding sensitivity",
    "COM0000011": "Payment exceeds field size -> reject",
    "PER0000012": "Tiny P, zero rate: payment 0.01",
    "BAD0000013": "Validation: zero term -> reject",
    "BAD0000014": "Validation: non-numeric principal",
}


def cents(value):
    """Round half-up to cents (COBOL ROUNDED default for positive values)."""
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def parse_loans(path):
    """Parse the 80-byte LOANREC layout (see copybooks/LOANREC.cpy)."""
    loans = []
    with open(path, encoding="ascii") as fh:
        for line in fh:
            rec = line.rstrip("\n").ljust(80)
            loans.append({
                "id": rec[0:10].strip(),
                "name": rec[10:40].strip(),
                "principal_raw": rec[40:51],
                "rate_raw": rec[51:57],
                "term_raw": rec[57:60],
                "date_raw": rec[60:66],
                "type": rec[66:67],
            })
    return loans


def validate(loan):
    """Return a reject reason code, or None if the record is valid."""
    if not loan["id"]:
        return "E0"
    if not loan["principal_raw"].isdigit() or int(loan["principal_raw"]) == 0:
        return "E1"
    if not loan["rate_raw"].isdigit() or int(loan["rate_raw"]) > 360000:
        return "E2"
    if not loan["term_raw"].isdigit() or not 1 <= int(loan["term_raw"]) <= 480:
        return "E3"
    d = loan["date_raw"]
    if not d.isdigit() or not 1 <= int(d[4:6]) <= 12:
        return "E4"
    return None


def level_payment(principal, rate_pct, term):
    """Exact amortization payment, rounded to cents."""
    r = rate_pct / Decimal(1200)
    if r == 0:
        return cents(principal / term)
    return cents(principal * r / (1 - (1 + r) ** -term))


def schedule(principal, rate_pct, term):
    """Yield (period, payment, interest, principal, balance) rows."""
    pay = level_payment(principal, rate_pct, term)
    balance = principal
    for period in range(1, term + 1):
        interest = cents(balance * rate_pct / Decimal(1200))
        if period == term or balance + interest <= pay:
            yield period, balance + interest, interest, balance, Decimal("0.00")
            return
        prin = pay - interest
        balance -= prin
        yield period, pay, interest, prin, balance


def evaluate(loan):
    """Compute the expected outcome for one input record."""
    reason = validate(loan)
    if reason:
        return {"status": "RJ", "reason": reason}
    principal = Decimal(int(loan["principal_raw"])) / 100
    rate = Decimal(int(loan["rate_raw"])) / 10000
    term = int(loan["term_raw"])
    pay = level_payment(principal, rate, term)
    if pay > MAX_PAYMENT:
        return {"status": "RJ", "reason": "E5"}
    first_interest = cents(principal * rate / Decimal(1200))
    if term > 1 and pay <= first_interest:
        return {"status": "RJ", "reason": "E6"}
    rows = list(schedule(principal, rate, term))
    return {
        "status": "OK",
        "reason": "  ",
        "payment": pay,
        "periods": len(rows),
        "final": rows[-1][1],
        "total_interest": sum(r[2] for r in rows),
        "total_paid": sum(r[1] for r in rows),
        "rows": rows,
    }


def generate(loans_path, out_path):
    lines = [
        "* EXPECTED RESULTS - GENERATED BY tools/amort_reference.py",
        "* (python decimal.Decimal, 50 significant digits, ROUND_HALF_UP)",
        "*",
        "* LOAN-ID    ST RC         PAYMENT  NPAY     FINAL-PAYMENT"
        "    TOTAL-INTEREST        TOTAL-PAID  CASE",
    ]
    for loan in parse_loans(loans_path):
        res = evaluate(loan)
        note = CASE_NOTES.get(loan["id"], "")
        if res["status"] == "OK":
            lines.append(
                f"  {loan['id']:<10} OK    {res['payment']:>15} {res['periods']:>5}"
                f" {res['final']:>17} {res['total_interest']:>17}"
                f" {res['total_paid']:>17}  {note}")
        else:
            lines.append(
                f"  {loan['id']:<10} RJ {res['reason']} {'':>15} {'':>5}"
                f" {'':>17} {'':>17} {'':>17}  {note}")
    with open(out_path, "w", encoding="ascii") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {out_path}")


def show(loans_path, loan_id):
    for loan in parse_loans(loans_path):
        if loan["id"] == loan_id:
            res = evaluate(loan)
            if res["status"] != "OK":
                print(f"{loan_id} rejected {res['reason']}")
                return
            print(f"{loan_id} payment {res['payment']}")
            for row in res["rows"]:
                print("{:>4} {:>16} {:>16} {:>16} {:>18}".format(*row))
            return
    print(f"{loan_id} not found")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "generate":
        generate(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "show":
        show(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
