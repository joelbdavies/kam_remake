program KM_MacCompatibilityProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Classes, Forms,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_Defaults, KM_GameTypes, KM_CommonClasses, KM_CommonUtils,
  KM_HandsCollection, KM_HandTypes, KM_GameSettings, KM_GameInfo, KM_Saves,
  KM_Terrain, KM_Projectiles, KM_AIFields, KM_GameUIDTracker, KM_ScriptSound,
  KM_Resource, KM_GameInputProcess, KM_Points, KM_UnitGroup, KM_UnitGroupTypes,
  KM_ResTypes, KM_ResTilesetTypes, KM_GameAppSettings, KM_KeysSettings,
  KM_ResKeys, KM_ResKeyFuncs;


type
  TKMProbe = class
    procedure ApplicationError(Sender: TObject; E: Exception);
  end;


procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then raise Exception.Create(aMessage);
end;


procedure TKMProbe.ApplicationError(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, E.ClassName, ': ', E.Message);
  DumpExceptionBackTrace(StdErr);
  Flush(StdErr);
  Halt(1);
end;


procedure CheckGame;
begin
  Check((gGame <> nil) and gGame.IsStarted, 'Game did not start');
  Check(not gGame.Scripting.ErrorHandler.HasErrors, 'Mission script error');
  Check(not gGame.Scripting.ErrorHandler.RuntimeErrorOccurred, 'Script runtime error');
end;


procedure Snapshot(aStream: TKMemoryStream);
begin
  aStream.Write(gGameParams.Tick);
  aStream.Write(GetKaMSeed);
  gUIDTracker.Save(aStream);
  gTerrain.Save(aStream);
  gHands.Save(aStream, False);
  if gHands.CanHaveAI then gAIFields.Save(aStream);
  gGame.Pathfinding.Save(aStream);
  gProjectiles.Save(aStream);
  gGame.Scripting.Save(aStream);
  gScriptSounds.Save(aStream);
  gRes.Units.SaveCustomData(aStream);
  gRes.Wares.SaveCustomData(aStream);
  gGame.SavePoints.Save(aStream);
end;


procedure CheckSave(const aName: string);
var
  info: TKMSaveInfo;
  beforeSave, afterSave, replay: TKMemoryStreamBinary;
  version: AnsiString;
  savedName: string;
  I: Integer;
  tick: Cardinal;
begin
  gGameSettings.SaveCheckpoints := True;
  info := TKMSaveInfo.Create(aName, False);
  try
    Check(info.IsValidStrictly, 'Legacy save is unavailable in the normal Load menu: ' + info.SaveError.ErrorString);
    Check(info.GameInfo.Version = 'r16406', 'Fixture is not an original MVP save');
    tick := info.GameInfo.TickCount;
  finally
    info.Free;
  end;
  gGameApp.NewGameSingleSave(aName);
  CheckGame;
  Check(gGameParams.Tick = tick, 'Original save loaded at the wrong tick');
  Check(gGameParams.SaveVersion = 'r16406', 'Legacy simulation version was lost');
  for I := 1 to 100 do gGameApp.DoGameTick;
  Check(gGameParams.Tick = tick + 100, 'Legacy game did not resume');
  beforeSave := TKMemoryStreamBinary.Create;
  afterSave := TKMemoryStreamBinary.Create;
  replay := TKMemoryStreamBinary.Create;
  try
    Snapshot(beforeSave);
    savedName := 'mac-compat-' + aName;
    gGame.SaveAndWait(savedName);
    gGame.WaitForAllSavesToBeDone;
    info := TKMSaveInfo.Create(savedName, False);
    try
      Check(info.IsValidStrictly and (info.GameInfo.Version = 'r16406'), 'Resave changed the legacy header');
    finally
      info.Free;
    end;
    gGameApp.NewGameSingleSave(savedName);
    CheckGame;
    Snapshot(afterSave);
    if (beforeSave.Size <> afterSave.Size) or not CompareMem(beforeSave.Memory, afterSave.Memory, beforeSave.Size) then
    begin
      beforeSave.SaveToFile(ExeDir + 'compat-before.bin');
      afterSave.SaveToFile(ExeDir + 'compat-after.bin');
      raise Exception.Create('Legacy resave/reload changed simulation or checkpoint state');
    end;
    gGame.GameInputProcess.SaveToStream(replay);
    replay.Position := 0;
    replay.ReadA(version);
    Check(version = 'r16406', 'Replay command header lost the legacy revision');
    WriteLn('PASS: legacy save ', aName, ' loads, resumes 100 ticks, resaves and reloads with identical state and r16406 headers');
  finally
    replay.Free;
    afterSave.Free;
    beforeSave.Free;
  end;
end;


procedure CheckReplay(const aName: string; aEndTick: Cardinal);
var
  previousTick, checkpointTick: Cardinal;
begin
  gGameApp.NewGameReplay(TKMSavesCollection.FullPath(aName, EXT_SAVE_BASE, False));
  CheckGame;
  Check(gGameParams.SaveVersion = 'r16406', 'Legacy replay did not select original simulation rules');
  checkpointTick := gGame.SavePoints.GetPreviousAvailableTick(aEndTick - 1);
  while gGameParams.Tick < aEndTick do
  begin
    previousTick := gGameParams.Tick;
    gGameApp.DoGameTick;
    gGameApp.UpdateState;
    gGameApp.UpdateStateIdle(100);
    CheckGame;
    Check(gGameParams.Tick = previousTick + 1, 'Legacy replay stopped before the requested tick');
  end;
  if checkpointTick > 0 then
  begin
    Check(gGameApp.TryLoadSavePoint(checkpointTick), 'Cannot restore the original replay checkpoint');
    CheckGame;
    Check(gGameParams.SaveVersion = 'r16406', 'Checkpoint lost its legacy simulation version');
    gGameApp.DoGameTick;
    Check(gGameParams.Tick = checkpointTick + 1, 'Restored replay checkpoint did not resume');
  end;
  WriteLn('PASS: legacy replay ', aName, ' reaches tick ', aEndTick,
    ' without a consistency error; original checkpoint ', checkpointTick, ' resumes');
end;


procedure CheckUpstream;
var
  I, X, Y: Integer;
  group: TKMUnitGroup;
  info, restored: TKMGameInfo;
  stream: TKMemoryStreamBinary;
  rejected: Boolean;
begin
  // Replacing the settings XML invalidated the formerly cached Hotkeys node.
  for I := 1 to 3 do
  begin
    gGameAppSettings.ReloadFavouriteMaps;
    gGameAppSettings.Root.AddOrFindChild('Hotkeys').AddOrFindChild(GetKeyFunctionStr(KEY_FUNC_LOW)).Attributes['Key'] := Ord('X');
    gKeySettings.UpdateResKeys;
    Check(gResKeys[KEY_FUNC_LOW] = Ord('X'), 'Hotkeys did not use the replacement settings tree');
  end;
  WriteLn('PASS: hotkeys survive repeated settings XML replacement');

  gGameApp.NewGameEmptyMap(32, 32);
  CheckGame;
  Check(gGameParams.SaveVersion = GAME_REVISION, 'New game inherited the legacy simulation version');
  gHands[0].HandType := hndHuman;
  for X := 15 to 18 do
    for Y := 15 to 18 do
      if not ((X = 16) and (Y = 16)) and not ((X = 17) and (Y = 17)) then
        gTerrain.ScriptTrySetTile(X, Y, BASE_TERRAIN[tkSand], 0);
  gHands.PlayerAnimals.AddUnit(utWolf, KMPoint(16, 16));
  group := gHands[0].AddUnitGroup(utAxeFighter, KMPoint(18, 15), dirSW, 1, 1);
  for I := 1 to 600 do
  begin
    if I = 20 then group.OrderWalk(KMPoint(15, 18), True, wtokPlayerOrder);
    gGameApp.DoGameTick;
    if KMSamePoint(group.FlagBearer.Position, KMPoint(15, 18)) then Break;
  end;
  Check(KMSamePoint(group.FlagBearer.Position, KMPoint(15, 18)), 'Pacing animal blocked the soldier');
  WriteLn('PASS: new r16421 games allow a soldier past a diagonally pacing animal');

  gGameApp.NewGameEmptyMap(32, 32);
  for I := 0 to gHands.Count - 1 do gHands[I].HandType := hndHuman;
  gGame.AfterStart; // Empty-map fixtures need the normal mission-start/base-save step.
  gGame.WaitForAllSavesToBeDone;
  for I := 1 to 5 do gGameApp.DoGameTick;
  gGame.SaveAndWait('mac-upstream-no-ai');
  gGame.WaitForAllSavesToBeDone;
  gGameApp.NewGameSaveAndReplay(TKMSavesCollection.FullPath('mac-upstream-no-ai', EXT_SAVE_MAIN, False),
    TKMSavesCollection.FullPath('mac-upstream-no-ai', EXT_SAVE_REPLAY, False));
  CheckGame;
  gGameApp.DoGameTick;
  Check(gGameParams.IsReplay and (gGameParams.Tick > 5), 'Replay without AI did not advance');
  WriteLn('PASS: replay without AI advances without updating uninitialized AI fields');

  info := TKMGameInfo.Create;
  restored := TKMGameInfo.Create;
  stream := TKMemoryStreamBinary.Create;
  try
    info.Version := 'r99999';
    info.Save(stream);
    stream.Position := 0;
    restored.Load(stream);
    Check(restored.ParseError.ErrorType = gipetUnsupportedVersion, 'Unknown save revision bypassed validation');
    stream.Clear;
    stream.WriteA('r99999');
    stream.Position := 0;
    rejected := False;
    try
      gGame.GameInputProcess.LoadFromStream(stream);
    except
      on E: EReadError do rejected := True;
    end;
    Check(rejected, 'Unknown replay revision bypassed validation');
    WriteLn('PASS: unknown save and replay revisions remain rejected with debug overrides disabled');
    stream.Clear;
    stream.WriteA('r16406');
    stream.Position := 0;
    rejected := False;
    try
      gGame.GameInputProcess.LoadFromStream(stream);
    except
      on E: EReadError do rejected := E.Message = 'Save and replay revisions do not match';
    end;
    Check(rejected, 'Mismatched save/replay revisions were not rejected before reading commands');
    WriteLn('PASS: current saves reject legacy replay companions before changing command state');
  finally
    stream.Free;
    restored.Free;
    info.Free;
  end;
end;


var
  probe: TKMProbe;
  dataDirectory: string;
begin
  try
    ConfigureGameFPU;
    Check(ParamCount >= 1, 'Usage: compatibility upstream | save name | replay name end-tick');
    dataDirectory := ExpandFileName(GetEnvironmentVariable('KAM_DATA_DIR'));
    Check((GetEnvironmentVariable('KAM_DATA_DIR') <> '') and (Pos('/assets.local/', dataDirectory + '/') > 0),
      'Use disposable KAM_DATA_DIR under assets.local');
    Application.Initialize;
    probe := TKMProbe.Create;
    Application.OnException := probe.ApplicationError;
    gMain := TKMMain.Create;
    Check(gMain.Start, 'Game startup failed');
    DBG_ALLOW_LOAD_UNSUP_VERSION_SAVE := False;
    gGameSettings.Autosave := False;
    gGameSettings.SaveCheckpoints := False;
    if (ParamStr(1) = 'upstream') and (ParamCount = 1) then CheckUpstream
    else if (ParamStr(1) = 'save') and (ParamCount = 2) then CheckSave(ParamStr(2))
    else if (ParamStr(1) = 'replay') and (ParamCount = 3) then CheckReplay(ParamStr(2), StrToInt(ParamStr(3)))
    else raise Exception.Create('Invalid arguments');
    Flush(Output);
    if gGame <> nil then gGameApp.StopGame(grCancel);
    gMain.Free;
    gMain := nil;
    probe.Free;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      Halt(1);
    end;
  end;
end.
