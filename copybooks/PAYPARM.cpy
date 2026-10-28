      *================================================================*
      * COPYBOOK : PAYPARM                                             *
      * TITLE    : PAYCALC CALL INTERFACE (PARAMETER BLOCK)            *
      * USED BY  : LOANCALC - WORKING-STORAGE  (CALLER)                *
      *            PAYCALC  - LINKAGE SECTION  (CALLED SUBPROGRAM)     *
      *                                                                *
      * USAGE    : LOANCALC  COPY PAYPARM                              *
      *                          REPLACING ==:TAG:== BY ==WS-PC==.     *
      *            PAYCALC   COPY PAYPARM                              *
      *                          REPLACING ==:TAG:== BY ==LK==.        *
      *                                                                *
      * BOTH SIDES COPY THE SAME MEMBER SO THE BYTE LAYOUT CAN NEVER   *
      * DRIFT.  ANY CHANGE HERE REQUIRES A RECOMPILE OF BOTH PROGRAMS. *
      *================================================================*
       01  :TAG:-PARMS.
      *    ---------------- INPUT  (SET BY CALLER) -------------------
           05  :TAG:-PRINCIPAL             PIC S9(9)V99    COMP-3.
           05  :TAG:-ANNUAL-RATE           PIC S9(2)V9(4)  COMP-3.
           05  :TAG:-TERM-MONTHS           PIC S9(3)       COMP-3.
      *    ---------------- OUTPUT (SET BY PAYCALC) ------------------
           05  :TAG:-MONTHLY-PAYMENT       PIC S9(9)V99    COMP-3.
           05  :TAG:-RETURN-CODE           PIC X(2).
               88  :TAG:-RC-OK             VALUE '00'.
               88  :TAG:-RC-INVALID-INPUT  VALUE '10'.
               88  :TAG:-RC-SIZE-ERROR     VALUE '20'.
           05  :TAG:-RETURN-MSG            PIC X(40).
