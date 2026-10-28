#=====================================================================
# LS LOAN SERVICING - GnuCOBOL BUILD
#
#   make            build the driver and both PAYCALC versions
#   make run        run the batch with the FIXED PAYCALC
#   make run-before run the batch with the PRE-FIX PAYCALC
#   make test       before/after regression run -> logs/*.log
#   make expected   regenerate the answer key from the Python model
#   make clean
#
# Layout mirrors the mainframe: one driver load module (LOANCALC) and
# two load libraries holding PAYCALC.  LOANCALC calls PAYCALC
# dynamically, so which version runs is decided at run time by
# COB_LIBRARY_PATH - the GnuCOBOL equivalent of STEPLIB.
#=====================================================================
COBC      ?= cobc
CPYDIR    := copybooks
BUILD     := build

# -D GNUCOBOL      selects LINE SEQUENTIAL files (see LOANCALC SELECTs)
# -Wno-additional  silences "RECORD clause ignored for LINE SEQUENTIAL";
#                  the clause is kept because it is correct on z/OS.
COBFLAGS  := -std=default -Wall -Wno-additional -D GNUCOBOL -I $(CPYDIR)

# Ubuntu's gcc predefines _FORTIFY_SOURCE; drop cobc's copy to keep the
# compile log clean.
export COB_CFLAGS := $(subst -D_FORTIFY_SOURCE=2,,$(shell $(COBC) --info 2>/dev/null | sed -n 's/^COB_CFLAGS *: //p'))

COPYBOOKS := $(wildcard $(CPYDIR)/*.cpy)

DRIVER    := $(BUILD)/bin/LOANCALC
PAY_AFTER := $(BUILD)/after/PAYCALC.so
PAY_BEFORE:= $(BUILD)/before/PAYCALC.so

.PHONY: all run run-before test expected clean

all: $(DRIVER) $(PAY_AFTER) $(PAY_BEFORE)

$(DRIVER): src/LOANCALC.cbl $(COPYBOOKS)
	@mkdir -p $(@D)
	$(COBC) -x $(COBFLAGS) -o $@ $<

$(PAY_AFTER): src/PAYCALC.cbl $(COPYBOOKS)
	@mkdir -p $(@D)
	$(COBC) -m $(COBFLAGS) -o $@ $<

$(PAY_BEFORE): src/before/PAYCALC.cbl $(COPYBOOKS)
	@mkdir -p $(@D)
	$(COBC) -m $(COBFLAGS) -o $@ $<

run: all
	scripts/run_batch.sh after

run-before: all
	scripts/run_batch.sh before

test: all
	scripts/run_tests.sh

expected:
	python3 tools/amort_reference.py generate data/LOANS.DAT \
	    tests/expected/EXPECTED-RESULTS.txt

clean:
	rm -rf $(BUILD) output
