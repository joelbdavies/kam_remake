program KM_MacDataProbe;
{$I KaM_Remake.inc}
uses
  cthreads, Interfaces, SysUtils, Classes,
  KM_FileIO, KM_FPU, KM_IoXML, KM_IoPNG, KM_CommonTypes, KM_CommonClasses, KM_GameSavePoints;


procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then raise Exception.Create(aMessage);
end;


procedure CheckXML(const aDirectory: string);
var
  document: TKMXmlDocument;
  campaign: TKMXmlNode;
  filename: string;
begin
  filename := aDirectory + '/progress.xml';
  document := TKMXmlDocument.Create('CampaignProgress');
  try
    document.LoadFromFile(aDirectory + '/missing.xml', 'CampaignProgress');
    Check(document.Root <> nil, 'Missing settings file did not retain root');
    document.Text := '<?xml version="1.0"?><CampaignProgress>' + LineEnding
      + '<campaign id="TSK" unlockedMission="3"><mission completed="True"/></campaign>'
      + '</CampaignProgress>';
    campaign := document.Root.FindNode('campaign');
    Check(campaign <> nil, 'Campaign element missing');
    Check(campaign.Attributes['id'].AsString = 'TSK', 'Campaign ID was lost');
    Check(campaign.Attributes['unlockedMission'].AsInteger = 3, 'Mission progress was lost');
    Check(campaign.ChildsCount = 1, 'XML child enumeration includes non-elements');
    Check(campaign.Childs[0].Attributes['completed'].AsBoolean, 'Mission state was lost');
    campaign.Attributes['name'] := 'Castle & "Keep"';
    document.SaveToFile(filename);
    document.LoadFromFile(filename, 'CampaignProgress');
    document.LoadFromFile(filename, 'CampaignProgress');
    campaign := document.Root.AddOrFindChild('campaign');
    Check(document.Root.ChildsCount = 1, 'Reload duplicated the campaign root');
    Check(campaign.Attributes['name'].AsString = 'Castle & "Keep"', 'XML escaping failed');
    Check(Pos('unlockedMission="3"', document.Text) > 0, 'XML text serialization lost progress');
    campaign.Clear;
    Check((campaign.ChildsCount = 0) and not campaign.HasAttribute('id'), 'Clear left old settings');
    campaign.AddChild('new');
    Check(campaign.HasChild('new'), 'Cannot add a child after Clear');
    WriteLn('PASS: XML settings and campaign progress persist across reloads');
  finally
    document.Free;
  end;
end;


procedure CheckStreams;
var
  source, restored: TKMemoryStream;
  encoded: string;
begin
  source := TKMemoryStreamBinary.Create;
  restored := TKMemoryStreamBinary.Create;
  try
    source.LoadFromBase64('AAECA/7/');
    Check((source.Size = 6) and (PByte(source.Memory)[4] = 254), 'Base64 binary decode failed');
    Check(source.ToBase64 = 'AAECA/7/', 'Base64 encode changed binary data');
    encoded := source.ToBase64Compressed;
    restored.LoadFromBase64Compressed(encoded);
    Check((restored.Size = source.Size) and CompareMem(source.Memory, restored.Memory, source.Size),
      'Compressed campaign script data changed');
    WriteLn('PASS: binary and compressed campaign script data round-trip');
  finally
    restored.Free;
    source.Free;
  end;
end;


procedure CheckSavePoints(aCount: Integer; const aDirectory: string);
const
  TICKS: array[0..3] of Cardinal = (17999, 8999, 35999, 26999);
var
  source, restored: TKMSavePointCollection;
  payload: TKMemoryStream;
  saved, repeated: TKMemoryStreamBinary;
  I, count, cursor: Integer;
  tick, previousTick, size, lastTick: Cardinal;
  filename: string;
begin
  source := TKMSavePointCollection.Create;
  restored := TKMSavePointCollection.Create;
  saved := TKMemoryStreamBinary.Create;
  repeated := TKMemoryStreamBinary.Create;
  try
    for I := 0 to aCount - 1 do
    begin
      payload := TKMemoryStreamBinary.Create;
      payload.Write(Integer(I));
      payload.Write(TICKS[I]);
      source.NewSavePointAndFree(payload, TICKS[I], I + 10, nil);
      Check(payload = nil, 'Checkpoint did not take ownership of the save stream');
    end;
    source.LastTick := 36000;
    WriteLn('Checking ', aCount, ' replay checkpoints');
    Flush(Output);
    source.Save(saved);
    saved.Position := 0;
    saved.CheckMarker('SavePoints');
    saved.Read(lastTick);
    saved.Read(count);
    Check((count = aCount) and (lastTick = 36000), 'Checkpoint header changed');
    previousTick := 0;
    for I := 0 to aCount - 1 do
    begin
      saved.CheckMarker('SavePoint');
      saved.Read(tick);
      saved.Read(cursor);
      saved.Read(size);
      Check(tick > previousTick, 'Checkpoints were not serialized in tick order');
      Check(cursor = source[tick].Cursor, 'Checkpoint replay cursor changed');
      previousTick := tick;
      saved.Position := saved.Position + size;
    end;
    Check(saved.Position = saved.Size, 'Checkpoint data has unexpected trailing bytes');
    filename := aDirectory + '/checkpoints-' + IntToStr(aCount) + '.spt';
    source.SaveToFileAsync(filename, nil);
    restored.LoadFromFile(filename);
    Check((restored.Count = aCount) and (restored.LastTick = source.LastTick),
      'Checkpoint reload changed the count or last tick');
    for I := 0 to aCount - 1 do
    begin
      tick := TICKS[I];
      Check(restored.ContainsTick(tick), 'Checkpoint missing after reload');
      Check(restored[tick].Cursor = source[tick].Cursor, 'Reload changed the replay cursor');
      Check((restored[tick].StreamCompressed.Size = source[tick].StreamCompressed.Size) and
        CompareMem(restored[tick].StreamCompressed.Memory, source[tick].StreamCompressed.Memory,
          source[tick].StreamCompressed.Size), 'Reload changed compressed save data');
    end;
    restored.Save(repeated);
    Check((saved.Size = repeated.Size) and CompareMem(saved.Memory, repeated.Memory, saved.Size),
      'Repeated checkpoint serialization changed the bytes');
    WriteLn('PASS: ', aCount, ' replay checkpoints save, reload and retain ordered data');
  finally
    repeated.Free;
    saved.Free;
    restored.Free;
    source.Free;
  end;
end;


procedure CheckPNG(const aDirectory: string);
var
  pixels, restored: TKMCardinalArray;
  width, height: Word;
  filename: UnicodeString;
  I: Integer;
begin
  filename := UTF8Decode(aDirectory + '/rgba.png');
  pixels := TKMCardinalArray.Create($FF0000FF, $8000FF00, $00FF0000, $12345678);
  SaveToPng(2, 2, pixels, filename);
  LoadFromPng(filename, width, height, restored);
  Check((width = 2) and (height = 2) and (Length(restored) = 4), 'PNG dimensions changed');
  for I := 0 to High(pixels) do
    Check(restored[I] = pixels[I], 'PNG color or alpha changed');
  WriteLn('PASS: PNG RGBA pixels preserve transparency');
end;


procedure CheckFiles(const aDirectory: string);
var
  source, copied, moved: UnicodeString;
  readAcc, writeAcc, execAcc: Boolean;
  refusedOverwrite: Boolean;
begin
  source := UTF8Decode(aDirectory) + '/source-' + WideChar($03A9) + '.txt';
  copied := UTF8Decode(aDirectory) + '/copy.txt';
  moved := UTF8Decode(aDirectory) + '/moved.txt';
  DeleteFile(copied);
  DeleteFile(moved);
  WriteText('save payload', UTF8Encode(source), TEncoding.UTF8);
  Check(KMFileSize(UTF8Encode(source)) > 0, 'File size failed');
  KMCopyFile(source, copied);
  Check(ReadTextA(source) = ReadTextA(copied), 'Copy changed file contents');
  refusedOverwrite := False;
  try
    KMCopyFile(source, copied);
  except
    on E: EInOutError do refusedOverwrite := True;
  end;
  Check(refusedOverwrite, 'Copy silently overwrote an existing file');
  KMCopyFile(source, copied, True);
  KMRenamePath(copied, moved);
  Check(FileExists(moved) and not FileExists(copied), 'Save rename failed');
  Check(ReadTextA(source) = ReadTextA(moved), 'Save rename changed contents');
  CheckFolderPermission(aDirectory, readAcc, writeAcc, execAcc);
  Check(readAcc and writeAcc and execAcc and IsDirectoryWriteable(aDirectory), 'Permission check failed');
  WriteLn('PASS: file size, Unicode paths, copy, overwrite protection and save rename');
end;


begin
  try
    ConfigureGameFPU;
    if ParamCount <> 1 then raise Exception.Create('Provide a scratch output directory');
    ForceDirectories(ParamStr(1));
    CheckXML(ParamStr(1));
    CheckStreams;
    CheckPNG(ParamStr(1));
    CheckFiles(ParamStr(1));
    CheckSavePoints(0, ParamStr(1));
    CheckSavePoints(1, ParamStr(1));
    CheckSavePoints(2, ParamStr(1));
    CheckSavePoints(4, ParamStr(1));
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      Halt(1);
    end;
  end;
end.
