unit KM_FPU;
{$I KaM_Remake.inc}
interface

procedure ConfigureGameFPU;
function IsGameFPUConfigured: Boolean;


implementation
uses
  Math;


procedure ConfigureGameFPU;
begin
  {$IFDEF CPUAARCH64}
  // CoreAudio and other native libraries expect IEEE exceptions to be masked.
  // ARM has no x87 control word or selectable extended precision.
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  SetRoundMode(rmNearest);
  {$ELSE}
  Set8087CW($133F);
  {$ENDIF}
end;


function IsGameFPUConfigured: Boolean;
begin
  {$IFDEF CPUAARCH64}
  Result := (GetRoundMode = rmNearest)
    and (GetExceptionMask = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  {$ELSE}
  Result := Get8087CW and $1F3F = $133F;
  {$ENDIF}
end;


end.
