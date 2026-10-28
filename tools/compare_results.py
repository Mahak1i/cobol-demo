#!/usr/bin/env python3
"""Compare a LOANCALC AMORTOUT file with the expected results.

Three independent checks per loan:

  1. Summary vs. the committed answer key (tests/expected/EXPECTED-RESULTS.txt):
     accept/reject status and reason, level payment, number of payments,
     final payment, total interest, total paid.
  2. Every schedule row ('D' record) vs. the Python reference model:
     due date, payment, interest, principal, remaining balance.
  3. Internal consistency of the COBOL output itself: payment = interest +
     principal on every row, balances chain correctly, the loan ends at
     exactly 0.00 and the 'T' trailer equals the sum of its 'D' records.

Usage:
  compare_results.py [--quiet] LOANS.DAT EXPECTED-RESULTS.txt AMORTOUT [LABEL]

  --quiet   list only failing loans (for large stress decks)

Exit status is 0 when every loan matches, 1 otherwise.
"""

import os
import sys
from collections import OrderedDict
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import amort_reference as ref  # noqa: E402


def amount(field):
    """Decode PIC S9(11)V99 SIGN LEADING SEPARATE (14 bytes)."""
    sign = -1 if field[0] == "-" else 1
    return sign * Decimal(int(field[1:])) / 100


def parse_amortout(path):
    """Group AMORTOUT records by loan id (see copybooks/AMORTREC.cpy)."""
    loans = OrderedDict()
    with open(path, encoding="ascii") as fh:
        for line in fh:
            rec = line.rstrip("\n").ljust(80)
            rtype, loan_id, data = rec[0], rec[1:11].strip(), rec[11:]
            loan = loans.setdefault(loan_id, {"hdr": None, "rows": [], "trl": None})
            if rtype == "H":
                loan["hdr"] = {
                    "principal": amount(data[0:14]),
                    "payment": amount(data[23:37]),
                    "status": data[37:39],
                    "reason": data[39:41],
                }
            elif rtype == "D":
                loan["rows"].append((
                    int(data[0:3]), data[3:9], amount(data[9:23]),
                    amount(data[23:37]), amount(data[37:51]), amount(data[51:65]),
                ))
            elif rtype == "T":
                loan["trl"] = {
                    "periods": int(data[0:3]),
                    "final": amount(data[3:17]),
                    "total_paid": amount(data[17:31]),
                    "total_interest": amount(data[31:45]),
                    "end_balance": amount(data[45:59]),
                }
    return loans


def parse_expected(path):
    expected = {}
    with open(path, encoding="ascii") as fh:
        for line in fh:
            if line.startswith("*") or not line.strip():
                continue
            loan_id, status = line[2:12].strip(), line[13:15]
            entry = {"status": status, "reason": line[16:18]}
            if status == "OK":
                f = line[19:].split()
                entry.update(payment=Decimal(f[0]), periods=int(f[1]),
                             final=Decimal(f[2]), total_interest=Decimal(f[3]),
                             total_paid=Decimal(f[4]))
            expected[loan_id] = entry
    return expected


def due_date(first_yyyymm, period):
    months = int(first_yyyymm[:4]) * 12 + int(first_yyyymm[4:6]) - 1 + period - 1
    return f"{months // 12:04d}{months % 12 + 1:02d}"


def money(value):
    return f"{value:,.2f}" if value is not None else "-"


def check_loan(loan, exp, actual):
    """Return a list of human-readable problems (empty list = PASS)."""
    problems = []
    if actual is None or actual["hdr"] is None:
        return ["no header record written for this loan"]
    hdr = actual["hdr"]

    if exp["status"] != hdr["status"] or exp["reason"].strip() != hdr["reason"].strip():
        problems.append(
            f"status            expected {exp['status']} {exp['reason']:<2}"
            f"   actual {hdr['status']} {hdr['reason']}")
    if exp["status"] != "OK" or hdr["status"] != "OK":
        return problems

    trl = actual["trl"] or {}
    for label, key, act in (
            ("level payment", "payment", hdr["payment"]),
            ("final payment", "final", trl.get("final")),
            ("total interest", "total_interest", trl.get("total_interest")),
            ("total paid", "total_paid", trl.get("total_paid"))):
        if act != exp[key]:
            diff = f"diff {act - exp[key]:+,.2f}" if act is not None else ""
            problems.append(f"{label:<17} expected {money(exp[key]):>18}"
                            f"   actual {money(act):>18}   {diff}")
    if trl.get("periods") != exp["periods"]:
        problems.append(f"payments made     expected {exp['periods']:>18}"
                        f"   actual {trl.get('periods')!s:>18}")
    if trl.get("end_balance") != Decimal("0.00"):
        problems.append(f"ending balance    expected {'0.00':>18}"
                        f"   actual {money(trl.get('end_balance')):>18}")

    # Row-by-row against the reference model.
    model = ref.evaluate(loan)["rows"]
    rows = actual["rows"]
    bad = [p for p, (m, a) in enumerate(zip(model, rows), 1)
           if a != (m[0], due_date(loan["date_raw"], m[0])) + tuple(m[1:])]
    if bad or len(rows) != len(model):
        first = f" (first at period {bad[0]})" if bad else ""
        problems.append(f"schedule rows     {len(model)} expected, {len(rows)} actual,"
                        f" {len(bad) + abs(len(model) - len(rows))} differ{first}")

    # Internal consistency of what the COBOL program wrote.
    balance = actual["hdr"]["principal"]
    for period, _, pay, intr, prin, bal in rows:
        if pay != intr + prin or bal != balance - prin:
            problems.append(f"row {period} does not foot: payment != interest +"
                            f" principal or balance does not chain")
            break
        balance = bal
    if trl and (sum(r[2] for r in rows) != trl["total_paid"]
                or sum(r[3] for r in rows) != trl["total_interest"]):
        problems.append("trailer totals do not equal the sum of the detail rows")
    return problems


def main(argv):
    quiet = "--quiet" in argv
    argv = [a for a in argv if a != "--quiet"]
    if len(argv) not in (4, 5):
        sys.exit(__doc__)
    loans_path, expected_path, amort_path = argv[1:4]
    label = argv[4] if len(argv) == 5 else amort_path

    loans = ref.parse_loans(loans_path)
    expected = parse_expected(expected_path)
    actual = parse_amortout(amort_path)

    print("=" * 96)
    print(f" LOANCALC RESULT VERIFICATION - {label}")
    print(f" input    : {loans_path}")
    print(f" expected : {expected_path}")
    print(f" actual   : {amort_path}")
    print("=" * 96)
    print(f" {'RESULT':<7}{'LOAN ID':<12}{'EXPECTED':>16}{'ACTUAL':>16}   CASE")
    print(f" {'-'*6:<7}{'-'*10:<12}{'-'*14:>16}{'-'*14:>16}   {'-'*40}")

    failures = 0
    details = []
    for loan in loans:
        exp = expected[loan["id"]]
        act = actual.get(loan["id"])
        problems = check_loan(loan, exp, act)
        hdr = act["hdr"] if act and act["hdr"] else None
        exp_txt = (money(exp["payment"]) if exp["status"] == "OK"
                   else f"REJECT {exp['reason']}")
        act_txt = ("-" if hdr is None else money(hdr["payment"])
                   if hdr["status"] == "OK" else f"REJECT {hdr['reason']}")
        result = "PASS" if not problems else "FAIL"
        failures += bool(problems)
        if quiet and not problems:
            continue
        print(f" {result:<7}{loan['id']:<12}{exp_txt:>16}{act_txt:>16}"
              f"   {ref.CASE_NOTES.get(loan['id'], '')}")
        if problems:
            details.append((loan["id"], problems))

    if details:
        print()
        print(" MISMATCH DETAIL")
        print(" " + "-" * 95)
        for loan_id, problems in details:
            print(f" {loan_id}")
            for p in problems:
                print(f"     {p}")
    print()
    print(f" SUMMARY: {len(loans)} cases, {len(loans) - failures} passed,"
          f" {failures} failed")
    print("=" * 96)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
