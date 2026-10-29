program KM_MacMouseProbe;
{$I KaM_Remake.inc}
{$modeswitch objectivec1}
uses
  cthreads, Interfaces, SysUtils, Types, Forms, Controls, LMessages, LCLType, ObjCRtl, ObjCRtl20,
  CocoaAll, CocoaUtils,
  KM_LCLControls, KM_FPU, KM_Main, KM_GameApp, KM_Game, KM_GameTypes,
  KM_Defaults, KM_GameSettings, KM_Cursor, KM_Points, KM_Viewport;


type
  TKMProbe = class
    procedure ApplicationError(Sender: TObject; E: Exception);
  end;

var
  cursorClass: ObjCRtl._Class;
  cursorSelector: ObjCRtl.SEL;
  cursorImplementation: IMP;
  cursorEncoding: PAnsiChar;
  cursorPosition: NSPoint;
  viewport: TKMViewport;


function ProbeMouseLocation(aObject: Pointer; aSelector: ObjCRtl.SEL): NSPoint; cdecl;
begin
  Result := cursorPosition;
end;


procedure RestoreNativeMethod;
begin
  if cursorImplementation <> nil then
    class_replaceMethod(cursorClass, cursorSelector, cursorImplementation, cursorEncoding);
  cursorImplementation := nil;
end;


procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then raise Exception.Create(aMessage);
end;


procedure TKMProbe.ApplicationError(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, E.ClassName, ': ', E.Message);
  DumpExceptionBackTrace(StdErr);
  RestoreNativeMethod;
  Halt(1);
end;


procedure CheckScroll(const aLabel: string; const aGlobal, aEvent: TPoint;
  aDirectionX, aDirectionY: Integer; aAllowScrolling: Boolean = True);
var
  position: TKMPointF;
begin
  // Override only this process's cursor query; never move the user's real pointer.
  cursorPosition := TCocoaScreenUtil.toCocoa(aGlobal);
  Check((Mouse.CursorPos.X = aGlobal.X) and (Mouse.CursorPos.Y = aGlobal.Y),
    'Cocoa global cursor fixture was not applied');
  gGameApp.MouseMove([], aEvent.X, aEvent.Y);
  viewport.Position := KMPointF(256, 256);
  viewport.UpdateStateIdle(100, aAllowScrolling, False);
  position := viewport.Position;
  Check(((aDirectionX = 0) and (position.X = 256)) or
        ((aDirectionX <> 0) and ((position.X - 256) * aDirectionX > 0)), aLabel + ': wrong horizontal movement');
  Check(((aDirectionY = 0) and (position.Y = 256)) or
        ((aDirectionY <> 0) and ((position.Y - 256) * aDirectionY > 0)), aLabel + ': wrong vertical movement');
end;


var
  probe: TKMProbe;
  deadline: QWord;
  dataDirectory: string;
  bounds, renderBounds: TRect;
  center, eventCenter: TPoint;
begin
  try
    ConfigureGameFPU;
    InitializeObjcRtl20('/usr/lib/libobjc.A.dylib');
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
    FEAT_SCROLL_ACCEL := False;
    IGNORE_MOUSE_SCROLLING := False;
    gMain.FormMain.WindowState := wsNormal;
    Check(gMain.GetScreenBounds(bounds), 'Monitor bounds unavailable');
    gMain.FormMain.SetBounds(bounds.Left + 100, bounds.Top + 100,
      bounds.Right - bounds.Left - 200, bounds.Bottom - bounds.Top - 200);
    Application.ProcessMessages;
    // Inject LCL focus state so this regression also runs on a locked desktop.
    gMain.FormMain.Perform(LM_ACTIVATE, WA_ACTIVE, 0);
    Check(gMain.IsFormActive, 'Form activation fixture failed');
    Check(gMain.GetScreenBounds(bounds), 'Monitor bounds unavailable after resize');
    renderBounds := gMain.ClientRect;
    Check((renderBounds.Left > bounds.Left + 5) and (renderBounds.Top > bounds.Top + 5) and
      (renderBounds.Right < bounds.Right - 5) and (renderBounds.Bottom < bounds.Bottom - 5),
      'Test window must be inset from every monitor edge');
    eventCenter := Point(gMain.FormMain.RenderArea.Width div 2, gMain.FormMain.RenderArea.Height div 2);
    center := gMain.ClientToScreen(eventCenter);
    viewport := TKMViewport.Create(0, 640, 480, nil);
    viewport.ResizeMap(512, 512, 0);
    cursorClass := objc_getMetaClass('NSEvent');
    cursorSelector := sel_registerName('mouseLocation');
    cursorImplementation := class_getMethodImplementation(cursorClass, cursorSelector);
    Check(cursorImplementation <> nil, 'Native cursor method unavailable');
    cursorEncoding := method_getTypeEncoding(class_getInstanceMethod(cursorClass, cursorSelector));
    cursorPosition := TCocoaScreenUtil.toCocoa(center);
    class_replaceMethod(cursorClass, cursorSelector, IMP(@ProbeMouseLocation), cursorEncoding);
    try
      CheckScroll('Left monitor edge', Point(bounds.Left, center.Y), eventCenter, -1, 0);
      CheckScroll('Right monitor edge', Point(bounds.Right - 1, center.Y), eventCenter, 1, 0);
      CheckScroll('Top monitor edge', Point(center.X, bounds.Top), eventCenter, 0, -1);
      CheckScroll('Bottom monitor edge', Point(center.X, bounds.Bottom - 1), eventCenter, 0, 1);
      CheckScroll('Return inside', center, eventCenter, 0, 0);
      WriteLn('PASS: all four monitor edges scroll outside an inset window and stop on return');

      // A rejected out-of-frame event must not make the old cached point win.
      CheckScroll('Rejected outside event', Point(bounds.Left, center.Y), Point(-1, eventCenter.Y), -1, 0);
      Check((gCursor.Pixel.X = eventCenter.X) and (gCursor.Pixel.Y = eventCenter.Y),
        'Out-of-frame event did not leave the expected stale game cursor');
      WriteLn('PASS: stale cursor after an out-of-frame event does not suppress monitor-edge scrolling');

      viewport.ScrollKeyRight := True;
      CheckScroll('Keyboard scrolling', center, eventCenter, 1, 0);
      viewport.ReleaseScrollKeys;
      CheckScroll('Scrolling disabled', Point(bounds.Left, center.Y), eventCenter, 0, 0, False);
      gMain.FormMain.Perform(LM_ACTIVATE, WA_INACTIVE, 0);
      Check(not gMain.IsFormActive, 'Form deactivation fixture failed');
      CheckScroll('Inactive window', Point(bounds.Left, center.Y), eventCenter, 0, 0);
      gMain.FormMain.Perform(LM_ACTIVATE, WA_ACTIVE, 0);
      WriteLn('PASS: keyboard scrolling, scrolling permission and inactive-window gates are preserved');
    finally
      RestoreNativeMethod;
    end;

    // Put the render area's left edge on the monitor edge for remote input.
    gMain.FormMain.Left := gMain.FormMain.Left + bounds.Left - renderBounds.Left;
    Application.ProcessMessages;
    gMain.FormMain.Perform(LM_ACTIVATE, WA_ACTIVE, 0);
    renderBounds := gMain.ClientRect;
    Check(renderBounds.Left = bounds.Left, 'Render area did not reach the monitor edge');
    center := gMain.ClientToScreen(eventCenter);
    cursorImplementation := class_getMethodImplementation(cursorClass, cursorSelector);
    cursorPosition := TCocoaScreenUtil.toCocoa(center);
    class_replaceMethod(cursorClass, cursorSelector, IMP(@ProbeMouseLocation), cursorEncoding);
    try
      CheckScroll('Remote event at left edge', center, Point(2, eventCenter.Y), -1, 0);
      CheckScroll('Remote event back inside', Point(bounds.Left, center.Y), eventCenter, 0, 0);
      CheckScroll('Right render boundary', Point(renderBounds.Right, center.Y), Point(2, eventCenter.Y), 0, 0);
      CheckScroll('Bottom render boundary', Point(center.X, renderBounds.Bottom), Point(2, eventCenter.Y), 0, 0);
      WriteLn('PASS: remote event coordinates win inside; right and bottom render boundaries use the global cursor');
    finally
      RestoreNativeMethod;
    end;
    viewport.Free;
    gGameApp.StopGame(grCancel);
    gMain.Free;
    gMain := nil;
    probe.Free;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      RestoreNativeMethod;
      Halt(1);
    end;
  end;
end.
