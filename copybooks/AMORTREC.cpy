      *================================================================*
      * COPYBOOK : AMORTREC                                            *
      * TITLE    : AMORTIZATION OUTPUT RECORD  (LRECL=80, RECFM=FB)    *
      * USED BY  : LOANCALC - FD AMORT-OUT-FILE                        *
      *            DOWNSTREAM BILLING / GL INTERFACE JOBS              *
      *                                                                *
      * USAGE    : COPY AMORTREC REPLACING ==:TAG:== BY ==OUT==.       *
      *                                                                *
      * ONE LOAN PRODUCES:                                             *
      *   'H' HEADER   - TERMS, LEVEL PAYMENT, ACCEPT/REJECT STATUS    *
      *   'D' DETAIL   - ONE PER PAYMENT PERIOD   (ACCEPTED LOANS)     *
      *   'T' TRAILER  - LOAN TOTALS              (ACCEPTED LOANS)     *
      *                                                                *
      * SIGNED AMOUNTS USE SIGN LEADING SEPARATE SO THE FILE IS        *
      * READABLE IN ISPF BROWSE AND BY NON-COBOL CONSUMERS.            *
      *================================================================*
       01  :TAG:-AMORT-RECORD.
           05  :TAG:-REC-TYPE              PIC X(1).
               88  :TAG:-REC-HEADER        VALUE 'H'.
               88  :TAG:-REC-DETAIL        VALUE 'D'.
               88  :TAG:-REC-TRAILER       VALUE 'T'.
           05  :TAG:-LOAN-ID               PIC X(10).
           05  :TAG:-REC-DATA              PIC X(69).
      *----------------------------------------------------------------*
      *    'H' - LOAN HEADER                                           *
      *----------------------------------------------------------------*
           05  :TAG:-HDR-DATA REDEFINES :TAG:-REC-DATA.
               10  :TAG:-HDR-PRINCIPAL     PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-HDR-ANNUAL-RATE   PIC 9(2)V9(4).
               10  :TAG:-HDR-TERM-MONTHS   PIC 9(3).
               10  :TAG:-HDR-PAYMENT       PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-HDR-STATUS        PIC X(2).
                   88  :TAG:-HDR-ACCEPTED  VALUE 'OK'.
                   88  :TAG:-HDR-REJECTED  VALUE 'RJ'.
               10  :TAG:-HDR-REASON        PIC X(2).
               10  FILLER                  PIC X(28).
      *----------------------------------------------------------------*
      *    'D' - ONE PAYMENT PERIOD                                    *
      *----------------------------------------------------------------*
           05  :TAG:-DTL-DATA REDEFINES :TAG:-REC-DATA.
               10  :TAG:-DTL-PERIOD        PIC 9(3).
               10  :TAG:-DTL-PAY-DATE      PIC 9(6).
               10  :TAG:-DTL-PAYMENT       PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-DTL-INTEREST      PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-DTL-PRINCIPAL     PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-DTL-BALANCE       PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  FILLER                  PIC X(4).
      *----------------------------------------------------------------*
      *    'T' - LOAN TOTALS                                           *
      *----------------------------------------------------------------*
           05  :TAG:-TRL-DATA REDEFINES :TAG:-REC-DATA.
               10  :TAG:-TRL-PAYMENTS-MADE PIC 9(3).
               10  :TAG:-TRL-FINAL-PAYMENT PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-TRL-TOTAL-PAID    PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-TRL-TOTAL-INTEREST
                                           PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  :TAG:-TRL-END-BALANCE   PIC S9(11)V99
                                           SIGN LEADING SEPARATE.
               10  FILLER                  PIC X(10).
