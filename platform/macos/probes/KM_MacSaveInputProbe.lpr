program KM_MacSaveInputProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Forms, LCLType, LMessages,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_CommonTypes, KM_Defaults, KM_GameTypes, KM_CommonClasses,
  KM_HandsCollection, KM_GameSettings, KM_GameSavePoints, KM_Viewport;


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


procedure CheckGame;
begin
  Check((gGame <> nil) and gGame.IsStarted, 'Game did not start');
  Check(not gGame.Scripting.ErrorHandler.HasErrors, 'Mission script error');
  Check(not gGame.Scripting.ErrorHandler.RuntimeErrorOccurred, 'Script runtime error');
end;


procedure CheckInput;
const
  ARROWS: array[0..3] of Word = (VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN);
var
  I: Integer;
  viewport: TKMViewport;
  key: Word;
  wasScrolling: Boolean;
begin
  viewport := gGame.ActiveInterface.Viewport;
  gMain.FormMain.ActiveControl := nil;
  for I := Low(ARROWS) to High(ARROWS) do
  begin
    Check(gMain.FormMain.RenderArea.Perform(CN_KEYDOWN, ARROWS[I], 0) <> 0,
      'Arrow event was not reported as handled to Cocoa');
    case ARROWS[I] of
      VK_LEFT: wasScrolling := viewport.ScrollKeyLeft;
      VK_UP: wasScrolling := viewport.ScrollKeyUp;
      VK_RIGHT: wasScrolling := viewport.ScrollKeyRight;
      VK_DOWN: wasScrolling := viewport.ScrollKeyDown;
    end;
    Check(wasScrolling, 'Consumed arrow did not reach the game camera');
    Check(gMain.FormMain.RenderArea.Perform(CN_KEYDOWN, ARROWS[I], 0) <> 0,
      'Repeated arrow event was not consumed');
    gMain.FormMain.RenderArea.Perform(CN_KEYUP, ARROWS[I], 0);
    gMain.FormMain.RenderArea.Perform(LM_KEYUP, ARROWS[I], 0);
    Check(not (viewport.ScrollKeyLeft or viewport.ScrollKeyUp or
      viewport.ScrollKeyRight or viewport.ScrollKeyDown), 'Arrow release left the camera scrolling');
  end;
  key := Ord('X');
  gMain.FormMain.FormKeyDown(nil, key, []);
  Check(key = Ord('X'), 'Printable key was consumed before text input');
  gMain.FormMain.FormKeyUp(nil, key, []);
  gMain.FormMain.RenderArea.Perform(CN_KEYDOWN, VK_RIGHT, 0);
  gMain.FormMain.OnDeactivate(gMain.FormMain);
  Check(not viewport.ScrollKeyRight, 'Deactivation left an arrow held');
  WriteLn('PASS: four arrows and repeats report handled to Cocoa, reach camera, release and deactivate correctly; printable key remains available');
  Flush(Output);
end;


procedure CheckSaveReload(const aName: string);
var
  savedTick: Cardinal;
  I, checkpointCount: Integer;
  unitsBefore, housesBefore: array of Integer;
  scriptBefore, scriptAfter, pointsBefore, pointsAfter: TKMemoryStreamBinary;
begin
  savedTick := gGameParams.Tick;
  checkpointCount := gGame.SavePoints.Count;
  SetLength(unitsBefore, gHands.Count);
  SetLength(housesBefore, gHands.Count);
  for I := 0 to gHands.Count - 1 do
  begin
    unitsBefore[I] := gHands[I].Units.Count;
    housesBefore[I] := gHands[I].Houses.Count;
  end;
  scriptBefore := TKMemoryStreamBinary.Create;
  scriptAfter := TKMemoryStreamBinary.Create;
  pointsBefore := TKMemoryStreamBinary.Create;
  pointsAfter := TKMemoryStreamBinary.Create;
  try
    gGame.Scripting.Save(scriptBefore);
    gGame.SavePoints.Save(pointsBefore);
    gGame.SaveAndWait(aName);
    gGame.WaitForAllSavesToBeDone;
    gGameApp.NewGameSingleSave(aName);
    CheckGame;
    Check(gGameParams.Tick = savedTick, 'Named save reload changed the game tick');
    Check(gGame.SavePoints.Count = checkpointCount, 'Named save reload lost checkpoints');
    Check(gHands.Count = Length(unitsBefore), 'Named save reload changed player count');
    for I := 0 to gHands.Count - 1 do
    begin
      Check(gHands[I].Units.Count = unitsBefore[I], 'Named save reload changed unit count');
      Check(gHands[I].Houses.Count = housesBefore[I], 'Named save reload changed house count');
    end;
    gGame.Scripting.Save(scriptAfter);
    gGame.SavePoints.Save(pointsAfter);
    Check((scriptBefore.Size = scriptAfter.Size) and
      CompareMem(scriptBefore.Memory, scriptAfter.Memory, scriptBefore.Size), 'Named save changed script state');
    Check((pointsBefore.Size = pointsAfter.Size) and
      CompareMem(pointsBefore.Memory, pointsAfter.Memory, pointsBefore.Size), 'Named save changed replay checkpoints');
    WriteLn('PASS: ', aName, ' saved/reloaded at tick ', savedTick, ' with ', checkpointCount,
      ' checkpoints, identical script/checkpoint bytes and entity counts');
    Flush(Output);
  finally
    pointsAfter.Free;
    pointsBefore.Free;
    scriptAfter.Free;
    scriptBefore.Free;
  end;
end;


var
  probe: TProbe;
  I, initialPoints, latestPoints: Integer;
  initialTick, finalTick, autoTick: Cardinal;
  dataDirectory, autoName: string;
  points: TKMSavePointCollection;
begin
  try
    ConfigureGameFPU;
    dataDirectory := ExcludeTrailingPathDelimiter(ExpandFileName(GetEnvironmentVariable('KAM_DATA_DIR')));
    Check((GetEnvironmentVariable('KAM_DATA_DIR') <> '') and
      (Pos('/assets.local/', dataDirectory + '/') > 0), 'Set KAM_DATA_DIR to disposable assets.local test data');
    Application.Initialize;
    probe := TProbe.Create;
    Application.OnException := probe.ApplicationError;
    gMain := TKMMain.Create;
    Check(gMain.Start, 'Game startup failed');
    gGameSettings.Autosave := True;
    gGameSettings.AutosaveFrequency := 600;
    gGameSettings.AutosaveCount := 5;
    gGameSettings.SaveCheckpoints := True;
    gGameSettings.SaveCheckpointsFreq := 9000;
    gGameApp.NewGameSingleSave('Town Tutorial2');
    CheckGame;
    WriteLn('Loaded original Town Tutorial2 at tick ', gGameParams.Tick);
    CheckSaveReload('mac-regression-recovered-tutorial2');
    gGameApp.NewGameSingleSave('Town Tutorial4');
    CheckGame;
    CheckInput;
    initialTick := gGameParams.Tick;
    initialPoints := gGame.SavePoints.Count;
    for I := 1 to 36000 do
    begin
      gGameApp.DoGameTick;
      gGameApp.UpdateState;
      gGameApp.UpdateStateIdle(100);
      CheckGame;
      if I mod 9000 = 0 then
      begin
        WriteLn('Simulated ', I div 600, ' more minutes; tick=', gGameParams.Tick,
          ', checkpoints=', gGame.SavePoints.Count);
        Flush(Output);
      end;
    end;
    finalTick := gGameParams.Tick;
    Check(finalTick >= initialTick + 36000, 'Simulation stopped before an additional hour');
    Check(gGame.SavePoints.Count >= initialPoints + 4, 'Hourly test did not create four new checkpoints');
    gGame.WaitForAllSavesToBeDone;
    CheckSaveReload('mac-regression-Town Tutorial');
    CheckSaveReload('mac-regression-Town Tutorial2');
    CheckSaveReload('mac-regression-Town Tutorial2');
    for I := 1 to 5 do
    begin
      autoName := AUTOSAVE_SAVE_NAME + Format('%.2d', [I]);
      points := TKMSavePointCollection.Create;
      try
        points.LoadFromFile(TKMGame.SaveName(autoName, 'spt', False));
        latestPoints := points.Count;
        Check(latestPoints >= 3, 'Rotated autosave has no recent checkpoints');
      finally
        points.Free;
      end;
      gGameApp.NewGameSingleSave(autoName);
      CheckGame;
      autoTick := gGameParams.Tick;
      Check((autoTick <= finalTick) and (autoTick > finalTick - Cardinal(I * 600)),
        'Rotated autosave did not advance to the latest minute');
      Check(gGame.SavePoints.Count = latestPoints, 'Autosave reload lost checkpoints');
      gGameApp.DoGameTick;
      Check(gGameParams.Tick > autoTick, 'Reloaded autosave did not resume');
      WriteLn('PASS: ', autoName, ' reloads at tick ', autoTick, ' and resumes with ', latestPoints, ' checkpoints');
      Flush(Output);
    end;
    gGameApp.StopGame(grCancel);
    gMain.Free;
    gMain := nil;
    probe.Free;
    WriteLn('PASS: original tutorial recovery, an additional hour, repeated named saves, overwrite and all five autosave slots');
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
