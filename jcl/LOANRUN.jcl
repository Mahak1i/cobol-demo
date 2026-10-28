//LOANRUN  JOB (LS,0142),'LOAN AMORTIZATION',CLASS=A,MSGCLASS=X,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//*********************************************************************
//* JOB      : LOANRUN                                                *
//* PURPOSE  : NIGHTLY LOAN AMORTIZATION SCHEDULE BATCH               *
//*                                                                   *
//*   STEP005  IEFBR14   DELETE PRIOR RUN'S OUTPUT (RERUNNABLE JOB)   *
//*   STEP010  LOANCALC  BUILD SCHEDULES, CALLS PAYCALC DYNAMICALLY   *
//*                                                                   *
//* RETURN CODES (STEP010)                                            *
//*   0000  ALL LOANS PROCESSED                                       *
//*   0004  ONE OR MORE LOANS REJECTED - REVIEW LOANRPT; DOWNSTREAM   *
//*         STEPS STILL RUN                                           *
//*   0016  I/O ERROR OR ARITHMETIC OVERFLOW - CALL ON-CALL SUPPORT,  *
//*         SYSOUT SHOWS PARAGRAPH, FILE STATUS AND LAST LOAN ID      *
//*                                                                   *
//* RESTART  : FROM STEP005.  STEP010 IS NOT RESTARTABLE MID-FILE.    *
//*********************************************************************
//         SET HLQ=LS.PROD
//*
//STEP005  EXEC PGM=IEFBR14
//DEL1     DD DSN=&HLQ..AMORTOUT,DISP=(MOD,DELETE,DELETE),
//            UNIT=SYSDA,SPACE=(TRK,(0))
//DEL2     DD DSN=&HLQ..LOANRPT,DISP=(MOD,DELETE,DELETE),
//            UNIT=SYSDA,SPACE=(TRK,(0))
//*
//STEP010  EXEC PGM=LOANCALC
//STEPLIB  DD DISP=SHR,DSN=LS.LOADLIB
//*                                        LOAN MASTER EXTRACT (INPUT)
//LOANIN   DD DISP=SHR,DSN=&HLQ..LOAN.EXTRACT
//*                                        AMORTIZATION FILE   (OUTPUT)
//AMORTOUT DD DSN=&HLQ..AMORTOUT,
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(50,25),RLSE),
//            DCB=(RECFM=FB,LRECL=80,BLKSIZE=0)
//*                                        PRINT REPORT        (OUTPUT)
//*                                        LRECL 133 = 132 + ASA BYTE
//LOANRPT  DD DSN=&HLQ..LOANRPT,
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(20,10),RLSE),
//            DCB=(RECFM=FBA,LRECL=133,BLKSIZE=0)
//SYSOUT   DD SYSOUT=*
//CEEDUMP  DD SYSOUT=*
//SYSUDUMP DD SYSOUT=*
//
