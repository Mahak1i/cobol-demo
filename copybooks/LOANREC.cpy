      *================================================================*
      * COPYBOOK : LOANREC                                             *
      * TITLE    : LOAN MASTER EXTRACT RECORD  (LRECL=80, RECFM=FB)    *
      * USED BY  : LOANCALC - FD LOAN-IN-FILE                          *
      *                                                                *
      * USAGE    : COPY LOANREC REPLACING ==:TAG:== BY ==IN==.         *
      *            THE :TAG: PREFIX LETS ONE LAYOUT SERVE AN FD, A     *
      *            WORKING-STORAGE SAVE AREA, ETC. WITHOUT DUPLICATE   *
      *            DATA NAMES.                                         *
      *                                                                *
      * AMOUNTS ARE UNSIGNED ZONED DECIMAL WITH IMPLIED DECIMAL POINT: *
      *   PRINCIPAL   9(9)V99   00025000000 = 250,000.00               *
      *   ANNUAL-RATE 9(2)V9(4) 065000      = 6.5000 PERCENT           *
      *================================================================*
       01  :TAG:-LOAN-RECORD.
           05  :TAG:-LOAN-ID               PIC X(10).
           05  :TAG:-BORROWER-NAME         PIC X(30).
           05  :TAG:-PRINCIPAL             PIC 9(9)V99.
           05  :TAG:-PRINCIPAL-X REDEFINES :TAG:-PRINCIPAL
                                           PIC X(11).
           05  :TAG:-ANNUAL-RATE           PIC 9(2)V9(4).
           05  :TAG:-TERM-MONTHS           PIC 9(3).
           05  :TAG:-FIRST-PAY-DATE.
               10  :TAG:-FIRST-PAY-YYYY    PIC 9(4).
               10  :TAG:-FIRST-PAY-MM      PIC 9(2).
           05  :TAG:-LOAN-TYPE             PIC X(1).
               88  :TAG:-TYPE-MORTGAGE     VALUE 'M'.
               88  :TAG:-TYPE-AUTO         VALUE 'A'.
               88  :TAG:-TYPE-PERSONAL     VALUE 'P'.
               88  :TAG:-TYPE-COMMERCIAL   VALUE 'C'.
           05  FILLER                      PIC X(13).
