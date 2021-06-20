{$I eDefines.inc}

unit iec104defs;

interface

uses sysutils;

type  EIEC104Exception = Exception;

const STARTDT_ACT   = $07;                    // start data transfer activation
      STARTDT_CON   = $0b;                    // start data transfer confirmation
      STOPDT_ACT    = $13;                    // stop data transfer activation
      STOPDT_CON    = $23;                    // stop data transfer confirmation
      TESTFR_ACT    = $43;                    // test frame activation
      TESTFR_CON    = $83;                    // test frame confirmation
// причины передачи
      COT_PERCYC    = 1;                      // периодически, циклически
      COT_BACK      = 2;                      // фоновое сканирование
      COT_SPONT     = 3;                      // спорадически
      COT_INIT      = 4;                      // сообщение об инициализации
      COT_REQ       = 5;                      // запрос или запрашиваемые данные
      COT_ACT       = 6;                      // активация
      COT_ACTCON    = 7;                      // подтверждение активации
      COT_DEACT     = 8;                      // деактивация
      COT_DEACTCON  = 9;                      // подтверждение деактивации
      COT_ACTTERM   = 10;                     // завершение активации
      COT_RETREM    = 11;                     // обратная информация вызванная удаленной командой
      COT_RETLOC    = 12;                     // обратная информация вызванная локальной командой
      COT_FILE      = 13;                     // передача файлов
      //
      COT_INTROGEN  = 20;                     // ответ на опрос станции
      COT_INTRO1    = 21;                     // ответ на опрос группы 1
      COT_INTRO2    = 22;                     // ответ на опрос группы 2
      COT_INTRO3    = 23;                     // ответ на опрос группы 3
      COT_INTRO4    = 24;                     // ответ на опрос группы 4
      COT_INTRO5    = 25;                     // ответ на опрос группы 5
      COT_INTRO6    = 26;                     // ответ на опрос группы 6
      COT_INTRO7    = 27;                     // ответ на опрос группы 7
      COT_INTRO8    = 28;                     // ответ на опрос группы 8
      COT_INTRO9    = 29;                     // ответ на опрос группы 9
      COT_INTRO10   = 30;                     // ответ на опрос группы 10
      COT_INTRO11   = 31;                     // ответ на опрос группы 11
      COT_INTRO12   = 32;                     // ответ на опрос группы 12
      COT_INTRO13   = 33;                     // ответ на опрос группы 13
      COT_INTRO14   = 34;                     // ответ на опрос группы 14
      COT_INTRO15   = 35;                     // ответ на опрос группы 15
      COT_INTRO16   = 36;                     // ответ на опрос группы 16
      COT_REQCOGEN  = 37;                     // ответ на опрос счетчиков
      COT_REQCO1    = 38;                     // ответ на опрос группы счетчиков 1
      COT_REQCO2    = 39;                     // ответ на опрос группы счетчиков 2
      COT_REQCO3    = 40;                     // ответ на опрос группы счетчиков 3
      COT_REQCO4    = 41;                     // ответ на опрос группы счетчиков 4
      //
      COT_BADTYPEID = 44;                     // неизвестный идентификатор типа
      COT_BADCOT    = 45;                     // неизвестный причина передачи
      COT_BADCA     = 46;                     // неизвестный общий адрес ASDU
      COT_BADIOA    = 47;                     // неизвестный адрес объекта информации

// идентификаторы типа ASDU: информация о процессе в направлении контроля
      M_SP_NA_1     = 1;                      // + одноэлементая информация
      M_SP_TA_1     = 2;                      // + одноэлементая информация с меткой времени
      M_DP_NA_1     = 3;                      // + двухэлементая информация
      M_DP_TA_1     = 4;                      // + двухэлементая информация с меткой времени
      M_ST_NA_1     = 5;                      // + информация о положении отпаек (отводов трансформатора)
      M_ST_TA_1     = 6;                      // + информация о положении отпаек с меткой времени
      M_BO_NA_1     = 7;                      // + строка из 32-х бит
      M_BO_TA_1     = 8;                      // + строка из 32-х бит с меткой времени
      M_ME_NA_1     = 9;                      // + нормализованное значение измеряемой величины
      M_ME_TA_1     = 10;                     // + нормализованное значение измеряемой величины с меткой времени
      M_ME_NB_1     = 11;                     // + масштабированное значение измеряемой величины
      M_ME_TB_1     = 12;                     // + масштабированное значение измеряемой величины с меткой времени
      M_ME_NC_1     = 13;                     // + значение измеряемой величины, короткий формат с плавающей точкой
      M_ME_TC_1     = 14;                     // + значение измеряемой величины, короткий формат с плавающей точкой с меткой времени
      M_IT_NA_1     = 15;                     // + интегральная сумма
      M_IT_TA_1     = 16;                     // + интегральная сумма с меткой времени
      M_EP_TA_1     = 17;                     // + информация о работе релейной защиты с меткой времени
      M_EP_TB_1     = 18;                     // упакованная информация о срабатывании пусковых органов защиты с меткой времени
      M_EP_TC_1     = 19;                     // упакованная информация о срабатывании выходных цепей защиты с меткой времени
      M_PS_NA_1     = 20;                     // упакованная одноэлементная информация с указателем изменения состояния
      M_ME_ND_1     = 21;                     // + нормализованное значение измеряемой величины без описателя качества
      //              22..29;                 // резерв
      M_SP_TB_1     = 30;                     // + одноэлементая информация с меткой времени CP56Time2a
      M_DP_TB_1     = 31;                     // + двухэлементая информация с меткой времени CP56Time2a
      M_ST_TB_1     = 32;                     // + информация о положении отпаек с меткой времени CP56Time2a
      M_BO_TB_1     = 33;                     // + строка из 32-х бит с меткой времени CP56Time2a
      M_ME_TD_1     = 34;                     // + нормализованное значение измеряемой величины с меткой времени CP56Time2a
      M_ME_TE_1     = 35;                     // + масштабированное значение измеряемой величины с меткой времени CP56Time2a
      M_ME_TF_1     = 36;                     // + значение измеряемой величины, короткий формат с плавающей точкой с меткой времени CP56Time2a
      M_IT_TB_1     = 37;                     // + интегральная сумма с меткой времени CP56Time2a
      M_EP_TD_1     = 38;                     // + информация о работе релейной защиты с меткой времени CP56Time2a
      M_EP_TE_1     = 39;                     // упакованная информация о срабатывании пусковых органов защиты с меткой времени CP56Time2a
      M_EP_TF_1     = 40;                     // упакованная информация о срабатывании выходных цепей защиты с меткой времени CP56Time2a
      //              41..44;                 // резерв
// идентификаторы типа ASDU: информация о процессе в направлении управления
      C_SC_NA_1     = 45;                     // + однопозиционная команда
      C_DC_NA_1     = 46;                     // + двухпозиционная команда
      C_RC_NA_1     = 47;                     // + команда пошагового регулирования
      C_SE_NA_1     = 48;                     // команда уставки, нормализованное значение
      C_SE_NB_1     = 49;                     // команда уставки, масштабированное значение
      C_SE_NC_1     = 50;                     // команда уставки, короткий формат с плавающей точкой
      C_BO_NA_1     = 51;                     // + строка из 32 бит
      //              52..57;                 // резерв
// идентификаторы типа ASDU: информация о процессе в направлении управления с меткой времени
      C_SC_TA_1     = 58;                     // + однопозиционная команда с меткой времени CP56Time2a
      C_DC_TA_1     = 59;                     // + двухпозиционная команда с меткой времени CP56Time2a
      C_RC_TA_1     = 60;                     // + команда пошагового регулирования с меткой времени CP56Time2a
      C_SE_TA_1     = 61;                     // команда уставки, нормализованное значение с меткой времени CP56Time2a
      C_SE_TB_1     = 62;                     // команда уставки, масштабированное значение с меткой времени CP56Time2a
      C_SE_TC_1     = 63;                     // команда уставки, короткий формат с плавающей точкой с меткой времени CP56Time2a
      C_BO_TA_1     = 64;                     // + строка из 32 бит с меткой времени CP56Time2a
      //              65..69;                 // резерв
// идентификаторы типа ASDU: системная информация в направлении контроля
      M_EI_NA_1     = 70;                     // + конец инициализации (должен быть COT_INIT)
      //              71..99;                 // резерв
// идентификаторы типа ASDU: системная информация в направлении управления
      C_IC_NA_1     = 100;                    // + команда опроса
      C_CI_NA_1     = 101;                    // + команда опроса счетчиков
      C_RD_NA_1     = 102;                    // + команда чтения
      C_CS_NA_1     = 103;                    // + команда синхронизации часов
      C_TS_NA_1     = 104;                    // + команда тестирования
      C_RP_NA_1     = 105;                    // + команда сброса процесса в исходное состояние
      C_CD_NA_1     = 106;                    // + команда определения запаздывания
      C_TS_TA_1     = 107;                    // + команда тестирования c меткой времени
      //              107..109;               // резерв
// идентификаторы типа ASDU: параметры в направлении управления
      P_ME_NA_1     = 110;                    // нормализованный параметр измеряемой величины
      P_ME_NB_1     = 111;                    // масштабированный параметр измеряемой величины
      P_ME_NC_1     = 112;                    // параметр измеряемой величины, короткий формат с плавающей точкой
      P_AC_NA_1     = 113;                    // параметр активации
      //              114..119;               // резерв
// идентификаторы типа ASDU: передача файлов
      F_FR_NA_1     = 120;                    // файл готов
      F_SR_NA_1     = 121;                    // секция готова
      F_SC_NA_1     = 122;                    // вызов директории, выбор файла, вызов файла, вызов секции
      F_LS_NA_1     = 123;                    // последняя секция, последний сегмент
      F_AF_NA_1     = 124;                    // подтверждение файла, подтверждение секции
      F_SG_NA_1     = 125;                    // сегмент
      F_DR_NA_1     = 126;                    // директория
      //              127;                    // резерв

// monitor direction:  slave(server)  -> master(client)
// control direction:  master(client) -> slave(server)
//
// Размеры информационных элементов:
      // Process information in monitor direction:  slave(server) -> master(client)
      szSIQ        = 1;                                                         // single-point information with quality descriptor
      szDIQ        = 1;                                                         // double-point information with quality descriptor
      szBSI        = 4;                                                         // binary state information
      szSCD        = 4;                                                         // status and change detection
      szQDS        = 1;                                                         // quality descriptor
      szVTI        = 1;                                                         // value with transient state indication
      szNVA        = 2;                                                         // normalized value
      szSVA        = 2;                                                         // scaled value
      szIEEESTD754 = 4;                                                         // short floating point number
      szBCR        = 5;                                                         // binary counter reading
      // защита
      szSEP        = 1;                                                         // single event of protection equipment
      szSPE        = 1;                                                         // start events of protection equipment
      szOCI        = 1;                                                         // output circuit information of protection equipment
      szQDP        = 1;                                                         // quality descriptor for events of protection equipment
      // команды
      szSCO        = 1;                                                         // single command
      szDCO        = 1;                                                         // double command
      szRCO        = 1;                                                         // regulating step command
      // метки времени
      szCP56Time2a = 7;                                                         // метка времени
      szCP24Time2a = 3;                                                         // метка времени
      szCP16Time2a = 2;                                                         // метка времени
      // qualifiers (классификаторы)
      szQOI        = 1;                                                         // qualifier of interrogation
      szQCC        = 1;                                                         // qualifier of counter interrogation command
      szQPM        = 1;                                                         // qualifier of parameter of measured values
      szQPA        = 1;                                                         // qualifier of parameter activation
      szQRP        = 1;                                                         // qualifier of reset process command
      szQOC        = 1;                                                         // qualifier of command
      szQOS        = 1;                                                         // qualifier of set-point command
      //
      szCOI        = 1;                                                         // cause of initialization
      szFBP        = 2;                                                         // fixed test bit pattern, two octets
      //
      szNOF        = 2;                                                         // name of file
      szLOF        = 3;                                                         // length of file or section
      szFRQ        = 1;                                                         // file ready qualifier
      szNOS        = 2;                                                         // name of section
      szSRQ        = 1;                                                         // section ready qualifier
      szSCQ        = 1;                                                         // select and call qualifier
      szLSQ        = 1;                                                         // last section or segment qualifier
      szCHS        = 1;                                                         // check sum
      szAFQ        = 1;                                                         // Acknowledge file or section qualifier
      szSOF        = 1;                                                         // status of file
      //

function IECASDUInfElementSize(AT: Byte): Integer;
//
function IECASDUTypeDescription(AT: Byte): String;
//
function IECASDUTypeShortDescription(AT: Byte): String;
//
function IECASDUCOTDescription(COT: Byte): String;

implementation

function IECASDUInfElementSize(AT: Byte): Integer;
begin
  Case AT of
    // идетификаторы типа ASDU: информация о процессе в направлении контроля
    M_SP_NA_1:  result:= szSIQ;                                                   // SIQ
    M_SP_TA_1:  result:= szSIQ + szCP24Time2a;                                    // SIQ + CP24Time2a
    M_DP_NA_1:  result:= szDIQ;                                                   // DIQ
    M_DP_TA_1:  result:= szDIQ + szCP24Time2a;                                    // DIQ + CP24Time2a
    M_ST_NA_1:  result:= szVTI + szQDS;                                           // VTI + QDS
    M_ST_TA_1:  result:= szVTI + szQDS + szCP24Time2a;                            // VTI + QDS + CP24Time2a
    M_BO_NA_1:  result:= szBSI + szQDS;                                           // BSI + QDS
    M_BO_TA_1:  result:= szBSI + szQDS + szCP24Time2a;                            // BSI + QDS + CP24Time2a
    M_ME_NA_1:  result:= szNVA + szQDS;                                           // NVA + QDS
    M_ME_TA_1:  result:= szNVA + szQDS + szCP24Time2a;                            // Measured value, normalized value with time tag
    M_ME_NB_1:  result:= szSVA + szQDS;                                           // Measured value, scaled value
    M_ME_TB_1:  result:= szSVA + szQDS + szCP24Time2a;                            // Measured value, scaled value with time tag
    M_ME_NC_1:  result:= szIEEESTD754 + szQDS;                                    // Measured value, short floating point value
    M_ME_TC_1:  result:= szIEEESTD754 + szQDS + szCP24Time2a;                     // Measured value, short floating point value with time tag
    M_IT_NA_1:  result:= szBCR;                                                   // Integrated totals
    M_IT_TA_1:  result:= szBCR + szCP24Time2a;                                    // Integrated totals with time tag
    M_EP_TA_1:  result:= szCP16Time2a + szCP24Time2a;                             // Event of protection equipment with time tag
    M_EP_TB_1:  result:= szSEP + szQDP + szCP16Time2a + szCP24Time2a;             // Packed start events of protection equipment with time tag
    M_EP_TC_1:  result:= szOCI + szQDP + szCP16Time2a + szCP24Time2a;             // Packed output circuit information of protection equipment with time tag
    M_PS_NA_1:  result:= szSCD + szQDS;                                           // Packed single-point information with status change detection
    M_ME_ND_1:  result:= szNVA;                                                   // Measured value, normalized value without quality descriptor
    //
    // Process telegrams with long time tag (7 octets)
    M_SP_TB_1:  result:= szSIQ + szCP56Time2a;                                    // Single point information with time tag CP56Time2a
    M_DP_TB_1:  result:= szDIQ + szCP56Time2a;                                    // Double point information with time tag CP56Time2a
    M_ST_TB_1:  result:= szVTI + szQDS + szCP56Time2a;                            // Step position information with time tag CP56Time2a
    M_BO_TB_1:  result:= szBSI + szQDS + szCP56Time2a;                            // Bit string of 32 bit with time tag CP56Time2a
    M_ME_TD_1:  result:= szNVA + szQDS + szCP56Time2a;                            // Measured value, normalized value with time tag CP56Time2a
    M_ME_TE_1:  result:= szSVA + szQDS + szCP56Time2a;                            // Measured value, scaled value with time tag CP56Time2a
    M_ME_TF_1:  result:= szIEEESTD754 + szQDS + szCP56Time2a;                     // Measured value, short floating point value with time tag CP56Time2a
    M_IT_TB_1:  result:= szBCR + szCP56Time2a;                                    // Integrated totals with time tag CP56Time2a
    M_EP_TD_1:  result:= szCP16Time2a + szCP56Time2a;                             // Event of protection equipment with time tag CP56Time2a
    M_EP_TE_1:  result:= szSEP + szQDP + szCP16Time2a + szCP56Time2a;             // Packed start events of protection equipment with time tag CP56time2a
    M_EP_TF_1:  result:= szOCI + szQDP + szCP16Time2a + szCP56Time2a;             // Packed output circuit information of protection equipment with time tag CP56Time2a
    //
    // идетификаторы типа ASDU: информация о процессе в направлении управления
    C_SC_NA_1:  result:= szSCO;                                                   // Single command
    C_DC_NA_1:  result:= szDCO;                                                   // Double command
    C_RC_NA_1:  result:= szRCO;                                                   // Regulating step command
    C_SE_NA_1:  result:= szNVA + szQOS;                                           // Setpoint command, normalized value
    C_SE_NB_1:  result:= szSVA + szQOS;                                           // Setpoint command, scaled value
    C_SE_NC_1:  result:= szIEEESTD754 + szQOS;                                    // Setpoint command, short floating point value
    C_BO_NA_1:  result:= szBSI;                                                   // Bit string 32 bit
    //
    // Command telegrams with long time tag (7 octets)
    C_SC_TA_1:  result:= szSCO + szCP56Time2a;                                    // Single command with time tag CP56Time2a
    C_DC_TA_1:  result:= szDCO + szCP56Time2a;                                    // Double command with time tag CP56Time2a
    C_RC_TA_1:  result:= szRCO + szCP56Time2a;                                    // Regulating step command with time tag CP56Time2a
    C_SE_TA_1:  result:= szNVA + szQOS + szCP56Time2a;                            // Setpoint command, normalized value with time tag CP56Time2a
    C_SE_TB_1:  result:= szSVA + szQOS + szCP56Time2a;                            // Setpoint command, scaled value with time tag CP56Time2a
    C_SE_TC_1:  result:= szIEEESTD754 + szQOS + szCP56Time2a;                     // Setpoint command, short floating point value with time tag CP56Time2a
    C_BO_TA_1:  result:= szBSI + szCP56Time2a;                                    // Bit string 32 bit with time tag CP56Time2a
    //
    // идетификаторы типа ASDU: системная информация в направлении контроля
    M_EI_NA_1:  result:= szCOI;                                                   // End of initialization
    //
    // идетификаторы типа ASDU: системная информация в направлении управления
    C_IC_NA_1:  result:= szQOI;                                                   // General Interrogation command
    C_CI_NA_1:  result:= szQCC;                                                   // Counter interrogation command
    C_RD_NA_1:  result:= 0;                                                       // Read command
    C_CS_NA_1:  result:= szCP56Time2a;                                            // Clock synchronization command
    C_TS_NA_1:  result:= szFBP;                                                   // (IEC 101) Test command
    C_RP_NA_1:  result:= szQRP;                                                   // Reset process command
    C_CD_NA_1:  result:= szCP16Time2a;                                            // (IEC 101) Delay acquisition command
    C_TS_TA_1:  result:= szFBP + szCP56Time2a;                                    // Test command with time tag CP56Time2a
    //
    // идетификаторы типа ASDU: параметры в направлении управления
    P_ME_NA_1:  result:= szNVA + szQPM;                                           // Parameter of measured value, normalized value
    P_ME_NB_1:  result:= szSVA + szQPM;                                           // Parameter of measured value, scaled value
    P_ME_NC_1:  result:= szIEEESTD754 + szQPM;                                    // Parameter of measured value, short floating point value
    P_AC_NA_1:  result:= szQPA;                                                   // Parameter activation
    //
    // идетификаторы типа ASDU: передача файлов
    F_FR_NA_1:  result:= szNOF + szLOF + szFRQ;                                   // File ready
    F_SR_NA_1:  result:= szNOF + szNOS + szLOF + szSRQ;                           // Section ready
    F_SC_NA_1:  result:= szNOF + szNOS + szSCQ;                                   // Call directory, select file, call file, call section
    F_LS_NA_1:  result:= szNOF + szNOS + szLSQ + szCHS;                           // Last section, last segment
    F_AF_NA_1:  result:= szNOF + szNOS + szAFQ;                                   // Ack file, Ack section
    // 125: result:= szNOF + szNOS + szLOS + szSegment;                           // Segment
    F_DR_NA_1:  result:= szNOF + szLOF + szSOF + szCP56Time2a;                    // Directory
    // 127: result:= 'QueryLog–Request archive file';                             // QueryLog–Request archive file
    //
    else raise EIEC104Exception.CreateFmt('unsupported ASDU type:%u', [AT]);
  end;
end;
//
function IECASDUTypeDescription(AT: Byte): String;
begin
  Case AT of
    // идетификаторы типа ASDU: информация о процессе в направлении контроля
    M_SP_NA_1:  result:= 'Single point information';
    M_SP_TA_1:  result:= 'Single point information with time tag';
    M_DP_NA_1:  result:= 'Double point information';
    M_DP_TA_1:  result:= 'Double point information with time tag';
    M_ST_NA_1:  result:= 'Step position information';
    M_ST_TA_1:  result:= 'Step position information with time tag';
    M_BO_NA_1:  result:= 'Bit string of 32 bit';
    M_BO_TA_1:  result:= 'Bit string of 32 bit with time tag';
    M_ME_NA_1:  result:= 'Measured value, normalized value';
    M_ME_TA_1:  result:= 'Measured value, normalized value with time tag';
    M_ME_NB_1:  result:= 'Measured value, scaled value';
    M_ME_TB_1:  result:= 'Measured value, scaled value with time tag';
    M_ME_NC_1:  result:= 'Measured value, short floating point value';
    M_ME_TC_1:  result:= 'Measured value, short floating point value with time tag';
    M_IT_NA_1:  result:= 'Integrated totals';
    M_IT_TA_1:  result:= 'Integrated totals with time tag';
    M_EP_TA_1:  result:= 'Event of protection equipment with time tag';
    M_EP_TB_1:  result:= 'Packed start events of protection equipment with time tag';
    M_EP_TC_1:  result:= 'Packed output circuit information of protection equipment with time tag';
    M_PS_NA_1:  result:= 'Packed single-point information with status change detection';
    M_ME_ND_1:  result:= 'Measured value, normalized value without quality descriptor';
    //
    // Process telegrams with long time tag (7 octets)
    M_SP_TB_1:  result:= 'Single point information with time tag CP56Time2a';
    M_DP_TB_1:  result:= 'Double point information with time tag CP56Time2a';
    M_ST_TB_1:  result:= 'Step position information with time tag CP56Time2a';
    M_BO_TB_1:  result:= 'Bit string of 32 bit with time tag CP56Time2a';
    M_ME_TD_1:  result:= 'Measured value, normalized value with time tag CP56Time2a';
    M_ME_TE_1:  result:= 'Measured value, scaled value with time tag CP56Time2a';
    M_ME_TF_1:  result:= 'Measured value, short floating point value with time tag CP56Time2a';
    M_IT_TB_1:  result:= 'Integrated totals with time tag CP56Time2a';
    M_EP_TD_1:  result:= 'Event of protection equipment with time tag CP56Time2a';
    M_EP_TE_1:  result:= 'Packed start events of protection equipment with time tag CP56time2a';
    M_EP_TF_1:  result:= 'Packed output circuit information of protection equipment with time tag CP56Time2a';
    //
    // идетификаторы типа ASDU: информация о процессе в направлении управления
    C_SC_NA_1:  result:= 'Single command';
    C_DC_NA_1:  result:= 'Double command';
    C_RC_NA_1:  result:= 'Regulating step command';
    C_SE_NA_1:  result:= 'Setpoint command, normalized value';
    C_SE_NB_1:  result:= 'Setpoint command, scaled value';
    C_SE_NC_1:  result:= 'Setpoint command, short floating point value';
    C_BO_NA_1:  result:= 'Bit string 32 bit';
    //
    // Command telegrams with long time tag (7 octets)
    C_SC_TA_1:  result:= 'Single command with time tag CP56Time2a';
    C_DC_TA_1:  result:= 'Double command with time tag CP56Time2a';
    C_RC_TA_1:  result:= 'Regulating step command with time tag CP56Time2a';
    C_SE_TA_1:  result:= 'Setpoint command, normalized value with time tag CP56Time2a';
    C_SE_TB_1:  result:= 'Setpoint command, scaled value with time tag CP56Time2a';
    C_SE_TC_1:  result:= 'Setpoint command, short floating point value with time tag CP56Time2a';
    C_BO_TA_1:  result:= 'Bit string 32 bit with time tag CP56Time2a';
    //
    // System information in monitor direction
    M_EI_NA_1:  result:= 'End of initialization';
    //
    // идетификаторы типа ASDU: системная информация в направлении управления
    C_IC_NA_1:  result:= 'General Interrogation command';
    C_CI_NA_1:  result:= 'Counter interrogation command';
    C_RD_NA_1:  result:= 'Read command';
    C_CS_NA_1:  result:= 'Clock synchronization command';
    C_TS_NA_1:  result:= '(IEC 101) Test command';
    C_RP_NA_1:  result:= 'Reset process command';
    C_CD_NA_1:  result:= '(IEC 101) Delay acquisition command';
    C_TS_TA_1:  result:= 'Test command with time tag CP56Time2a';
    //
    // идетификаторы типа ASDU: параметры в направлении управления
    P_ME_NA_1:  result:= 'Parameter of measured value, normalized value';
    P_ME_NB_1:  result:= 'Parameter of measured value, scaled value';
    P_ME_NC_1:  result:= 'Parameter of measured value, short floating point value';
    P_AC_NA_1:  result:= 'Parameter activation';
    //
    // идетификаторы типа ASDU: передача файлов
    F_FR_NA_1:  result:= 'File ready';
    F_SR_NA_1:  result:= 'Section ready';
    F_SC_NA_1:  result:= 'Call directory, select file, call file, call section';
    F_LS_NA_1:  result:= 'Last section, last segment';
    F_AF_NA_1:  result:= 'Ack file, Ack section';
    F_SG_NA_1:  result:= 'Segment';
    F_DR_NA_1:  result:= 'Directory';
    127:        result:= 'QueryLog–Request archive file';
    //
    else result:= 'Unknown';
  end;
  result:= result + ' (' + IntToStr(AT) + ')';
end;
//
function IECASDUTypeShortDescription(AT: Byte): String;
begin
  Case AT of
    // идетификаторы типа ASDU: информация о процессе в направлении контроля
    M_SP_NA_1:  result:= 'M_SP_NA_1';
    M_SP_TA_1:  result:= 'M_SP_TA_1';
    M_DP_NA_1:  result:= 'M_DP_NA_1';
    M_DP_TA_1:  result:= 'M_DP_TA_1';
    M_ST_NA_1:  result:= 'M_ST_NA_1';
    M_ST_TA_1:  result:= 'M_ST_TA_1';
    M_BO_NA_1:  result:= 'M_BO_NA_1';
    M_BO_TA_1:  result:= 'M_BO_TA_1';
    M_ME_NA_1:  result:= 'M_ME_NA_1';
    M_ME_TA_1:  result:= 'M_ME_TA_1';
    M_ME_NB_1:  result:= 'M_ME_NB_1';
    M_ME_TB_1:  result:= 'M_ME_TB_1';
    M_ME_NC_1:  result:= 'M_ME_NC_1';
    M_ME_TC_1:  result:= 'M_ME_TC_1';
    M_IT_NA_1:  result:= 'M_IT_NA_1';
    M_IT_TA_1:  result:= 'M_IT_TA_1';
    M_EP_TA_1:  result:= 'M_EP_TA_1';
    M_EP_TB_1:  result:= 'M_EP_TB_1';
    M_EP_TC_1:  result:= 'M_EP_TC_1';
    M_PS_NA_1:  result:= 'M_PS_NA_1';
    M_ME_ND_1:  result:= 'M_ME_ND_1';
    //
    // Process telegrams with long time tag (7 octets)
    M_SP_TB_1:  result:= 'M_SP_TB_1';
    M_DP_TB_1:  result:= 'M_DP_TB_1';
    M_ST_TB_1:  result:= 'M_ST_TB_1';
    M_BO_TB_1:  result:= 'M_BO_TB_1';
    M_ME_TD_1:  result:= 'M_ME_TD_1';
    M_ME_TE_1:  result:= 'M_ME_TE_1';
    M_ME_TF_1:  result:= 'M_ME_TF_1';
    M_IT_TB_1:  result:= 'M_IT_TB_1';
    M_EP_TD_1:  result:= 'M_EP_TD_1';
    M_EP_TE_1:  result:= 'M_EP_TE_1';
    M_EP_TF_1:  result:= 'M_EP_TF_1';
    //
    // идетификаторы типа ASDU: информация о процессе в направлении управления
    C_SC_NA_1:  result:= 'C_SC_NA_1';
    C_DC_NA_1:  result:= 'C_DC_NA_1';
    C_RC_NA_1:  result:= 'C_RC_NA_1';
    C_SE_NA_1:  result:= 'C_SE_NA_1';
    C_SE_NB_1:  result:= 'C_SE_NB_1';
    C_SE_NC_1:  result:= 'C_SE_NC_1';
    C_BO_NA_1:  result:= 'C_BO_NA_1';
    //
    // Command telegrams with long time tag (7 octets)
    C_SC_TA_1:  result:= 'C_SC_TA_1';
    C_DC_TA_1:  result:= 'C_DC_TA_1';
    C_RC_TA_1:  result:= 'C_RC_TA_1';
    C_SE_TA_1:  result:= 'C_SE_TA_1';
    C_SE_TB_1:  result:= 'C_SE_TB_1';
    C_SE_TC_1:  result:= 'C_SE_TC_1';
    C_BO_TA_1:  result:= 'C_BO_TA_1';
    //
    // System information in monitor direction
    M_EI_NA_1:  result:= 'M_EI_NA_1';
    //
    // идетификаторы типа ASDU: системная информация в направлении управления
    C_IC_NA_1:  result:= 'C_IC_NA_1';
    C_CI_NA_1:  result:= 'C_CI_NA_1';
    C_RD_NA_1:  result:= 'C_RD_NA_1';
    C_CS_NA_1:  result:= 'C_CS_NA_1';
    C_TS_NA_1:  result:= 'C_TS_NA_1';
    C_RP_NA_1:  result:= 'C_RP_NA_1';
    C_CD_NA_1:  result:= 'C_CD_NA_1';
    C_TS_TA_1:  result:= 'C_TS_TA_1';
    //
    // идетификаторы типа ASDU: параметры в направлении управления
    P_ME_NA_1:  result:= 'P_ME_NA_1';
    P_ME_NB_1:  result:= 'P_ME_NB_1';
    P_ME_NC_1:  result:= 'P_ME_NC_1';
    P_AC_NA_1:  result:= 'P_AC_NA_1';
    //
    // идетификаторы типа ASDU: передача файлов
    F_FR_NA_1:  result:= 'F_FR_NA_1';
    F_SR_NA_1:  result:= 'F_SR_NA_1';
    F_SC_NA_1:  result:= 'F_SC_NA_1';
    F_LS_NA_1:  result:= 'F_LS_NA_1';
    F_AF_NA_1:  result:= 'F_AF_NA_1';
    F_SG_NA_1:  result:= 'F_SG_NA_1';
    F_DR_NA_1:  result:= 'F_DR_NA_1';
    //
    else result:= '?_??_??_?';
  end;
  result:= result + ' (' + IntToStr(AT) + ')';
end;
//
function IECASDUCOTDescription(COT: Byte): String;
begin
  Case COT and $3F of
    COT_PERCYC:     result:= 'periodic, cyclic';
    COT_BACK:       result:= 'background interrogation';
    COT_SPONT:      result:= 'spontaneous';
    COT_INIT:       result:= 'initialized';
    COT_REQ:        result:= 'interrogation or interrogated';
    COT_ACT:        result:= 'activation';
    COT_ACTCON:     result:= 'confirmation activation';
    COT_DEACT:      result:= 'deactivation';
    COT_DEACTCON:   result:= 'confirmation deactivation';
    COT_ACTTERM:    result:= 'termination activation';
    COT_RETREM:     result:= 'feedback, caused by distant command';
    COT_RETLOC:     result:= 'feedback, caused by local command';
    COT_FILE:       result:= 'data transmission';
    14..19:         result:= 'reserved';
    COT_INTROGEN: result:= 'interrogated by general interrogation';
    COT_INTRO1..COT_INTRO16:  result:= 'interrogated by interrogation group ' + IntToStr(COT-20);
    COT_REQCOGEN: result:= 'interrogated by counter general interrogation';
    COT_REQCO1..COT_REQCO4:   result:= 'interrogated by interrogation counter group ' + IntToStr(COT-37);
    COT_BADTYPEID:  result:= 'type-Identification unknown';
    COT_BADCOT:     result:= 'cause unknown';
    COT_BADCA:      result:= 'ASDU address unknown';
    COT_BADIOA:     result:= 'information object address unknown';
    else            result:= 'unknown';
  end;
  result:= result + ' (' + IntToStr(COT) + ')';
end;

end.