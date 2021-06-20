{$I eDefines.inc}

program iec104_test;

uses
  SysUtils, iec104, iec104defs;

var IEC104Server: TIEC104Server;
    I, J: Integer;
    Cmd: TIECCommand;

begin
  IEC104Server:= TIEC104Server.Create('0.0.0.0', '2404');
  //
  IEC104Server.UseORGAddress:= True;
  IEC104Server.ASDUAddressSize:= 2;
  IEC104Server.ASDUAddress:= 1;
  IEC104Server.IOASize:= 3;
  // add information objects
  For I:= 1 to 200 do begin
    IEC104Server.AddIOValue(M_SP_NA_1, M_SP_TB_1, I);
    IEC104Server.SetIOValue(I, LongWord(I mod 2));
  end;
  For I:= 300 to 400 do begin
    IEC104Server.AddIOValue(M_ME_NC_1, M_ME_TF_1, I, 1);
    IEC104Server.SetIOValue(I, Random()*1000);
  end;
  For I:= 401 to 600 do begin
    IEC104Server.AddIOValue(M_IT_NA_1, M_IT_TB_1, I, 0);
    IEC104Server.SetIOValue(I, I);
  end;
  // command
  IEC104Server.AddIOValue(C_SC_NA_1, 0, 700);
  //
  IEC104Server.Start();
  // test sporadic
  I:= 0;
  While true do begin
    // IEC104Server.SetIOValue(5, Random()*1000);
    // IEC104Server.SetIOValue(6, Random()*1000);
    // IEC104Server.SetIOValue(7, 0);
    If I mod 2 = 0 then IEC104Server.SetIOBadQuality(300) else IEC104Server.SetIOValue(300, Random()*1000);
    Inc(I);

    For J:= 1 to 50 do begin
      Sleep(100);
      Cmd:= IEC104Server.GetCommand();
      If Cmd <> Nil then begin
        try
          WriteLn('COMMAND --------------------->', CMD.Value);


        finally
          FreeAndNil(Cmd);
        end;
      end;
    end;


  end;





  Readln;
  //
  FreeAndNil(IEC104Server);
end.
