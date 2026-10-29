program KM_MacCampaignProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, TypInfo, Forms,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_CommonTypes, KM_Defaults, KM_GameTypes, KM_CommonClasses,
  KM_HandsCollection, KM_Campaigns;


type
  TProbe = class
    procedure ApplicationError(Sender: TObject; E: Exception);
  end;


procedure TProbe.ApplicationError(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, E.ClassName, ': ', E.Message);
  DumpExceptionBackTrace(StdErr);
  Flush(StdErr);
  Halt(1);
end;


procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then raise Exception.Create(aMessage);
end;


procedure CheckScript;
begin
  Check(gGame <> nil, 'Mission did not create a game');
  Check(not gGame.Scripting.ErrorHandler.HasErrors,
    gGame.Scripting.ErrorHandler.ErrorString.GameMessage);
  Check(not gGame.Scripting.ErrorHandler.RuntimeErrorOccurred, 'Script runtime error');
end;


var
  probe: TProbe;
  deadline: QWord;
  campaign, outputDirectory: string;
  mission, I, requestedTicks, requestedSeed: Integer;
  savedTick: Cardinal;
  scriptBefore, scriptAfter: TKMemoryStreamBinary;
  unitsBefore, housesBefore: array of Integer;
  completedCampaign: TKMCampaign;
  reloadedProgress: TKMCampaignSavedData;
begin
  try
    ConfigureGameFPU;
    Check(ParamCount in [3, 4, 5], 'Usage: KM_MacCampaignProbe TSK|TPR mission-number output-directory [ticks [seed]]');
    requestedTicks := 600;
    if ParamCount >= 4 then requestedTicks := StrToInt(ParamStr(4));
    requestedSeed := 0;
    if ParamCount = 5 then
    begin
      requestedSeed := StrToInt(ParamStr(5));
      Check(requestedSeed > 0, 'Seed must be a positive integer');
    end;
    campaign := ParamStr(1);
    mission := StrToInt(ParamStr(2));
    outputDirectory := ExpandFileName(ParamStr(3));
    ForceDirectories(outputDirectory);
    Application.Initialize;
    probe := TProbe.Create;
    Application.OnException := probe.ApplicationError;
    gMain := TKMMain.Create;
    Check(gMain.Start, 'Game startup failed');
    deadline := GetTickCount64 + 30000;
    while gGameApp.Campaigns.IsScanning do
    begin
      Application.ProcessMessages;
      gGameApp.UpdateState;
      gGameApp.UpdateStateIdle(10);
      Check(GetTickCount64 < deadline, 'Campaign scan timed out');
      Sleep(10);
    end;
    CUSTOM_SEED_VALUE := requestedSeed;
    WriteLn('Starting ', campaign, ' mission ', mission, ' (seed override=', requestedSeed, ')');
    Flush(Output);
    gGameApp.NewGameCampaignMap(campaign, mission - 1);
    CheckScript;
    Check(gGame.IsStarted, 'Mission did not start');
    for I := 1 to requestedTicks do
    begin
      gGameApp.DoGameTick;
      gGameApp.UpdateState;
      gGameApp.UpdateStateIdle(100);
      CheckScript;
    end;
    savedTick := gGameParams.Tick;
    Check(savedTick >= Cardinal(requestedTicks), Format(
      'Simulation stopped at %d/%d ticks (result=%s, paused=%s)',
      [savedTick, requestedTicks, GetEnumName(TypeInfo(TKMGameResultMsg), Ord(gGame.GameResult)),
       BoolToStr(gGame.IsPaused, True)]));
    SetLength(unitsBefore, gHands.Count);
    SetLength(housesBefore, gHands.Count);
    for I := 0 to gHands.Count - 1 do
    begin
      unitsBefore[I] := gHands[I].Units.Count;
      housesBefore[I] := gHands[I].Houses.Count;
    end;
    scriptBefore := TKMemoryStreamBinary.Create;
    scriptAfter := TKMemoryStreamBinary.Create;
    gGame.Scripting.Save(scriptBefore);
    gGameApp.PrintScreen(outputDirectory + '/' + campaign + IntToStr(mission) + '.png', itPng);
    Check(FileExists(outputDirectory + '/' + campaign + IntToStr(mission) + '.png'), 'Screenshot was not saved');
    gGame.SaveAndWait('mac-smoke-' + campaign + IntToStr(mission));
    gGameApp.NewGameSingleSave('mac-smoke-' + campaign + IntToStr(mission));
    CheckScript;
    Check(gGameParams.Tick = savedTick, 'Save reload changed the game tick');
    Check(gHands.Count = Length(unitsBefore), 'Save reload changed the player count');
    for I := 0 to gHands.Count - 1 do
    begin
      Check(gHands[I].Units.Count = unitsBefore[I], 'Save reload changed the unit count');
      Check(gHands[I].Houses.Count = housesBefore[I], 'Save reload changed the house count');
    end;
    gGame.Scripting.Save(scriptAfter);
    Check((scriptBefore.Size = scriptAfter.Size) and
      CompareMem(scriptBefore.Memory, scriptAfter.Memory, scriptBefore.Size),
      'Save reload changed script state');
    scriptBefore.Free;
    scriptAfter.Free;
    for I := 1 to 10 do
    begin
      gGameApp.DoGameTick;
      CheckScript;
    end;
    // Exercise the real victory/exit persistence path, without claiming a playthrough.
    completedCampaign := gGameApp.Campaigns.CampaignById(campaign);
    gGame.PlayerVictory(gGame.PlayerLoc);
    gGameApp.DoGameTick;
    Check(gGame.GameResult = grWin, 'Victory did not reach the game result');
    gGameApp.StopGame(grWin);
    reloadedProgress := TKMCampaignSavedData.Create(completedCampaign.Spec);
    try
      reloadedProgress.SetMapsCount(completedCampaign.Spec.MissionsCount);
      reloadedProgress.LoadProgress;
      Check(reloadedProgress.MapsProgressData[mission - 1].Completed, 'Mission completion did not persist');
      if mission < completedCampaign.Spec.MissionsCount then
        Check(reloadedProgress.UnlockedMission >= mission, 'Next mission did not unlock');
    finally
      reloadedProgress.Free;
    end;
    WriteLn('PASS: ', campaign, ' mission ', mission, ': startup, ', savedTick,
      ' ticks, rendered frame, save/reload, preserved script state and entity counts, resumed simulation, victory/unlock persistence');
    Flush(Output);
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
