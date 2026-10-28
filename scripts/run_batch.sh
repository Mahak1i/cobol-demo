#!/usr/bin/env bash
#=====================================================================
# run_batch.sh  before|after  [input-file]
#
# GnuCOBOL stand-in for jcl/LOANRUN.jcl: maps the DDNAMEs to files,
# points the dynamic-call search path ("STEPLIB") at the chosen
# PAYCALC version, runs LOANCALC and reports the step return code.
#   output/<version>/AMORTOUT.DAT  - amortization file
#   output/<version>/LOANRPT.TXT   - printed report
#=====================================================================
set -u
cd "$(dirname "$0")/.."

VERSION="${1:-after}"
INPUT="${2:-data/LOANS.DAT}"
case "$VERSION" in
    before|after) ;;
    *) echo "usage: $0 before|after [input-file]" >&2; exit 2 ;;
esac

OUTDIR="output/$VERSION"
mkdir -p "$OUTDIR"

export COB_LIBRARY_PATH="build/$VERSION"     # //STEPLIB  DD
export DD_LOANIN="$INPUT"                    # //LOANIN   DD
export DD_AMORTOUT="$OUTDIR/AMORTOUT.DAT"    # //AMORTOUT DD
export DD_LOANRPT="$OUTDIR/LOANRPT.TXT"      # //LOANRPT  DD

echo "//LOANRUN  STEP010 EXEC PGM=LOANCALC   PAYCALC=$VERSION"
echo "//STEPLIB  DD $COB_LIBRARY_PATH"
echo "//LOANIN   DD $DD_LOANIN"
echo "//AMORTOUT DD $DD_AMORTOUT"
echo "//LOANRPT  DD $DD_LOANRPT"
echo
build/bin/LOANCALC
RC=$?
echo
echo "STEP010 LOANCALC ENDED - COND CODE $(printf '%04d' "$RC")"
exit $RC
