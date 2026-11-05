program KM_MacCocoaEventProbe;
{$I KaM_Remake.inc}
{$modeswitch objectivec1}
uses
  cthreads, Interfaces, SysUtils, Forms, ObjCRtl, ObjCRtl20, CocoaAll, MacOSAll,
  GLCocoaNSContext, CocoaWindows, KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game,
  KM_Defaults, KM_GameTypes, KM_GameSettings, KM_InterfaceGamePlay, KM_ControlsEdit;


type
  TKMGamePlayAccess = class(TKMGamePlayInterface)
    function OpenSaveEdit: TKMFilenameEdit;
  end;
  TKMProbe = class
    procedure ApplicationError(Sender: TObject; E: Exception);
  end;
  TKMNativeKeyDown = procedure(aObject: Pointer; aSelector: ObjCRtl.SEL; aEvent: NSEvent); cdecl;

var
  nativeKeyDownCount: Cardinal;
  documentClass, viewClass: ObjCRtl._Class;
  keyDownSelector: ObjCRtl.SEL;
  documentKeyDown, viewKeyDown: TKMNativeKeyDown;
  documentImplementation, viewImplementation: IMP;
  documentEncoding, viewEncoding: PAnsiChar;


procedure ProbeDocumentKeyDown(aObject: Pointer; aSelector: ObjCRtl.SEL; aEvent: NSEvent); cdecl;
begin
  Inc(nativeKeyDownCount);
  documentKeyDown(aObject, aSelector, aEvent);
end;


procedure ProbeViewKeyDown(aObject: Pointer; aSelector: ObjCRtl.SEL; aEvent: NSEvent); cdecl;
begin
  Inc(nativeKeyDownCount);
  viewKeyDown(aObject, aSelector, aEvent);
end;


procedure RestoreNativeMethods;
begin
  if Assigned(documentKeyDown) then
    class_replaceMethod(documentClass, keyDownSelector, documentImplementation, documentEncoding);
  if Assigned(viewKeyDown) then
    class_replaceMethod(viewClass, keyDownSelector, viewImplementation, viewEncoding);
  documentKeyDown := nil;
  viewKeyDown := nil;
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
  RestoreNativeMethods;
  Halt(1);
end;


function TKMGamePlayAccess.OpenSaveEdit: TKMFilenameEdit;
begin
  Button_Menu_Save.OnClick(Button_Menu_Save);
  Result := FilenameEdit_Save;
end;


procedure SendKey(const aLabel: string; aCode: Word; const aCharacters: UnicodeString;
  aRepeat: Boolean = False; aExpectNativeBypass: Boolean = True);
var
  event: NSEvent;
  characters: NSString;
  pool: NSAutoreleasePool;
  window: NSWindow;
  before: Cardinal;
begin
  pool := NSAutoreleasePool.alloc.init;
  characters := NSString.alloc.initWithUTF8String(PChar(UTF8Encode(aCharacters)));
  try
    window := TCocoaOpenGLView(gMain.FormMain.RenderArea.Handle).window;
    before := nativeKeyDownCount;
    event := NSEvent.keyEventWithType_location_modifierFlags_timestamp_windowNumber_context_characters_charactersIgnoringModifiers_isARepeat_keyCode(
      NSKeyDown, NSMakePoint(0, 0), 0, 0, window.windowNumber, nil, characters, characters, aRepeat, aCode);
    // Dispatch through the real application and current first responder. Calling
    // KeyEvAfterDown directly skips Cocoa's intermediate text-input processing.
    NSApp.sendEvent(event);
    event := NSEvent.keyEventWithType_location_modifierFlags_timestamp_windowNumber_context_characters_charactersIgnoringModifiers_isARepeat_keyCode(
      NSKeyUp, NSMakePoint(0, 0), 0, 0, window.windowNumber, nil, characters, characters, False, aCode);
    NSApp.sendEvent(event);
    if aExpectNativeBypass then
      Check(nativeKeyDownCount = before, aLabel + ': handled game key reached Cocoa text/command processing');
  finally
    characters.release;
    pool.release;
  end;
end;


var
  probe: TKMProbe;
  edit: TKMFilenameEdit;
  deadline: QWord;
  I, focusMode: Integer;
  dataDirectory: string;
  expectedText: UnicodeString;
  beforeText: Cardinal;
  window: NSWindow;
const
  FUNCTION_CODES: array[1..12] of Word = (kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
    kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12);
begin
  try
    ConfigureGameFPU;
    InitializeObjcRtl20('/usr/lib/libobjc.A.dylib');
    Check(Assigned(object_setClass), 'Objective-C test runtime did not load');
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
    window := TCocoaOpenGLView(gMain.FormMain.RenderArea.Handle).window;
    // Test-only method observers preserve Cocoa/KVO classes and call the original
    // implementations. They detect native processing of keys already handled by the game.
    keyDownSelector := sel_registerName('keyDown:');
    documentClass := object_getClass(TCocoaWindowContent(gMain.FormMain.Handle).documentView);
    viewClass := object_getClass(NSObject(gMain.FormMain.RenderArea.Handle));
    documentImplementation := class_getMethodImplementation(documentClass, keyDownSelector);
    documentKeyDown := TKMNativeKeyDown(documentImplementation);
    viewImplementation := class_getMethodImplementation(viewClass, keyDownSelector);
    viewKeyDown := TKMNativeKeyDown(viewImplementation);
    documentEncoding := method_getTypeEncoding(class_getInstanceMethod(documentClass, keyDownSelector));
    viewEncoding := method_getTypeEncoding(class_getInstanceMethod(viewClass, keyDownSelector));
    class_replaceMethod(documentClass, keyDownSelector, IMP(@ProbeDocumentKeyDown), documentEncoding);
    class_replaceMethod(viewClass, keyDownSelector, IMP(@ProbeViewKeyDown), viewEncoding);
    for focusMode := 0 to 1 do
    begin
      if focusMode = 0 then
      begin
        gMain.FormMain.ActiveControl := nil;
        window.makeFirstResponder(TCocoaWindowContent(gMain.FormMain.Handle).documentView);
        Check(window.firstResponder = TCocoaWindowContent(gMain.FormMain.Handle).documentView, 'Form could not become first responder');
      end
      else
        gMain.FormMain.RenderArea.SetFocus;
      WriteLn('First responder: ', window.firstResponder.className.UTF8String);
      Flush(Output);
      edit := TKMGamePlayAccess(gGame.GamePlayInterface).OpenSaveEdit;
      edit.Text := 'Town Tutorial2';
      edit.CursorPos := Length(edit.Text);
      SendKey('Backspace', kVK_Delete, #127);
      Check(edit.Text = 'Town Tutorial', 'Backspace did not delete exactly once');
      SendKey('Repeated Backspace', kVK_Delete, #127, True);
      Check(edit.Text = 'Town Tutoria', 'Repeated Backspace did not delete exactly once');
      SendKey('Left', kVK_LeftArrow, System.WideChar(NSLeftArrowFunctionKey));
      SendKey('Forward Delete', kVK_ForwardDelete, System.WideChar(NSDeleteFunctionKey));
      Check(edit.Text = 'Town Tutori', 'Forward Delete did not delete exactly once');
      SendKey('Home', kVK_Home, System.WideChar(NSHomeFunctionKey));
      Check(edit.CursorPos = 0, 'Home did not move to start');
      SendKey('End', kVK_End, System.WideChar(NSEndFunctionKey));
      Check(edit.CursorPos = Length(edit.Text), 'End did not move to end');
      SendKey('Up', kVK_UpArrow, System.WideChar(NSUpArrowFunctionKey));
      SendKey('Down', kVK_DownArrow, System.WideChar(NSDownArrowFunctionKey));
      SendKey('Right', kVK_RightArrow, System.WideChar(NSRightArrowFunctionKey));
      SendKey('Page Up', kVK_PageUp, System.WideChar(NSPageUpFunctionKey));
      SendKey('Page Down', kVK_PageDown, System.WideChar(NSPageDownFunctionKey));
      edit.Text := '';
      edit.MaxLen := 255;
      beforeText := nativeKeyDownCount;
      expectedText := '';
      for I := 32 to 126 do
      begin
        SendKey('ASCII ' + IntToStr(I), kVK_ANSI_A, System.WideChar(I), False, False);
        if not (Chr(I) in ['<', '>', '|', '"', '\', '/', ':', '*', '?']) then
          expectedText := expectedText + System.WideChar(I);
        Check(edit.Text = expectedText, 'Text was lost or duplicated at ASCII ' + IntToStr(I));
      end;
      Check(nativeKeyDownCount > beforeText, 'Native observer did not see printable input');
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
      WriteLn('PASS: native application dispatch, focus mode ', focusMode,
        ', editing/navigation/F1-F12 bypass native command processing; 95 ASCII characters arrive exactly once');
      Flush(Output);
    end;
    RestoreNativeMethods;
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
      RestoreNativeMethods;
      Halt(1);
    end;
  end;
end.
