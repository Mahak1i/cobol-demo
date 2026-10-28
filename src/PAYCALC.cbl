       IDENTIFICATION DIVISION.
       PROGRAM-ID.    PAYCALC.
      *================================================================*
      * PROGRAM   : PAYCALC                                            *
      * TITLE     : LEVEL MONTHLY PAYMENT CALCULATION                  *
      * SYSTEM    : LS - LOAN SERVICING BATCH                          *
      * TYPE      : CALLED SUBPROGRAM                                  *
      * CALLED BY : LOANCALC                                           *
      *                                                                *
      * FORMULA   :            P * R * (1 + R) ** N                    *
      *             PAYMENT = ----------------------                   *
      *                          (1 + R) ** N  -  1                    *
      *                                                                *
      *             R = ANNUAL RATE / 12 / 100    N = TERM IN MONTHS   *
      *             WHEN R = 0 THE PAYMENT IS SIMPLY P / N.            *
      *                                                                *
      * PRECISION : INTERMEDIATES ARE COMP-3 WITH 16-24 DECIMALS, SO   *
      *             THE UNROUNDED PAYMENT IS GOOD TO BETTER THAN 1E-8  *
      *             FOR EVERY INPUT 1000-VALIDATE-INPUT ACCEPTS.  THE  *
      *             RESULT IS ROUNDED HALF-UP TO THE CENT EXACTLY      *
      *             ONCE, ON THE FINAL COMPUTE.  FIELDS WIDER THAN 18  *
      *             DIGITS NEED ARITH(EXTEND) ON ENTERPRISE COBOL.     *
      *                                                                *
      * RETURN    : LK-RETURN-CODE  00 = OK                            *
      *                             10 = INVALID INPUT                 *
      *                             20 = SIZE ERROR (RESULT TOO LARGE  *
      *                                  FOR A RECEIVING FIELD)        *
      *----------------------------------------------------------------*
      * MAINTENANCE LOG                                                *
      * DATE       CHG-ID  PROGRAMMER  DESCRIPTION                     *
      * ---------- ------- ----------- ------------------------------- *
      * 1998-03-14 ORIG    R.KOWALSKI  INITIAL VERSION                 *
      * 2003-07-22 LS0057  T.ABERNATHY ADD ZERO-RATE PATH FOR PROMO    *
      *                                0% PERSONAL LOANS               *
      * 2026-10-28 LS0142  LS MAINT    PRECISION DEFECTS: PAYMENTS OFF *
      *                                BY 1 CENT TO MILLIONS OF        *
      *                                DOLLARS.                        *
      *                                FIX-1 WIDEN P*R*(1+R)**N FIELD  *
      *                                FIX-2 ADD ROUNDED               *
      *                                FIX-3 WIDEN RATE AND (1+R)**N   *
      *                                FIX-4 ON SIZE ERROR -> RC 20    *
      *                                EVERY CHANGED LINE IS TAGGED    *
      *                                LS0142 IN COLUMNS 73-80.        *
      *                                SEE CHANGELOG.MD FOR DETAIL.    *
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
      *                                                                *
      * SIZING (WORST CASE ACCEPTED BY 1000-VALIDATE-INPUT):           *
      *   P <= 999,999,999.99   R <= 0.03   N <= 480                   *
      *   (1+R)**N <= 1.03**480 = 1.43 MILLION  -> 7 INTEGER DIGITS    *
      *   (1+R)**N - 1 CAN BE AS SMALL AS 1.7E-7 (0.0001%, 2 MONTHS)   *
      *   AND THE DIVIDE MAGNIFIES ANY ERROR IN IT.  ROUNDING (1+R)**N *
      *   AT 18 DECIMALS CAN MOVE THE PAYMENT BY 0.003 - ENOUGH TO     *
      *   FLIP A CENT.  AT 24 DECIMALS THE WORST CASE IS 3E-9.         *
      *   P*R*(1+R)**N <= 4.3E13                -> 14 INTEGER DIGITS   *
      *----------------------------------------------------------------*
       01  WS-CALC-FIELDS.
      * LS0142 FIX-3: RATE WAS V9(6) - 0.0054166.. WAS CUT TO 0.005416
      *               (0.012% LOW, 4% LOW AT A 0.01% PROMO RATE).
      *               18 DECIMALS KEEPS IT EXACT TO 5E-19.
           05  WS-MONTHLY-RATE         PIC S9V9(18)       COMP-3.       LS0142
      * LS0142 FIX-3: (1+R)**N WAS 9(3)V9(6) - LOST ITS HIGH-ORDER
      *               DIGITS ABOVE 999 (LONG TERMS / HIGH RATES) AND
      *               ALL BUT 6 DECIMALS.  NOW 7 INTEGER + 24 DECIMALS.
           05  WS-GROWTH-FACTOR        PIC S9(7)V9(24)    COMP-3.       LS0142
      * LS0142 FIX-1: P*R*(1+R)**N WAS S9(7)V99 - A COPY OF AN OLD
      *               PRINCIPAL PICTURE.  OVERFLOWED SILENTLY ABOVE
      *               9,999,999.99 AND DROPPED EVERY DIGIT PAST THE
      *               CENT BEFORE THE DIVIDE.  NOW 15 + 16 = 31 DIGITS.
           05  WS-PAYMENT-WORK         PIC S9(15)V9(16)   COMP-3.       LS0142

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
      * LS0142 FIX-3: ROUND (NOT TRUNCATE) R AT THE 18TH DECIMAL.
           COMPUTE WS-MONTHLY-RATE ROUNDED = LK-ANNUAL-RATE / 1200      LS0142
      * LS0142 FIX-4: EVERY COMPUTE NOW TRAPS SIZE ERROR.  BEFORE,
      *               AN OVERFLOW SILENTLY DROPPED HIGH-ORDER DIGITS.
               ON SIZE ERROR                                            LS0142
                   PERFORM 9000-SIZE-ERROR                              LS0142
           END-COMPUTE                                                  LS0142

           IF WS-MONTHLY-RATE = ZERO
      *        LS0057 - ZERO-RATE PROMO: STRAIGHT-LINE PRINCIPAL
      * LS0142 FIX-2: WITHOUT ROUNDED THE QUOTIENT WAS TRUNCATED -
      *               10,000.00 / 36 = 277.7777.. WAS BILLED AS 277.77
      *               INSTEAD OF 277.78 (THE SHORTFALL PILED UP ON THE
      *               LAST PAYMENT).
               COMPUTE LK-MONTHLY-PAYMENT ROUNDED =                     LS0142
                       LK-PRINCIPAL / LK-TERM-MONTHS
                   ON SIZE ERROR                                        LS0142
                       PERFORM 9000-SIZE-ERROR                          LS0142
               END-COMPUTE                                              LS0142
           ELSE
      * LS0142 FIX-3: (1+R)**N IS NOW CARRIED TO 24 DECIMALS AND
      *               ROUNDED ONCE, INSTEAD OF TRUNCATED TO 6.
               COMPUTE WS-GROWTH-FACTOR ROUNDED =                       LS0142
                       (1 + WS-MONTHLY-RATE) ** LK-TERM-MONTHS
                   ON SIZE ERROR                                        LS0142
                       PERFORM 9000-SIZE-ERROR                          LS0142
               END-COMPUTE                                              LS0142
      * LS0142 FIX-1: NUMERATOR KEEPS 16 DECIMALS INTO THE DIVIDE.
               COMPUTE WS-PAYMENT-WORK ROUNDED =                        LS0142
                       LK-PRINCIPAL * WS-MONTHLY-RATE
                                    * WS-GROWTH-FACTOR
                   ON SIZE ERROR                                        LS0142
                       PERFORM 9000-SIZE-ERROR                          LS0142
               END-COMPUTE                                              LS0142
      * LS0142 FIX-2: ROUND HALF-UP TO THE CENT - THE ONLY ROUNDING
      *               TO CENTS IN THE WHOLE CALCULATION.
      * LS0142 FIX-4: A PAYMENT TOO BIG FOR PIC S9(9)V99 IS REJECTED
      *               (RC 20) INSTEAD OF LOSING ITS LEADING DIGITS -
      *               1,009,999,999.99 USED TO COME OUT AS 9,999,999.00.
               COMPUTE LK-MONTHLY-PAYMENT ROUNDED =                     LS0142
                       WS-PAYMENT-WORK / (WS-GROWTH-FACTOR - 1)
                   ON SIZE ERROR                                        LS0142
                       PERFORM 9000-SIZE-ERROR                          LS0142
               END-COMPUTE                                              LS0142
           END-IF                                                       LS0142

      * LS0142 FIX-4: ON ANY SIZE ERROR THE CALLER GETS RC 20 AND A
      *               ZERO PAYMENT - NEVER A PARTIAL OR TRUNCATED ONE.
           IF NOT LK-RC-OK                                              LS0142
               MOVE ZERO               TO LK-MONTHLY-PAYMENT            LS0142
           END-IF.                                                      LS0142

      *================================================================*
      * LS0142 FIX-4: A RESULT DID NOT FIT ITS RECEIVING FIELD.        *
      *================================================================*
       9000-SIZE-ERROR.                                                 LS0142
           SET LK-RC-SIZE-ERROR        TO TRUE                          LS0142
           MOVE 'PAYMENT EXCEEDS FIELD CAPACITY'                        LS0142
                                       TO LK-RETURN-MSG.                LS0142
