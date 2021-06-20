{$I eDefines.inc}

unit iec104time;

interface

var IECTimeDiff: TDateTime;
    IECTimeValid: Boolean;

function IECNow(): TDateTime;

implementation

uses sysutils;

function IECNow(): TDateTime;
begin
  result:= Now() + IECTimeDiff;
end;

initialization
  IECTimeDiff:= 0;
  IECTimeValid:= False;
end.
