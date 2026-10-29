program GraphicsProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, Forms, Controls, SysUtils,
  dglOpenGL, KM_RenderControl;

var
  form: TForm;
  render: TKMRenderControl;
  pixel: array [0..3] of Byte;
begin
  try
  Application.Initialize;
  form := TForm.CreateNew(nil);
  try
    form.Caption := 'KaM Remake graphics check';
    form.SetBounds(100, 100, 640, 480);
    render := TKMRenderControl.Create(form);
    render.Parent := form;
    render.Align := alClient;
    form.Show;
    Application.ProcessMessages;
    render.CreateRenderContext;
    if not Assigned(glGetString) then
      raise Exception.Create('OpenGL functions were not loaded');
    WriteLn('OpenGL: ', PAnsiChar(glGetString(GL_VERSION)));
    WriteLn('Renderer: ', PAnsiChar(glGetString(GL_RENDERER)));
    glViewport(0, 0, render.Width, render.Height);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity;
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity;
    glColor4f(0, 1, 0, 1);
    glBegin(GL_QUADS);
    glVertex2f(-1, -1);
    glVertex2f(1, -1);
    glVertex2f(1, 1);
    glVertex2f(-1, 1);
    glEnd;
    glReadPixels(render.Width div 2, render.Height div 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, @pixel[0]);
    if (glGetError <> GL_NO_ERROR) or (pixel[0] <> 0) or (pixel[1] <> 255) or (pixel[2] <> 0) then
      raise Exception.CreateFmt('Legacy renderer pixel check failed: %d,%d,%d', [pixel[0], pixel[1], pixel[2]]);
    render.SwapBuffers;
    Application.ProcessMessages;
    WriteLn('PASS: Cocoa context, legacy GL_QUADS, pixel readback, buffer swap');
    render.DestroyRenderContext;
  finally
    form.Free;
  end;
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      Halt(1);
    end;
  end;
end.
