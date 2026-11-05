program KM_MacKeyboardProbe;
{$I KaM_Remake.inc}
{$modeswitch objectivec1}
uses
  cthreads, Interfaces, SysUtils, Classes, Forms, Controls, StdCtrls, LCLType,
  CocoaAll, MacOSAll, GLCocoaNSContext, CocoaCommonCallback,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameParams,
  KM_Defaults, KM_GameTypes, KM_GameSettings, KM_InterfaceGamePlay,
  KM_ControlsEdit;


type
  TKMGamePlayAccess = class(TKMGamePlayInterface)
    function OpenSaveEdit: TKMFilenameEdit;
  end;
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


function TKMGamePlayAccess.OpenSaveEdit: TKMFilenameEdit;
begin
  Button_Menu_Save.OnClick(Button_Menu_Save);
  Result := FilenameEdit_Save;
end;


procedure SendKey(const aLabel: string; aCode: Word; const aCharacters: UnicodeString;
  aModifiers: NSUInteger = 0; aRepeat: Boolean = False);
var
  callback: TLCLCommonCallback;
  event: NSEvent;
  characters: NSString;
  pool: NSAutoreleasePool;
  allowBefore, allowAfter: Boolean;
begin
  pool := NSAutoreleasePool.alloc.init;
  characters := NSString.alloc.initWithUTF8String(PChar(UTF8Encode(aCharacters)));
  try
    callback := TCocoaOpenGLView(gMain.FormMain.RenderArea.Handle).callback;
    event := NSEvent.keyEventWithType_location_modifierFlags_timestamp_windowNumber_context_characters_charactersIgnoringModifiers_isARepeat_keyCode(
      NSKeyDown, NSMakePoint(0, 0), aModifiers, 0, 0, nil, characters, characters, aRepeat, aCode);
    callback.KeyEvBefore(event, allowBefore);
    callback.KeyEvAfterDown(allowAfter);
    Check(not allowAfter, aLabel + ': Cocoa was allowed to handle the event again (beep path)');
    event := NSEvent.keyEventWithType_location_modifierFlags_timestamp_windowNumber_context_characters_charactersIgnoringModifiers_isARepeat_keyCode(
      NSKeyUp, NSMakePoint(0, 0), aModifiers, 0, 0, nil, characters, characters, False, aCode);
    callback.KeyEvBefore(event, allowBefore);
    callback.KeyEvAfter;
  finally
    characters.release;
    pool.release;
  end;
end;


var
  probe: TKMProbe;
  edit: TKMFilenameEdit;
  deadline: QWord;
  I: Integer;
  key: Word;
  character: Char;
  expectedText: UnicodeString;
  nativeEdit: TEdit;
  dataDirectory: string;
const
  FUNCTION_CODES: array[1..12] of Word = (kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
    kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12);
begin
  try
    ConfigureGameFPU;
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
    gGameSettings.Autosave := False;
    gGameApp.NewGameCampaignMap('TSK', 1);
    Check((gGame <> nil) and gGame.IsStarted, 'Mission did not start');
    edit := TKMGamePlayAccess(gGame.GamePlayInterface).OpenSaveEdit;
    edit.Text := 'Town Tutorial2';
    edit.CursorPos := Length(edit.Text);
    SendKey('Backspace', kVK_Delete, #127);
    Check(edit.Text = 'Town Tutorial', 'Backspace did not delete exactly one character');
    SendKey('Backspace repeat', kVK_Delete, #127, 0, True);
    Check(edit.Text = 'Town Tutoria', 'Repeated Backspace changed the wrong characters');
    SendKey('Left', kVK_LeftArrow, System.WideChar(NSLeftArrowFunctionKey));
    SendKey('Forward Delete', kVK_ForwardDelete, System.WideChar(NSDeleteFunctionKey));
    Check(edit.Text = 'Town Tutori', 'Forward Delete did not delete at the cursor');
    SendKey('Home', kVK_Home, System.WideChar(NSHomeFunctionKey));
    Check(edit.CursorPos = 0, 'Home did not move to start');
    SendKey('End', kVK_End, System.WideChar(NSEndFunctionKey));
    Check(edit.CursorPos = Length(edit.Text), 'End did not move to end');
    edit.Text := '';
    edit.MaxLen := 255;
    expectedText := '';
    for I := 32 to 126 do
    begin
      SendKey('ASCII ' + IntToStr(I), kVK_ANSI_A, System.WideChar(I));
      if not (Chr(I) in ['<', '>', '|', '"', '\', '/', ':', '*', '?']) then
        expectedText := expectedText + System.WideChar(I);
      Check(edit.Text = expectedText, 'Printable character was lost, duplicated or incorrectly filtered: ' + IntToStr(I));
    end;
    Check(Pos('ABCDEFGHIJKLMNOPQRSTUVWXYZ', edit.Text) > 0, 'Uppercase text was lost');
    Check(Pos('abcdefghijklmnopqrstuvwxyz', edit.Text) > 0, 'Lowercase text was lost');
    Check(Pos('0123456789', edit.Text) > 0, 'Digits were lost');
    edit.Text := 'abc';
    edit.CursorPos := 3;
    // Cocoa reads Ctrl/Shift from NSApp.currentEvent; this callback-only test
    // validates modifier semantics through the form with an explicit shift state.
    key := Ord('A');
    gMain.FormMain.FormKeyDown(nil, key, [ssCtrl]);
    Check(key = 0, 'Control shortcut was not consumed before native command processing');
    key := Ord('A');
    gMain.FormMain.FormKeyUp(nil, key, [ssCtrl]);
    Check((edit.SelectionStart = 0) and (edit.SelectionEnd = 3), 'Select-all was lost');
    SendKey('Replace selection', kVK_ANSI_X, 'x');
    Check(edit.Text = 'x', 'Typing did not replace the selection exactly once');
    edit.Text := '';
    SendKey('Backspace on empty text', kVK_Delete, #127);
    SendKey('Delete on empty text', kVK_ForwardDelete, System.WideChar(NSDeleteFunctionKey));
    SendKey('Tab', kVK_Tab, #9);
    SendKey('Return', kVK_Return, #13);
    SendKey('Keypad Return', kVK_ANSI_KeypadEnter, #13);
    SendKey('Escape', kVK_Escape, #27);
    for I := 1 to 12 do
    begin
      edit := TKMGamePlayAccess(gGame.GamePlayInterface).OpenSaveEdit;
      edit.Text := '';
      SendKey('F' + IntToStr(I), FUNCTION_CODES[I], System.WideChar(NSF1FunctionKey + I - 1));
    end;
    edit := TKMGamePlayAccess(gGame.GamePlayInterface).OpenSaveEdit;
    edit.Text := 'navigation';
    SendKey('Up', kVK_UpArrow, System.WideChar(NSUpArrowFunctionKey));
    SendKey('Down', kVK_DownArrow, System.WideChar(NSDownArrowFunctionKey));
    SendKey('Right', kVK_RightArrow, System.WideChar(NSRightArrowFunctionKey));
    SendKey('Page Up', kVK_PageUp, System.WideChar(NSPageUpFunctionKey));
    SendKey('Page Down', kVK_PageDown, System.WideChar(NSPageDownFunctionKey));
    SendKey('Shift-Left', kVK_LeftArrow, System.WideChar(NSLeftArrowFunctionKey), NSShiftKeyMask);
    SendKey('Control-A callback', kVK_ANSI_A, #1, NSControlKeyMask);
    SendKey('Command-A', kVK_ANSI_A, 'a', NSCommandKeyMask);
    SendKey('Option-A', kVK_ANSI_A, 'a', NSAlternateKeyMask);
    SendKey('Control-Left', kVK_LeftArrow, System.WideChar(NSLeftArrowFunctionKey), NSControlKeyMask);
    // A native debug edit owns its keys; Form.KeyPreview must not also edit the game save name.
    nativeEdit := TEdit.Create(gMain.FormMain);
    try
      nativeEdit.Parent := gMain.FormMain;
      gMain.FormMain.ActiveControl := nativeEdit;
      edit.Text := 'unchanged';
      edit.CursorPos := Length(edit.Text);
      key := VK_BACK;
      gMain.FormMain.FormKeyDown(nil, key, []);
      Check((key = VK_BACK) and (edit.Text = 'unchanged'), 'Native edit key leaked into the game');
      gMain.FormMain.FormKeyUp(nil, key, []);
      character := 'x';
      gMain.FormMain.FormKeyPress(nil, character);
      Check((character = 'x') and (edit.Text = 'unchanged'), 'Native edit text leaked into the game');
      gMain.FormMain.ActiveControl := nil;
      SendKey('Close save dialog', kVK_Escape, #27);
      key := VK_RIGHT;
      gMain.FormMain.FormKeyDown(nil, key, []);
      Check(gGame.ActiveInterface.Viewport.ScrollKeyRight, 'Held key did not reach camera');
      gMain.FormMain.ActiveControl := nativeEdit;
      key := VK_RIGHT;
      gMain.FormMain.FormKeyUp(nil, key, []);
      Check(not gGame.ActiveInterface.Viewport.ScrollKeyRight, 'Focus change left camera key held');
    finally
      nativeEdit.Free;
      gMain.FormMain.ActiveControl := nil;
    end;
    WriteLn('PASS: Cocoa consumes editing, navigation, 95 printable ASCII characters, F1-F12, shortcuts and repeats; native controls retain input and focus changes release held keys');
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
