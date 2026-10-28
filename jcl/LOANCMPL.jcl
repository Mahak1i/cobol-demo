//LOANCMPL JOB (LS,0142),'LS0142 COMPILE',CLASS=A,MSGCLASS=X,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//*********************************************************************
//* JOB      : LOANCMPL                                               *
//* PURPOSE  : COMPILE AND LINK-EDIT THE LOAN AMORTIZATION BATCH      *
//*            (ENTERPRISE COBOL 6.4, IGYWCL CATALOGED PROCEDURE)     *
//*                                                                   *
//*   STEP010  PAYCALC   -> LS.LOADLIB(PAYCALC)  (CALLED, DYNAMIC)    *
//*   STEP020  LOANCALC  -> LS.LOADLIB(LOANCALC) (BATCH MAIN)         *
//*                                                                   *
//* COMPILER OPTIONS                                                  *
//*   ARITH(EXTEND)  REQUIRED - PAYCALC WORK FIELDS ARE UP TO 31      *
//*                  DIGITS (PIC S9(15)V9(16) COMP-3).  THE DEFAULT   *
//*                  ARITH(COMPAT) CAPS NUMERIC ITEMS AT 18 DIGITS.   *
//*   DYNAM          LOANCALC CALLS PAYCALC THROUGH A DATA NAME, SO   *
//*                  THE CALL IS DYNAMIC REGARDLESS; DYNAM MAKES IT   *
//*                  EXPLICIT.  A NEW PAYCALC NEEDS NO RE-LINK OF     *
//*                  LOANCALC.                                        *
//*   TRUNC(STD)     STANDARD TRUNCATION FOR BINARY ITEMS             *
//*   SSRANGE        SUBSCRIPT / REFERENCE-MODIFICATION CHECKING      *
//*   DEFINE(GNUCOBOL) IS DELIBERATELY NOT SET: THE >>IF GNUCOBOL     *
//*                  BLOCKS IN LOANCALC COMPILE OUT, LEAVING QSAM FB  *
//*                  FILES.                                           *
//*                                                                   *
//* CHANGE LS0142 2026-10-28  PAYCALC PRECISION FIX - RECOMPILE       *
//*                           PAYCALC ONLY.  LOANCALC UNCHANGED.      *
//*********************************************************************
//         SET SRCLIB=LS.SOURCE.COBOL
//         SET CPYLIB=LS.SOURCE.COPYLIB
//         SET LOADLIB=LS.LOADLIB
//*
//*-------------------------------------------------------------------*
//* STEP010 - PAYCALC (CALLED SUBPROGRAM)                             *
//*-------------------------------------------------------------------*
//STEP010  EXEC IGYWCL,
//             PARM.COBOL=('ARITH(EXTEND),TRUNC(STD),SSRANGE',
//             'MAP,XREF,LIST'),
//             PARM.LKED='LIST,XREF,MAP,RENT'
//COBOL.SYSIN   DD DISP=SHR,DSN=&SRCLIB(PAYCALC)
//COBOL.SYSLIB  DD DISP=SHR,DSN=&CPYLIB
//LKED.SYSLMOD  DD DISP=SHR,DSN=&LOADLIB(PAYCALC)
//*
//*-------------------------------------------------------------------*
//* STEP020 - LOANCALC (BATCH MAIN) - SKIPPED IF STEP010 RC > 4       *
//*-------------------------------------------------------------------*
//STEP020  EXEC IGYWCL,COND=(4,LT,STEP010.LKED),
//             PARM.COBOL=('ARITH(EXTEND),DYNAM,TRUNC(STD)',
//             'SSRANGE,MAP,XREF'),
//             PARM.LKED='LIST,XREF,MAP,RENT'
//COBOL.SYSIN   DD DISP=SHR,DSN=&SRCLIB(LOANCALC)
//COBOL.SYSLIB  DD DISP=SHR,DSN=&CPYLIB
//LKED.SYSLMOD  DD DISP=SHR,DSN=&LOADLIB(LOANCALC)
//
