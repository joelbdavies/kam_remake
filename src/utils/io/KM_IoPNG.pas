unit KM_IoPNG;
{$I KaM_Remake.inc}
interface
uses
  KM_CommonTypes,
  {$IFDEF WDC} PNGImage; {$ENDIF}
  {$IFDEF FPC} FPImage, FPReadPNG, FPWritePNG; {$ENDIF}


  procedure SaveToPng(aWidth, aHeight: Word; const aPixelData: TKMCardinalArray; const aFilename: UnicodeString);
  procedure LoadFromPng(const aFile: UnicodeString; var aWidth, aHeight: Word; var aPixelData: TKMCardinalArray);


implementation
uses
  SysUtils;


procedure SaveToPng(aWidth, aHeight: Word; const aPixelData: TKMCardinalArray; const aFilename: UnicodeString);
var
  {$IFDEF WDC} Png: PNGImage.TPngImage; {$ENDIF}
  {$IFDEF FPC}
  Png: TFPMemoryImage;
  writer: TFPWriterPNG;
  color: TFPColor;
  {$ENDIF}
  I, K: Integer;
  T: Cardinal;
begin
  ForceDirectories(ExtractFilePath(aFilename));

  {$IFDEF WDC}
    Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, aWidth, aHeight);
    try
      for I := 0 to aHeight - 1 do
      for K := 0 to aWidth - 1 do
      begin
        T := aPixelData[I * aWidth + K];
        Png.Canvas.Pixels[K, I] := T and $FFFFFF; //Ignore alpha
        Png.AlphaScanline[I]^[K] := T shr 24; //Alpha
      end;

      Png.SaveToFile(aFilename);
    finally
      Png.Free;
    end;
  {$ENDIF}
  {$IFDEF FPC}
    Png := TFPMemoryImage.Create(aWidth, aHeight);
    writer := TFPWriterPNG.Create;
    try
      writer.UseAlpha := True;
      for I := 0 to aHeight - 1 do
      for K := 0 to aWidth - 1 do
      begin
        T := aPixelData[I * aWidth + K];
        color.Red := (T and $FF) * $101;
        color.Green := ((T shr 8) and $FF) * $101;
        color.Blue := ((T shr 16) and $FF) * $101;
        color.Alpha := (T shr 24) * $101;
        Png.Colors[K, I] := color;
      end;
      Png.SaveToFile(UTF8Encode(aFilename), writer);
    finally
      writer.Free;
      Png.Free;
    end;
  {$ENDIF}
end;


procedure LoadFromPng(const aFile: UnicodeString; var aWidth, aHeight: Word; var aPixelData: TKMCardinalArray);
var
  {$IFDEF WDC}
  Png: TPngImage;
  T: Byte;
  {$ENDIF}
  {$IFDEF FPC}
  Png: TFPMemoryImage;
  reader: TFPReaderPNG;
  color: TFPColor;
  {$ENDIF}
  I, K: Integer;
begin
  {$IFDEF WDC}
    Png := TPngImage.Create;
    Png.LoadFromFile(aFile);

    aWidth := Png.Width;
    aHeight := Png.Height;
    SetLength(aPixelData, Png.Width * Png.Height);

    //There are ways to process PNG transparency
    case Png.TransparencyMode of
      ptmNone:
        for K:=0 to Png.Height-1 do for I:=0 to Png.Width-1 do
          aPixelData[K * Png.Width + I] := cardinal(Png.Pixels[I,K]) or $FF000000;
      ptmBit:
        begin
          T := 0;
          if TChunktRNS(Png.Chunks.ItemFromClass(TChunktRNS)).DataSize > 0 then
            T := TChunktRNS(Png.Chunks.ItemFromClass(TChunktRNS)).PaletteValues[0]; //We don't handle multi-transparent palettes yet
          for K := 0 to Png.Height - 1 do for I := 0 to Png.Width - 1 do
            if PByteArray(Png.Scanline[K])^[I] = T then
              aPixelData[K * Png.Width + I] := cardinal(Png.Pixels[I,K]) and $FFFFFF //avoid black edging
            else
              aPixelData[K * Png.Width + I] := cardinal(Png.Pixels[I,K]) or $FF000000;
        end;
      ptmPartial:
        for K := 0 to Png.Height - 1 do for I := 0 to Png.Width - 1 do
        begin
          T := Png.AlphaScanline[K]^[I];
          aPixelData[K * Png.Width + I] := cardinal(Png.Pixels[I,K]) or (T shl 24);
        end;
      else
        raise Exception.Create('Unknown PNG transparency mode');
    end;

    Png.Free;
  {$ENDIF}
  {$IFDEF FPC}
    Png := TFPMemoryImage.Create(0, 0);
    reader := TFPReaderPNG.Create;
    try
      Png.LoadFromFile(UTF8Encode(aFile), reader);
      if (Png.Width > High(Word)) or (Png.Height > High(Word)) then
        raise Exception.Create('PNG dimensions exceed the game limit');
      aWidth := Png.Width;
      aHeight := Png.Height;
      SetLength(aPixelData, Png.Width * Png.Height);
      for K := 0 to Png.Height - 1 do
      for I := 0 to Png.Width - 1 do
      begin
        color := Png.Colors[I, K];
        aPixelData[K * Png.Width + I] := Cardinal(color.Red shr 8)
          or (Cardinal(color.Green shr 8) shl 8)
          or (Cardinal(color.Blue shr 8) shl 16)
          or (Cardinal(color.Alpha shr 8) shl 24);
      end;
    finally
      reader.Free;
      Png.Free;
    end;
  {$ENDIF}
end;


end.
