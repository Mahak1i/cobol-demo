#!/usr/bin/env bash
#=====================================================================
# stress_test.sh [seed] [count] - random-deck regression
#
# Generates a reproducible random deck across the full input domain,
# builds its answer key with the Python Decimal model, runs it through
# the FIXED LOANCALC/PAYCALC and verifies every schedule row.
#
# Output: logs/stress-run.log  (also reports the pre-fix failure count)
#=====================================================================
set -u
cd "$(dirname "$0")/.."
SEED="${1:-19980314}"
COUNT="${2:-2000}"
DIR=output/stress
mkdir -p "$DIR" logs
make -s all >/dev/null || exit 1

python3 tools/gen_stress_deck.py "$SEED" "$COUNT" "$DIR/STRESS.DAT"
python3 tools/amort_reference.py generate "$DIR/STRESS.DAT" \
        "$DIR/EXPECTED-STRESS.txt" >/dev/null

{
    echo "LS0142 STRESS RUN - SEED $SEED, $COUNT RANDOM LOANS, FIXED PAYCALC"
    echo
    COB_LIBRARY_PATH=build/after DD_LOANIN="$DIR/STRESS.DAT" \
    DD_AMORTOUT="$DIR/AMORTOUT.DAT" DD_LOANRPT="$DIR/LOANRPT.TXT" \
        build/bin/LOANCALC | grep -v ' - REJECTED '
    echo
    echo "ANSWER KEY OUTCOMES:"
    awk '!/^\*/ {print "  " $2, ($2 == "RJ" ? $3 : "")}' \
        "$DIR/EXPECTED-STRESS.txt" | sort | uniq -c
    echo
    python3 tools/compare_results.py --quiet "$DIR/STRESS.DAT" \
        "$DIR/EXPECTED-STRESS.txt" "$DIR/AMORTOUT.DAT" \
        "STRESS SEED $SEED (FAILURES ONLY)"
    RC=$?

    # For scale: the same deck through the PRE-FIX PAYCALC.
    COB_LIBRARY_PATH=build/before DD_LOANIN="$DIR/STRESS.DAT" \
    DD_AMORTOUT="$DIR/AMORTOUT-BEFORE.DAT" DD_LOANRPT="$DIR/LOANRPT-BEFORE.TXT" \
        build/bin/LOANCALC >/dev/null
    echo
    echo "SAME DECK WITH THE PRE-FIX PAYCALC (src/before/PAYCALC.cbl):"
    python3 tools/compare_results.py --quiet "$DIR/STRESS.DAT" \
        "$DIR/EXPECTED-STRESS.txt" "$DIR/AMORTOUT-BEFORE.DAT" | grep SUMMARY
    exit $RC
} 2>&1 | tee logs/stress-run.log
exit "${PIPESTATUS[0]}"
