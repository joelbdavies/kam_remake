unit KM_IoGraphicUtils;
{$I KaM_Remake.inc}
interface
uses
  KM_CommonTypes
  {$IFDEF MSWindows}, Windows {$ENDIF}
  {$IFDEF WDC}, Graphics, JPEG, PNGImage {$ENDIF} //Lazarus doesn't have JPEG library yet -> FPReadJPEG?
  ;

  procedure SavePixelDataToFile(const aFilePath: string; aImageType: TKMImageType; aWidth, aHeight: Integer; var aPixelData: TKMCardinalArray);

implementation
uses
  SysUtils, KM_FileIO
{$IFDEF WDC}, Dialogs, KM_Log{$ENDIF}
{$IFDEF FPC}, FPImage, FPWritePNG, FPWriteJPEG, FPWriteBMP{$ENDIF}
  ;


procedure SavePixelDataToFile(const aFilePath: string; aImageType: TKMImageType; aWidth, aHeight: Integer; var aPixelData: TKMCardinalArray);
{$IFDEF WDC}
var
  filePath: string;
  mkbmp: TBitmap;
  jpg: TJpegImage;
  png: TPngImage;
{$ENDIF}
{$IFDEF FPC}
var
  image: TFPMemoryImage;
  writer: TFPCustomImageWriter;
  color: TFPColor;
  pixel: Cardinal;
  X, Y: Integer;
{$ENDIF}
begin
{$IFDEF FPC}
  if (aWidth <= 0) or (aHeight <= 0) or (Length(aPixelData) <> aWidth * aHeight) then
    raise EArgumentException.Create('Invalid screenshot pixel buffer');
  ForceDirectories(ExtractFilePath(aFilePath));
  image := TFPMemoryImage.Create(aWidth, aHeight);
  writer := nil;
  try
    for Y := 0 to aHeight - 1 do
      for X := 0 to aWidth - 1 do
      begin
        pixel := aPixelData[Y * aWidth + X]; // OpenGL BGRA, already flipped vertically
        color.Red := ((pixel shr 16) and $FF) * 257;
        color.Green := ((pixel shr 8) and $FF) * 257;
        color.Blue := (pixel and $FF) * 257;
        color.Alpha := $FFFF;
        image.Colors[X, Y] := color;
      end;
    case aImageType of
      itPng: writer := TFPWriterPNG.Create;
      itJpeg: begin
                writer := TFPWriterJPEG.Create;
                TFPWriterJPEG(writer).CompressionQuality := 90;
              end;
      itBmp: writer := TFPWriterBMP.Create;
    end;
    image.SaveToFile(ChangeFileExt(aFilePath, IMAGE_TYPE_EXT[aImageType]), writer);
  finally
    writer.Free;
    image.Free;
  end;
{$ENDIF}
{$IFDEF WDC}
  ForceDirectories(ExtractFilePath(aFilePath));
  filePath := ChangeFileExt(aFilePath, IMAGE_TYPE_EXT[aImageType]);

  mkbmp := TBitmap.Create;
  try
    try
      mkbmp.Handle := CreateBitmap(aWidth, aHeight, 1, 32, @aPixelData[0]);

      case aImageType of
        itJpeg: begin
                  jpg := TJpegImage.Create;
                  try
                    jpg.Assign(mkbmp);
                    jpg.ProgressiveEncoding := True;
                    jpg.ProgressiveDisplay  := True;
                    jpg.Performance         := jpBestQuality;
                    jpg.CompressionQuality  := 90;
                    jpg.Compress;
                    jpg.SaveToFile(filePath);
                  finally
                    jpg.Free;
                  end;
                end;
        itPng:  begin
                  png := TPngImage.CreateBlank(COLOR_RGBALPHA, 16, aWidth, aHeight);
                  try
                    png.Assign(mkbmp);
                    png.SaveToFile(filePath);
                  finally
                    png.Free;
                  end;
                end;
        itBmp:  mkbmp.SaveToFile(filePath);
      end;
    except
      on E: Exception do
      begin
        gLog.AddTime('Error while saving image: ' + E.ClassName + ': ' + E.Message);

        ShowMessage('Error saving image. Try to reduce max image size or choose other image format');

        if FileExists(filePath) then
          KMDeleteFile(filePath);
      end;
    end;
  finally
    mkbmp.Free;
  end;
{$ENDIF}
end;


end.
