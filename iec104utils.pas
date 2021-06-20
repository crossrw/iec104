{$I eDefines.inc}

unit iec104utils;

interface

uses SysUtils;

// максимальное количество подключений
const MAX_CLIENT_COUNT    = 32;
      MAX_COMMANDS_COUNT  = 128;

type  TIECFunctionFormat = (I_Format, S_Format, U_Format);

      TASDUDataBlockId = record
        ASDUType: Byte;             // идентификатор типа
        NumberOfObjects: Byte;      // количество объектов информации
        COT: Byte;                  // причина передачи
        SQ: Boolean;                // формат "Information Object"
        Test: Boolean;              // test
        PN: Boolean;                // positiv/negativ
        ORG: Byte;                  // адрес инициатора, может отсутствовать!
        ASDUAddress: Word;          // общий адрес ASDU
      end;

      TInformationObject = class
        private
          FASDUType:  Byte;                                         // идентификатор типа для общего опроса
          FSASDUType: Byte;                                         // идентификатор типа для спонтанной передачи
          FIOAddress: LongWord;                                     // адрес объекта информации
          FGroup:     Integer;                                      // группа, если 0, то не группа не используется
          FQuality:   Boolean;                                      //
          FChangeStatus: array[0..MAX_CLIENT_COUNT-1] of Boolean;   // признаки изменений для каждого соединения
          FDataReady: Boolean;                                      // значение установлено
          //
          FDT:        TDateTime;                                    // метка времени
          FDTValid:   Boolean;
          FValue:     Variant;                                      // значение
          //
          function ByteValue(const AIndex: Integer = -1): Byte;
          function SingleValue(const AIndex: Integer = -1): Single;
          function IntegerValue(const AIndex: Integer = -1): Integer;
          function SmallIntValue(const AIndex: Integer = -1): SmallInt;
          function WordValue(const AIndex: Integer = -1): Word;
          function LWordValue(const AIndex: Integer = -1): LongWord;
          function DateTimeValue(const AIndex: Integer = -1): TDateTime;
          //
          function SIQ: Byte;
          function DIQ: Byte;
          function SEP: Byte;         // Single event of protection equipment
        public
          constructor Create(AASDUType, ASASDUType: Byte; AIOAddress: LongWord; AGroup: Integer);
          //
          procedure SetValue(AValue: Variant);
          procedure SetBadQuality();
          //
          function EncodeIOData(ASDU: PByteArray; ASpont: Boolean): Integer;
          //
          function ASDUType(ASpont: Boolean): Byte;
          function NeedSporadic(AIndex: Integer): Boolean;
          function SporadicSupported: Boolean;
          //
          procedure ClearChangeStatus(AIndex: Integer);
          procedure SetChangeStatus;
          //
          property IOAddress: LongWord read FIOAddress;
          property DataReady: Boolean read FDataReady;
          property Group: Integer read FGroup;
      end;

// тип функции
function IECFunctionFormat(B: Byte): TIECFunctionFormat;
// передаваемый порядковый номер
function IECGetNS(Buf: PByteArray): Word;
// принимаемый порядковый номер
function IECGetNR(Buf: PByteArray): Word;
//
function decodeCP56Time2a(Buf: PByteArray; var DT: TDateTime): Integer;
//
function encodeCP56Time2a(Buf: PByteArray; DT: TDateTime; ADTValid: Boolean): Integer;
//
function encodeCP24Time2a(Buf: PByteArray; DT: TDateTime; ADTValid: Boolean): Integer;
//
function decodeUInt16(Buf: PByteArray; var CP16: Word): Integer;
//
function encodeUInt16(Buf: PByteArray; CP16: Word): Integer;
//
function decodeUInt32(Buf: PByteArray; var CP32: LongWord): Integer;
//
function QCCDescription(V: Byte): String;

implementation

uses DateUtils, variants, iec104time, iec104defs;

type  TQualityElement = (qeBL, qeSB, qeNT, qeIV, qeOV, qeEI);
      TQDS = set of TQualityElement;
      // элементы описателя качества:
      // BL - блокировка значения
      // SB - есть замещение значения
      // NT - неактуальное значение
      // IV - недействительное значение
      // OV - есть переполнение
      // EI - elapsed time invalid

function encodeQDS(const Quality: TQDS): Byte;
var QDS: Byte;
begin
  QDS:= 0;
  If qeBL in Quality then QDS:= QDS or $10;     // BL - блокировка значения
  If qeSB in Quality then QDS:= QDS or $20;     // SB - есть замещение значения
  If qeNT in Quality then QDS:= QDS or $40;     // NT - неактуальное значение
  If qeIV in Quality then QDS:= QDS or $80;     // IV - недействительное значения
  If qeOV in Quality then QDS:= QDS or $01;     // OV - есть переполнение
  If qeEI in Quality then QDS:= QDS or $08;     // EI - неверное время продолжительности
  Result:= QDS;
end;

// ------------------------------------------------------------------------------

constructor TInformationObject.Create(AASDUType, ASASDUType: Byte; AIOAddress: LongWord; AGroup: Integer);
var I: Integer;
begin
  inherited Create;
  //
  FASDUType:= AASDUType;
  FSASDUType:= ASASDUType;
  FIOAddress:= AIOAddress;
  FGroup:= AGroup;
  FQuality:= False;
  FDataReady:= False;
  For I:= 0 to MAX_CLIENT_COUNT-1 do FChangeStatus[I]:= False;
end;

procedure TInformationObject.SetValue(AValue: Variant);
begin
  FDataReady:= True;
  If (not VarSameValue(AValue, FValue)) or (not FQuality) then begin
    FDT:= IECNow();
    FDTValid:= IECTimeValid;
    FQuality:= True;
    FValue:= AValue;
    SetChangeStatus();
  end;
end;

procedure TInformationObject.SetBadQuality();
begin
  If FQuality or (not FDataReady) then begin
    If not FDataReady then begin
      FDataReady:= True;
      FValue:= 0;
    end;
    FDT:= IECNow();
    FDTValid:= IECTimeValid;
    FQuality:= False;
    SetChangeStatus();
  end;
end;

function TInformationObject.ByteValue(const AIndex: Integer = -1): Byte;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.WordValue(const AIndex: Integer = -1): Word;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.LWordValue(const AIndex: Integer = -1): LongWord;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.SingleValue(const AIndex: Integer = -1): Single;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.DateTimeValue(const AIndex: Integer = -1): TDateTime;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.IntegerValue(const AIndex: Integer = -1): Integer;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.SmallIntValue(const AIndex: Integer = -1): SmallInt;
begin
  try
    If AIndex >= 0 then Result:= FValue[AIndex] else Result:= FValue;
  except
    Result:= 0;
  end;
end;

function TInformationObject.SIQ: Byte;
var B: Byte;
begin
  If ByteValue() <> 0 then B:= 1 else B:= 0;
  If not FQuality then B:= B or encodeQDS([qeIV]);
  result:= B;
end;

function TInformationObject.DIQ: Byte;
var B: Byte;
begin
  Case ByteValue() of
    0:    B:= 1;          // OFF
    1:    B:= 2;          // ON
    else  B:= 0;          // неопределенное или промежуточное состояние
  end;
  If not FQuality then B:= B or encodeQDS([qeIV]);
  Result:= B;
end;

function TInformationObject.SEP: Byte;
var B: Byte;
begin
  Case ByteValue() of
    0:    B:= 1;          // OFF
    1:    B:= 2;          // ON
    else  B:= 0;          // неопределенное состояние
  end;
  If not FQuality then B:= B or encodeQDS([qeEI, qeIV]) else B:= B or encodeQDS([qeEI]);
  Result:= B;
end;

function TInformationObject.EncodeIOData(ASDU: PByteArray; ASpont: Boolean): Integer;
var Offset: Integer;
    DT: TDateTime;
    IntV: Integer;
    SIntV: SmallInt;
    LWV: LongWord;
    SV: Single;
    WV: Word;
begin
  Offset:= 0;
  // данные
  Case ASDUType(ASpont) of
    // одноэлементная информация
    M_SP_NA_1: begin                    // одноэлементная информация с описателем качества
      ASDU^[Offset]:= SIQ();
      Offset:= Offset + 1;
    end;
    M_SP_TA_1: begin                    // одноэлементная информация с описателем качества и меткой времени
      ASDU^[Offset]:= SIQ();
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_SP_TB_1: begin                    // одноэлементая информация с меткой времени CP56Time2a
      ASDU^[Offset]:= SIQ();
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // двухэлементная информация
    M_DP_NA_1: begin                    // двухэлементная информация
      ASDU^[Offset]:= DIQ();
      Offset:= Offset + 1;
    end;
    M_DP_TA_1: begin                    // двухэлементная информация с меткой времени
      ASDU^[Offset]:= DIQ();
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_DP_TB_1: begin                    // двухэлементная информация с меткой времени CP56Time2a
      ASDU^[Offset]:= DIQ();
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // информация о положении отпаек (отводов трансформатора)
    M_ST_NA_1: begin                    // информация о положении отпаек (отводов трансформатора)
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
    end;
    M_ST_TA_1: begin                    // информация о положении отпаек с меткой времени
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_ST_TB_1: begin                    // информация о положении отпаек с меткой времени CP56Time2a
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // строка из 32-х бит
    M_BO_NA_1: begin                    // строка из 32-х бит
      LWV:= LWordValue();
      Move(LWV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
    end;
    M_BO_TA_1: begin                    // строка из 32-х бит с меткой времени
      LWV:= LWordValue();
      Move(LWV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_BO_TB_1: begin                    // строка из 32-х бит с меткой времени CP56Time2a
      LWV:= LWordValue();
      Move(LWV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // нормализованное значение измеряемой величины
    M_ME_NA_1: begin                    // нормализованное значение измеряемой величины
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
    end;
    M_ME_ND_1: begin                    // нормализованное значение измеряемой величины без описателя качества
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
    end;
    M_ME_TA_1: begin                    // нормализованное значение измеряемой величины с меткой времени
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_ME_TD_1: begin                    // нормализованное значение измеряемой величины с меткой времени CP56Time2a
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;



    // масштабированное значение измеряемой величины
    M_ME_NB_1: begin                    // масштабированное значение измеряемой величины
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
    end;
    M_ME_TB_1: begin                    // масштабированное значение измеряемой величины с меткой времени
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_ME_TE_1: begin                    // масштабированное значение измеряемой величины с меткой времени CP56Time2a
      SIntV:= SmallIntValue();
      Move(SIntV, ASDU^[Offset], 2);
      Offset:= Offset + 2;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // короткий формат с плавающей точкой
    M_ME_NC_1: begin                    // значение измеряемой величины, короткий формат с плавающей точкой
      SV:= SingleValue();
      Move(SV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
    end;
    M_ME_TC_1: begin                    // значение измеряемой величины, короткий формат с плавающей точкой с меткой времени
      SV:= SingleValue();
      Move(SV, ASDU^[Offset], SizeOf(SV));
      Offset:= Offset + SizeOf(SV);
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_ME_TF_1: begin                    // значение измеряемой величины, короткий формат с плавающей точкой с меткой времени CP56Time2a
      SV:= SingleValue();
      Move(SV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // интегральная сумма
    M_IT_NA_1: begin                    // интегральная сумма
      //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
      //   +---+---+---+---+---+---+---+---+
      // 0 |             Value             |
      // 1 |             Value             |
      // 2 |             Value             |
      // 3 | S |         Value             |  S - sign
      // 4 |IV |CA |CY |    Seq number     |  IV:1 - invalid value;
      //                                      CA:0 - counter was not adjusted since last reading
      //                                      CA:1 - counter was adjusted since last reading
      //                                      CY:0 - no counter overflow occurred in the corresponding integration period
      //                                      CY:1 - counter overflow occurred in the corresponding integration period
      //                                      Seq number - ???
      IntV:= IntegerValue();
      Move(IntV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
    end;
    M_IT_TA_1: begin                    // интегральная сумма с меткой времени
      IntV:= IntegerValue();
      Move(IntV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_IT_TB_1: begin                    // интегральная сумма с меткой времени CP56Time2a
      IntV:= IntegerValue();
      Move(IntV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      If FQuality then ASDU^[Offset]:= 0 else ASDU^[Offset]:= encodeQDS([qeIV]);
      Offset:= Offset + 1;
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    // события
    M_EP_TA_1: begin                    // информация о работе релейной защиты с меткой времени
      // SEP
      ASDU^[Offset]:= SEP();
      Offset:= Offset + 1;
      // CP16Time2a - продолжительность
      Offset:= Offset + encodeUInt16(@ASDU^[Offset], 0);
      // CP24Time2a
      Offset:= Offset + encodeCP24Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    M_EP_TD_1: begin                    // информация о работе релейной защиты с меткой времени CP56Time2a
      // SEP
      ASDU^[Offset]:= SEP();
      Offset:= Offset + 1;
      // CP16Time2a
      Offset:= Offset + encodeUInt16(@ASDU^[Offset], 0);
      // CP56Time2a
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], FDT, FDTValid);
    end;
    //
    // команды
    C_SC_NA_1: begin                    // однопозиционная команда
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_SC_TA_1: begin                    // однопозиционная команда с меткой времени
      ASDU^[Offset]:= ByteValue(0);
      Offset:= Offset + 1;
      DT:= DateTimeValue(1);
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], DT, True);
    end;
    C_DC_NA_1: begin                    // двухпозиционная команда
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_DC_TA_1: begin                    // двухпозиционная команда с меткой времени
      ASDU^[Offset]:= ByteValue(0);
      Offset:= Offset + 1;
      DT:= DateTimeValue(1);
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], DT, True);
    end;
    C_RC_NA_1: begin                    // команда пошагового регулирования
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_RC_TA_1: begin                    // команда пошагового регулирования с меткой времени
      ASDU^[Offset]:= ByteValue(0);
      Offset:= Offset + 1;
      DT:= DateTimeValue(1);
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], DT, True);
    end;
    C_BO_NA_1: begin                    // строка из 32 бит
      LWV:= LWordValue();
      Move(LWV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
    end;
    C_BO_TA_1: begin                    // строка из 32 бит с меткой времени CP56Time2a
      LWV:= LWordValue(0);
      Move(LWV, ASDU^[Offset], 4);
      Offset:= Offset + 4;
      DT:= DateTimeValue(1);
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], DT, True);
    end;
    M_EI_NA_1: begin                    // конец инициализации (должен быть COT_INIT)
      //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
      //   +---+---+---+---+---+---+---+---+
      // 0 |BS1|      couse of init        |  0 - local power switch on
      //                                      1 - local manual reset
      //                                      2 - remote reset
      //                                      BS1:0 - initialization with unchanged local parameters
      //                                      BS1:1 - initialization after change of local parameters
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_IC_NA_1: begin                    // команда общего опроса
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_CI_NA_1: begin                    // команда опроса счётчиков
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_RD_NA_1: begin                    // команда опроса одного объекта
      // данные отсутствуют
    end;
    C_CS_NA_1: begin                    // Clock synchronization command
      DT:= DateTimeValue();
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], DT, IECTimeValid);
    end;
    C_TS_NA_1: begin                    // тестирование канала связи
      ASDU^[Offset]:=   $AA;            // фиксированная тестовая константа
      ASDU^[Offset+1]:= $55;
      Offset:= Offset + 2;
    end;
    C_RP_NA_1: begin                    // установка процесса в начальное состояние
      ASDU^[Offset]:= ByteValue();
      Offset:= Offset + 1;
    end;
    C_CD_NA_1: begin                    // команда определения запаздывания
      WV:= WordValue();
      Offset:= Offset + encodeUInt16(@ASDU^[Offset], WV);
    end;
    C_TS_TA_1: begin                    // команда тестирования c меткой времени
      WV:= WordValue(0);
      DT:= DateTimeValue(1);
      Offset:= Offset + encodeUInt16(@ASDU^[Offset], WV);
      Offset:= Offset + encodeCP56Time2a(@ASDU^[Offset], DT, IECTimeValid);
    end;




  end;
  Result:= Offset;
end;

procedure TInformationObject.ClearChangeStatus(AIndex: Integer);
begin
  FChangeStatus[AIndex]:= False;
end;

procedure TInformationObject.SetChangeStatus;
var I: Integer;
begin
  For I:= 0 to MAX_CLIENT_COUNT-1 do FChangeStatus[I]:= True;
end;

function TInformationObject.SporadicSupported: Boolean;
begin
  Result:= FSASDUType > 0;
end;

function TInformationObject.NeedSporadic(AIndex: Integer): Boolean;
begin
  Result:= FDataReady and FChangeStatus[AIndex] and SporadicSupported();
end;

function TInformationObject.ASDUType(ASpont: Boolean): Byte;
begin
  If ASpont and SporadicSupported then Result:= FSASDUType else Result:= FASDUType;
end;

// тип функции
function IECFunctionFormat(B: Byte): TIECFunctionFormat;
begin
  If (B and 1) = 0 then result:= I_Format else
  If (B and 3) = 1 then result:= S_Format else result:= U_Format;
end;
// передаваемый порядковый номер
function IECGetNS(Buf: PByteArray): Word;
begin
  result:= (Buf^[2] shr 1) + (Buf^[3] shl 7);
end;
// принимаемый порядковый номер
function IECGetNR(Buf: PByteArray): Word;
begin
  result:= (Buf^[4] shr 1) + (Buf^[5] shl 7);
end;
//
function decodeCP56Time2a(Buf: PByteArray; var DT: TDateTime): Integer;
var MS: Word;
begin
  //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
  //   +---+---+---+---+---+---+---+---+
  // 0 |   миллисекунды, младший байт  |
  // 1 |   миллисекунды, старший байт  |  0..59999 мс
  // 2 |IV |RES|      минуты           |  0..59, IV - недействительное значение
  // 3 |SU |  RES  |      часы         |  0..23, SU - летнее время
  // 4 |дни недели |    дни месяца     |  1..7 (0 - не используется), 1..31
  // 5 |       RES     |    месяцы     |  1..12
  // 6 |RES|          годы             |  0..99
  Result:= 7;
  try
    If (Buf^[2] and $80) = 0 then begin
      // значение действительно
      MS:= Buf^[0] + 256*Buf^[1];
      DT:= EncodeDateTime((Buf^[6] and $7F) + 2000,         // year
                          Buf^[5] and $1F,                  // month
                          Buf^[4] and $1F,                  // day
                          Buf^[3] and $1F,                  // hour
                          Buf^[2] and $3F,                  // minute
                          MS div 1000,                      // second
                          MS mod 1000);                     // msecond
    end else DT:= 0;      // значение не действительно
  except
    DT:= 0;
  end;
end;
//
function encodeCP56Time2a(Buf: PByteArray; DT: TDateTime; ADTValid: Boolean): Integer;
var Year, Month, Day, Hour, Minute, Second, MSecond, MS: Word;
begin
  try
    DecodeDateTime(DT, Year, Month, Day, Hour, Minute, Second, MSecond);
    MS:= Second*1000 + MSecond;
    Buf^[0]:= Lo(MS);
    Buf^[1]:= Hi(MS);
    Buf^[2]:= Minute;
    If not ADTValid then Buf^[2]:= Buf^[2] or $80;
    Buf^[3]:= Hour;
    Buf^[4]:= Day;
    Buf^[5]:= Month;
    Buf^[6]:= Year - 2000;
  except
    // некорректное время
    FillChar(Buf^, 7, 0);
    Buf^[2]:= $80;
  end;
  Result:= 7;
end;
//
function encodeCP24Time2a(Buf: PByteArray; DT: TDateTime; ADTValid: Boolean): Integer;
var Year, Month, Day, Hour, Minute, Second, MSecond, MS: Word;
begin
  //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
  //   +---+---+---+---+---+---+---+---+
  // 0 |   миллисекунды, младший байт  |
  // 1 |   миллисекунды, старший байт  |  0..59999 мс
  // 2 |IV |RES|      минуты           |  0..59, IV - недействительное значение, RES=0 - Genuine time, RES=1 - Substituted time
  DecodeDateTime(DT, Year, Month, Day, Hour, Minute, Second, MSecond);
  MS:= Second*1000 + MSecond;
  Buf^[0]:= Lo(MS);
  Buf^[1]:= Hi(MS);
  Buf^[2]:= Minute;
  If not ADTValid then Buf^[2]:= Buf^[2] or $80;
  Result:= 3;
end;
//
function decodeUInt16(Buf: PByteArray; var CP16: Word): Integer;
begin
  CP16:= Buf^[0] + Buf^[1]*256;
  Result:= 2;
end;
//
function encodeUInt16(Buf: PByteArray; CP16: Word): Integer;
begin
  Buf^[0]:= Lo(CP16);
  Buf^[1]:= Hi(CP16);
  Result:= 2;
end;
//
function decodeUInt32(Buf: PByteArray; var CP32: LongWord): Integer;
begin
  CP32:= Buf^[0] + Buf^[1]*256 + Buf^[2]*256*256 + Buf^[3]*256*256*256;
  Result:= 4;
end;
//
function QCCDescription(V: Byte): String;
begin
  Case V of
    0:    result:= 'Not used';
    1..4: result:= 'Request of counters group ' + IntToStr(V);            // запрос счётчиков группы N
    5:    result:= 'General request of counters';                         // общий запрос счётчиков
    else  result:= 'Reserv (' + IntToStr(V) + ')';
  end;
end;

end.