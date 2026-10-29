unit KM_AudioDecode;
{$I KaM_Remake.inc}
interface
uses
  SysUtils;

  procedure LoadAudioPCM16(const aFilename: UnicodeString; out aData: TBytes; out aSampleRate, aChannels: Integer);


implementation
uses
  Bass;


procedure LoadAudioPCM16(const aFilename: UnicodeString; out aData: TBytes; out aSampleRate, aChannels: Integer);
var
  stream: HSTREAM;
  info: BASS_CHANNELINFO;
  byteCount: QWord;
  bytesRead: DWORD;
  position: Integer;
begin
  // BASS supplies a maintained ARM64 decoder; the old Vorbis binding assumes
  // Windows-sized C longs and cannot safely describe macOS library structs.
  stream := BASS_StreamCreateFile(BASS_FILE_NAME, PAnsiChar(UTF8Encode(aFilename)), 0, 0, BASS_STREAM_DECODE);
  if stream = 0 then
    raise Exception.CreateFmt('Cannot decode audio %s (BASS error %d)', [aFilename, BASS_ErrorGetCode]);
  try
    if not BASS_ChannelGetInfo(stream, info) or not (info.chans in [1, 2]) then
      raise Exception.Create('Sound effects require mono or stereo PCM');
    byteCount := BASS_ChannelGetLength(stream, BASS_POS_BYTE);
    if (byteCount = 0) or (byteCount > High(Integer)) then
      raise Exception.Create('Invalid decoded sound length');
    SetLength(aData, byteCount);
    position := 0;
    while position < Length(aData) do
    begin
      bytesRead := BASS_ChannelGetData(stream, @aData[position], Length(aData) - position);
      if bytesRead = High(DWORD) then
      begin
        if BASS_ErrorGetCode = BASS_ERROR_ENDED then Break;
        raise Exception.CreateFmt('Audio decode failed (BASS error %d)', [BASS_ErrorGetCode]);
      end;
      if bytesRead = 0 then Break;
      Inc(position, bytesRead);
    end;
    if position = 0 then raise Exception.Create('Decoded sound is empty');
    SetLength(aData, position);
    aSampleRate := info.freq;
    aChannels := info.chans;
  finally
    BASS_StreamFree(stream);
  end;
end;


end.
