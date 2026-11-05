program KM_MacScriptProbe;
{$I KaM_Remake.inc}
uses
  cthreads, SysUtils, uPSCompiler, uPSRuntime, uPSUtils, KM_FPU;

type
  TProbeIds = array of Integer;
  TProbePoint = record
    X, Y: Integer;
  end;

  TProbeHost = class
  public
    Checks: Integer;
    function Scale(aValue: Integer): Integer;
    function Echo(aValue: UnicodeString): UnicodeString;
    function Ids(aPlayer: Byte): TProbeIds;
    function Sum(aIds: TProbeIds): Integer;
    function Point(aX, aY: Integer): TProbePoint;
    function Distance(aPoint: TProbePoint): Integer;
    function Fraction(aValue: Single; aMultiplier: Double): Double;
    procedure Formation(aPlayer, aType: Byte; out aCount, aColumns: Integer);
    procedure Check(aCondition: Boolean; aLabel: AnsiString);
  end;


function TProbeHost.Scale(aValue: Integer): Integer;
begin
  Result := aValue * 3;
end;


function TProbeHost.Echo(aValue: UnicodeString): UnicodeString;
begin
  Result := aValue + WideChar($03A9);
end;


function TProbeHost.Ids(aPlayer: Byte): TProbeIds;
begin
  if aPlayer = 0 then Exit(nil);
  Result := TProbeIds.Create(-7, aPlayer, 9001);
end;


function TProbeHost.Sum(aIds: TProbeIds): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(aIds) do Inc(Result, aIds[I]);
end;


function TProbeHost.Point(aX, aY: Integer): TProbePoint;
begin
  Result.X := aX;
  Result.Y := aY;
end;


function TProbeHost.Distance(aPoint: TProbePoint): Integer;
begin
  Result := aPoint.X - aPoint.Y;
end;


function TProbeHost.Fraction(aValue: Single; aMultiplier: Double): Double;
begin
  Result := aValue * aMultiplier;
end;


procedure TProbeHost.Formation(aPlayer, aType: Byte; out aCount, aColumns: Integer);
begin
  aCount := 20 + aPlayer;
  aColumns := 3 + aType;
end;


procedure TProbeHost.Check(aCondition: Boolean; aLabel: AnsiString);
begin
  if not aCondition then raise Exception.Create('Script check failed: ' + aLabel);
  Inc(Checks);
  WriteLn('PASS: script host ', aLabel);
  Flush(Output);
end;


function ConfigureCompiler(aCompiler: TPSPascalCompiler; const aName: AnsiString): Boolean;
begin
  aCompiler.AddTypeS('TProbeIds', 'array of Integer').ExportName := True;
  aCompiler.AddTypeS('TProbePoint', 'record X, Y: Integer; end').ExportName := True;
  aCompiler.AddDelphiFunction('function Scale(aValue: Integer): Integer');
  aCompiler.AddDelphiFunction('function Echo(aValue: UnicodeString): UnicodeString');
  aCompiler.AddDelphiFunction('function Ids(aPlayer: Byte): TProbeIds');
  aCompiler.AddDelphiFunction('function Sum(aIds: TProbeIds): Integer');
  aCompiler.AddDelphiFunction('function Point(aX, aY: Integer): TProbePoint');
  aCompiler.AddDelphiFunction('function Distance(aPoint: TProbePoint): Integer');
  aCompiler.AddDelphiFunction('function Fraction(aValue: Single; aMultiplier: Double): Double');
  aCompiler.AddDelphiFunction('procedure Formation(aPlayer, aType: Byte; out aCount, aColumns: Integer)');
  aCompiler.AddDelphiFunction('procedure Check(aCondition: Boolean; aLabel: AnsiString)');
  Result := True;
end;


procedure RunProbe;
const
  SCRIPT = 'var values: TProbeIds; p: TProbePoint; count, columns, i: Integer; text: UnicodeString; begin '
    + 'Check(Scale(-7) = -21, ''signed integer''); '
    + 'Check(Fraction(1.5, 2.5) = 3.75, ''floating point''); '
    + 'Formation(2, 1, count, columns); Check((count = 22) and (columns = 4), ''out parameters''); '
    + 'text := Echo(''KaM ''); Check((Length(text) = 5) and (Ord(text[5]) = 937), ''Unicode return''); '
    + 'p := Point(-4, 18); Check((p.X = -4) and (p.Y = 18), ''record return''); '
    + 'Check(Distance(p) = -22, ''record argument''); '
    + 'for i := 1 to 100 do begin values := Ids(2); values[0] := -8; end; '
    + 'Check((Length(values) = 3) and (values[2] = 9001), ''array return and ownership''); '
    + 'Check(Sum(values) = 8995, ''array argument''); '
    + 'values := Ids(0); Check(Length(values) = 0, ''empty array return''); end.';
var
  compiler: TPSPascalCompiler;
  runtime: TPSExec;
  host: TProbeHost;
  bytecode: AnsiString;
  I: Integer;
begin
  compiler := TPSPascalCompiler.Create;
  runtime := TPSExec.Create;
  host := TProbeHost.Create;
  try
    compiler.OnUses := ConfigureCompiler;
    if not compiler.Compile(SCRIPT) then
    begin
      for I := 0 to compiler.MsgCount - 1 do WriteLn(compiler.Msg[I].MessageToString);
      raise Exception.Create('Script did not compile');
    end;
    compiler.GetOutput(bytecode);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Scale, 'Scale', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Echo, 'Echo', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Ids, 'Ids', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Sum, 'Sum', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Point, 'Point', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Distance, 'Distance', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Fraction, 'Fraction', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Formation, 'Formation', cdRegister);
    runtime.RegisterDelphiMethod(host, @TProbeHost.Check, 'Check', cdRegister);
    if not runtime.LoadData(bytecode) then raise Exception.Create('Script bytecode did not load');
    runtime.GetTypeNo(runtime.GetType('TProbeIds')).NativeTypeInfo := TypeInfo(TProbeIds);
    runtime.GetTypeNo(runtime.GetType('TProbePoint')).NativeTypeInfo := TypeInfo(TProbePoint);
    if not runtime.RunScript then
      raise Exception.Create(PSErrorToString(runtime.ExceptionCode, runtime.ExceptionString));
    if host.Checks <> 9 then raise Exception.Create('Script did not execute all checks');
  finally
    runtime.Free;
    compiler.Free;
    host.Free;
  end;
end;


begin
  try
    ConfigureGameFPU;
    RunProbe;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      Halt(1);
    end;
  end;
end.
