program KM_MacTrajectoryProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Classes, Forms,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_Defaults, KM_GameTypes, KM_CommonClasses, KM_CommonUtils,
  KM_HandsCollection, KM_GameSettings, KM_Terrain, KM_Projectiles,
  KM_AIFields, KM_GameUIDTracker, KM_ScriptSound, KM_Resource,
  KM_GameInputProcess, KM_Houses, KM_ResTypes, KM_UnitGroup, KM_Points, KM_CommonTypes;


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


procedure Snapshot(const aDirectory: string);
var
  stream: TKMemoryStreamBinary;
  prefix: string;

  procedure WritePart(const aName: string);
  begin
    stream.SaveToFile(prefix + aName + '.bin');
    stream.Clear;
  end;

begin
  prefix := aDirectory + '/' + IntToStr(gGameParams.Tick) + '-';
  stream := TKMemoryStreamBinary.Create(False);
  try
    stream.Write(gGameParams.Tick);
    stream.Write(GetKaMSeed);
    gUIDTracker.Save(stream);
    WritePart('rng-ids');
    gTerrain.Save(stream);
    WritePart('terrain');
    gHands.Save(stream, False);
    WritePart('hands');
    if gHands.CanHaveAI then gAIFields.Save(stream);
    WritePart('ai-fields');
    gGame.Pathfinding.Save(stream);
    WritePart('pathfinding');
    gProjectiles.Save(stream);
    WritePart('projectiles');
    gGame.Scripting.Save(stream);
    WritePart('script');
    gScriptSounds.Save(stream);
    WritePart('script-sounds');
    gRes.Units.SaveCustomData(stream);
    gRes.Wares.SaveCustomData(stream);
    WritePart('custom-resources');
  finally
    stream.Free;
  end;
end;


procedure IssueOrders(aCutTick: Integer);
var
  X, Y: Integer;
  loc: TKMPoint;
  house: TKMHouse;
  group: TKMUnitGroup;
begin
  if (gGameParams.Tick = 1000) or (gGameParams.Tick = 2000) then
  begin
    house := gHands[gGame.PlayerLoc].FindHouse(htStore, 1);
    if house <> nil then
      for Y := house.Entrance.Y + 1 to house.Entrance.Y + 5 do
        for X := house.Entrance.X - 3 to house.Entrance.X + 3 do
        begin
          loc := KMPoint(X, Y);
          if gHands[gGame.PlayerLoc].CanAddFieldPlan(loc, ftRoad) then
          begin
            gGame.GameInputProcess.CmdBuild(gicBuildToggleFieldPlan, loc, ftRoad);
            WriteLn('ORDER tick=', gGameParams.Tick, ' road=', X, ',', Y);
            Flush(Output);
            Exit;
          end;
        end;
  end;
  if (gGameParams.Tick <> 100) and (gGameParams.Tick <> Cardinal(aCutTick - 10))
    and (gGameParams.Tick <> Cardinal(aCutTick + 100)) and (gGameParams.Tick <> 3100) then Exit;
  house := gHands[gGame.PlayerLoc].FindHouse(htSchool, 1);
  if house <> nil then
  begin
    gGame.GameInputProcess.CmdHouse(gicHouseSchoolTrain, house, Ord(utSerf), 1);
    WriteLn('ORDER tick=', gGameParams.Tick, ' school=', house.UID, ' train serf');
  end;
  if gHands[gGame.PlayerLoc].UnitGroups.Count > 0 then
  begin
    group := gHands[gGame.PlayerLoc].UnitGroups[0];
    gGame.GameInputProcess.CmdArmy(gicArmyFormation, group, 0, 1);
    WriteLn('ORDER tick=', gGameParams.Tick, ' group=', group.UID, ' widen formation');
  end;
  Flush(Output);
end;


var
  probe: TKMProbe;
  phase, campaign, outputDirectory, dataDirectory: string;
  mission, cutTick, endTick: Integer;
  previousTick: Cardinal;
  deadline: QWord;
begin
  try
    ConfigureGameFPU;
    Check(ParamCount = 6, 'Usage: trajectory start|save|resume TSK|TPR mission cut-tick end-tick output-directory');
    phase := ParamStr(1);
    campaign := ParamStr(2);
    mission := StrToInt(ParamStr(3));
    cutTick := StrToInt(ParamStr(4));
    endTick := StrToInt(ParamStr(5));
    outputDirectory := ExpandFileName(ParamStr(6));
    ForceDirectories(outputDirectory);
    dataDirectory := ExpandFileName(GetEnvironmentVariable('KAM_DATA_DIR'));
    Check((GetEnvironmentVariable('KAM_DATA_DIR') <> '') and (Pos('/assets.local/', dataDirectory + '/') > 0),
      'Use a disposable KAM_DATA_DIR under assets.local');
    Check((phase = 'start') or (phase = 'save') or (phase = 'resume'), 'Invalid phase');
    Check((cutTick > 100) and (endTick > cutTick), 'Invalid tick range');
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
    gGameSettings.Autosave := False;
    gGameSettings.SaveCheckpoints := False;
    if phase = 'resume' then
    begin
      CUSTOM_SEED_VALUE := 0;
      gGameApp.NewGameSingleSave('mac-trajectory-' + campaign + IntToStr(mission));
      Check(gGameParams.Tick = Cardinal(cutTick), 'Reloaded the wrong tick');
      Snapshot(outputDirectory);
    end
    else
    begin
      CUSTOM_SEED_VALUE := 4;
      gGameApp.NewGameCampaignMap(campaign, mission - 1);
      CUSTOM_SEED_VALUE := 0; // Loading must restore the saved RNG, not the startup override.
    end;
    CheckGame;
    while gGameParams.Tick < Cardinal(endTick) do
    begin
      IssueOrders(cutTick);
      previousTick := gGameParams.Tick;
      gGameApp.DoGameTick;
      gGameApp.UpdateState;
      gGameApp.UpdateStateIdle(100);
      CheckGame;
      Check(gGameParams.Tick = previousTick + 1, 'Simulation did not advance exactly one tick');
      if (gGameParams.Tick >= Cardinal(cutTick)) and
        ((gGameParams.Tick <= Cardinal(cutTick + 10)) or (gGameParams.Tick mod 100 = 0)) then
        Snapshot(outputDirectory);
      if (phase = 'save') and (gGameParams.Tick = Cardinal(cutTick)) then
      begin
        gGame.SaveAndWait('mac-trajectory-' + campaign + IntToStr(mission));
        gGame.WaitForAllSavesToBeDone;
        Break;
      end;
    end;
    WriteLn('PASS: ', phase, ' ', campaign, mission, ' reached tick ', gGameParams.Tick, ' RNG=', GetKaMSeed);
    Flush(Output);
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
