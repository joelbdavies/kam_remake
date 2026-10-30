program KM_MacUpstreamProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Classes, Forms,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_Defaults, KM_GameTypes, KM_CommonClasses,
  KM_HandsCollection, KM_HandTypes, KM_GameSettings, KM_GameInfo, KM_Saves,
  KM_Terrain,
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


procedure CheckUpstream;
const
  UNSUPPORTED_REVISIONS: array[0..1] of AnsiString = ('r16406', 'r99999');
var
  I, X, Y: Integer;
  group: TKMUnitGroup;
  info, restored: TKMGameInfo;
  stream: TKMemoryStreamBinary;
  rejected: Boolean;
  version: AnsiString;
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
    // Saving always writes this build's revision, even if Version was set by a prior load.
    info.Version := 'r16406';
    info.Save(stream);
    stream.Position := 0;
    restored.Load(stream);
    Check((restored.ParseError.ErrorType = gipetNone) and (restored.Version = GAME_REVISION),
      'New save did not use the current revision');
    stream.Clear;
    gGame.GameInputProcess.SaveToStream(stream);
    stream.Position := 0;
    stream.ReadA(version);
    Check(version = GAME_REVISION, 'New replay did not use the current revision');
    WriteLn('PASS: new saves and replay commands always write the current revision');
    for version in UNSUPPORTED_REVISIONS do
    begin
      stream.Clear;
      stream.WriteA('KaM_GameInfo');
      stream.WriteA(version);
      stream.Position := 0;
      restored.Load(stream);
      Check(restored.ParseError.ErrorType = gipetUnsupportedVersion,
        'Unsupported save revision bypassed validation: ' + string(version));
      stream.Clear;
      stream.WriteA(version);
      stream.Position := 0;
      rejected := False;
      try
        gGame.GameInputProcess.LoadFromStream(stream);
      except
        on E: EReadError do rejected := Pos('Unsupported replay version:', E.Message) = 1;
      end;
      Check(rejected, 'Unsupported replay was not rejected before reading commands: ' + string(version));
      WriteLn('PASS: ', version, ' save and replay headers are rejected with debug overrides disabled');
    end;
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
    Check(ParamCount = 0, 'Usage: KM_MacUpstreamProbe');
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
    CheckUpstream;
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
