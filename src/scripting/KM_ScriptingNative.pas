unit KM_ScriptingNative;
{$I KaM_Remake.inc}
interface
uses
  uPSRuntime, uPSUtils;

  procedure RegisterNativeScriptTypes(aRuntime: TPSExec);


implementation
uses
  TypInfo,
  KM_CommonTypes, KM_Defaults, KM_Points, KM_ResTypes, KM_MapTypes,
  KM_ScriptingTypes, KM_TerrainTypes;


procedure RegisterNativeScriptTypes(aRuntime: TPSExec);

  procedure RegisterType(const aName: AnsiString; aTypeInfo: PTypeInfo);
  var
    index: Cardinal;
  begin
    index := aRuntime.GetType(aName);
    if index <> InvalidVal then
      aRuntime.GetTypeNo(index).NativeTypeInfo := aTypeInfo;
  end;

begin
  // FPC's call manager needs native RTTI for aggregate arguments and results.
  // Script-only types remain owned by PascalScript and never cross this boundary.
  RegisterType('TIntegerArray', TypeInfo(TIntegerArray));
  RegisterType('TAnsiStringArray', TypeInfo(TAnsiStringArray));
  RegisterType('TKMPoint', TypeInfo(TKMPoint));
  RegisterType('TKMTerrainTileBrief', TypeInfo(TKMTerrainTileBrief));
  RegisterType('TKMAIAttackInfo', TypeInfo(TKMAIAttackInfo));
  RegisterType('TKMDefencePositionInfo', TypeInfo(TKMDefencePositionInfo));
  RegisterType('TByteSet', TypeInfo(TByteSet));
  RegisterType('TKMGroupTypeSet', TypeInfo(TKMGroupTypeSet));
  RegisterType('TKMHouseTypeSet', TypeInfo(TKMHouseTypeSet));
  RegisterType('TKMMissionDifficultySet', TypeInfo(TKMMissionDifficultySet));
  RegisterType('TKMUnitTypeSet', TypeInfo(TKMUnitTypeSet));
  RegisterType('TKMWareTypeSet', TypeInfo(TKMWareTypeSet));
end;


end.
