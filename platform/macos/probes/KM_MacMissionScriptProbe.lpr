program KM_MacMissionScriptProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Forms,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_CommonTypes, KM_Defaults, KM_GameTypes, KM_HandsCollection,
  KM_GameSettings, KM_ResTypes, KM_Resource, KM_Houses, KM_Points, KM_Terrain,
  KM_ScriptingEvents, KM_ScriptingTypes, KM_ScriptingConsoleCommands,
  KM_UnitGroup, KM_HandTypes, KM_FileIO;

type
  TProbe = class
    procedure ApplicationError(Sender: TObject; E: Exception);
  end;

procedure TProbe.ApplicationError(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, E.ClassName, ': ', E.Message);
  DumpExceptionBackTrace(StdErr);
  Halt(1);
end;

procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then raise Exception.Create(aMessage);
end;

procedure CheckGame;
begin
  Check((gGame <> nil) and gGame.IsStarted, 'Mission failed to start');
  Check(not gGame.Scripting.ErrorHandler.HasErrors, 'Mission script error: ' + gGame.Scripting.ErrorHandler.ErrorString.GameMessage);
  Check(not gGame.Scripting.ErrorHandler.RuntimeErrorOccurred, 'Script runtime error');
end;

function StartHouse(aType: TKMHouseType): TKMHouse;
var
  X, Y: Integer;
  entrance, origin: TKMPoint;
begin
  Check(gHands[0].Locks.HouseCanBuild(aType), 'Required house is not buildable');
  for Y := 5 to gTerrain.MapY - 5 do
    for X := 5 to gTerrain.MapX - 5 do
    begin
      entrance := KMPoint(X, Y);
      if not gHands[0].CanAddHousePlan(entrance, aType) then Continue;
      origin := KMPoint(X - gRes.Houses[aType].EntranceOffsetX, Y);
      Result := gHands[0].AddHouseWIP(aType, origin);
      Result.BuildingState := hbsWood;
      // Supply the diagnostic fixture directly, then exercise the actual
      // construction completion and OnHouseBuilt event path.
      Result.WareAddToBuild(wtTimber, gRes.Houses[aType].WoodCost);
      Result.WareAddToBuild(wtStone, gRes.Houses[aType].StoneCost);
      Exit;
    end;
  raise Exception.Create('No legal site found for required house');
end;

procedure CompleteHouse(aHouse: TKMHouse);
var
  I: Integer;
begin
  for I := 1 to 1000 do
  begin
    if aHouse.IsComplete then Break;
    aHouse.IncBuildingProgress;
  end;
  Check(aHouse.IsComplete, 'Construction did not finish');
  CheckGame;
end;

procedure CheckCallbacks(const aFixture: UnicodeString);
var
  I: Integer;
  group: TKMUnitGroup;
  newType: TKMUnitType;
  newCount: Integer;
  mixed: Boolean;
  commandParams: TKMScriptCommandParamsArray;
begin
  gGameApp.NewGameEmptyMap(32, 32);
  for I := 0 to gHands.Count - 1 do gHands[I].HandType := hndHuman;
  KMCopyFile(aFixture, ExeDir + 'mac-mission-events.script', True);
  gGame.Scripting.LoadFromFile(ExeDir + 'mac-mission-events.script', '', nil);
  CheckGame;
  gGame.AfterStart;
  CheckGame;
  Check(not gHands[0].Locks.HouseCanBuild(htMarket), 'Fixture market already unlocked');
  for I := 1 to 3 do gGameApp.DoGameTick;
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htMarket), 'Mission-start or tick handlers did not execute exactly once');
  WriteLn('PASS: default/custom mission-start callbacks and three tick events change game state');
  gScriptEvents.ProcBeacon(0, -17, 23);
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htGoldMine), 'Integer callback arguments did not arrive in order');
  gScriptEvents.ProcGameSpeedChanged(1.75);
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htIronMine), 'Single callback argument was lost');
  WriteLn('PASS: signed integer and fractional event arguments reach script handlers');
  group := gHands[0].AddUnitGroup(utAxeFighter, KMPoint(16, 16), dirS, 1, 1);
  newType := utBowman;
  newCount := 7;
  mixed := False;
  gScriptEvents.ProcGroupBeforeOrderSplit(group, newType, newCount, mixed);
  CheckGame;
  Check((newType = utAxeFighter) and (newCount = 2) and mixed,
    'Mutable enum/integer/boolean callback values did not propagate between handlers and back to game');
  WriteLn('PASS: multiple group-split handlers return modified enum, integer and boolean values');
  commandParams[0] := 'True';
  commandParams[1] := '-17';
  commandParams[2] := '1.25';
  commandParams[3] := 'native text';
  Check(gScriptEvents.CallConsoleCommand(0, 'eventcheck', commandParams), 'Typed script command was not linked');
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htWeaponSmithy), 'Typed script command did not execute');
  Check(gScriptEvents.CallConsoleCommand(0, 'noargs', commandParams), 'Empty script command was not linked');
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htArmorWorkshop), 'Empty script command did not execute');
  WriteLn('PASS: script commands execute with zero or four typed parameters');
end;

procedure CheckMission4;
var
  I: Integer;
  house: TKMHouse;
begin
  gGameApp.NewGameCampaignMap('TSK', 3);
  CheckGame;
  Check(gHands[0].Houses.FindHouse(htSchool, 0, 0) = nil, 'Unexpected starting school');
  Check(gHands[0].Houses.FindHouse(htQuarry, 0, 0) = nil, 'Unexpected starting quarry');
  Check(gHands[0].Locks.HouseCanBuild(htSchool), 'School not available at start');
  Check(not gHands[0].Locks.HouseCanBuild(htQuarry), 'Quarry available before school');
  Check(gHands[0].Locks.HouseBlocked[htWoodcutters], 'Woodcutter not initially script-blocked');
  WriteLn('PASS: TSK4 mission-start script applies building restrictions');
  house := StartHouse(htSchool);
  CompleteHouse(house);
  Check(gHands[0].Locks.HouseCanBuild(htQuarry), 'School did not unlock quarry');
  Check(not gHands[0].Locks.HouseCanBuild(htWoodcutters), 'School alone unexpectedly unlocked woodcutter');
  WriteLn('PASS: completing school unlocks quarry; woodcutter remains blocked');
  for I := 1 to 10 do gGameApp.DoGameTick;
  house := StartHouse(htQuarry);
  house.IncBuildingProgress;
  Check(not gHands[0].Locks.HouseCanBuild(htWoodcutters), 'Unfinished quarry unlocked woodcutter');
  CompleteHouse(house);
  Check(not gHands[0].Locks.HouseBlocked[htWoodcutters], 'Quarry event did not remove script block');
  Check(gHands[0].Locks.HouseCanBuild(htWoodcutters), 'Completed school and quarry did not unlock woodcutter');
  WriteLn('PASS: completing quarry fires mission script and makes woodcutter buildable');
  gGame.SaveAndWait('mac-tsk4-building-unlock');
  gGame.WaitForAllSavesToBeDone;
  gGameApp.NewGameSingleSave('mac-tsk4-building-unlock');
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htWoodcutters), 'Save/reload lost woodcutter unlock');
  for I := 1 to 10 do gGameApp.DoGameTick;
  CheckGame;
  Check(gHands[0].Locks.HouseCanBuild(htWoodcutters), 'Resuming relocked woodcutter');
  WriteLn('PASS: woodcutter remains buildable after save/reload and resumed simulation');
end;


var
  probe: TProbe;
  deadline: QWord;
  dataDirectory, fixtureFile: string;
begin
  try
    Check(ParamCount = 1, 'Usage: KM_MacMissionScriptProbe path/to/mission-events.script');
    fixtureFile := ExpandFileName(ParamStr(1));
    Check(FileExists(fixtureFile), 'Missing event script fixture');
    dataDirectory := ExpandFileName(GetEnvironmentVariable('KAM_DATA_DIR'));
    Check((GetEnvironmentVariable('KAM_DATA_DIR') <> '') and
      (Pos('/assets.local/', dataDirectory + '/') > 0), 'Use disposable test data');
    ConfigureGameFPU;
    Application.Initialize;
    probe := TProbe.Create;
    Application.OnException := probe.ApplicationError;
    gMain := TKMMain.Create;
    Check(gMain.Start, 'Native startup failed');
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
    CheckCallbacks(fixtureFile);
    CheckMission4;
    gGameApp.StopGame(grCancel);
    gMain.Free;
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
