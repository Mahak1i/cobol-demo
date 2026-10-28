#!/usr/bin/env bash
#=====================================================================
# run_tests.sh - before/after regression run for change LS0142
#
# Runs the same input through LOANCALC twice - once with the pre-fix
# PAYCALC, once with the fixed one - and verifies each AMORTOUT file
# against the answer key produced independently by Python Decimal.
#
#   logs/before-run.log   expected to show mismatches
#   logs/after-run.log    expected to show every case passing
#   logs/file-status-test.log  missing input -> controlled RC 16
#   samples/                   report + AMORTOUT from the fixed run
#
# Exit 0 only when the fixed version passes every case.
#=====================================================================
set -u
cd "$(dirname "$0")/.."
mkdir -p logs

INPUT=data/LOANS.DAT
EXPECTED=tests/expected/EXPECTED-RESULTS.txt

run_one() {
    local version="$1" label="$2"
    {
        echo "######################################################################"
        echo "# LS0142 REGRESSION RUN - $label"
        echo "# $(date -u '+%Y-%m-%d %H:%M:%S UTC')   $(cobc --version | head -1)"
        echo "######################################################################"
        echo
        scripts/run_batch.sh "$version" "$INPUT"
        echo
        python3 tools/compare_results.py "$INPUT" "$EXPECTED" \
            "output/$version/AMORTOUT.DAT" "$label"
    } 2>&1 | tee "logs/$version-run.log"
    return "${PIPESTATUS[0]}"
}

# The 'before' run is expected to fail verification; record, don't stop.
run_one before "BEFORE FIX (src/before/PAYCALC.cbl)" || true
echo
run_one after  "AFTER FIX  (src/PAYCALC.cbl)"
STATUS=$?

# Publish the fixed run's outputs so they can be browsed without a build.
mkdir -p samples
cp output/after/LOANRPT.TXT  samples/LOANRPT.TXT
cp output/after/AMORTOUT.DAT samples/AMORTOUT.DAT

# FILE STATUS handling: a missing input dataset must end the step with
# a controlled RC 16 and a diagnostic, not a runtime crash.
echo
{
    echo "######################################################################"
    echo "# FILE STATUS NEGATIVE TEST - LOANIN DATASET DOES NOT EXIST"
    echo "######################################################################"
    echo
    scripts/run_batch.sh after data/NO-SUCH-FILE.DAT
    RC=$?
    echo
    if [ "$RC" -eq 16 ]; then
        echo "RESULT: PASS - OPEN FAILURE TRAPPED, STEP ENDED RC 16"
    else
        echo "RESULT: FAIL - EXPECTED RC 16, GOT RC $RC"
        STATUS=1
    fi
} 2>&1 | tee logs/file-status-test.log
grep -q "RESULT: PASS" logs/file-status-test.log || STATUS=1

echo
if [ "$STATUS" -eq 0 ]; then
    echo "LS0142 REGRESSION: FIXED VERSION PASSES ALL CASES"
else
    echo "LS0142 REGRESSION: FIXED VERSION HAS MISMATCHES" >&2
fi
exit "$STATUS"
