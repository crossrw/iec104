{$I eDefines.inc}

unit iec104;

interface

uses Classes, SysUtils, Contnrs, blcksock, SynaUtil, syncobjs, iec104utils;

{$DEFINE DEBUG_IEC104}

// server IEC104
type  TIECCommand = class
      private
        FASDUType:  Byte;                                         // идентификатор типа для общего опроса
        FIOAddress: LongWord;                                     // адрес объекта информации
        FCOT:       Byte;                                         // причина передачи
        FDT:        TDateTime;
        FValue:     Variant;
      public
        constructor Create(AASDUType: Byte; AIOAddress: LongWord; ACOT: Byte; ADT: TDateTime; const AValue: Variant);
        //
        property Value: Variant read FValue;
      end;

      TIEC104Server = class(TThread)
      private
        FSock: TTCPBlockSocket;
        FHandlerList: array[0..MAX_CLIENT_COUNT-1] of TThread;
        FCmdCritSection: TCriticalSection;
        FRecCommands: TObjectQueue;
        FIOList: TThreadList;
        //
        FUseORGAddress: Boolean;
        FCASize: Integer;
        FIOASize: Integer;
        FMaxUnconfirmedPackets: Integer;
        FCA: Word;
        //
        procedure SetCA(ACA: Word);
        procedure SetIOASize(AIOASize: Integer);
        procedure SetCASize(ACASize: Integer);
        procedure SetMaxUnconfirmedPackets(AMaxUnconfirmedPackets: Integer);
        //
        function GetIndexOfFreeHandler(): Integer;
        //
        function GetIOByAddress(AIOAddress: LongWord): TInformationObject;
        procedure PushCommand(IECCommand: TIECCommand);
        //
        procedure AddLog(ALogLevel: Integer; const AMessage: String);
      public
        constructor Create(const IP, Port: String);
        destructor Destroy; override;
        //
        // AASDUType  - тип данных, используемый при опросе
        // ASASDUType - тип данных, используемый при спорадической передаче (0 если не используется спорадическая передача)
        // AIOAddress - адрес объекта информации
        // AGroup     - группа (1..16), 0 - общая группа
        procedure AddIOValue(AASDUType, ASASDUType: Byte; AIOAddress: LongWord; const AGroup: Integer = 0);
        procedure SetIOValue(AIOAddress: LongWord; const AValue: Variant);
        procedure SetIOBadQuality(AIOAddress: LongWord);
        //
        function GetCommand(): TIECCommand;
        //
        property UseORGAddress: Boolean read FUseORGAddress write FUseORGAddress;                             // использовать адрес инициатора
        property ASDUAddress: Word read FCA write SetCA;                                                      // общий адрес ASDU
        property ASDUAddressSize: Integer read FCASize write SetCASize;                                       // длина общего адреса (1 или 2)
        property IOASize: Integer read FIOASize write SetIOASize;                                             // длина адреса объекта информации (1, 2 или 3)
        property MaxUnconfirmedPackets: Integer read FMaxUnconfirmedPackets write SetMaxUnconfirmedPackets;   // максимальное количество неподтвержденных пакетов
      protected
        procedure Execute; override;
     end;

implementation

uses dateutils, variants, iec104defs, iec104time;

type TIEC104Handler = class(TThread)
      private
        FOwner: TIEC104Server;
        FSock: TTCPBlockSocket;
        FMyIndex: Integer;
        //
        FTestFRTimer:  LongWord;                                                // таймер тестирования канала
        FSporadicTimer:LongWord;                                                // таймер спорадической рассылки
        FConfirmTimer: LongWord;                                                // таймер задержки перед подтверждением принимаемых пакетов
        FTestFRActive: Boolean;                                                 // признак ожидания ответа на тестирование канала
        //
        FStartDT: Boolean;                                                      // разрешено передавать данные
        //
        WaitRecNumber: Word;                                                    // ожидаемый номер принимаемого пакета
        ConfRecNumber: Word;                                                    // последний подтвержденный номер принимаемого пакета
        NextSendNumber: Word;                                                   // номер следующего передаваемого пакета
        //
        FTimeDelay: Word;                                                       // запаздывание канала связи
        //
        FTypeGroups: array[1..37] of TList;                                     // используется при группировке IO
        //
        procedure SendSConfirmation;
        procedure SendUConfirmation(B: Byte);
        procedure SendIFormat(ASDU: PByteArray; ASDULen: Byte);
        //
        procedure SendIASDU(COT: Byte; IO: TInformationObject); overload;
        procedure SendIASDU(COT: Byte; ASDUType: Byte; IOList: TList); overload;
        procedure SendIASDU(COT: Byte; ASDUType: Byte; IOAddress: LongWord; const Value: Variant); overload;
        //
        procedure SendCounterInterrogation(RQT: Byte);
        procedure SendInterrogation(QOI: Byte);
        procedure SendSporadic();
        //
        function decodeDataBlockId(ASDU: PByteArray; var ASDUDataBlockId: TASDUDataBlockId): Integer;
        function encodeIOA(ASDU: PByteArray; const IOA: LongWord): Integer;
        function decodeIOA(ASDU: PByteArray; var IOA: LongWord): Integer;
        function encodeCA(ASDU: PByteArray; const CA: Word): Integer;
        //
        function isBroadcastASDUAddress(ASDUAddress: Word): Boolean;
        procedure ParseASDU(ASDU: PByteArray; ASDULen: Byte);
        procedure PushCommand(const ADataBlockId: TASDUDataBlockId; IO: TInformationObject; ADT: TDateTime; AValue: Variant);
        procedure ClearChangeStatus;
        //
        function TestFRTimerExpired: Boolean;
        procedure ResetTestFRTimer;
        //
        function ConfirmTimerExpired: Boolean;
        procedure ResetConfirmTimer;
        //
        procedure Disconnect;
        //
        procedure AddLog(ALogLevel: Integer; const AMessage: String);
        procedure DebugPrint(const ASDUDataBlockId: TASDUDataBlockId);
      public
        constructor Create(AOwner: TIEC104Server; ASock, AIndex: Integer);
        destructor Destroy; override;
      protected
        procedure Execute; override;
     end;

const LOG_ERR   = 3;
      LOG_DEBUG = 7;

      BIT_PN    = $40;                          // P/N: 0 - положительное подтверждение, 1 - отрицательное подтверждение
      BIT_TEST  = $80;                          // T:   1 - тест (проверка без управления)
      BIT_SQ    = $80;                          // классификатор переменной структуры

const READ_TIMEOUT    = 100;                    // тайм-аут чтения из сокета
      TESTFRTIMEOUT   = 60000;                  // тайм-аут проверок канала при отсутствии активности
      FRCONFTIMEOUT   = 10000;                  // время ожидания ответа на проверку активности канала
      SPORADICPERIOD  = 1000;                   // период проверки необходимости спорадической передачи
      CONFIRMDELAY    = 3000;                   // задержка перед подтверждением приема пакетов

constructor TIEC104Server.Create(const IP, Port: String);
var I: Integer;
begin
{$IFDEF DEBUG_IEC104}
  AddLog(LOG_DEBUG, Format('IEC104 daemon created, listen on %s:%s', [IP, Port]));
{$ENDIF}
  inherited Create(True);
  //
  For I:= 0 to MAX_CLIENT_COUNT-1 do FHandlerList[I]:= Nil;
  FRecCommands:= TObjectQueue.Create();
  FIOList:= TThreadList.Create;
  //
  FCmdCritSection:= TCriticalSection.Create();
  FMaxUnconfirmedPackets:= 128;
  FUseORGAddress:= True;
  FIOASize:= 3;
  FCASize:= 2;
  FCA:= 1;
  //
  FSock:= TTCPBlockSocket.Create;
  FSock.CreateSocket;
  FSock.EnableReuse(True);
  FSock.Bind(IP, Port);
  If FSock.LastError <> 0 then AddLog(LOG_ERR, Format('can''t bind socket:%s code:%d', [FSock.LastErrorDesc, FSock.LastError]));
  FSock.Listen;
  If FSock.LastError <> 0 then AddLog(LOG_ERR, Format('can''t listen socket:%s code:%d', [FSock.LastErrorDesc, FSock.LastError]));
end;

destructor TIEC104Server.Destroy;
var I: Integer;
begin
{$IFDEF DEBUG_IEC104}
  AddLog(LOG_DEBUG, 'TIEC104Server destroyed');
{$ENDIF}
  inherited;
  // удаление обработчиков
  For I:= 0 to MAX_CLIENT_COUNT-1 do begin
    If FHandlerList[I] <> Nil then FreeAndNil(FHandlerList[I]);
  end;
  FreeAndNil(FCmdCritSection);
  While FRecCommands.Count > 0 do FRecCommands.Pop.Free;
  FreeAndNil(FRecCommands);
  With FIOList.LockList do try
    For I:= 1 to Count do TInformationObject(Items[I-1]).Free;
  finally
    FIOList.UnlockList;
  end;
  FreeAndNil(FIOList);
  FreeAndNil(FSock);
end;

procedure TIEC104Server.SetIOASize(AIOASize: Integer);
begin
  If not (AIOASize in [1,2,3]) then raise EIEC104Exception.CreateFmt('invalid value of information object address size: %d', [AIOASize]);
  FIOASize:= AIOASize;
end;

procedure TIEC104Server.SetCASize(ACASize: Integer);
begin
  If not (ACASize in [1,2]) then raise EIEC104Exception.CreateFmt('invalid value of common address size: %d', [ACASize]);
  FCASize:= ACASize;
end;

procedure TIEC104Server.SetCA(ACA: Word);
begin
  If FCASize = 1 then begin
    If ACA > $FE then raise EIEC104Exception.Create('invalid value of common address');
  end else begin
    If ACA > $FFFE then raise EIEC104Exception.Create('invalid value of common address');
  end;
  FCA:= ACA;
end;

procedure TIEC104Server.SetMaxUnconfirmedPackets(AMaxUnconfirmedPackets: Integer);
begin
  If (AMaxUnconfirmedPackets < 1) or (AMaxUnconfirmedPackets > 32767) then raise EIEC104Exception.Create('invalid value of MaxUnconfirmedPackets');
  FMaxUnconfirmedPackets:= AMaxUnconfirmedPackets;
end;

function TIEC104Server.GetIndexOfFreeHandler(): Integer;
var FreeIndex, I: Integer;
begin
  // расчистка списка соединений и получение индекса свободного соединения
  FreeIndex:= -1;
  For I:= MAX_CLIENT_COUNT-1 downto 0 do begin
    If FHandlerList[I] <> Nil then begin
      If TIEC104Handler(FHandlerList[I]).Terminated then begin
        FreeAndNil(FHandlerList[I]);
        FreeIndex:= I;
      end;
    end else FreeIndex:= I;
  end;
  Result:= FreeIndex;
end;

function TIEC104Server.GetIOByAddress(AIOAddress: LongWord): TInformationObject;
var IO: TInformationObject;
    I: Integer;
begin
  result:= Nil;
  With FIOList.LockList do try
    For I:= 1 to Count do begin
      IO:= TInformationObject(Items[I-1]);
      If IO.IOAddress = AIOAddress then begin
        result:= IO;
        Exit;
      end;
    end;
  finally
    FIOList.UnlockList;
  end;
end;

procedure TIEC104Server.AddIOValue(AASDUType, ASASDUType: Byte; AIOAddress: LongWord; const AGroup: Integer = 0);
begin
  // If (AASDUType < M_SP_NA_1) or (AASDUType > M_EP_TF_1) or (AASDUType in [22..29]) then raise EIEC104Exception.CreateFmt('invalid ASDU type value:%u', [AASDUType]);
  // If (ASASDUType < M_SP_NA_1) or (AASDUType > M_EP_TF_1) or (AASDUType in [22..29]) then raise EIEC104Exception.CreateFmt('invalid spontaneous ASDU type value:%u', [ASASDUType]);
  //
  If GetIOByAddress(AIOAddress) <> Nil then raise EIEC104Exception.CreateFmt('duplicate information object address:%u', [AIOAddress]);
  FIOList.Add(TInformationObject.Create(AASDUType, ASASDUType, AIOAddress, AGroup));
end;

procedure TIEC104Server.SetIOValue(AIOAddress: LongWord; const AValue: Variant);
var IO: TInformationObject;
begin
  IO:= GetIOByAddress(AIOAddress);
  If IO = Nil then raise EIEC104Exception.CreateFmt('information object with address %u not found', [AIOAddress]);
  IO.SetValue(AValue);
end;

procedure TIEC104Server.SetIOBadQuality(AIOAddress: LongWord);
var IO: TInformationObject;
begin
  IO:= GetIOByAddress(AIOAddress);
  If IO = Nil then raise EIEC104Exception.CreateFmt('information object with address %u not found', [AIOAddress]);
  IO.SetBadQuality();
end;

procedure TIEC104Server.PushCommand(IECCommand: TIECCommand);
begin
  FCmdCritSection.Enter;
  try
    If FRecCommands.Count < MAX_COMMANDS_COUNT then FRecCommands.Push(IECCommand);
  finally
    FCmdCritSection.Leave;
  end;
end;

function TIEC104Server.GetCommand(): TIECCommand;
begin
  FCmdCritSection.Enter;
  try
    If FRecCommands.Count > 0 then result:= TIECCommand(FRecCommands.Pop) else result:= Nil;
  finally
    FCmdCritSection.Leave;
  end;
end;

procedure TIEC104Server.Execute;
var IEC104Handler: TIEC104Handler;
    ClientSock, I: Integer;
begin
  With FSock do begin
    While not Terminated do begin
      try
        If CanRead(1000) then begin
          ClientSock:= Accept;
          If LastError = 0 then begin
            I:= GetIndexOfFreeHandler();
            If I >= 0 then begin
              IEC104Handler:= TIEC104Handler.Create(Self, ClientSock, I);
              FHandlerList[I]:= IEC104Handler;
            end else AddLog(LOG_ERR, 'too many connections, refused');
          end else AddLog(LOG_ERR, Format('Accept() failure:%s code:%d', [LastErrorDesc, LastError]));
        end;
      except
        on E: Exception do AddLog(LOG_ERR, 'exception on TIEC104Server.Execute:'+E.Message);
        else AddLog(LOG_ERR, 'unknown exception on TIEC104Server.Execute');
      end;
    end;
  end;
end;

procedure TIEC104Server.AddLog(ALogLevel: Integer; const AMessage: String);
begin
{$IFDEF DEBUG_IEC104}
  Writeln(Format('IEC_SRV: %s', [AMessage]));
{$ENDIF}
end;

// -----------------------------------------------------------------------------

constructor TIEC104Handler.Create(AOwner: TIEC104Server; ASock, AIndex: Integer);
var I: Integer;
begin
  inherited Create(True);
  //
  FMyIndex:= AIndex;
  {$IFDEF DEBUG_IEC104}
  AddLog(LOG_DEBUG, 'TIEC104Handler created');
  {$ENDIF}
  FSock:= TTCPBlockSocket.Create;
  FSock.Socket:= ASock;
  FSock.MaxLineLength:= 1024;
  FOwner:= AOwner;
  //
  For I:= Low(FTypeGroups) to High(FTypeGroups) do FTypeGroups[I]:= TList.Create;
  //
  FStartDT:= False;
  //
  WaitRecNumber:= 0;                                                            // ожидаемый номер принимаемого пакета
  ConfRecNumber:= 0;                                                            // последний подтвержденный номер принимаемого пакета
  NextSendNumber:= 0;                                                           // номер следующего передаваемого пакета
  //
  FTestFRActive:= False;
  FSporadicTimer:= 0;                                                           // таймер спорадической рассылки
  FConfirmTimer:= 0;                                                            // таймер задержки перед подтверждением принимаемых пакетов
  FTestFRTimer:= 0;                                                             // таймер тестирования канала
  //
  FTimeDelay:= 0;                                                               // запаздывание канала связи
  //
  Start;
end;

destructor TIEC104Handler.Destroy;
var I: Integer;
begin
  inherited;
  //
  For I:= Low(FTypeGroups) to High(FTypeGroups) do FTypeGroups[I].Free;
  FreeAndNil(FSock);
end;

// подтверждение принятых "I" пакетов
procedure TIEC104Handler.SendSConfirmation;
var SendBuf: array[0..5] of Byte;
begin
  SendBuf[0]:= $68;
  SendBuf[1]:= 4;                               // len
  SendBuf[2]:= 1;                               // format S
  SendBuf[3]:= 0;                               // not use
  SendBuf[4]:= (WaitRecNumber shl 1) and $FE;   // NR (LO)
  SendBuf[5]:= (WaitRecNumber shr 7) and $FF;   // NR (HI)
  //
  FSock.SendBuffer(@SendBuf, 6);
  //
  ConfRecNumber:= WaitRecNumber;
  {$IFDEF DEBUG_IEC104}
  AddLog(LOG_DEBUG, '-> send "S": NR=' + IntToStr(WaitRecNumber));
  {$ENDIF}
end;

procedure TIEC104Handler.SendUConfirmation(B: Byte);
var SendBuf: array[0..5] of Byte;
begin
  SendBuf[0]:= $68;
  SendBuf[1]:= 4;                               // len
  SendBuf[2]:= B;                               // control field
  SendBuf[3]:= 0;                               // not use
  SendBuf[4]:= 0;                               // not use
  SendBuf[5]:= 0;                               // not use
  //
  FSock.SendBuffer(@SendBuf, 6);
  {$IFDEF DEBUG_IEC104}
  Case B of
    TESTFR_ACT:  AddLog(LOG_DEBUG, '-> send "U": TESTFR.act');
    TESTFR_CON:  AddLog(LOG_DEBUG, '-> send "U": TESTFR.con');
    STARTDT_CON: AddLog(LOG_DEBUG, '-> send "U": STARTDT.con');
    STOPDT_CON:  AddLog(LOG_DEBUG, '-> send "U": STOPDT.con');
    else AddLog(LOG_DEBUG, '-> send "U"');
  end;
  {$ENDIF}
end;

procedure TIEC104Handler.SendIFormat(ASDU: PByteArray; ASDULen: Byte);
var SendBuf: array[0..255] of Byte;
begin
  SendBuf[0]:= $68;
  SendBuf[1]:= ASDULen + 4;                     // len
  SendBuf[2]:= (NextSendNumber shl 1) and $FE;  // NS (LO) + format I
  SendBuf[3]:= (NextSendNumber shr 7) and $FF;  // NS (HI)
  SendBuf[4]:= (WaitRecNumber shl 1) and $FE;   // NR (LO)
  SendBuf[5]:= (WaitRecNumber shr 7) and $FF;   // NR (HI)
  Move(ASDU^, SendBuf[6], ASDULen);
  //
  FSock.SendBuffer(@SendBuf, ASDULen + 6);
  {$IFDEF DEBUG_IEC104}
  AddLog(LOG_DEBUG, Format('-> send "I", NS:%u NR:%u ASDUId:"%s" IOCount:%u COT:"%s"', [NextSendNumber, WaitRecNumber, IECASDUTypeShortDescription(ASDU^[0]), ASDU^[1], IECASDUCOTDescription(ASDU^[2])]));
  {$ENDIF}
  //
  NextSendNumber:= (NextSendNumber + 1) and $7FFF;
  ConfRecNumber:= WaitRecNumber;
end;

procedure TIEC104Handler.SendIASDU(COT: Byte; IO: TInformationObject);
var ASDU: array[0..255] of Byte;
    Offset: Integer;
begin
  // если данные не установлены, то ничего не делаем
  If not IO.DataReady then Exit;
  //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
  //   +---+---+---+---+---+---+---+---+
  // 0 |                               |  идентификатор типа
  // 1 |SQ |     Number of objects     |  классификатор переменной структуры
  // 2 | T |P/N|        COT            |  COT - причина передачи, T:1 - тест (проверка без управления), P/N:0 - положительное подтверждение, P/N:1 - отрицательное подтверждение
  // 3 |              ORG              |  адрес инициатора, может отсутствовать
  // 4 |   Common ASDU address (LO)    |  общий адрес ASDU, может быть один или два байта
  // 5 |   Common ASDU address (HI)    |
  ASDU[0]:= IO.ASDUType(COT = COT_SPONT); // идентификатор типа
  ASDU[1]:= 1;                            // число объектов 1, SQ=0
  ASDU[2]:= COT;                          // причина передачи
  // устанавливаем бит P/N в случае ошибки IEC 60870-5-101 (7.2.3)
  If COT in [COT_BADTYPEID, COT_BADCOT, COT_BADCA, COT_BADIOA] then ASDU[2]:= ASDU[2] or BIT_PN;
  Offset:= 3;
  // адрес инициатора
  If FOwner.FUseORGAddress then begin
    ASDU[Offset]:= 0;
    Offset:= Offset + 1;
  end;
  // общий адрес ASDU (1 или 2 байта)
  Offset:= Offset + encodeCA(@ASDU[Offset], FOwner.FCA);
  // объект информации:
  Offset:= Offset + encodeIOA(@ASDU[Offset], IO.IOAddress);
  Offset:= Offset + IO.EncodeIOData(@ASDU[Offset], COT = COT_SPONT);
  // передача пакета
  SendIFormat(@ASDU, Offset);
  IO.ClearChangeStatus(FMyIndex);
end;

procedure TIEC104Handler.SendIASDU(COT: Byte; ASDUType: Byte; IOList: TList);
var ASDU: array[0..255] of Byte;
    Offset, IOIndex: Integer;
    IO: TInformationObject;
    IOCounter: Byte;
begin
  IOIndex:= 0;
  //
  repeat
    IOCounter:= 0;                          // счетчик IO
    //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    //   +---+---+---+---+---+---+---+---+
    // 0 |                               |  идентификатор типа
    // 1 |SQ |     Number of objects     |  классификатор переменной структуры
    // 2 | T |P/N|        COT            |  COT - причина передачи, T:1 - тест (проверка без управления), P/N:0 - положительное подтверждение, P/N:1 - отрицательное подтверждение
    // 3 |              ORG              |  адрес инициатора, может отсутствовать
    // 4 |   Common ASDU address (LO)    |  общий адрес ASDU, может быть один или два байта
    // 5 |   Common ASDU address (HI)    |
    //
    ASDU[0]:= ASDUType;                     // идентификатор типа
    ASDU[1]:= 0;                            // число объектов N, SQ=0
    ASDU[2]:= COT;                          // причина передачи
    Offset:= 3;
    // адрес инициатора
    If FOwner.FUseORGAddress then begin
      ASDU[Offset]:= 0;
      Offset:= Offset + 1;
    end;
    // общий адрес ASDU (1 или 2 байта)
    Offset:= Offset + encodeCA(@ASDU[Offset], FOwner.FCA);
    // объекты информации:
    repeat
      IO:= TInformationObject(IOList[IOIndex]);
      Offset:= Offset + encodeIOA(@ASDU[Offset], IO.IOAddress);
      Offset:= Offset + IO.EncodeIOData(@ASDU[Offset], False);
      IOCounter:= IOCounter + 1;
      IOIndex:= IOIndex + 1;
    until (Offset > 220) or (IOCounter >= 126) or (IOIndex >= IOList.Count);
    ASDU[1]:= IOCounter;                    // число объектов N, SQ=0
    // передача пакета
    SendIFormat(@ASDU, Offset);
  until IOIndex >= IOList.Count;
end;

procedure TIEC104Handler.SendIASDU(COT: Byte; ASDUType: Byte; IOAddress: LongWord; const Value: Variant);
var IO: TInformationObject;
begin
  IO:= TInformationObject.Create(ASDUType, ASDUType, IOAddress, -1);
  try
    IO.SetValue(Value);
    SendIASDU(COT, IO);
  finally
    FreeAndNil(IO);
  end;
end;

procedure TIEC104Handler.SendCounterInterrogation(RQT: Byte);
var IO: TInformationObject;
    I: Integer;
begin
  // групповой метод (более эффективен)
  For I:= Low(FTypeGroups) to High(FTypeGroups) do FTypeGroups[I].Clear;
  // группируем IO по типам
  With FOwner.FIOList.LockList do try
    For I:= 1 to Count do begin
      IO:= TInformationObject(Items[I-1]);
      // передаем содержимое всех переменных с идентификаторами типов M_IT_NA_1, M_IT_TA_1, M_IT_TB_1 (IEC60870-5-101 7.4.5)
      If IO.DataReady and (IO.ASDUType(False) in [M_IT_NA_1, M_IT_TA_1, M_IT_TB_1]) and ((RQT = 5) or (RQT = IO.Group)) then FTypeGroups[IO.ASDUType(False)].Add(IO);
    end;
  finally
    FOwner.FIOList.UnlockList;
  end;
  // передаем данные
  For I:= Low(FTypeGroups) to High(FTypeGroups) do begin
    If FTypeGroups[I].Count > 0 then begin
      If RQT = 5 then SendIASDU(COT_REQCOGEN, I, FTypeGroups[I]) else SendIASDU(COT_REQCOGEN + RQT, I, FTypeGroups[I]);
    end;
  end;
  //
  // передача IO отдельными пакетами (менее эффективен)
  // With FOwner.FIOList.LockList do try
  //   For I:= 1 to Count do begin
  //     IO:= TInformationObject(Items[I-1]);
  //     If IO.ASDUType(False) in [M_IT_NA_1, M_IT_TA_1, M_IT_TB_1] then begin
  //       If RQT = 5 then        SendIASDU(COT_REQCOGEN, IO) else
  //       If IO.Group = RQT then SendIASDU(COT_REQCOGEN + RQT, IO);
  //     end;
  //   end;
  // finally
  //   FOwner.FIOList.UnlockList;
  // end;
end;

procedure TIEC104Handler.SendInterrogation(QOI: Byte);
var IO: TInformationObject;
    I: Integer;
begin
  // групповой метод (более эффективен)
  For I:= Low(FTypeGroups) to High(FTypeGroups) do FTypeGroups[I].Clear;
  // группируем IO по типам
  With FOwner.FIOList.LockList do try
    For I:= 1 to Count do begin
      IO:= TInformationObject(Items[I-1]);
      // передаем содержимое всех переменных с идентификаторами типов <1>, <3>, <5>, <7>, <9>, <11>, <13>, <20> или <21> (IEC60870-5-101 7.4.5)
      // If IO.ASDUType(False) in [M_SP_NA_1, M_DP_NA_1, M_ST_NA_1, M_BO_NA_1, M_ME_NA_1, M_ME_NB_1, M_ME_NC_1, M_PS_NA_1, M_ME_ND_1] then begin
      If IO.DataReady and (IO.ASDUType(False) in [1..14, 20, 21, 30..36]) and ((QOI = COT_INTROGEN) or (IO.Group = (QOI - 20))) then FTypeGroups[IO.ASDUType(False)].Add(IO);
    end;
  finally
    FOwner.FIOList.UnlockList;
  end;
  // передаем данные
  For I:= Low(FTypeGroups) to High(FTypeGroups) do begin
    If FTypeGroups[I].Count > 0 then SendIASDU(QOI, I, FTypeGroups[I]);
  end;
  //
  // передача IO отдельными пакетами (менее эффективен)
  // With FOwner.FIOList.LockList do try
  //   For I:= 1 to Count do begin
  //     IO:= TInformationObject(Items[I-1]);
  //     // передаем содержимое всех переменных с идентификаторами типов <1>, <3>, <5>, <7>, <9>, <11>, <13>, <20> или <21> (IEC60870-5-101 7.4.5)
  //     // If IO.ASDUType(False) in [M_SP_NA_1, M_DP_NA_1, M_ST_NA_1, M_BO_NA_1, M_ME_NA_1, M_ME_NB_1, M_ME_NC_1, M_PS_NA_1, M_ME_ND_1] then begin
  //     If (IO.ASDUType(False) in [1..14, 20, 21, 30..36]) and ((QOI = COT_INTROGEN) or (IO.Group = (QOI - 20))) then SendIASDU(QOI, IO);
  //   end;
  // finally
  //   FOwner.FIOList.UnlockList;
  // end;
end;

procedure TIEC104Handler.SendSporadic();
var IO: TInformationObject;
    GT: LongWord;
    I: Integer;
begin
  // проверка таймера спорадической передачи, передача не чаще одного раза в SPORADICPERIOD мс
  GT:= GetTick();
  If TickDelta(FSporadicTimer, GT) < SPORADICPERIOD then Exit;
  FSporadicTimer:= GT;
  //
  With FOwner.FIOList.LockList do try
    For I:= 1 to Count do begin
      IO:= TInformationObject(Items[I-1]);
      If IO.NeedSporadic(FMyIndex) then SendIASDU(COT_SPONT, IO);
    end;
  finally
    FOwner.FIOList.UnlockList;
  end;
end;

function TIEC104Handler.decodeDataBlockId(ASDU: PByteArray; var ASDUDataBlockId: TASDUDataBlockId): Integer;
var Offset: Integer;
begin
  //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
  //   +---+---+---+---+---+---+---+---+
  // 0 |                               |  идентификатор типа
  // 1 |SQ |     Number of objects     |  классификатор переменной структуры
  // 2 | T |P/N|        COT            |  COT - причина передачи, T:1 - тест (проверка без управления), P/N:0 - положительное подтверждение, P/N:1 - отрицательное подтверждение
  // 3 |              ORG              |  адрес инициатора, может отсутствовать
  // 4 |   Common ASDU address (LO)    |  общий адрес ASDU, может быть один или два байта
  // 5 |   Common ASDU address (HI)    |
  //
  ASDUDataBlockId.ASDUType:= ASDU^[0];
  ASDUDataBlockId.NumberOfObjects:= ASDU^[1] and $7F;
  ASDUDataBlockId.SQ:=    (ASDU^[1] and BIT_SQ) <> 0;
  ASDUDataBlockId.PN:=    (ASDU^[2] and BIT_PN) <> 0;
  ASDUDataBlockId.Test:=  (ASDU^[2] and BIT_TEST) <> 0;
  ASDUDataBlockId.COT:=   ASDU^[2] and $3F;
  Offset:= 3;
  If FOwner.FUseORGAddress then begin
    ASDUDataBlockId.ORG:= ASDU^[Offset];
    Offset:= Offset + 1;
  end else ASDUDataBlockId.ORG:= 0;
  //
  If FOwner.FCASize = 2 then begin
    ASDUDataBlockId.ASDUAddress:= ASDU^[Offset] + 256*ASDU^[Offset + 1];
    Offset:= Offset + 2;
  end else begin
    ASDUDataBlockId.ASDUAddress:= ASDU^[Offset];
    Offset:= Offset + 1;
  end;
  //
  result:= Offset;
end;

function TIEC104Handler.encodeIOA(ASDU: PByteArray; const IOA: LongWord): Integer;
begin
  Case FOwner.FIOASize of
    1: begin
      ASDU^[0]:= IOA and $FF;
      result:= 1;
    end;
    2: begin
      ASDU^[0]:= IOA and $FF;
      ASDU^[1]:= (IOA shr 8) and $FF;
      result:= 2;
    end;
    3: begin
      ASDU^[0]:= IOA and $FF;
      ASDU^[1]:= (IOA shr 8) and $FF;
      ASDU^[2]:= (IOA shr 16) and $FF;
      result:= 3;
    end;
    else result:= 0;
  end;
end;

function TIEC104Handler.decodeIOA(ASDU: PByteArray; var IOA: LongWord): Integer;
begin
  Case FOwner.FIOASize of
    1: begin
      IOA:= ASDU^[0];
      result:= 1;
    end;
    2: begin
      IOA:= ASDU^[0] + 256*ASDU^[1];
      result:= 2;
    end;
    3: begin
      IOA:= ASDU^[0] + 256*(ASDU^[1] + 256*ASDU^[2]);
      result:= 3;
    end;
    else result:= 0;
  end;
end;

function TIEC104Handler.encodeCA(ASDU: PByteArray; const CA: Word): Integer;
begin
  If FOwner.FCASize = 2 then begin
    ASDU^[0]:= Lo(CA);
    ASDU^[1]:= Hi(CA);
    result:= 2;
  end else begin
    ASDU^[0]:= Lo(CA);
    result:= 1;
  end;
end;

function TIEC104Handler.isBroadcastASDUAddress(ASDUAddress: Word): Boolean;
begin
  If FOwner.FCASize = 2 then result:= ASDUAddress = $FFFF else result:= ASDUAddress = $FF;
end;

function BTOB(B: Boolean): Byte;
begin
  If B then result:= 1 else result:= 0;
end;

procedure TIEC104Handler.DebugPrint(const ASDUDataBlockId: TASDUDataBlockId);
begin
  AddLog(7, Format('   ASDU type:"%s"', [IECASDUTypeDescription(ASDUDataBlockId.ASDUType)]));
  AddLog(7, Format('   Number of objects:%u SQ:%u', [ASDUDataBlockId.NumberOfObjects, BTOB(ASDUDataBlockId.SQ)]));
  AddLog(7, Format('   COT:"%s"', [IECASDUCOTDescription(ASDUDataBlockId.COT)]));
  AddLog(7, Format('   T:%u P/N:%u', [BTOB(ASDUDataBlockId.Test), BTOB(ASDUDataBlockId.PN)]));
  AddLog(7, Format('   ORG:%u Common ASDU address:%u', [ASDUDataBlockId.ORG, ASDUDataBlockId.ASDUAddress]));
end;

procedure TIEC104Handler.ParseASDU(ASDU: PByteArray; ASDULen: Byte);
var ASDUDataBlockId: TASDUDataBlockId;
    ObjectIndex, Offset, I: Integer;
    QOI, QCC, RQT, QRP, SCO, DCO, RCO: Byte;
    IO: TInformationObject;
    IOA, BSI: LongWord;
    CP16, TSC: Word;
    DT: TDateTime;
    VV: Variant;
begin
  // разбор заголовка
  Offset:= decodeDataBlockId(ASDU, ASDUDataBlockId);
{$IFDEF DEBUG_IEC104}
  DebugPrint(ASDUDataBlockId);
{$ENDIF}
  // Если SQ=0, то после ASDU address идет последовательность "Information object" (IO)
  // Каждый IO состоит из IOA ("Information object address") (3 байта), "Information Elements" и "Time Tag" (не обязательно)
  //
  // Если SQ=1, то после ASDU address идет один "Information object", который состоит из "Information object address" (3 байта) и
  // последовательности "Information Element". В конце может присутствовать один "Time Tag".
  //
  // Разница в том, что при SQ=0 каждый из "Information Elements" имеет свой IOA и свой "Time Tag", при SQ=1 все "Information Elements"
  // имеют одинаковый IOA и единый "Time Tag".
  //
  // Проверка "Common ASDU address"
  If not (isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) or (ASDUDataBlockId.ASDUAddress = FOwner.FCA)) then begin
    AddLog(LOG_DEBUG, Format('ASDU address does not match: received:%u expexted:%u, packet is dropped', [ASDUDataBlockId.ASDUAddress, FOwner.FCA]));
    Exit;
  end;
  // использование широковещательного адреса допустимо только для следующих ASDU: C_IC_NA_1, C_CI_NA_1, C_CS_NA_1, C_RP_NA_1 (IEC60870-5-104 7.2.4)
  // цикл по объектам информации
  For ObjectIndex:= 1 to ASDUDataBlockId.NumberOfObjects do begin
    // Information object address
    If (not ASDUDataBlockId.SQ) or (ASDUDataBlockId.SQ and (ObjectIndex = 1)) then begin
      // если SQ=0 получаем адрес каждого очередного "Information object"
      // если SQ=1 получаем адрес только первого "Information object"
      Offset:= Offset + decodeIOA(@ASDU^[Offset], IOA);
    end else begin
      // если SQ=1 то адреса последующих "Information object" увеличиваются на 1: IEC 60870-5-101 (7.2.2.1)
      IOA:= IOA + 1;
    end;
{$IFDEF DEBUG_IEC104}
    AddLog(7, Format('    IO_index:%d IO_Address:%u', [ObjectIndex, IOA]));
{$ENDIF}
    // разбор "Information Object"
    Case ASDUDataBlockId.ASDUType of
      C_IC_NA_1: begin      // Interrogation command, допустим широковещательный адрес
        // Команда опроса C_IC ACT запрашивает полный объем или заданный определенный поднабор опрашиваемой информации на КП.
        // Поднабор (группа) выбирается с помощью описателя опроса QOI.
        // Команда опроса станции требует от контролируемых станций передать актуальное состояние их информации, обычно передаваемой спорадически (причина передачи = 3),
        // на контролирующую станцию с причинами передачи от <20> до <36>.
        // Опрос станции используется для синхронизации информации о процессе на контролирующей станции и контролируемых станциях.
        // Он также используется для обновления информации на контролирующей станции после процедуры инициализации или после того, как контролирующая станция обнаружит
        // потерю канала (безуспешное повторение запроса канального уровня) и последующее восстановление его.
        // Ответ на опрос станции должен включать объекты информации о процессе, которые запомнены на контролируемой станции.
        // В ответ на опрос станции эти объекты информации передаются с идентификаторами типов <1>, <3>, <5>, <7>, <9>, <11>, <13>, <20> или <21> и могут также передаваться в 
        // других ASDU с идентификаторами типов от <1> до <14>, <20>, <21>, от <30> до <36> и с причинами 
        // передачи <1> — периодически/циклически, <2> — фоновое сканирование или <3> — спорадически.
        //
        QOI:= ASDU^[Offset];
        // QOI - Qualifier of Interrogation, может принимать значения:
        // - General interrogation (общий опрос)
        // - Interrogation of group N (опрос группы N)
        If QOI in [20..36] then begin
          // общий опрос, опрос группы N
          AddLog(7, '    C_IC_NA_1: QUI=' + IntToStr(QOI));
          // В ответ надо передать:
          // - подтверждение активации C_IC_NA_1 с причиной передачи COT = 7 (confirmation activation)
          // - актуальное состояние всех точек измерения с причиной передачи COT = 20 (interrogated by general interrogation)
          // - завершение активации C_IC_NA_1 с причиной передачи COT = 10 (termination activation)
          If ASDUDataBlockId.COT = COT_ACT then begin
            // активация, подтверждение активации
            SendIASDU(COT_ACTCON, C_IC_NA_1, 0, QOI);
            // передаем содержимое всех переменных с идентификаторами типов <1>, <3>, <5>, <7>, <9>, <11>, <13>, <20> или <21> (IEC60870-5-101 7.4.5)
            SendInterrogation(QOI);
            // завершение активации
            SendIASDU(COT_ACTTERM, C_IC_NA_1, 0, QOI);
          end else
          If ASDUDataBlockId.COT = COT_DEACT then begin
            // деактивация, подтверждение деактивации
            SendIASDU(COT_DEACTCON, C_IC_NA_1, 0, QOI);
          end else SendIASDU(COT_BADCOT, C_IC_NA_1, 0, QOI);    // недопустимая причина передачи
        end else begin
          AddLog(7, Format('    QOI: Unknown %u', [QOI]));
        end;
      end;
      C_CI_NA_1: begin      // опрос счётчиков, допустим широковещательный адрес
        // qualifier of counter interrogation command
        //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
        //   +---+---+---+---+---+---+---+---+
        // 0 |  FRZ  |         RQT           |
        // RQT: 1 - запрос счетчиков группы 1
        //      2 - запрос счетчиков группы 2
        //      3 - запрос счетчиков группы 3
        //      4 - запрос счетчиков группы 4
        //      5 - общий запрос счетчиков
        // FRZ: 0 - просто чтение
        //      1 - counter freeze without reset (value frozen represents integrated total)
        //      2 - counter freeze with reset (value frozen represents incremental information)
        //      3 - сброс счётчиков
        QCC:= ASDU^[Offset];
        RQT:= QCC and $3F;
        AddLog(7, Format('    C_CI_NA_1: QCC=%u RQT=%u FRZ=%u', [QCC, RQT, (QCC shr 6) and $03]));
        // QСС - Qualifier of counter interrogation:
        // - общий опрос счетчиков (5)
        // - опрос счетчиков группы N (1..4)
        If RQT in [1..5] then begin
          If ASDUDataBlockId.COT = COT_ACT then begin
            // активация, подтверждение активации
            SendIASDU(COT_ACTCON, C_CI_NA_1, 0, QCC);
            // передаем содержимое всех переменных с идентификаторами типов <15>, <16>, <37> (IEC60870-5-101)
            SendCounterInterrogation(RQT);
            // завершение активации
            SendIASDU(COT_ACTTERM, C_CI_NA_1, 0, QCC);
          end else
          If ASDUDataBlockId.COT = COT_DEACT then begin
            // деактивация, подтверждение деактивации
            SendIASDU(COT_DEACTCON, C_CI_NA_1, 0, QCC);
          end else SendIASDU(COT_BADCOT, C_CI_NA_1, 0, QCC);          // недопустимая причина передачи
        end else begin
          AddLog(7, Format('    QCC: Unknown %u', [QCC]));
        end;
      end;
      C_RD_NA_1: begin      // команда чтения одного объекта
        AddLog(7, '  C_RD_NA_1:' + IntToStr(IOA));
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_RD_NA_1, IOA, 0);                    // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_REQ then begin
          // причина: запрос (5)
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // передаём данные объекта
            SendIASDU(COT_REQ, IO);
          end else SendIASDU(COT_BADIOA, C_RD_NA_1, IOA, 0);          // неизвестный адрес объекта информации
        end else SendIASDU(COT_BADCOT, C_RD_NA_1, IOA, 0);            // недопустимая причина передачи
      end;
      C_CS_NA_1: begin      // синхронизация часов, допустим широковещательный адрес
        decodeCP56Time2a(@ASDU^[Offset], DT);
        AddLog(7, '    C_CS_NA_1:' + FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', DT));
        If ASDUDataBlockId.COT = COT_ACT then begin
          // причина: активация (6)
          // возвращаем текущее время ДО корректировки, минус задержка в канале (IEC 60870-5-5 6.7)
          SendIASDU(COT_ACTCON, C_CS_NA_1, 0, IncMilliSecond(IECNow(), -FTimeDelay));
          // коррекция времени с учетом запаздывания передачи в канале
          If DT <> 0 then begin
            IECTimeDiff:= IncMilliSecond(DT, FTimeDelay) - Now();
            IECTimeValid:= True;
          end;
        end else SendIASDU(COT_BADCOT, C_CS_NA_1, 0, DT);             // недопустимая причина передачи
      end;
      C_TS_NA_1: begin      // тестирование канала связи
        AddLog(7, '    C_TS_NA_1');
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_TS_NA_1, 0, 0);                      // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // причина: активация (6)
          SendIASDU(COT_ACTCON, C_TS_NA_1, 0, 0);
        end else SendIASDU(COT_BADCOT, C_TS_NA_1, 0, 0);              // недопустимая причина передачи
      end;
      C_RP_NA_1: begin      // установка процесса в начальное состояние, допустим широковещательный адрес
        QRP:= ASDU^[Offset];
        AddLog(7, '    C_RP_NA_1: ' + IntToStr(QRP));
        // 0 - не используется
        // 1 - общая установка процесса в исходное состояние
        // 2 - удаление из буфера событий данных с меткой времени, относящихся к зависшим задачам ?
        If ASDUDataBlockId.COT = COT_ACT then begin
          // подтверждение
          SendIASDU(COT_ACTCON, C_RP_NA_1, 0, QRP);
          // передача сообщения M_EI_NA_1 (конец инициализации)
          SendIASDU(COT_INIT, M_EI_NA_1, 0, 2);
        end else SendIASDU(COT_BADCOT, C_RP_NA_1, 0, 0);              // недопустимая причина передачи
      end;
      C_CD_NA_1: begin      // команда определения запаздывания
        // Опции из МЭК 60870-5-5, подпункт 6.13:
        // C_CD_NA_1 СПОРАДИЧЕСКИ (установка запаздывания) в направлении управления используется.
        // Когда получена команда синхронизации часов, информация о времени должна быть скорректирована
        // контролируемой станцией на значение, полученное в команде установления значения запаздывания.
        decodeUInt16(@ASDU^[Offset], CP16);
        AddLog(7, '    C_CD_NA_1:' + IntToStr(CP16));
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_CD_NA_1, 0, CP16);                  // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT in [COT_SPONT, COT_ACT] then begin
          // подтверждение
          SendIASDU(COT_ACTCON, C_CD_NA_1, 0, CP16);
          FTimeDelay:= CP16;
        end else SendIASDU(COT_BADCOT, C_CD_NA_1, 0, CP16);          // недопустимая причина передачи
      end;
      C_TS_TA_1: begin      // команда тестирования c меткой времени
        //  TSC
        decodeUInt16(@ASDU^[Offset], TSC);
        //  CP56Time2a
        decodeCP56Time2a(@ASDU^[Offset+2], DT);
        AddLog(7, Format('    C_TS_TA_1: TSC:%u CP56Time2a:%s', [TSC, FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', DT)]));
        // передаем через массив вариантов
        VV:= VarArrayCreate([0, 1], varVariant);
        VV[0]:= TSC;
        VV[1]:= DT;
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_TS_TA_1, 0, VV);                   // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // причина: активация (6)
          SendIASDU(COT_ACTCON, C_TS_TA_1, 0, VV);
        end else SendIASDU(COT_BADCOT, C_TS_TA_1, 0, VV);            // недопустимая причина передачи
      end;
      P_ME_NA_1: begin      // TODO: Parameter of measured value, normalized value
        AddLog(7, '    P_ME_NA_1: not implemented');
      end;
      P_ME_NB_1: begin      // TODO: Parameter of measured value, scaled value
        AddLog(7, '    P_ME_NB_1: not implemented');
      end;
      P_ME_NC_1: begin      // TODO: Parameter of measured value, short floating point value
        AddLog(7, '    P_ME_NC_1: not implemented');
      end;
      P_AC_NA_1: begin      // TODO: Parameter activation
        AddLog(7, '    P_AC_NA_1: not implemented');
      end;
      C_SC_NA_1: begin      // одиночная команда
        // SCO: single command
        //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
        //   +---+---+---+---+---+---+---+---+
        // 0 |S/E|         QU        | 0 |SCS|
        // 
        // SCS - single command state: 0 - OFF, 1 - ON
        // QU:  0     - no additional definition
        //      1     - short pulse duration (circuit-breaker), duration determined by a system parameter in the outstation
        //      2     - long pulse duration, duration determined by a system parameter in the outstation
        //      3     - persistent output
        //      4..31 - reserved
        // S/E: 0 - execute, 1 - select
        SCO:= ASDU^[Offset];
        AddLog(7, '    C_SC_NA_1:' + IntToStr(SCO));
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_SC_NA_1, IOA, SCO);                    // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_SC_NA_1, C_SC_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_SC_NA_1, IOA, SCO);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, IECNow(), SCO);
            end else SendIASDU(COT_BADTYPEID, C_SC_NA_1, IOA, SCO);     // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_SC_NA_1, IOA, SCO);          // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_SC_NA_1, IOA, SCO);
        end else SendIASDU(COT_BADCOT, C_SC_NA_1, IOA, SCO);            // недопустимая причина передачи
      end;
      C_SC_TA_1: begin      // Single command with time stamp CP56Time2a
        SCO:= ASDU^[Offset];
        decodeCP56Time2a(@ASDU^[Offset+1], DT);
        AddLog(7, Format('    C_SC_TA_1: SCO:%u CP56Time2a:%s', [SCO, FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', DT)]));
        //
        VV:= VarArrayCreate([0, 1], varVariant);
        VV[0]:= SCO;
        VV[1]:= DT;
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_SC_TA_1, IOA, VV);                     // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_SC_NA_1, C_SC_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_SC_TA_1, IOA, VV);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, DT, SCO);
            end else SendIASDU(COT_BADTYPEID, C_SC_TA_1, IOA, VV);      // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_SC_TA_1, IOA, VV);           // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_SC_TA_1, IOA, VV);
        end else SendIASDU(COT_BADCOT, C_SC_TA_1, IOA, VV);             // недопустимая причина передачи
      end;
      C_DC_NA_1: begin      // двухпозиционная команда
        // DCO: double command
        //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
        //   +---+---+---+---+---+---+---+---+
        // 0 |S/E|         QU        |  DCS  |
        // 
        // DCS - double command state: 0 - not permitted, 1 - OFF, 2 - ON, 3 - not permitted
        // QU:  0     - no additional definition
        //      1     - short pulse duration (circuit-breaker), duration determined by a system parameter in the outstation
        //      2     - long pulse duration, duration determined by a system parameter in the outstation
        //      3     - persistent output
        //      4..31 - reserved
        // S/E: 0 - execute, 1 - select
        DCO:= ASDU^[Offset];
        AddLog(7, '    C_DC_NA_1:' + IntToStr(DCO));
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_DC_NA_1, IOA, DCO);                    // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_DC_NA_1, C_DC_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_DC_NA_1, IOA, DCO);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, IECNow(), DCO);
            end else SendIASDU(COT_BADTYPEID, C_DC_NA_1, IOA, DCO);       // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_DC_NA_1, IOA, DCO);            // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_DC_NA_1, IOA, DCO);
        end else SendIASDU(COT_BADCOT, C_DC_NA_1, IOA, DCO);              // недопустимая причина передачи
      end;
      C_DC_TA_1: begin      // двухпозиционная команда с меткой времени CP56Time2a
        DCO:= ASDU^[Offset];
        decodeCP56Time2a(@ASDU^[Offset+1], DT);
        AddLog(7, Format('    C_DC_TA_1: DCO:%u CP56Time2a:%s', [DCO, FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', DT)]));
        //
        VV:= VarArrayCreate([0, 1], varVariant);
        VV[0]:= DCO;
        VV[1]:= DT;
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_DC_TA_1, IOA, VV);                     // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_DC_NA_1, C_DC_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_DC_TA_1, IOA, VV);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, IECNow(), DCO);
            end else SendIASDU(COT_BADTYPEID, C_DC_TA_1, IOA, VV);      // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_DC_TA_1, IOA, VV);           // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_DC_TA_1, IOA, VV);
        end else SendIASDU(COT_BADCOT, C_DC_TA_1, IOA, VV);             // недопустимая причина передачи
      end;
      C_RC_NA_1: begin      // команда пошагового регулирования
        // RCO: double command
        //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
        //   +---+---+---+---+---+---+---+---+
        // 0 |S/E|         QU        |  RCS  |
        // 
        // RCS - regulating command state: 0 - not permitted, 1 - next step LOWER, 2 - next step HIGHER, 3 - not permitted
        // QU:  0     - no additional definition
        //      1     - short pulse duration (circuit-breaker), duration determined by a system parameter in the outstation
        //      2     - long pulse duration, duration determined by a system parameter in the outstation
        //      3     - persistent output
        //      4..31 - reserved
        // S/E: 0 - execute, 1 - select
        RCO:= ASDU^[Offset];
        AddLog(7, '    C_DC_NA_1:' + IntToStr(RCO));
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_RC_NA_1, IOA, RCO);                   // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_RC_NA_1, C_RC_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_RC_NA_1, IOA, RCO);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, IECNow(), RCO);
            end else SendIASDU(COT_BADTYPEID, C_RC_NA_1, IOA, RCO);     // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_RC_NA_1, IOA, RCO);          // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_RC_NA_1, IOA, RCO);
        end else SendIASDU(COT_BADCOT, C_RC_NA_1, IOA, RCO);            // недопустимая причина передачи
      end;
      C_RC_TA_1: begin      // команда пошагового регулирования с меткой времени
        RCO:= ASDU^[Offset];
        decodeCP56Time2a(@ASDU^[Offset+1], DT);
        AddLog(7, Format('    C_RC_TA_1: RCO:%u CP56Time2a:%s', [RCO, FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', DT)]));
        //
        VV:= VarArrayCreate([0, 1], varVariant);
        VV[0]:= RCO;
        VV[1]:= DT;
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_RC_TA_1, IOA, VV);                    // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_RC_NA_1, C_RC_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_RC_TA_1, IOA, VV);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, DT, RCO);
            end else SendIASDU(COT_BADTYPEID, C_RC_TA_1, IOA, VV);      // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_RC_TA_1, IOA, VV);           // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_RC_TA_1, IOA, VV);
        end else SendIASDU(COT_BADCOT, C_RC_TA_1, IOA, VV);             // недопустимая причина передачи
      end;
      C_SE_NA_1: begin      // TODO: Setpoint command, normalized value
        AddLog(7, '    C_SE_NA_1: not implemented');
      end;
      C_SE_NB_1: begin      // TODO: Setpoint command, scaled value
        AddLog(7, '    C_SE_NB_1: not implemented');
      end;
      C_SE_NC_1: begin      // TODO: Setpoint command, short floating point value
        AddLog(7, '    C_SE_NC_1: not implemented');
      end;
      C_SE_TA_1: begin      // TODO: Setpoint command, normalized value
        AddLog(7, '    C_SE_TA_1: not implemented');
      end;
      C_SE_TB_1: begin      // TODO: Setpoint command, scaled value
        AddLog(7, '    C_SE_TB_1: not implemented');
      end;
      C_SE_TC_1: begin      // TODO: Setpoint command, short floating point value
        AddLog(7, '    C_SE_TC_1: not implemented');
      end;
      C_BO_NA_1: begin      // Bit string 32 bit
        decodeUInt32(@ASDU^[Offset], BSI);
        AddLog(7, '    C_BO_NA_1:' + IntToStr(BSI));
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_BO_NA_1, IOA, BSI);                      // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_BO_NA_1, C_BO_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_BO_NA_1, IOA, BSI);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, IECNow(), BSI);
            end else SendIASDU(COT_BADTYPEID, C_BO_NA_1, IOA, BSI);       // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_BO_NA_1, IOA, BSI);            // неизвестный адрес объекта информации
        end else
        If ASDUDataBlockId.COT = COT_DEACT then begin
          // деактивация, подтверждение деактивации
          SendIASDU(COT_DEACTCON, C_BO_NA_1, IOA, BSI);
        end else SendIASDU(COT_BADCOT, C_BO_NA_1, IOA, BSI);              // недопустимая причина передачи
      end;
      C_BO_TA_1: begin      // Bit string 32 bit with timestamp
        decodeUInt32(@ASDU^[Offset], BSI);
        decodeCP56Time2a(@ASDU^[Offset+4], DT);
        AddLog(7, Format('    C_BO_TA_1: RCO:%u CP56Time2a:%s', [BSI, FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', DT)]));
        //
        VV:= VarArrayCreate([0, 1], varVariant);
        VV[0]:= BSI;
        VV[1]:= DT;
        //
        If isBroadcastASDUAddress(ASDUDataBlockId.ASDUAddress) then begin
          SendIASDU(COT_BADCA, C_BO_TA_1, IOA, VV);                       // неизвестный общий адрес ASDU
        end else
        If ASDUDataBlockId.COT = COT_ACT then begin
          // активация, подтверждение активации или COT_BADIOA неизвестный адрес
          IO:= FOwner.GetIOByAddress(IOA);
          If IO <> Nil then begin
            // проверка типа
            If IO.ASDUType(False) in [C_BO_NA_1, C_BO_TA_1] then begin
              // передаём подтверждение
              SendIASDU(COT_ACTCON, C_BO_TA_1, IOA, VV);
              // ставим команду в очередь
              PushCommand(ASDUDataBlockId, IO, DT, BSI);
            end else SendIASDU(COT_BADTYPEID, C_BO_TA_1, IOA, VV);        // неизвестный тип ASDU
          end else SendIASDU(COT_BADIOA, C_BO_TA_1, IOA, VV);             // неизвестный адрес объекта информации
        end else SendIASDU(COT_BADCOT, C_BO_TA_1, IOA, VV);               // недопустимая причина передачи
      end;
    end;
    // переходим к следующему "Information object"
    Offset:= Offset + IECASDUInfElementSize(ASDUDataBlockId.ASDUType);
  end;
end;

procedure TIEC104Handler.PushCommand(const ADataBlockId: TASDUDataBlockId; IO: TInformationObject; ADT: TDateTime; AValue: Variant);
begin
  // игнорирую команды тестирования
  If ADataBlockId.Test then Exit;
  //
  FOwner.PushCommand(TIECCommand.Create(ADataBlockId.ASDUType, IO.ASDUType(False), ADataBlockId.COT, ADT, AValue));
end;

procedure TIEC104Handler.Execute;
var APDU: Array[0..255] of Byte;
    APDULen: Byte;
    NS, NR: Word;
begin
  ResetTestFRTimer();
  repeat
    try
      If FSock.CanReadEx(READ_TIMEOUT) then begin
        If FSock.WaitingDataEx <= 0 then raise EIEC104Exception.Create('connection closed by client side');
        // Формат APCI:
        //   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
        //   +---+---+---+---+---+---+---+---+
        // 0 |          START 68H            |  стартовый флаг
        // 1 |       Длина APDU (<=253)      |  длина APDU, начиная с байта "Control Field 1" (максимум 253)
        // 2 |        Control Fields 1       |
        // 3 |        Control Fields 2       |
        // 4 |        Control Fields 3       |
        // 5 |        Control Fields 4       |
        // Далее следует ASDU по ГОСТ Р МЭК 870-5-101 и ГОСТ Р МЭК 870-5-104.
        // ASDU присутствует только для пакетов типа "I".
        //
        // читаем два байта: стартовый и длина ADPU
        FSock.RecvBufferEx(@APDU, 2, READ_TIMEOUT);
        If APDU[0] <> $68 then raise EIEC104Exception.Create('start byte <> 0x68');                     // стартовый байт
        APDULen:= APDU[1];
        If APDULen > 253 then raise EIEC104Exception.Create('size of ADPU more then 253 bytes');        // длина ADPU
        // дочитываем ADPU до конца
        FSock.RecvBufferEx(@APDU[2], APDULen, READ_TIMEOUT);
        // ADPU прочитан
        //
        Case IECFunctionFormat(APDU[2]) of
          I_Format: begin                                                                               // I-format: функции передачи данных с нумерацией
            // сбрасываем таймер отсутствия активности
            ResetTestFRTimer();
            //
            NS:= IECGetNS(@APDU);       // номер полученного пакета
            NR:= IECGetNR(@APDU);       // номер подтвержденного (моего) пакета
            {$IFDEF DEBUG_IEC104}
            AddLog(LOG_DEBUG, Format('<- receive "I" format, NS=%u NR=%u ADPU.len=%u', [NS, NR, APDULen]));
            {$ENDIF}
            // если номер принятого пакета больше номера ожидаемого, то это означает, что был один или несколько потерянных пакетов, которые до меня не дошли
            If NS > WaitRecNumber then raise EIEC104Exception.CreateFmt('violation of the numbering received sequence, received:%u wait:%u', [NS, WaitRecNumber]);
            // если номера совпадают, то все хорошо, начинаем разбор ASDU
            If NS = WaitRecNumber then begin
              // переходим к ожиданию следующего пакета
              WaitRecNumber:= (WaitRecNumber + 1) and $7FFF;
              //
              If FStartDT then begin
                // разбор ASDU
                If APDULen > 4 then ParseASDU(@APDU[6], APDULen - 4);
              end else begin
                AddLog(LOG_DEBUG, 'transmission diasabled, STOPDT active');
              end;
            end else begin
              // если принятый номер меньше ожидаемого, то этот пакет принят повторно, ничего не делаем
              AddLog(LOG_DEBUG, Format('already receive %u packet, dropped', [NS]));
            end;
          end;
          S_Format: begin                                                                               // S-format: формат функции управления с нумерацией
            // пакеты служат для подтверждения приёма пакетов
            // сбрасываем таймер отсутствия активности
            ResetTestFRTimer();
            //
            NR:= IECGetNR(@APDU);
            {$IFDEF DEBUG_IEC104}
            AddLog(LOG_DEBUG, '<- receive "S" format, NR=' + IntToStr(NR));
            {$ENDIF}
          end;
          U_Format: begin                                                                               // U-format: unnumbered control functions
            // пакет имеет фиксированную длинну и содержит только 4 байта "Control Fields", причем используется только "Control Field 1"
            // сбрасываем таймер отсутствия активности
            ResetTestFRTimer();
            //
            Case APDU[2] of
              STARTDT_ACT: begin
                // start data transfer activation
                {$IFDEF DEBUG_IEC104}
                AddLog(LOG_DEBUG, '<- receive "U" format: STARTDT.act = 1');
                {$ENDIF}
                SendUConfirmation(STARTDT_CON);
                If not FStartDT then begin
                  ClearChangeStatus();
                  FStartDT:= True;
                end;
              end;
              STARTDT_CON: begin
                // start data transfer confirmation, unused
                {$IFDEF DEBUG_IEC104}
                AddLog(LOG_DEBUG, '<- receive "U" format: STARTDT.con = 1');
                {$ENDIF}
              end;
              STOPDT_ACT: begin
                // stop data transfer activation
                {$IFDEF DEBUG_IEC104}
                AddLog(LOG_DEBUG, '<- receive "U" format: STOPDT.act = 1');
                {$ENDIF}
                SendUConfirmation(STOPDT_CON);
                FStartDT:= False;
              end;
              STOPDT_CON: begin
                // stop data transfer confirmation, unused
                {$IFDEF DEBUG_IEC104}
                AddLog(LOG_DEBUG, '<- receive "U" format: STOPDT.con = 1');
                {$ENDIF}
              end;
              TESTFR_ACT: begin
                // test frame activation
                {$IFDEF DEBUG_IEC104}
                AddLog(LOG_DEBUG, '<- receive "U" format: TESTFR.act = 1');
                {$ENDIF}
                SendUConfirmation(TESTFR_CON);
              end;
              TESTFR_CON: begin
                // test frame confirmation
                {$IFDEF DEBUG_IEC104}
                AddLog(LOG_DEBUG, '<- receive "U" format: TESTFR.con = 1');
                {$ENDIF}
                // пришло подтверждение на проверку активности, работа канала подтверждена
                FTestFRActive:= False;
                ResetTestFRTimer();
              end;
              else AddLog(LOG_DEBUG, '<- receive "U" format: unknown');
            end;
          end;
        end;
      end;
      // спорадическая передача
      If FStartDT then SendSporadic();
      // проверка необходимости передачи пакетов подтверждения приема
      If WaitRecNumber > ConfRecNumber then begin
        If ConfirmTimerExpired() then begin
          SendSConfirmation();
          ResetConfirmTimer();
        end;
      end else ResetConfirmTimer();
      // проверка необходимости проверки активности канала
      If TestFRTimerExpired() then begin
        // если процедура проверки уже активна, то разрываем соединение
        If FTestFRActive then raise EIEC104Exception.Create('client not answer on TESTFR.act command, disconnect');
        // начинаем процедуру тестирования канала
        ResetTestFRTimer();
        FTestFRActive:= True;
        // отправляю запрос на тестирование
        SendUConfirmation(TESTFR_ACT);
      end;
    except
      on E: ESynapseError do begin
        AddLog(LOG_ERR, Format('ESynapseError:%s, code:%d',[E.ErrorMessage, E.ErrorCode]));
        Disconnect;
      end;
      on E: EIEC104Exception do begin
        AddLog(LOG_ERR, E.Message);
        Disconnect;
      end;
      on E: Exception do begin
        AddLog(LOG_ERR, Format('Exception:%s',[E.Message]));
        Disconnect;
      end;
    end;
  until Terminated;
end;

procedure TIEC104Handler.ResetTestFRTimer;
begin
  If not FTestFRActive then FTestFRTimer:= GetTick();
end;

function TIEC104Handler.TestFRTimerExpired: Boolean;
begin
  result:= TickDelta(FTestFRTimer, GetTick()) > TESTFRTIMEOUT;
end;

procedure TIEC104Handler.ResetConfirmTimer;
begin
  FConfirmTimer:= GetTick();
end;

function TIEC104Handler.ConfirmTimerExpired: Boolean;
begin
  result:= TickDelta(FConfirmTimer, GetTick()) > CONFIRMDELAY;
end;

procedure TIEC104Handler.ClearChangeStatus;
var IO: TInformationObject;
    I: Integer;
begin
  With FOwner.FIOList.LockList do try
    For I:= 1 to Count do begin
      IO:= TInformationObject(Items[I-1]);
      IO.ClearChangeStatus(FMyIndex);
    end;
  finally
    FOwner.FIOList.UnlockList;
  end;
end;

procedure TIEC104Handler.Disconnect;
begin
  FSock.CloseSocket;
  Terminate;
end;

procedure TIEC104Handler.AddLog(ALogLevel: Integer; const AMessage: String);
begin
{$IFDEF DEBUG_IEC104}
  Writeln(Format('IEC %d: %s', [FMyIndex, AMessage]));
{$ENDIF}
end;

// ------------------------------------------------------------------------------

constructor TIECCommand.Create(AASDUType: Byte; AIOAddress: LongWord; ACOT: Byte; ADT: TDateTime; const AValue: Variant);
begin
  inherited Create;
  //
  FASDUType:= AASDUType;
  FIOAddress:= AIOAddress;
  FCOT:= ACOT;
  FDT:= ADT;
  FValue:= AValue;
end;


end.
