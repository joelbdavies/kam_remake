program KM_MacCollectionProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Classes, Forms,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_Defaults, KM_CommonTypes, KM_CommonClasses, KM_CommonUtils,
  KM_GameTypes, KM_GameSettings, KM_HandsCollection, KM_HandTypes,
  KM_Terrain, KM_Points, KM_ResTypes, KM_HouseBarracks, KM_AIGeneral,
  KM_AITypes, KM_ScriptSound, KM_MediaTypes, KM_GameSavePoints;


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


procedure NewMission;
begin
  CUSTOM_SEED_VALUE := 4;
  gGameApp.NewGameCampaignMap('TSK', 1);
  CUSTOM_SEED_VALUE := 0;
  Check((gGame <> nil) and gGame.IsStarted, 'Fixture mission did not start');
  gGameSettings.Autosave := False;
  gGameSettings.SaveCheckpoints := False;
end;


function ReadPendingIDs(aGeneral: TKMGeneral): TArray<Integer>;
var
  stream, marker: TKMemoryStreamBinary;
  I, offset, count, previous: Integer;
begin
  stream := TKMemoryStreamBinary.Create(False);
  marker := TKMemoryStreamBinary.Create(False);
  try
    aGeneral.Save(stream);
    marker.PlaceMarker('AIGeneral_unitsEquipOrdered');
    offset := -1;
    for I := 0 to stream.Size - marker.Size do
      if CompareMem(PByte(stream.Memory) + I, marker.Memory, marker.Size) then
      begin
        offset := I + marker.Size;
        Break;
      end;
    Check(offset >= 0, 'AI equipment-order marker not found');
    stream.Position := offset;
    stream.Read(count);
    Check((count >= 0) and (stream.Size - stream.Position = count * SizeOf(Integer)),
      'AI equipment count does not match its serialized IDs');
    SetLength(Result, count);
    previous := -1;
    for I := 0 to count - 1 do
    begin
      stream.Read(Result[I]);
      Check(Result[I] > previous, 'AI pending IDs were not saved in sorted order');
      Check(gHands.GetUnitByUID(Result[I]) <> nil, 'Pending equipment lost its actual warrior');
      previous := Result[I];
    end;
  finally
    marker.Free;
    stream.Free;
  end;
end;


procedure CheckEquipment(aCount: Integer);
var
  owner, I, X, Y: Integer;
  barracks: TKMHouseBarracks;
  pendingBefore, pendingAfter: TArray<Integer>;
  general: TKMGeneral;
begin
  NewMission;
  owner := -1;
  for I := 0 to gHands.Count - 1 do
    if (I <> gGame.PlayerLoc) and (gHands[I].UnitGroups.Count = 0) then
    begin
      owner := I;
      Break;
    end;
  if owner < 0 then
  begin
    owner := gHands.Count;
    Check(owner < MAX_HANDS, 'No spare player slot for equipment fixture');
    gHands.AddPlayers(1);
  end;
  gHands[owner].Enabled := True;
  gHands[owner].HandType := hndComputer;
  barracks := nil;
  for Y := 6 to gTerrain.MapY - 6 do
  begin
    for X := 6 to gTerrain.MapX - 6 do
      if gTerrain.CanPlaceHouse(KMPoint(X, Y), htBarracks) then
      begin
        barracks := TKMHouseBarracks(gHands[owner].AddHouse(htBarracks, X, Y, True));
        Break;
      end;
    if barracks <> nil then Break;
  end;
  Check(barracks <> nil, 'No space for fixture barracks');
  for I := 1 to aCount do barracks.CreateRecruitInside(False);
  barracks.WareAddToIn(wtAxe, aCount);
  gHands[owner].AI.Setup.UnlimitedEquip := True;
  gHands[owner].AI.Setup.ArmyType := atLeather;
  gHands[owner].AI.Setup.AutoAttack := False;
  gHands[owner].AI.Setup.AutoDefend := False;
  gHands[owner].AI.Setup.MaxSoldiers := aCount;
  general := gHands[owner].AI.General;
  general.DefencePositions.Clear;
  general.DefencePositions.TroopFormations[gtMelee].NumUnits := aCount;
  general.DefencePositions.TroopFormations[gtMelee].UnitsPerRow := 1;
  general.DefencePositions.Add(KMPointDir(barracks.Entrance.X, barracks.Entrance.Y + 4, dirS), gtMelee, 10, dtFrontLine);
  gHands[owner].AddAIType(aitClassic);
  gHands[owner].AI.AfterMissionInit([aitClassic]);
  general.UpdateState(MAX_HANDS - owner);
  pendingBefore := ReadPendingIDs(general);
  Check(Length(pendingBefore) = aCount, Format('Expected %d actual pending warriors, got %d', [aCount, Length(pendingBefore)]));
  gGame.SaveAndWait('mac-equipment-boundary-' + IntToStr(aCount));
  gGame.WaitForAllSavesToBeDone;
  gGameApp.NewGameSingleSave('mac-equipment-boundary-' + IntToStr(aCount));
  pendingAfter := ReadPendingIDs(gHands[owner].AI.General);
  Check(Length(pendingAfter) = aCount, 'Reload changed pending equipment count');
  for I := 0 to aCount - 1 do
    Check(pendingBefore[I] = pendingAfter[I], 'Reload changed pending equipment IDs');
  for I := 1 to 200 do gGameApp.DoGameTick;
  Check(Length(ReadPendingIDs(gHands[owner].AI.General)) = 0, 'Equipped warriors did not leave the pending queue');
  WriteLn('PASS: ', aCount, ' AI equipment orders save/reload with live warrior references and complete after resuming');
  Flush(Output);
end;


procedure CheckSoundRequests(aCount: Integer);
var
  source, restored: TKMScriptSoundsManager;
  saved, afterLoad: TKMemoryStreamBinary;
  I: Integer;
  ids: TArray<Integer>;
  expected: string;
begin
  NewMission;
  source := TKMScriptSoundsManager.Create;
  restored := TKMScriptSoundsManager.Create;
  saved := TKMemoryStreamBinary.Create(False);
  afterLoad := TKMemoryStreamBinary.Create(False);
  try
    SetLength(ids, aCount);
    for I := 0 to aCount - 1 do
      ids[I] := source.AddSound(HAND_NONE, '__mac_regression_missing_sound__', afWav,
        KMPoint(1, 1), False, 1, 10, False, True);
    // Reverse insertion order to exercise sorting; the second hand has not acknowledged yet.
    for I := aCount - 1 downto 0 do source.AddRemoveRequest(ids[I], 0, [0, 1]);
    source.Save(saved);
    expected := 'RemoveRequests: CNT = ' + IntToStr(aCount) + ':';
    Check(Pos(expected, source.GetDbgString) > 0, 'Sound requests did not remain pending');
    saved.Position := 0;
    restored.Load(saved);
    restored.Save(afterLoad);
    Check((saved.Size = afterLoad.Size) and CompareMem(saved.Memory, afterLoad.Memory, saved.Size),
      'Sound request save/reload changed serialized state');
    saved.Position := 0;
    restored.Load(saved); // Reloading into an existing manager must replace old requests.
    Check(Pos(expected, restored.GetDbgString) > 0, 'Repeated sound load changed pending requests');
    for I := 0 to aCount - 1 do restored.AddRemoveRequest(ids[I], 1, [0, 1]);
    Check(Pos('Script sounds cnt = 0|RemoveRequests: CNT = 0:', restored.GetDbgString) > 0,
      'Reloaded sound requests did not finish when the remaining hand acknowledged');
    WriteLn('PASS: ', aCount, ' pending sound removals retain IDs/hand acknowledgements and finish after repeated reload');
    Flush(Output);
  finally
    afterLoad.Free;
    saved.Free;
    restored.Free;
    source.Free;
  end;
end;


procedure CheckCheckpointLimit(aLimit: Integer);
var
  I, expected: Integer;
  tick, previousTick: Cardinal;
  points: TKMSavePointCollection;
  filename: string;
begin
  NewMission;
  gGameSettings.SaveCheckpoints := True;
  gGameSettings.SaveCheckpointsFreq := GAME_SAVE_CHECKPOINT_FREQ_MIN;
  gGameSettings.SaveCheckpointsLimit := aLimit;
  // Seed the collection just below the limit, then cross two real scheduling boundaries.
  // This covers the default/max limits without simulating many empty hours.
  for I := 1 to aLimit - 1 do
  begin
    gGameApp.DoGameTick;
    gGame.MakeSavePoint;
  end;
  while gGameParams.Tick <= Cardinal(2 * gGameSettings.SaveCheckpointsFreq) do
  begin
    previousTick := gGameParams.Tick;
    gGameApp.DoGameTick;
    Check(gGameParams.Tick = previousTick + 1, 'Checkpoint fixture stopped advancing');
    Check(gGame.SavePoints.Count <= aLimit, Format('Checkpoint limit %d exceeded: %d', [aLimit, gGame.SavePoints.Count]));
  end;
  expected := aLimit;
  Check(gGame.SavePoints.Count = expected, 'Checkpoint scheduler stopped before its configured limit');
  filename := TKMGame.SaveName('mac-limit-' + IntToStr(aLimit), 'spt', False);
  ForceDirectories(ExtractFilePath(filename));
  gGame.SavePoints.SaveToFileAsync(filename, nil);
  points := TKMSavePointCollection.Create;
  try
    points.LoadFromFile(filename);
    Check(points.Count = expected, 'Checkpoint limit collection did not round-trip');
    for tick in gGame.SavePoints.GetAvailableTicks do
      Check(points.ContainsTick(tick), 'Boundary checkpoint tick was lost');
  finally
    points.Free;
  end;
  WriteLn('PASS: checkpoint limit ', aLimit, ' holds before/at/after scheduled boundaries and reloads');
  Flush(Output);
end;


var
  probe: TKMProbe;
  deadline: QWord;
  dataDirectory: string;
begin
  try
    ConfigureGameFPU;
    Check((ParamCount = 0) or ((ParamCount = 1) and
      ((ParamStr(1) = 'equipment') or (ParamStr(1) = 'sound') or (ParamStr(1) = 'checkpoints'))),
      'Usage: KM_MacCollectionProbe [equipment|sound|checkpoints]');
    dataDirectory := ExpandFileName(GetEnvironmentVariable('KAM_DATA_DIR'));
    Check((GetEnvironmentVariable('KAM_DATA_DIR') <> '') and (Pos('/assets.local/', dataDirectory + '/') > 0),
      'Use a disposable KAM_DATA_DIR under assets.local');
    Application.Initialize;
    probe := TKMProbe.Create;
    Application.OnException := probe.ApplicationError;
    gMain := TKMMain.Create;
    Check(gMain.Start, 'Startup failed');
    deadline := GetTickCount64 + 30000;
    while gGameApp.Campaigns.IsScanning do
    begin
      Application.ProcessMessages;
      gGameApp.UpdateState;
      gGameApp.UpdateStateIdle(10);
      Check(GetTickCount64 < deadline, 'Campaign scan timed out');
      Sleep(10);
    end;
    if (ParamCount = 0) or (ParamStr(1) = 'equipment') then
    begin
      CheckEquipment(0);
      CheckEquipment(1);
      CheckEquipment(2);
      CheckEquipment(8);
    end;
    if (ParamCount = 0) or (ParamStr(1) = 'sound') then
    begin
      CheckSoundRequests(0);
      CheckSoundRequests(1);
      CheckSoundRequests(2);
      CheckSoundRequests(8);
    end;
    if (ParamCount = 0) or (ParamStr(1) = 'checkpoints') then
    begin
      CheckCheckpointLimit(0);
      CheckCheckpointLimit(1);
      CheckCheckpointLimit(2);
      CheckCheckpointLimit(GAME_SAVE_CHECKPOINT_CNT_LIMIT_DEF);
      CheckCheckpointLimit(GAME_SAVE_CHECKPOINT_CNT_LIMIT_MAX);
    end;
    gGameApp.StopGame(grCancel);
    gMain.Free;
    gMain := nil;
    probe.Free;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      Flush(StdErr);
      Halt(1);
    end;
  end;
end.
