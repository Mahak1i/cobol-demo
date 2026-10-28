       IDENTIFICATION DIVISION.
       PROGRAM-ID.    PAYCALC.
      *================================================================*
      * PROGRAM   : PAYCALC                                            *
      * TITLE     : LEVEL MONTHLY PAYMENT CALCULATION                  *
      * SYSTEM    : LS - LOAN SERVICING BATCH                          *
      * TYPE      : CALLED SUBPROGRAM                                  *
      * CALLED BY : LOANCALC                                           *
      *                                                                *
      * *** PRE-FIX VERSION - KEPT FOR THE DEFECT INVESTIGATION. ***   *
      * *** CONTAINS THE PRECISION DEFECTS RAISED IN LS0142.     ***   *
      * *** DO NOT PROMOTE.  SEE ../PAYCALC.CBL FOR THE FIX.     ***   *
      *                                                                *
      * FORMULA   :            P * R * (1 + R) ** N                    *
      *             PAYMENT = ----------------------                   *
      *                          (1 + R) ** N  -  1                    *
      *                                                                *
      *             R = ANNUAL RATE / 12 / 100    N = TERM IN MONTHS   *
      *             WHEN R = 0 THE PAYMENT IS SIMPLY P / N.            *
      *                                                                *
      * RETURN    : LK-RETURN-CODE  00 = OK                            *
      *                             10 = INVALID INPUT                 *
      *----------------------------------------------------------------*
      * MAINTENANCE LOG                                                *
      * DATE       CHG-ID  PROGRAMMER  DESCRIPTION                     *
      * ---------- ------- ----------- ------------------------------- *
      * 1998-03-14 ORIG    R.KOWALSKI  INITIAL VERSION                 *
      * 2003-07-22 LS0057  T.ABERNATHY ADD ZERO-RATE PATH FOR PROMO    *
      *                                0% PERSONAL LOANS               *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER.   IBM-Z15.
       OBJECT-COMPUTER.   IBM-Z15.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-ID               PIC X(8)  VALUE 'PAYCALC'.

      *----------------------------------------------------------------*
      * CALCULATION WORK AREAS                                         *
      *----------------------------------------------------------------*
       01  WS-CALC-FIELDS.
           05  WS-MONTHLY-RATE         PIC V9(6)          COMP-3.
           05  WS-GROWTH-FACTOR        PIC 9(3)V9(6)      COMP-3.
           05  WS-PAYMENT-WORK         PIC S9(7)V99       COMP-3.

       LINKAGE SECTION.
       COPY PAYPARM REPLACING ==:TAG:== BY ==LK==.

       PROCEDURE DIVISION USING LK-PARMS.
      *================================================================*
       0000-MAINLINE.
      *================================================================*
           SET LK-RC-OK                TO TRUE
           MOVE SPACES                 TO LK-RETURN-MSG
           MOVE ZERO                   TO LK-MONTHLY-PAYMENT

           PERFORM 1000-VALIDATE-INPUT

           IF LK-RC-OK
               PERFORM 2000-CALCULATE-PAYMENT
           END-IF

           GOBACK.

      *================================================================*
      * DEFENSIVE EDITS - THE CALLER VALIDATES TOO, BUT THIS MODULE    *
      * MUST NOT TRUST ITS CALLERS.                                    *
      *================================================================*
       1000-VALIDATE-INPUT.
           EVALUATE TRUE
               WHEN LK-PRINCIPAL NOT > ZERO
                   SET LK-RC-INVALID-INPUT TO TRUE
                   MOVE 'PRINCIPAL MUST BE GREATER THAN ZERO'
                                       TO LK-RETURN-MSG
               WHEN LK-ANNUAL-RATE < ZERO
                 OR LK-ANNUAL-RATE > 36
                   SET LK-RC-INVALID-INPUT TO TRUE
                   MOVE 'ANNUAL RATE MUST BE 0 - 36 PERCENT'
                                       TO LK-RETURN-MSG
               WHEN LK-TERM-MONTHS < 1
                 OR LK-TERM-MONTHS > 480
                   SET LK-RC-INVALID-INPUT TO TRUE
                   MOVE 'TERM MUST BE 1 - 480 MONTHS'
                                       TO LK-RETURN-MSG
               WHEN OTHER
                   CONTINUE
           END-EVALUATE.

      *================================================================*
      * LEVEL PAYMENT                                                  *
      *================================================================*
       2000-CALCULATE-PAYMENT.
           COMPUTE WS-MONTHLY-RATE = LK-ANNUAL-RATE / 1200

           IF WS-MONTHLY-RATE = ZERO
      *        LS0057 - ZERO-RATE PROMO: STRAIGHT-LINE PRINCIPAL
               COMPUTE LK-MONTHLY-PAYMENT =
                       LK-PRINCIPAL / LK-TERM-MONTHS
           ELSE
               COMPUTE WS-GROWTH-FACTOR =
                       (1 + WS-MONTHLY-RATE) ** LK-TERM-MONTHS
               COMPUTE WS-PAYMENT-WORK =
                       LK-PRINCIPAL * WS-MONTHLY-RATE
                                    * WS-GROWTH-FACTOR
               COMPUTE LK-MONTHLY-PAYMENT =
                       WS-PAYMENT-WORK / (WS-GROWTH-FACTOR - 1)
           END-IF.
