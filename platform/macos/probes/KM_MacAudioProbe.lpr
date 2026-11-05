program AudioProbe;
{$I KaM_Remake.inc}
uses
  cthreads, SysUtils, Math, Bass, OpenAL, KM_FPU, KM_AudioDecode;


procedure CheckStream(const aFilename: string);
var
  stream: HSTREAM;
  position: QWord;
begin
  stream := BASS_StreamCreateFile(BASS_FILE_NAME, PChar(aFilename), 0, 0, 0);
  if stream = 0 then
    raise Exception.CreateFmt('Cannot open %s: BASS error %d', [aFilename, BASS_ErrorGetCode]);
  try
    BASS_ChannelSetAttribute(stream, BASS_ATTRIB_VOL, 0.12);
    if not BASS_ChannelPlay(stream, False) then
      raise Exception.CreateFmt('Cannot play stream: BASS error %d', [BASS_ErrorGetCode]);
    Sleep(400);
    position := BASS_ChannelGetPosition(stream, BASS_POS_BYTE);
    if (position = 0) or (position = High(QWord)) then
      raise Exception.Create('Audio playback did not advance');
    WriteLn('PASS: BASS playback advanced ', position, ' bytes: ', ExtractFileName(aFilename));
    Flush(Output);
  finally
    BASS_StreamFree(stream);
  end;
end;


procedure CheckDecoder(const aFilename: string);
var
  data: TBytes;
  sampleRate, channels: Integer;
begin
  LoadAudioPCM16(UTF8Decode(aFilename), data, sampleRate, channels);
  if (Length(data) = 0) or (sampleRate <= 0) or not (channels in [1, 2]) then
    raise Exception.Create('Native sound decoding returned invalid PCM');
  WriteLn('PASS: OGG decoded ', Length(data), ' bytes at ', sampleRate, ' Hz, ', channels, ' channels');
end;


procedure CheckEffects;
var
  device: TALCdevice;
  context: TALCcontext;
  buffer, source: TALuint;
  state: TALint;
  samples: array [0..4409] of SmallInt;
  I: Integer;
begin
  if not InitOpenAL then raise Exception.Create('Cannot load native OpenAL');
  device := alcOpenDevice(nil);
  if device = nil then raise Exception.Create('Cannot open OpenAL output');
  try
    context := alcCreateContext(device, nil);
    if context = nil then raise Exception.Create('Cannot create OpenAL context');
    try
      if alcMakeContextCurrent(context) = 0 then raise Exception.Create('Cannot activate OpenAL context');
      for I := Low(samples) to High(samples) do
        samples[I] := Round(8000 * Sin(2 * Pi * 220 * I / 22050));
      alGenBuffers(1, @buffer);
      alGenSources(1, @source);
      try
        alBufferData(buffer, AL_FORMAT_MONO16, @samples[0], SizeOf(samples), 22050);
        alSourcei(source, AL_BUFFER, buffer);
        alSourcef(source, AL_GAIN, 0.08);
        alSourcePlay(source);
        Sleep(80);
        alGetSourcei(source, AL_SOURCE_STATE, @state);
        if (alGetError <> AL_NO_ERROR) or (state <> AL_PLAYING) then
          raise Exception.Create('OpenAL source did not start');
        Sleep(200);
        alGetSourcei(source, AL_SOURCE_STATE, @state);
        if state <> AL_STOPPED then raise Exception.Create('OpenAL source did not finish');
        WriteLn('PASS: OpenAL sample started and completed');
      finally
        alDeleteSources(1, @source);
        alDeleteBuffers(1, @buffer);
      end;
    finally
      alcMakeContextCurrent(nil);
      alcDestroyContext(context);
    end;
  finally
    alcCloseDevice(device);
  end;
end;


begin
  try
    ConfigureGameFPU;
    WriteLn('Initializing native audio');
    Flush(Output);
    if not (ParamCount in [2, 3]) then raise Exception.Create('Provide music, campaign narration, and optionally an OGG file');
    if not BASS_Init(-1, 44100, 0, nil, nil) then
      raise Exception.CreateFmt('Cannot initialize BASS: error %d', [BASS_ErrorGetCode]);
    try
      CheckStream(ParamStr(1));
      CheckStream(ParamStr(2));
      CheckEffects;
      if ParamCount = 3 then CheckDecoder(ParamStr(3));
    finally
      BASS_Free;
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
