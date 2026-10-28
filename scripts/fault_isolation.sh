#!/usr/bin/env bash
#=====================================================================
# fault_isolation.sh - which LS0142 fix repairs which test case?
#
# Builds throw-away variants of the PRE-FIX PAYCALC with exactly one
# (or a subset) of the fixes applied, runs the standard test deck
# through each, and prints a PASS/FAIL matrix.  This is how the
# defect was proven to have several independent root causes: no
# single fix makes the deck pass.
#
# Output: logs/fault-isolation.log
#=====================================================================
set -u
cd "$(dirname "$0")/.."
make -s all >/dev/null || exit 1

WORK=build/isolation
rm -rf "$WORK"; mkdir -p "$WORK"
BEFORE=src/before/PAYCALC.cbl

# Each fix as a sed program against the pre-fix source (columns 8-72).
FIX1='s/WS-PAYMENT-WORK         PIC S9(7)V99       COMP-3/WS-PAYMENT-WORK         PIC S9(15)V9(16)   COMP-3/'
FIX2='s/COMPUTE LK-MONTHLY-PAYMENT =/COMPUTE LK-MONTHLY-PAYMENT ROUNDED =/'
FIX3='s/WS-MONTHLY-RATE         PIC V9(6)          COMP-3/WS-MONTHLY-RATE         PIC S9V9(18)       COMP-3/
s/WS-GROWTH-FACTOR        PIC 9(3)V9(6)      COMP-3/WS-GROWTH-FACTOR        PIC S9(7)V9(24)    COMP-3/
s/COMPUTE WS-MONTHLY-RATE =/COMPUTE WS-MONTHLY-RATE ROUNDED =/
s/COMPUTE WS-GROWTH-FACTOR =/COMPUTE WS-GROWTH-FACTOR ROUNDED =/'

build_variant() {    # name, sed programs...
    local name="$1"; shift
    local src="$WORK/$name.cbl"
    cp "$BEFORE" "$src"
    for prog in "$@"; do sed -i "$prog" "$src"; done
    mkdir -p "$WORK/$name"
    cobc -m -Wno-additional -D GNUCOBOL -I copybooks \
         -o "$WORK/$name/PAYCALC.so" "$src" || exit 1
}

run_variant() {      # name, steplib
    local name="$1" lib="$2"
    COB_LIBRARY_PATH="$lib" DD_LOANIN=data/LOANS.DAT \
    DD_AMORTOUT="$WORK/$name.AMORTOUT" DD_LOANRPT="$WORK/$name.LOANRPT" \
        build/bin/LOANCALC >/dev/null
    python3 tools/compare_results.py data/LOANS.DAT \
        tests/expected/EXPECTED-RESULTS.txt "$WORK/$name.AMORTOUT" \
        | awk '$1=="PASS"||$1=="FAIL" {print $2, $1}' > "$WORK/$name.result"
}

export COB_CFLAGS="$(cobc --info | sed -n 's/^COB_CFLAGS *: //p' \
                     | sed 's/-D_FORTIFY_SOURCE=2//')"

build_variant fix1    "$FIX1"
build_variant fix2    "$FIX2"
build_variant fix3    "$FIX3"
build_variant fix123  "$FIX1" "$FIX2" "$FIX3"

run_variant none     build/before
run_variant fix1     "$WORK/fix1"
run_variant fix2     "$WORK/fix2"
run_variant fix3     "$WORK/fix3"
run_variant fix123   "$WORK/fix123"
run_variant final    build/after

{
    echo "LS0142 FAULT ISOLATION - PRE-FIX PAYCALC WITH SELECTED FIXES APPLIED"
    echo
    echo "  FIX-1  widen P*R*(1+R)**N work field  S9(7)V99    -> S9(15)V9(16)"
    echo "  FIX-2  ROUNDED on the payment COMPUTEs (amortized and zero-rate)"
    echo "  FIX-3  widen R and (1+R)**N           V9(6) -> S9V9(18), 9(3)V9(6) -> S9(7)V9(24)"
    echo "  FIX-4  ON SIZE ERROR -> RC 20 (only in the final src/PAYCALC.cbl)"
    echo
    printf "  %-11s %-6s %-6s %-6s %-6s %-9s %-9s  %s\n" \
           "LOAN ID" "NONE" "FIX-1" "FIX-2" "FIX-3" "FIX-1+2+3" "ALL FOUR" "CASE"
    printf "  %-11s %-6s %-6s %-6s %-6s %-9s %-9s  %s\n" \
           "----------" "----" "-----" "-----" "-----" "---------" "--------" "----"
    while read -r id _; do
        note=$(python3 -c "import sys; sys.path.insert(0,'tools'); \
import amort_reference as r; print(r.CASE_NOTES.get('$id',''))")
        cells=()
        for v in none fix1 fix2 fix3 fix123 final; do
            cells+=("$(awk -v id="$id" '$1==id {print $2}' "$WORK/$v.result")")
        done
        printf "  %-11s %-6s %-6s %-6s %-6s %-9s %-9s  %s\n" "$id" "${cells[@]}" "$note"
    done < "$WORK/none.result"
    echo
    for v in none fix1 fix2 fix3 fix123 final; do
        printf "  %-7s passes %2d of %d\n" "$v" \
            "$(grep -c PASS "$WORK/$v.result")" "$(wc -l < "$WORK/$v.result")"
    done
} | tee logs/fault-isolation.log
