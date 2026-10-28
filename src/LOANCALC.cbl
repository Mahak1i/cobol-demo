       IDENTIFICATION DIVISION.
       PROGRAM-ID.    LOANCALC.
      *================================================================*
      * PROGRAM   : LOANCALC                                           *
      * TITLE     : LOAN AMORTIZATION SCHEDULE - BATCH DRIVER          *
      * SYSTEM    : LS - LOAN SERVICING BATCH                          *
      * TYPE      : BATCH MAIN PROGRAM                                 *
      * CALLS     : PAYCALC  (LEVEL MONTHLY PAYMENT) - DYNAMIC CALL    *
      *                                                                *
      * FUNCTION  : FOR EACH LOAN ON THE MASTER EXTRACT:               *
      *             1. EDIT THE RECORD (NUMERIC, RANGES, DATE).        *
      *             2. CALL PAYCALC FOR THE LEVEL MONTHLY PAYMENT.     *
      *             3. BUILD THE FULL AMORTIZATION SCHEDULE:           *
      *                  INTEREST  = BALANCE * RATE / 1200  (ROUNDED)  *
      *                  PRINCIPAL = PAYMENT - INTEREST                *
      *                  BALANCE   = BALANCE - PRINCIPAL               *
      *                THE LAST PAYMENT IS ADJUSTED TO BALANCE PLUS    *
      *                INTEREST SO EVERY LOAN ENDS AT EXACTLY 0.00.    *
      *                IF ROUNDING MAKES THE LEVEL PAYMENT RETIRE THE  *
      *                LOAN EARLY, THE SCHEDULE STOPS AT PAYOFF.       *
      *             4. WRITE H/D/T RECORDS TO AMORTOUT AND A PRINTED   *
      *                SCHEDULE TO LOANRPT.  REJECTS GO TO BOTH.       *
      *                                                                *
      * FILES     : DDNAME    DIR  DESCRIPTION                         *
      *             LOANIN    IN   LOAN MASTER EXTRACT  (LOANREC)      *
      *             AMORTOUT  OUT  AMORTIZATION FILE    (AMORTREC)     *
      *             LOANRPT   OUT  132-COLUMN PRINT REPORT             *
      *                                                                *
      * RETURN    : 00 = ALL LOANS PROCESSED                           *
      * CODES       04 = ONE OR MORE LOANS REJECTED - SEE REPORT       *
      *             16 = I/O ERROR OR ARITHMETIC OVERFLOW - RUN ENDED  *
      *----------------------------------------------------------------*
      * MAINTENANCE LOG                                                *
      * DATE       CHG-ID  PROGRAMMER  DESCRIPTION                     *
      * ---------- ------- ----------- ------------------------------- *
      * 1998-03-14 ORIG    R.KOWALSKI  INITIAL VERSION                 *
      * 2003-07-22 LS0057  T.ABERNATHY ZERO-RATE PROMO LOANS           *
      * 2011-02-09 LS0098  M.OYELARAN  EARLY-PAYOFF STOP AND FINAL     *
      *                                PAYMENT ADJUSTMENT              *
      * 2026-10-28 LS0142  LS MAINT    NO SOURCE CHANGE.  THE PRECISION*
      *                                FIX IS IN PAYCALC, WHICH IS     *
      *                                CALLED DYNAMICALLY, SO THE NEW  *
      *                                LOAD MODULE IS PICKED UP FROM   *
      *                                STEPLIB.  REGRESSION TESTED.    *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER.   IBM-Z15.
       OBJECT-COMPUTER.   IBM-Z15.

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *----------------------------------------------------------------*
      * ON Z/OS THESE ARE QSAM DATASETS (RECFM=FB).  UNDER GNUCOBOL    *
      * THE BUILD DEFINES GNUCOBOL SO THE TEST FILES CAN BE PLAIN      *
      * TEXT (ONE RECORD PER LINE).  THE DDNAME IS MAPPED TO A PATH BY *
      * ENVIRONMENT VARIABLE DD_LOANIN, DD_AMORTOUT AND DD_LOANRPT.    *
      *----------------------------------------------------------------*
           SELECT LOAN-IN-FILE     ASSIGN TO LOANIN
      >>IF GNUCOBOL IS DEFINED
                                   ORGANIZATION IS LINE SEQUENTIAL
      >>END-IF
                                   FILE STATUS IS WS-LOANIN-STATUS.

           SELECT AMORT-OUT-FILE   ASSIGN TO AMORTOUT
      >>IF GNUCOBOL IS DEFINED
                                   ORGANIZATION IS LINE SEQUENTIAL
      >>END-IF
                                   FILE STATUS IS WS-AMORTOUT-STATUS.

           SELECT LOAN-RPT-FILE    ASSIGN TO LOANRPT
      >>IF GNUCOBOL IS DEFINED
                                   ORGANIZATION IS LINE SEQUENTIAL
      >>END-IF
                                   FILE STATUS IS WS-LOANRPT-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  LOAN-IN-FILE
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS
           RECORD CONTAINS 80 CHARACTERS.
       COPY LOANREC REPLACING ==:TAG:== BY ==IN==.

       FD  AMORT-OUT-FILE
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS
           RECORD CONTAINS 80 CHARACTERS.
       COPY AMORTREC REPLACING ==:TAG:== BY ==OUT==.

       FD  LOAN-RPT-FILE
           RECORDING MODE IS F
           BLOCK CONTAINS 0 RECORDS
           RECORD CONTAINS 132 CHARACTERS.
       01  RPT-RECORD                  PIC X(132).

       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-ID               PIC X(8)  VALUE 'LOANCALC'.

      *----------------------------------------------------------------*
      * FILE STATUS AREAS - CHECKED AFTER EVERY OPEN/READ/WRITE/CLOSE  *
      *----------------------------------------------------------------*
       01  WS-FILE-STATUSES.
           05  WS-LOANIN-STATUS        PIC X(2).
               88  LOANIN-OK                     VALUE '00'.
               88  LOANIN-EOF                    VALUE '10'.
           05  WS-AMORTOUT-STATUS      PIC X(2).
               88  AMORTOUT-OK                   VALUE '00'.
           05  WS-LOANRPT-STATUS       PIC X(2).
               88  LOANRPT-OK                    VALUE '00'.

      *----------------------------------------------------------------*
      * SWITCHES                                                       *
      *----------------------------------------------------------------*
       01  WS-SWITCHES.
           05  WS-EOF-SW               PIC X(1)  VALUE 'N'.
               88  END-OF-INPUT                  VALUE 'Y'.
           05  WS-LOAN-STATUS-SW       PIC X(1)  VALUE SPACE.
               88  LOAN-ACCEPTED                 VALUE 'A'.
               88  LOAN-REJECTED                 VALUE 'R'.
           05  WS-FINAL-PERIOD-SW      PIC X(1)  VALUE 'N'.
               88  FINAL-PERIOD                  VALUE 'Y'.
               88  NOT-FINAL-PERIOD              VALUE 'N'.
           05  WS-SCHEDULE-SW          PIC X(1)  VALUE 'N'.
               88  SCHEDULE-IN-PROGRESS          VALUE 'Y'.
               88  NO-SCHEDULE-IN-PROGRESS       VALUE 'N'.

      *----------------------------------------------------------------*
      * REJECT REASON                                                  *
      *----------------------------------------------------------------*
       01  WS-REJECT-INFO.
           05  WS-REJECT-CODE          PIC X(2)  VALUE SPACES.
               88  RJ-LOAN-ID-BLANK              VALUE 'E0'.
               88  RJ-BAD-PRINCIPAL              VALUE 'E1'.
               88  RJ-BAD-RATE                   VALUE 'E2'.
               88  RJ-BAD-TERM                   VALUE 'E3'.
               88  RJ-BAD-DATE                   VALUE 'E4'.
               88  RJ-PAYMENT-OVERFLOW           VALUE 'E5'.
               88  RJ-NEGATIVE-AMORTIZATION      VALUE 'E6'.
               88  RJ-PAYCALC-INPUT              VALUE 'E9'.
           05  WS-REJECT-TEXT          PIC X(40) VALUE SPACES.

      *----------------------------------------------------------------*
      * COUNTERS AND RUN CONTROL TOTALS                                *
      *----------------------------------------------------------------*
       01  WS-COUNTERS.
           05  WS-RECORDS-READ         PIC S9(7)     COMP-3 VALUE 0.
           05  WS-LOANS-ACCEPTED       PIC S9(7)     COMP-3 VALUE 0.
           05  WS-LOANS-REJECTED       PIC S9(7)     COMP-3 VALUE 0.
           05  WS-AMORT-RECS-WRITTEN   PIC S9(9)     COMP-3 VALUE 0.

       01  WS-CONTROL-TOTALS.
           05  WS-CTL-PRINCIPAL        PIC S9(13)V99 COMP-3 VALUE 0.
           05  WS-CTL-INTEREST         PIC S9(13)V99 COMP-3 VALUE 0.
           05  WS-CTL-PAID             PIC S9(13)V99 COMP-3 VALUE 0.

      *----------------------------------------------------------------*
      * PER-LOAN SCHEDULE WORK AREAS                                   *
      * BALANCES ARE WIDER THAN THE PAYMENT SO PAYOFF ARITHMETIC       *
      * (BALANCE + INTEREST) CAN NEVER OVERFLOW.                       *
      *----------------------------------------------------------------*
       01  WS-SCHEDULE-WORK.
           05  WS-PERIOD-NO            PIC S9(3)     COMP-3.
           05  WS-PAYMENTS-MADE        PIC S9(3)     COMP-3.
           05  WS-LEVEL-PAYMENT        PIC S9(9)V99  COMP-3.
           05  WS-BALANCE              PIC S9(11)V99 COMP-3.
           05  WS-PERIOD-INTEREST      PIC S9(9)V99  COMP-3.
           05  WS-PERIOD-PRINCIPAL     PIC S9(11)V99 COMP-3.
           05  WS-PERIOD-PAYMENT       PIC S9(11)V99 COMP-3.
           05  WS-PAYOFF-AMOUNT        PIC S9(11)V99 COMP-3.
           05  WS-LOAN-TOTAL-PAID      PIC S9(11)V99 COMP-3.
           05  WS-LOAN-TOTAL-INTEREST  PIC S9(11)V99 COMP-3.
           05  WS-DUE-DATE.
               10  WS-DUE-YYYY         PIC 9(4).
               10  WS-DUE-MM           PIC 9(2).
           05  WS-DUE-DATE-N REDEFINES WS-DUE-DATE
                                       PIC 9(6).

      *----------------------------------------------------------------*
      * PAYCALC PARAMETER BLOCK - SAME COPYBOOK AS PAYCALC LINKAGE     *
      *----------------------------------------------------------------*
       COPY PAYPARM REPLACING ==:TAG:== BY ==WS-PC==.

       01  WS-PAYCALC-PGM              PIC X(8)  VALUE 'PAYCALC'.

      *----------------------------------------------------------------*
      * RUN DATE AND ABEND MESSAGE                                     *
      *----------------------------------------------------------------*
       01  WS-CURRENT-DATE-DATA.
           05  WS-CURR-YYYY            PIC 9(4).
           05  WS-CURR-MM              PIC 9(2).
           05  WS-CURR-DD              PIC 9(2).
           05  FILLER                  PIC X(13).

       01  WS-ABEND-INFO.
           05  WS-ABEND-PARAGRAPH      PIC X(30) VALUE SPACES.
           05  WS-ABEND-MESSAGE        PIC X(50) VALUE SPACES.
           05  WS-ABEND-STATUS         PIC X(2)  VALUE SPACES.
      *    THE FD RECORD AREA IS UNDEFINED BEFORE THE FIRST READ AND
      *    AFTER END OF FILE, SO THE ABEND ROUTINE REPORTS THIS COPY.
           05  WS-LAST-LOAN-ID         PIC X(10) VALUE '(NONE)'.

      *----------------------------------------------------------------*
      * REPORT CONTROL                                                 *
      *----------------------------------------------------------------*
       01  WS-REPORT-CONTROL.
           05  WS-LINE-COUNT           PIC S9(3)     COMP   VALUE 99.
           05  WS-LINES-PER-PAGE       PIC S9(3)     COMP   VALUE 58.
           05  WS-LINE-SPACING         PIC S9(1)     COMP   VALUE 1.
           05  WS-PAGE-COUNT           PIC S9(5)     COMP-3 VALUE 0.

       01  WS-PRINT-LINE               PIC X(132).

      *----------------------------------------------------------------*
      * REPORT LINES  (132 PRINT POSITIONS)                            *
      *----------------------------------------------------------------*
       01  RPT-HEADING-1.
           05  FILLER                  PIC X(8)  VALUE 'LOANCALC'.
           05  FILLER                  PIC X(12) VALUE '  RUN DATE: '.
           05  RPT-H1-RUN-DATE.
               10  RPT-H1-YYYY         PIC 9(4).
               10  FILLER              PIC X(1)  VALUE '-'.
               10  RPT-H1-MM           PIC 9(2).
               10  FILLER              PIC X(1)  VALUE '-'.
               10  RPT-H1-DD           PIC 9(2).
           05  FILLER                  PIC X(17) VALUE SPACES.
           05  FILLER                  PIC X(44) VALUE
               'LS LOAN SERVICING - AMORTIZATION SCHEDULES  '.
           05  FILLER                  PIC X(30) VALUE SPACES.
           05  FILLER                  PIC X(5)  VALUE 'PAGE '.
           05  RPT-H1-PAGE             PIC ZZ,ZZ9.

       01  RPT-HEADING-2.
           05  FILLER                  PIC X(132) VALUE ALL '='.

       01  RPT-LOAN-LINE-1.
           05  FILLER                  PIC X(9)  VALUE 'LOAN ID: '.
           05  RPT-L1-LOAN-ID          PIC X(10).
           05  FILLER                  PIC X(13) VALUE
               '   BORROWER: '.
           05  RPT-L1-BORROWER         PIC X(30).
           05  FILLER                  PIC X(9)  VALUE '   TYPE: '.
           05  RPT-L1-TYPE             PIC X(12).
           05  FILLER                  PIC X(49) VALUE SPACES.

       01  RPT-LOAN-LINE-2.
           05  FILLER                  PIC X(11) VALUE 'PRINCIPAL: '.
           05  RPT-L2-PRINCIPAL        PIC ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(9)  VALUE '   RATE: '.
           05  RPT-L2-RATE             PIC Z9.9999.
           05  FILLER                  PIC X(10) VALUE '%   TERM: '.
           05  RPT-L2-TERM             PIC ZZ9.
           05  FILLER                  PIC X(18) VALUE
               ' MONTHS   1ST DUE '.
           05  RPT-L2-FIRST-YYYY       PIC 9(4).
           05  FILLER                  PIC X(1)  VALUE '-'.
           05  RPT-L2-FIRST-MM         PIC 9(2).
           05  FILLER                  PIC X(21) VALUE
               '   MONTHLY PAYMENT:  '.
           05  RPT-L2-PAYMENT          PIC ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(18) VALUE SPACES.

       01  RPT-COLUMN-HEADING-1.
           05  FILLER                  PIC X(4)  VALUE SPACES.
           05  FILLER                  PIC X(3)  VALUE 'PMT'.
           05  FILLER                  PIC X(5)  VALUE SPACES.
           05  FILLER                  PIC X(7)  VALUE '  DUE  '.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE
               '            PAYMENT'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE
               '           INTEREST'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE
               '          PRINCIPAL'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE
               '            BALANCE'.
           05  FILLER                  PIC X(25) VALUE SPACES.

       01  RPT-COLUMN-HEADING-2.
           05  FILLER                  PIC X(4)  VALUE SPACES.
           05  FILLER                  PIC X(3)  VALUE '---'.
           05  FILLER                  PIC X(5)  VALUE SPACES.
           05  FILLER                  PIC X(7)  VALUE '-------'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE ALL '-'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE ALL '-'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE ALL '-'.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  FILLER                  PIC X(19) VALUE ALL '-'.
           05  FILLER                  PIC X(25) VALUE SPACES.

       01  RPT-DETAIL-LINE.
           05  FILLER                  PIC X(4)  VALUE SPACES.
           05  RPT-DTL-PERIOD          PIC ZZ9.
           05  FILLER                  PIC X(5)  VALUE SPACES.
           05  RPT-DTL-DUE-YYYY        PIC 9(4).
           05  FILLER                  PIC X(1)  VALUE '-'.
           05  RPT-DTL-DUE-MM          PIC 9(2).
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-DTL-PAYMENT         PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-DTL-INTEREST        PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-DTL-PRINCIPAL       PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-DTL-BALANCE         PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-DTL-NOTE            PIC X(22).

       01  RPT-LOAN-TOTAL-LINE.
           05  FILLER                  PIC X(4)  VALUE SPACES.
           05  FILLER                  PIC X(15) VALUE
               'LOAN TOTALS    '.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-TOT-PAID            PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-TOT-INTEREST        PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-TOT-PRINCIPAL       PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-TOT-BALANCE         PIC ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-TOT-PAYMENTS        PIC ZZ9.
           05  FILLER                  PIC X(19) VALUE
               ' PAYMENTS          '.

       01  RPT-REJECT-LINE.
           05  FILLER                  PIC X(19) VALUE
               '*** REJECTED ***   '.
           05  FILLER                  PIC X(9)  VALUE 'LOAN ID: '.
           05  RPT-RJ-LOAN-ID          PIC X(10).
           05  FILLER                  PIC X(3)  VALUE SPACES.
           05  RPT-RJ-BORROWER         PIC X(30).
           05  FILLER                  PIC X(10) VALUE '   REASON '.
           05  RPT-RJ-CODE             PIC X(2).
           05  FILLER                  PIC X(2)  VALUE ': '.
           05  RPT-RJ-TEXT             PIC X(40).
           05  FILLER                  PIC X(7)  VALUE SPACES.

       01  RPT-CONTINUED-LINE.
           05  FILLER                  PIC X(9)  VALUE 'LOAN ID: '.
           05  RPT-CN-LOAN-ID          PIC X(10).
           05  FILLER                  PIC X(113) VALUE
               '   (CONTINUED)'.

       01  RPT-CONTROL-HEADING.
           05  FILLER                  PIC X(40) VALUE
               'RUN CONTROL TOTALS'.
           05  FILLER                  PIC X(92) VALUE SPACES.

       01  RPT-CONTROL-COUNT-LINE.
           05  RPT-CC-LABEL            PIC X(40).
           05  RPT-CC-COUNT            PIC ZZZ,ZZZ,ZZ9.
           05  FILLER                  PIC X(81) VALUE SPACES.

       01  RPT-CONTROL-AMOUNT-LINE.
           05  RPT-CA-LABEL            PIC X(40).
           05  RPT-CA-AMOUNT           PIC Z,ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(71) VALUE SPACES.

       PROCEDURE DIVISION.
      *================================================================*
       0000-MAINLINE.
      *================================================================*
           PERFORM 1000-INITIALIZE

           PERFORM 2000-PROCESS-LOAN
               UNTIL END-OF-INPUT

           PERFORM 9000-TERMINATE

           GOBACK.

      *================================================================*
      * INITIALIZATION                                                 *
      *================================================================*
       1000-INITIALIZE.
           MOVE FUNCTION CURRENT-DATE  TO WS-CURRENT-DATE-DATA
           MOVE WS-CURR-YYYY           TO RPT-H1-YYYY
           MOVE WS-CURR-MM             TO RPT-H1-MM
           MOVE WS-CURR-DD             TO RPT-H1-DD

           DISPLAY 'LOANCALC - LOAN AMORTIZATION BATCH STARTED  '
                   RPT-H1-RUN-DATE

           PERFORM 1100-OPEN-FILES
           PERFORM 8000-READ-LOAN-RECORD.

       1100-OPEN-FILES.
           OPEN INPUT LOAN-IN-FILE
           IF NOT LOANIN-OK
               MOVE '1100-OPEN-FILES'  TO WS-ABEND-PARAGRAPH
               MOVE 'OPEN FAILED - LOANIN'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-LOANIN-STATUS   TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF

           OPEN OUTPUT AMORT-OUT-FILE
           IF NOT AMORTOUT-OK
               MOVE '1100-OPEN-FILES'  TO WS-ABEND-PARAGRAPH
               MOVE 'OPEN FAILED - AMORTOUT'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-AMORTOUT-STATUS TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF

           OPEN OUTPUT LOAN-RPT-FILE
           IF NOT LOANRPT-OK
               MOVE '1100-OPEN-FILES'  TO WS-ABEND-PARAGRAPH
               MOVE 'OPEN FAILED - LOANRPT'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-LOANRPT-STATUS  TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF.

      *================================================================*
      * ONE LOAN: EDIT -> PAYMENT -> SCHEDULE (OR REJECT) -> NEXT      *
      *================================================================*
       2000-PROCESS-LOAN.
           ADD 1                       TO WS-RECORDS-READ
           MOVE IN-LOAN-ID             TO WS-LAST-LOAN-ID
           SET LOAN-ACCEPTED           TO TRUE
           MOVE SPACES                 TO WS-REJECT-CODE
                                          WS-REJECT-TEXT

           PERFORM 2100-VALIDATE-LOAN

           IF LOAN-ACCEPTED
               PERFORM 2200-CALCULATE-PAYMENT
           END-IF

           IF LOAN-ACCEPTED
               PERFORM 2300-BUILD-SCHEDULE
           ELSE
               PERFORM 2900-REJECT-LOAN
           END-IF

           PERFORM 8000-READ-LOAN-RECORD.

      *----------------------------------------------------------------*
      * RECORD EDITS - FIRST FAILURE WINS                              *
      *----------------------------------------------------------------*
       2100-VALIDATE-LOAN.
           EVALUATE TRUE
               WHEN IN-LOAN-ID = SPACES
                   SET RJ-LOAN-ID-BLANK  TO TRUE
                   MOVE 'LOAN ID IS BLANK'
                                       TO WS-REJECT-TEXT
               WHEN IN-PRINCIPAL NOT NUMERIC
                   SET RJ-BAD-PRINCIPAL  TO TRUE
                   MOVE 'PRINCIPAL IS NOT NUMERIC'
                                       TO WS-REJECT-TEXT
               WHEN IN-PRINCIPAL = ZERO
                   SET RJ-BAD-PRINCIPAL  TO TRUE
                   MOVE 'PRINCIPAL IS ZERO'
                                       TO WS-REJECT-TEXT
               WHEN IN-ANNUAL-RATE NOT NUMERIC
               WHEN IN-ANNUAL-RATE > 36
                   SET RJ-BAD-RATE       TO TRUE
                   MOVE 'ANNUAL RATE NOT NUMERIC OR OVER 36%'
                                       TO WS-REJECT-TEXT
               WHEN IN-TERM-MONTHS NOT NUMERIC
               WHEN IN-TERM-MONTHS < 1
               WHEN IN-TERM-MONTHS > 480
                   SET RJ-BAD-TERM       TO TRUE
                   MOVE 'TERM MUST BE 001 - 480 MONTHS'
                                       TO WS-REJECT-TEXT
               WHEN IN-FIRST-PAY-DATE NOT NUMERIC
               WHEN IN-FIRST-PAY-MM < 1
               WHEN IN-FIRST-PAY-MM > 12
                   SET RJ-BAD-DATE       TO TRUE
                   MOVE 'FIRST PAYMENT DATE INVALID (YYYYMM)'
                                       TO WS-REJECT-TEXT
               WHEN OTHER
                   CONTINUE
           END-EVALUATE

           IF WS-REJECT-CODE NOT = SPACES
               SET LOAN-REJECTED       TO TRUE
           END-IF.

      *----------------------------------------------------------------*
      * LEVEL PAYMENT FROM PAYCALC, THEN THE AMORTIZATION GUARD        *
      *----------------------------------------------------------------*
       2200-CALCULATE-PAYMENT.
           MOVE IN-PRINCIPAL           TO WS-PC-PRINCIPAL
           MOVE IN-ANNUAL-RATE         TO WS-PC-ANNUAL-RATE
           MOVE IN-TERM-MONTHS         TO WS-PC-TERM-MONTHS

           CALL WS-PAYCALC-PGM USING WS-PC-PARMS

           EVALUATE TRUE
               WHEN WS-PC-RC-OK
                   MOVE WS-PC-MONTHLY-PAYMENT
                                       TO WS-LEVEL-PAYMENT
               WHEN WS-PC-RC-SIZE-ERROR
                   SET RJ-PAYMENT-OVERFLOW TO TRUE
                   MOVE WS-PC-RETURN-MSG TO WS-REJECT-TEXT
                   SET LOAN-REJECTED   TO TRUE
               WHEN OTHER
                   SET RJ-PAYCALC-INPUT TO TRUE
                   MOVE WS-PC-RETURN-MSG TO WS-REJECT-TEXT
                   SET LOAN-REJECTED   TO TRUE
           END-EVALUATE

      *    A PAYMENT THAT DOES NOT EXCEED THE FIRST MONTH'S INTEREST
      *    NEVER REDUCES THE BALANCE (NEGATIVE AMORTIZATION) - E.G. A
      *    PRINCIPAL SO SMALL THE PAYMENT ROUNDS TO 0.00.  NOT A
      *    PRODUCT THIS SYSTEM SERVICES, SO REJECT IT.
           IF LOAN-ACCEPTED AND IN-TERM-MONTHS > 1
               COMPUTE WS-PERIOD-INTEREST ROUNDED =
                       IN-PRINCIPAL * IN-ANNUAL-RATE / 1200
                   ON SIZE ERROR
                       MOVE '2200-CALCULATE-PAYMENT'
                                       TO WS-ABEND-PARAGRAPH
                       MOVE 'SIZE ERROR ON FIRST-PERIOD INTEREST'
                                       TO WS-ABEND-MESSAGE
                       PERFORM 9900-ABEND
               END-COMPUTE
               IF WS-LEVEL-PAYMENT NOT > WS-PERIOD-INTEREST
                   SET RJ-NEGATIVE-AMORTIZATION TO TRUE
                   MOVE 'PAYMENT DOES NOT COVER INTEREST'
                                       TO WS-REJECT-TEXT
                   SET LOAN-REJECTED   TO TRUE
               END-IF
           END-IF.

      *----------------------------------------------------------------*
      * FULL SCHEDULE FOR AN ACCEPTED LOAN                             *
      *----------------------------------------------------------------*
       2300-BUILD-SCHEDULE.
           ADD 1                       TO WS-LOANS-ACCEPTED
           MOVE IN-PRINCIPAL           TO WS-BALANCE
           MOVE ZERO                   TO WS-PAYMENTS-MADE
                                          WS-LOAN-TOTAL-PAID
                                          WS-LOAN-TOTAL-INTEREST
           MOVE IN-FIRST-PAY-DATE      TO WS-DUE-DATE
           SET NOT-FINAL-PERIOD        TO TRUE

           PERFORM 2310-WRITE-HEADER-RECORD
           PERFORM 7300-PRINT-LOAN-HEADING
           SET SCHEDULE-IN-PROGRESS    TO TRUE

           PERFORM 2320-PROCESS-PERIOD
               VARYING WS-PERIOD-NO FROM 1 BY 1
                 UNTIL FINAL-PERIOD

           SET NO-SCHEDULE-IN-PROGRESS TO TRUE
           PERFORM 2350-WRITE-TRAILER-RECORD
           PERFORM 7500-PRINT-LOAN-TOTALS

           ADD IN-PRINCIPAL            TO WS-CTL-PRINCIPAL
           ADD WS-LOAN-TOTAL-INTEREST  TO WS-CTL-INTEREST
           ADD WS-LOAN-TOTAL-PAID      TO WS-CTL-PAID.

       2310-WRITE-HEADER-RECORD.
           MOVE SPACES                 TO OUT-AMORT-RECORD
           SET OUT-REC-HEADER          TO TRUE
           MOVE IN-LOAN-ID             TO OUT-LOAN-ID
           MOVE IN-PRINCIPAL           TO OUT-HDR-PRINCIPAL
           MOVE IN-ANNUAL-RATE         TO OUT-HDR-ANNUAL-RATE
           MOVE IN-TERM-MONTHS         TO OUT-HDR-TERM-MONTHS
           MOVE WS-LEVEL-PAYMENT       TO OUT-HDR-PAYMENT
           SET OUT-HDR-ACCEPTED        TO TRUE
           MOVE SPACES                 TO OUT-HDR-REASON
           PERFORM 8100-WRITE-AMORT-RECORD.

      *----------------------------------------------------------------*
      * ONE PAYMENT PERIOD                                             *
      *   INTEREST IS COMPUTED FROM THE ANNUAL RATE IN ONE COMPUTE SO  *
      *   NO PRE-ROUNDED MONTHLY RATE CAN BIAS THE CENT ROUNDING.      *
      *   LAST PERIOD (OR EARLY PAYOFF): PAY BALANCE + INTEREST.       *
      *----------------------------------------------------------------*
       2320-PROCESS-PERIOD.
           COMPUTE WS-PERIOD-INTEREST ROUNDED =
                   WS-BALANCE * IN-ANNUAL-RATE / 1200
               ON SIZE ERROR
                   MOVE '2320-PROCESS-PERIOD'
                                       TO WS-ABEND-PARAGRAPH
                   MOVE 'SIZE ERROR ON PERIOD INTEREST'
                                       TO WS-ABEND-MESSAGE
                   PERFORM 9900-ABEND
           END-COMPUTE

           COMPUTE WS-PAYOFF-AMOUNT = WS-BALANCE + WS-PERIOD-INTEREST

           IF WS-PERIOD-NO = IN-TERM-MONTHS
           OR WS-PAYOFF-AMOUNT NOT > WS-LEVEL-PAYMENT
      *        LS0098 - FINAL PAYMENT ADJUSTED SO BALANCE ENDS AT 0.00
               SET FINAL-PERIOD        TO TRUE
               MOVE WS-PAYOFF-AMOUNT   TO WS-PERIOD-PAYMENT
               MOVE WS-BALANCE         TO WS-PERIOD-PRINCIPAL
           ELSE
               MOVE WS-LEVEL-PAYMENT   TO WS-PERIOD-PAYMENT
               COMPUTE WS-PERIOD-PRINCIPAL =
                       WS-LEVEL-PAYMENT - WS-PERIOD-INTEREST
           END-IF

           SUBTRACT WS-PERIOD-PRINCIPAL FROM WS-BALANCE
           ADD 1                       TO WS-PAYMENTS-MADE
           ADD WS-PERIOD-PAYMENT       TO WS-LOAN-TOTAL-PAID
           ADD WS-PERIOD-INTEREST      TO WS-LOAN-TOTAL-INTEREST

           PERFORM 2330-WRITE-DETAIL-RECORD
           PERFORM 7400-PRINT-DETAIL-LINE
           PERFORM 2340-ADVANCE-DUE-DATE.

       2330-WRITE-DETAIL-RECORD.
           MOVE SPACES                 TO OUT-AMORT-RECORD
           SET OUT-REC-DETAIL          TO TRUE
           MOVE IN-LOAN-ID             TO OUT-LOAN-ID
           MOVE WS-PERIOD-NO           TO OUT-DTL-PERIOD
           MOVE WS-DUE-DATE-N          TO OUT-DTL-PAY-DATE
           MOVE WS-PERIOD-PAYMENT      TO OUT-DTL-PAYMENT
           MOVE WS-PERIOD-INTEREST     TO OUT-DTL-INTEREST
           MOVE WS-PERIOD-PRINCIPAL    TO OUT-DTL-PRINCIPAL
           MOVE WS-BALANCE             TO OUT-DTL-BALANCE
           PERFORM 8100-WRITE-AMORT-RECORD.

       2340-ADVANCE-DUE-DATE.
           IF WS-DUE-MM = 12
               MOVE 1                  TO WS-DUE-MM
               ADD 1                   TO WS-DUE-YYYY
           ELSE
               ADD 1                   TO WS-DUE-MM
           END-IF.

       2350-WRITE-TRAILER-RECORD.
           MOVE SPACES                 TO OUT-AMORT-RECORD
           SET OUT-REC-TRAILER         TO TRUE
           MOVE IN-LOAN-ID             TO OUT-LOAN-ID
           MOVE WS-PAYMENTS-MADE       TO OUT-TRL-PAYMENTS-MADE
           MOVE WS-PERIOD-PAYMENT      TO OUT-TRL-FINAL-PAYMENT
           MOVE WS-LOAN-TOTAL-PAID     TO OUT-TRL-TOTAL-PAID
           MOVE WS-LOAN-TOTAL-INTEREST TO OUT-TRL-TOTAL-INTEREST
           MOVE WS-BALANCE             TO OUT-TRL-END-BALANCE
           PERFORM 8100-WRITE-AMORT-RECORD.

      *----------------------------------------------------------------*
      * REJECTED LOAN - HEADER RECORD WITH STATUS 'RJ' + REPORT LINE   *
      *----------------------------------------------------------------*
       2900-REJECT-LOAN.
           ADD 1                       TO WS-LOANS-REJECTED

           MOVE SPACES                 TO OUT-AMORT-RECORD
           SET OUT-REC-HEADER          TO TRUE
           MOVE IN-LOAN-ID             TO OUT-LOAN-ID
           MOVE ZERO                   TO OUT-HDR-PRINCIPAL
                                          OUT-HDR-ANNUAL-RATE
                                          OUT-HDR-TERM-MONTHS
                                          OUT-HDR-PAYMENT
           IF IN-PRINCIPAL IS NUMERIC
               MOVE IN-PRINCIPAL       TO OUT-HDR-PRINCIPAL
           END-IF
           SET OUT-HDR-REJECTED        TO TRUE
           MOVE WS-REJECT-CODE         TO OUT-HDR-REASON
           PERFORM 8100-WRITE-AMORT-RECORD

           MOVE IN-LOAN-ID             TO RPT-RJ-LOAN-ID
           MOVE IN-BORROWER-NAME       TO RPT-RJ-BORROWER
           MOVE WS-REJECT-CODE         TO RPT-RJ-CODE
           MOVE WS-REJECT-TEXT         TO RPT-RJ-TEXT
           MOVE RPT-REJECT-LINE        TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE

           DISPLAY 'LOANCALC - REJECTED ' IN-LOAN-ID
                   ' ' WS-REJECT-CODE ' ' WS-REJECT-TEXT.

      *================================================================*
      * REPORT WRITING                                                 *
      *================================================================*
       7000-PRINT-LINE.
           IF WS-LINE-COUNT + WS-LINE-SPACING > WS-LINES-PER-PAGE
               PERFORM 7100-PRINT-PAGE-HEADINGS
           END-IF

           WRITE RPT-RECORD FROM WS-PRINT-LINE
               AFTER ADVANCING WS-LINE-SPACING LINES
           IF NOT LOANRPT-OK
               MOVE '7000-PRINT-LINE'  TO WS-ABEND-PARAGRAPH
               MOVE 'WRITE FAILED - LOANRPT'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-LOANRPT-STATUS  TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF

           ADD WS-LINE-SPACING         TO WS-LINE-COUNT
           MOVE 1                      TO WS-LINE-SPACING.

       7100-PRINT-PAGE-HEADINGS.
           ADD 1                       TO WS-PAGE-COUNT
           MOVE WS-PAGE-COUNT          TO RPT-H1-PAGE

      >>IF GNUCOBOL IS DEFINED
      *    LINE SEQUENTIAL WRITES 'AFTER ADVANCING' AS NEWLINES BEFORE
      *    THE DATA, SO A FORM FEED WOULD BE GLUED TO THE END OF THE
      *    PREVIOUS LINE.  END THAT LINE FIRST.  (ON Z/OS THE ASA
      *    CARRIAGE CONTROL BYTE HANDLES THIS - NOT NEEDED THERE.)
           IF WS-PAGE-COUNT > 1
               WRITE RPT-RECORD FROM SPACES
                   AFTER ADVANCING 1 LINE
               PERFORM 7110-CHECK-RPT-WRITE
           END-IF
      >>END-IF

           WRITE RPT-RECORD FROM RPT-HEADING-1
               AFTER ADVANCING PAGE
           PERFORM 7110-CHECK-RPT-WRITE
           WRITE RPT-RECORD FROM RPT-HEADING-2
               AFTER ADVANCING 1 LINE
           PERFORM 7110-CHECK-RPT-WRITE
           MOVE 2                      TO WS-LINE-COUNT

      *    A SCHEDULE THAT SPILLS ONTO A NEW PAGE GETS ITS LOAN ID AND
      *    COLUMN HEADINGS REPEATED.
           IF SCHEDULE-IN-PROGRESS
               MOVE IN-LOAN-ID         TO RPT-CN-LOAN-ID
               WRITE RPT-RECORD FROM RPT-CONTINUED-LINE
                   AFTER ADVANCING 2 LINES
               PERFORM 7110-CHECK-RPT-WRITE
               WRITE RPT-RECORD FROM RPT-COLUMN-HEADING-1
                   AFTER ADVANCING 2 LINES
               PERFORM 7110-CHECK-RPT-WRITE
               WRITE RPT-RECORD FROM RPT-COLUMN-HEADING-2
                   AFTER ADVANCING 1 LINE
               PERFORM 7110-CHECK-RPT-WRITE
               ADD 5                   TO WS-LINE-COUNT
               MOVE 1                  TO WS-LINE-SPACING
           END-IF.

       7110-CHECK-RPT-WRITE.
           IF NOT LOANRPT-OK
               MOVE '7100-PRINT-PAGE-HEADINGS'
                                       TO WS-ABEND-PARAGRAPH
               MOVE 'WRITE FAILED - LOANRPT'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-LOANRPT-STATUS  TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF.

       7300-PRINT-LOAN-HEADING.
      *    KEEP THE LOAN HEADING, COLUMN HEADINGS AND FIRST DETAIL
      *    LINE TOGETHER - START A NEW PAGE IF FEWER THAN 8 LINES LEFT.
           IF WS-LINE-COUNT + 8 > WS-LINES-PER-PAGE
               PERFORM 7100-PRINT-PAGE-HEADINGS
           END-IF

           MOVE IN-LOAN-ID             TO RPT-L1-LOAN-ID
           MOVE IN-BORROWER-NAME       TO RPT-L1-BORROWER
           EVALUATE TRUE
               WHEN IN-TYPE-MORTGAGE
                   MOVE 'MORTGAGE'     TO RPT-L1-TYPE
               WHEN IN-TYPE-AUTO
                   MOVE 'AUTO'         TO RPT-L1-TYPE
               WHEN IN-TYPE-PERSONAL
                   MOVE 'PERSONAL'     TO RPT-L1-TYPE
               WHEN IN-TYPE-COMMERCIAL
                   MOVE 'COMMERCIAL'   TO RPT-L1-TYPE
               WHEN OTHER
                   MOVE 'UNKNOWN'      TO RPT-L1-TYPE
           END-EVALUATE
           MOVE RPT-LOAN-LINE-1        TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE

           MOVE IN-PRINCIPAL           TO RPT-L2-PRINCIPAL
           MOVE IN-ANNUAL-RATE         TO RPT-L2-RATE
           MOVE IN-TERM-MONTHS         TO RPT-L2-TERM
           MOVE IN-FIRST-PAY-YYYY      TO RPT-L2-FIRST-YYYY
           MOVE IN-FIRST-PAY-MM        TO RPT-L2-FIRST-MM
           MOVE WS-LEVEL-PAYMENT       TO RPT-L2-PAYMENT
           MOVE RPT-LOAN-LINE-2        TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE

           MOVE RPT-COLUMN-HEADING-1   TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE
           MOVE RPT-COLUMN-HEADING-2   TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE.

       7400-PRINT-DETAIL-LINE.
           MOVE WS-PERIOD-NO           TO RPT-DTL-PERIOD
           MOVE WS-DUE-YYYY            TO RPT-DTL-DUE-YYYY
           MOVE WS-DUE-MM              TO RPT-DTL-DUE-MM
           MOVE WS-PERIOD-PAYMENT      TO RPT-DTL-PAYMENT
           MOVE WS-PERIOD-INTEREST     TO RPT-DTL-INTEREST
           MOVE WS-PERIOD-PRINCIPAL    TO RPT-DTL-PRINCIPAL
           MOVE WS-BALANCE             TO RPT-DTL-BALANCE

           EVALUATE TRUE
               WHEN NOT-FINAL-PERIOD
                   MOVE SPACES         TO RPT-DTL-NOTE
               WHEN WS-PERIOD-NO < IN-TERM-MONTHS
                   MOVE '<- PAID OFF EARLY'
                                       TO RPT-DTL-NOTE
               WHEN WS-PERIOD-PAYMENT NOT = WS-LEVEL-PAYMENT
                   MOVE '<- FINAL (ADJUSTED)'
                                       TO RPT-DTL-NOTE
               WHEN OTHER
                   MOVE '<- FINAL'     TO RPT-DTL-NOTE
           END-EVALUATE

           MOVE RPT-DETAIL-LINE        TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE.

       7500-PRINT-LOAN-TOTALS.
           MOVE WS-LOAN-TOTAL-PAID     TO RPT-TOT-PAID
           MOVE WS-LOAN-TOTAL-INTEREST TO RPT-TOT-INTEREST
           MOVE IN-PRINCIPAL           TO RPT-TOT-PRINCIPAL
           MOVE WS-BALANCE             TO RPT-TOT-BALANCE
           MOVE WS-PAYMENTS-MADE       TO RPT-TOT-PAYMENTS
           MOVE RPT-LOAN-TOTAL-LINE    TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE.

       7600-PRINT-CONTROL-TOTALS.
           PERFORM 7100-PRINT-PAGE-HEADINGS

           MOVE RPT-CONTROL-HEADING    TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE

           MOVE 'LOAN RECORDS READ ...................'
                                       TO RPT-CC-LABEL
           MOVE WS-RECORDS-READ        TO RPT-CC-COUNT
           MOVE RPT-CONTROL-COUNT-LINE TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE

           MOVE 'LOANS ACCEPTED ......................'
                                       TO RPT-CC-LABEL
           MOVE WS-LOANS-ACCEPTED      TO RPT-CC-COUNT
           MOVE RPT-CONTROL-COUNT-LINE TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE

           MOVE 'LOANS REJECTED ......................'
                                       TO RPT-CC-LABEL
           MOVE WS-LOANS-REJECTED      TO RPT-CC-COUNT
           MOVE RPT-CONTROL-COUNT-LINE TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE

           MOVE 'AMORTIZATION RECORDS WRITTEN ........'
                                       TO RPT-CC-LABEL
           MOVE WS-AMORT-RECS-WRITTEN  TO RPT-CC-COUNT
           MOVE RPT-CONTROL-COUNT-LINE TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE

           MOVE 'TOTAL PRINCIPAL SCHEDULED ...........'
                                       TO RPT-CA-LABEL
           MOVE WS-CTL-PRINCIPAL       TO RPT-CA-AMOUNT
           MOVE RPT-CONTROL-AMOUNT-LINE
                                       TO WS-PRINT-LINE
           MOVE 2                      TO WS-LINE-SPACING
           PERFORM 7000-PRINT-LINE

           MOVE 'TOTAL INTEREST SCHEDULED ............'
                                       TO RPT-CA-LABEL
           MOVE WS-CTL-INTEREST        TO RPT-CA-AMOUNT
           MOVE RPT-CONTROL-AMOUNT-LINE
                                       TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE

           MOVE 'TOTAL PAYMENTS SCHEDULED ............'
                                       TO RPT-CA-LABEL
           MOVE WS-CTL-PAID            TO RPT-CA-AMOUNT
           MOVE RPT-CONTROL-AMOUNT-LINE
                                       TO WS-PRINT-LINE
           PERFORM 7000-PRINT-LINE.

      *================================================================*
      * FILE I/O                                                       *
      *================================================================*
       8000-READ-LOAN-RECORD.
           READ LOAN-IN-FILE
               AT END
                   SET END-OF-INPUT    TO TRUE
           END-READ

           IF NOT LOANIN-OK AND NOT LOANIN-EOF
               MOVE '8000-READ-LOAN-RECORD'
                                       TO WS-ABEND-PARAGRAPH
               MOVE 'READ FAILED - LOANIN'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-LOANIN-STATUS   TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF.

       8100-WRITE-AMORT-RECORD.
           WRITE OUT-AMORT-RECORD
           IF NOT AMORTOUT-OK
               MOVE '8100-WRITE-AMORT-RECORD'
                                       TO WS-ABEND-PARAGRAPH
               MOVE 'WRITE FAILED - AMORTOUT'
                                       TO WS-ABEND-MESSAGE
               MOVE WS-AMORTOUT-STATUS TO WS-ABEND-STATUS
               PERFORM 9900-ABEND
           END-IF
           ADD 1                       TO WS-AMORT-RECS-WRITTEN.

      *================================================================*
      * END OF JOB                                                     *
      *================================================================*
       9000-TERMINATE.
           PERFORM 7600-PRINT-CONTROL-TOTALS
           PERFORM 9100-CLOSE-FILES

           DISPLAY 'LOANCALC - RECORDS READ    : ' WS-RECORDS-READ
           DISPLAY 'LOANCALC - LOANS ACCEPTED  : ' WS-LOANS-ACCEPTED
           DISPLAY 'LOANCALC - LOANS REJECTED  : ' WS-LOANS-REJECTED
           DISPLAY 'LOANCALC - AMORTOUT RECORDS: '
                   WS-AMORT-RECS-WRITTEN

           IF WS-LOANS-REJECTED > ZERO
               MOVE 4                  TO RETURN-CODE
           ELSE
               MOVE 0                  TO RETURN-CODE
           END-IF

           DISPLAY 'LOANCALC - ENDED, RETURN CODE ' RETURN-CODE.

       9100-CLOSE-FILES.
           CLOSE LOAN-IN-FILE
           IF NOT LOANIN-OK
               DISPLAY 'LOANCALC - CLOSE FAILED - LOANIN  STATUS '
                       WS-LOANIN-STATUS
               MOVE 16                 TO RETURN-CODE
           END-IF

           CLOSE AMORT-OUT-FILE
           IF NOT AMORTOUT-OK
               DISPLAY 'LOANCALC - CLOSE FAILED - AMORTOUT STATUS '
                       WS-AMORTOUT-STATUS
               MOVE 16                 TO RETURN-CODE
           END-IF

           CLOSE LOAN-RPT-FILE
           IF NOT LOANRPT-OK
               DISPLAY 'LOANCALC - CLOSE FAILED - LOANRPT  STATUS '
                       WS-LOANRPT-STATUS
               MOVE 16                 TO RETURN-CODE
           END-IF

           IF RETURN-CODE = 16
               MOVE '9100-CLOSE-FILES' TO WS-ABEND-PARAGRAPH
               MOVE 'ONE OR MORE FILES FAILED TO CLOSE'
                                       TO WS-ABEND-MESSAGE
               PERFORM 9900-ABEND
           END-IF.

      *================================================================*
      * CONTROLLED ABEND: REPORT WHERE AND WHY, END WITH RC 16.        *
      * (A Z/OS SHOP WOULD TYPICALLY CALL CEE3ABD HERE FOR A U-ABEND.) *
      *================================================================*
       9900-ABEND.
           DISPLAY '**************************************************'
           DISPLAY 'LOANCALC - ABNORMAL TERMINATION'
           DISPLAY '  PARAGRAPH  : ' WS-ABEND-PARAGRAPH
           DISPLAY '  REASON     : ' WS-ABEND-MESSAGE
           DISPLAY '  FILE STATUS: ' WS-ABEND-STATUS
           DISPLAY '  LAST LOAN  : ' WS-LAST-LOAN-ID
           DISPLAY '  RECORDS READ ' WS-RECORDS-READ
           DISPLAY '**************************************************'
           MOVE 16                     TO RETURN-CODE
           STOP RUN.
