program KM_MacCursorProbe;
{$I KaM_Remake.inc}
{$modeswitch objectivec1}
uses
  cthreads, Interfaces, SysUtils, TypInfo, Forms, CocoaAll, LCLIntf,
  KM_LCLControls, KM_FPU, KM_Main, KM_ResTypes, KM_ResSprites;


type
  TKMProbe = class
    procedure ApplicationError(Sender: TObject; E: Exception);
  end;


procedure TKMProbe.ApplicationError(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, E.ClassName, ': ', E.Message);
  DumpExceptionBackTrace(StdErr);
  Halt(1);
end;


var
  probe: TKMProbe;
  cursor: TKMCursorImageType;
  previousCursor: NSCursor;
  bitmap: NSBitmapImageRep;
  pixel: array[0..4] of NSUInteger;
  x, y, alphaIndex, transparent, opaque, partial, dirtyTransparent, mismatch: Integer;
  expected, rgba, actualAlpha: Cardinal;
  redIndex, colorMismatch, totalMismatches: Integer;
  dataDirectory, outputDirectory: string;
  rxData: PRXData;
  sourceSprites: TKMResSprites;
  imageData: NSData;
begin
  try
    ConfigureGameFPU;
    dataDirectory := ExpandFileName(GetEnvironmentVariable('KAM_DATA_DIR'));
    if (GetEnvironmentVariable('KAM_DATA_DIR') = '') or (Pos('/assets.local/', dataDirectory + '/') = 0) then
      raise Exception.Create('Use a disposable KAM_DATA_DIR under assets.local');
    outputDirectory := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
    if (ParamStr(1) = '') or (Pos('/assets.local/', outputDirectory) = 0) then
      raise Exception.Create('Use an output directory under assets.local');
    ForceDirectories(outputDirectory);
    Application.Initialize;
    probe := TKMProbe.Create;
    Application.OnException := probe.ApplicationError;
    gMain := TKMMain.Create;
    if not gMain.Start then raise Exception.Create('Startup failed');
    sourceSprites := TKMResSprites.Create(nil, nil, True);
    if not sourceSprites.LoadSprites(rxGui, True) then raise Exception.Create('Could not load cursor sprite source');
    rxData := @sourceSprites[rxGui].RXData;
    totalMismatches := 0;
    previousCursor := NSCursor(NSCursor.currentCursor.retain);
    try
      for cursor := Low(TKMCursorImageType) to kmcPaintBucket do
      begin
        LCLIntf.SetCursor(Screen.Cursors[Ord(cursor) + 1]);
        bitmap := NSBitmapImageRep.imageRepWithData(NSCursor.currentCursor.image.TIFFRepresentation);
        if bitmap = nil then raise Exception.Create('Missing native cursor image');
        if cursor = kmcInvisible then
        begin
          if (bitmap.pixelsWide <> 1) or (bitmap.pixelsHigh <> 1) then
            raise Exception.Create('Invisible cursor dimensions changed');
        end
        else
          if (bitmap.pixelsWide <> rxData.Size[CURSOR_SPRITE_INDEX[cursor]].X) or
             (bitmap.pixelsHigh <> rxData.Size[CURSOR_SPRITE_INDEX[cursor]].Y) then
            raise Exception.Create('Native cursor dimensions differ from source');
        if not bitmap.hasAlpha or (bitmap.bitsPerSample <> 8) or (bitmap.samplesPerPixel <> 4) then
          raise Exception.Create('Expected RGBA cursor bitmap');
        alphaIndex := 3;
        if bitmap.bitmapFormat and NSAlphaFirstBitmapFormat <> 0 then alphaIndex := 0;
        redIndex := 0;
        if alphaIndex = 0 then redIndex := 1;
        transparent := 0;
        opaque := 0;
        partial := 0;
        dirtyTransparent := 0;
        mismatch := 0;
        colorMismatch := 0;
        for y := 0 to bitmap.pixelsHigh - 1 do
          for x := 0 to bitmap.pixelsWide - 1 do
          begin
            bitmap.getPixel_atX_y(@pixel[0], x, y);
            actualAlpha := pixel[alphaIndex];
            case actualAlpha of
              0: begin
                   Inc(transparent);
                   if pixel[0] + pixel[1] + pixel[2] + pixel[3] <> 0 then Inc(dirtyTransparent);
                 end;
              255: Inc(opaque);
            else
              Inc(partial);
            end;
            if cursor = kmcInvisible then
              expected := 0
            else
            begin
              rgba := rxData.RGBA[CURSOR_SPRITE_INDEX[cursor], y * bitmap.pixelsWide + x];
              expected := rgba shr 24;
              if expected <> 0 then
              begin
                // Match the existing game's binary cursor opacity policy.
                expected := 255;
                if (pixel[redIndex] <> (rgba and $FF)) or
                   (pixel[redIndex + 1] <> ((rgba shr 8) and $FF)) or
                   (pixel[redIndex + 2] <> ((rgba shr 16) and $FF)) then Inc(colorMismatch);
              end;
            end;
            if actualAlpha <> expected then Inc(mismatch);
          end;
        Inc(totalMismatches, mismatch + colorMismatch + dirtyTransparent);
        WriteLn('CURSOR ', GetEnumName(TypeInfo(TKMCursorImageType), Ord(cursor)),
          ' size=', bitmap.pixelsWide, 'x', bitmap.pixelsHigh,
          ' transparent=', transparent, ' opaque=', opaque, ' partial=', partial,
          ' dirty-transparent=', dirtyTransparent, ' alpha-mismatches=', mismatch, ' color-mismatches=', colorMismatch);
        imageData := bitmap.representationUsingType_properties(NSPNGFileType, nil);
        if not imageData.writeToFile_atomically(NSSTR(outputDirectory + IntToStr(Ord(cursor)) + '.png'), True) then
          raise Exception.Create('Could not export native cursor image');
        if (mismatch = 0) and (colorMismatch = 0) and (dirtyTransparent = 0) then
          WriteLn('PASS: ', GetEnumName(TypeInfo(TKMCursorImageType), Ord(cursor)),
            ' native pixels match source colors and opacity, with clear transparent pixels');
      end;
    finally
      previousCursor.set_;
      previousCursor.release;
    end;
    if totalMismatches <> 0 then
      raise Exception.CreateFmt('%d native cursor pixel mismatches', [totalMismatches]);
    sourceSprites.Free;
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
