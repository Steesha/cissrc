program NativeISCC;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Native command-line compiler for Unix and Windows hosts
}

uses
  {$IFDEF UNIX}cthreads, cwstring, BaseUnix, Termio,{$ENDIF}
  {$IFDEF MSWINDOWS}Windows, PathFunc, Shared.CommonFunc,{$ENDIF}
  SysUtils, fpjson, Shared.FileClass, Shared.CompilerInt.Struct,
  Compiler.Compile, TrustFunc, ISPP.Base, ISPP.Intf, Shared.FPCStringUtils;

{$I ISCmplr.images.inc}

type
  TCompileContext = record
    Script: TTextFileReader;
    Line, ScriptFilename, LastProgress: String;
    LineNumber: Integer;
    Quiet, Preprocess, ShowProgress, Cancelled: Boolean;
  end;
  PCompileContext = ^TCompileContext;
  TStdinScriptReader = class(TTextFileReader)
  public
    function Read(var Buffer; Count: Cardinal): Cardinal; override;
  end;

var
  MessagesJsonl: Boolean;
  AbortRequested: Integer;

{$IFDEF MSWINDOWS}
var
  ConsoleReadThread, ConsoleInterrupts: Integer;

function CancelSynchronousIo(Thread: THandle): BOOL; stdcall;
  external kernel32 name 'CancelSynchronousIo';

function InterruptHandler(ControlType: DWORD): BOOL; stdcall;
const
  ErrorNotFound = 1168;
var
  ThreadID: DWORD;
  Thread: THandle;
begin
  Result := (ControlType = CTRL_C_EVENT) or (ControlType = CTRL_BREAK_EVENT);
  if not Result then
    Exit;
  InterlockedExchange(AbortRequested, 1);
  InterlockedIncrement(ConsoleInterrupts);
  try
    ThreadID := DWORD(InterlockedCompareExchange(ConsoleReadThread, 0, 0));
    if ThreadID = 0 then
      Exit;
    Thread := OpenThread(THREAD_TERMINATE, False, ThreadID);
    if Thread = 0 then
      Exit;
    try
      while InterlockedCompareExchange(ConsoleReadThread, 0, 0) <> 0 do begin
        if CancelSynchronousIo(Thread) or (GetLastError <> ErrorNotFound) then
          Break;
        { The reader may have announced the read before entering ReadFile }
        Sleep(1);
      end;
    finally
      CloseHandle(Thread);
    end;
  finally
    InterlockedDecrement(ConsoleInterrupts);
  end;
end;
{$ELSE}
procedure InterruptHandler(Signal: cint); cdecl;
begin
  InterlockedExchange(AbortRequested, 1);
end;

{$ENDIF}

function TStdinScriptReader.Read(var Buffer; Count: Cardinal): Cardinal;
{$IFDEF MSWINDOWS}
var
  Available, Mode: DWORD;
  ReadSucceeded: BOOL;
begin
  if Count = 0 then
    Exit(0);
  if GetConsoleMode(Handle, Mode) then begin
    InterlockedExchange(ConsoleReadThread, Integer(GetCurrentThreadId));
    try
      if InterlockedCompareExchange(AbortRequested, 0, 0) <> 0 then
        Abort;
      ReadSucceeded := ReadFile(Handle, Buffer, Count, DWORD(Result), nil);
      if InterlockedCompareExchange(AbortRequested, 0, 0) <> 0 then
        Abort;
      if not ReadSucceeded then
        RaiseLastError;
    finally
      InterlockedExchange(ConsoleReadThread, 0);
      { Let any handler targeting this read finish before starting other I/O }
      while InterlockedCompareExchange(ConsoleInterrupts, 0, 0) <> 0 do
        Sleep(1);
    end;
    Exit;
  end;
  if GetFileType(Handle) <> FILE_TYPE_PIPE then
    Exit(inherited Read(Buffer, Count));
  repeat
    if InterlockedCompareExchange(AbortRequested, 0, 0) <> 0 then
      Abort;
    if not PeekNamedPipe(Handle, nil, 0, nil, @Available, nil) then begin
      if GetLastError = ERROR_BROKEN_PIPE then
        Exit(0);
      RaiseLastError;
    end;
    if Available = 0 then
      Sleep(100);
  until Available <> 0;
  if Available < Count then
    Count := Available;
  Result := inherited Read(Buffer, Count);
end;
{$ELSE}
var
  Input: TPollFD;
  Ready: Integer;
begin
  Input := Default(TPollFD);
  Input.fd := Handle;
  Input.events := POLLIN;
  repeat
    if InterlockedCompareExchange(AbortRequested, 0, 0) <> 0 then
      Abort;
    { A finite wait also detects a signal delivered just before poll starts }
    Ready := fpPoll(@Input, 1, 100);
    if (Ready < 0) and (fpGetErrNo <> ESysEINTR) then
      RaiseLastError;
  until Ready > 0;
  if InterlockedCompareExchange(AbortRequested, 0, 0) <> 0 then
    Abort;
  Result := inherited Read(Buffer, Count);
end;
{$ENDIF}

procedure WriteDiagnostic(const Severity, Filename, MessageText: String; const Line: Integer = 0);
var
  Diagnostic: TJSONObject;
begin
  if MessagesJsonl then begin
    Diagnostic := TJSONObject.Create;
    try
      if Line <> 0 then
        Diagnostic.Add('line', Line);
      if Filename <> '' then
        Diagnostic.Add('filename', UTF8Encode(Filename));
      Diagnostic.Add('message', UTF8Encode(MessageText));
      Diagnostic.Add('severity', UTF8Encode(Severity));
      WriteLn(StdErr, Diagnostic.AsJSON);
    finally
      Diagnostic.Free;
    end;
  end else begin
    if Filename <> '' then
      Write(StdErr, UTF8Encode(Filename), ':');
    if Line > 0 then
      Write(StdErr, Line, ': ');
    WriteLn(StdErr, UTF8Encode(MessageText));
  end;
end;

procedure CommandLineError(const MessageText: String);
begin
  WriteDiagnostic('error', '', MessageText);
  Halt(isceInvalidParam);
end;

function GetArgument(const Index: Integer): String;
begin
  Result := {$IFDEF MSWINDOWS}NewParamStr(Index){$ELSE}ParamStr(Index){$ENDIF};
end;

function GetShortArgument(const Arg: String): String;
begin
  Result := '';
  if (Length(Arg) >= 2) and
     (((Arg[1] = '-') and (Arg[2] <> '-')) {$IFDEF MSWINDOWS}or (Arg[1] = '/'){$ENDIF}) then
    Result := Copy(Arg, 2, MaxInt);
end;

function ProgressWidth: Integer;
{$IFDEF MSWINDOWS}
var
  Info: TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), Info) then
    Result := Info.dwSize.X - 1
  else
    Result := 0;
{$ELSE}
var
  Size: TWinSize;
begin
  if IsATTY(Output) <> 1 then
    Exit(0);
  if (fpIOCtl(TextRec(Output).Handle, TIOCGWINSZ, @Size) = 0) and (Size.ws_col > 0) then
    Result := Size.ws_col - 1
  else
    Result := 79;
{$ENDIF}
end;

procedure PrintProgress(var Context: TCompileContext; const MessageText: String);
var
  Text, Current: String;
  Width: Integer;
  {$IFDEF MSWINDOWS}
  Written: DWORD;
  {$ENDIF}
begin
  Width := ProgressWidth;
  if Width < 1 then
    Exit;
  Current := Copy(Trim(MessageText), 1, Width);
  if (Current = '') or (Current = Context.LastProgress) then
    Exit;
  Text := Current;
  if Length(Text) < Length(Context.LastProgress) then
    Text := Text + UnicodeString(StringOfChar(' ', Length(Context.LastProgress) - Length(Text)));
  Text := #13 + Copy(Text, 1, Width);
  {$IFDEF MSWINDOWS}
  if not WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), PWideChar(Text), Length(Text), Written, nil) then
    Exit;
  {$ELSE}
  Write(UTF8Encode(Text));
  Flush(Output);
  {$ENDIF}
  Context.LastProgress := Current;
end;

procedure EndProgress(var Context: TCompileContext);
begin
  if Context.LastProgress <> '' then begin
    WriteLn;
    Flush(Output);
    Context.LastProgress := '';
  end;
end;

function CompilerCallback(Code: Integer; var Data: TCompilerCallbackData;
  AppData: NativeInt): Integer; stdcall;
var
  Context: PCompileContext;
  Filename, Progress: String;
begin
  Context := PCompileContext(AppData);
  if InterlockedCompareExchange(AbortRequested, 0, 0) <> 0 then begin
    if Code in [iscbReadScript, iscbNotifyStatus, iscbNotifyIdle] then begin
      Context^.Cancelled := True;
      Exit(iscrRequestAbort);
    end;
    if Code = iscbNotifyPreproc then
      Exit(iscrSuccess);
    if (Code = iscbNotifyError) and not Assigned(Data.ErrorMsg) then
      Context^.Cancelled := True;
  end;
  case Code of
    iscbReadScript:
      if not Context^.Script.Eof then begin
        Inc(Context^.LineNumber);
        Context^.Line := Context^.Script.ReadLine;
        if Pos(#0, Context^.Line) <> 0 then
          raise Exception.CreateFmt('Illegal null character on line %d', [Context^.LineNumber]);
        Data.LineRead := PChar(Context^.Line);
      end;
    iscbNotifyStatus:
      if Data.Warning then begin
        EndProgress(Context^);
        WriteDiagnostic('warning', '', Data.StatusMsg);
      end else if Context^.ShowProgress then
        PrintProgress(Context^, Data.StatusMsg)
      else if not (Context^.Quiet or Context^.Preprocess) then
        WriteLn(UTF8Encode(UnicodeString(Data.StatusMsg)));
    iscbNotifyIdle:
      if Context^.ShowProgress and (Data.CompressProgress <> 0) and (Data.CompressProgressMax <> 0) then begin
        Progress := InnoFormat('Compressing: %.2f%% done', [Data.CompressProgress / Data.CompressProgressMax * 100]);
        if Data.BytesCompressedPerSecond <> 0 then
          Progress := Progress + InnoFormat(' at %.2f kb/s', [Data.BytesCompressedPerSecond / 1024]);
        if Data.SecondsRemaining <> -1 then
          Progress := Progress + InnoFormat(', %d seconds remaining', [Data.SecondsRemaining]);
        PrintProgress(Context^, Progress);
      end;
    iscbNotifyPreproc:
      if Context^.Preprocess then
        Write(UTF8Encode(UnicodeString(Data.PreprocessedScript)));
    iscbNotifySuccess:
      if not Context^.Quiet and not Context^.Preprocess and
         Assigned(Data.OutputExeFilename) and (Data.OutputExeFilename^ <> #0) then
        WriteLn(UTF8Encode(UnicodeString(Data.OutputExeFilename)));
    iscbNotifyError:
      if Assigned(Data.ErrorMsg) then begin
        EndProgress(Context^);
        Filename := Data.ErrorFilename;
        if MessagesJsonl and not Assigned(Data.ErrorFilename) then
          Filename := Context^.ScriptFilename;
        WriteDiagnostic('error', Filename, Data.ErrorMsg, Data.ErrorLine);
      end;
  end;
  Result := iscrSuccess;
end;

procedure Usage;
begin
  WriteLn('Usage: iscc [options] script.iss');
  WriteLn('       iscc [options] -');
  WriteLn('  --compiler-path=<path>     Directory containing compiler assets');
  WriteLn('  --build-public-key=<path> Trust this ISSig public key for compiler assets');
  WriteLn('  --output=yes|no, -o+|-o-   Enable or disable installer output');
  WriteLn('  --output-dir=<path>, -o<path> Override OutputDir');
  WriteLn('  --output-filename=<name>, -f<name> Override OutputBaseFilename');
  WriteLn('  --preprocess, -e           Write preprocessed script to stdout');
  WriteLn('  --define=<name>[=<value>], -d<definition>  Define an ISPP macro');
  WriteLn('  --include-dirs=<paths>, -i<paths>          Add ISPP include directories');
  WriteLn('  --include=<file>, -j<file>                 Preinclude an ISPP file');
  WriteLn('  --inline-start=<text>, -{#<text>          Set the ISPP opening delimiter');
  WriteLn('  --inline-end=<text>, -}<text>              Set the ISPP closing delimiter');
  WriteLn('  --verbose=<number>, -v<number>            Set the ISPP verbose level');
  WriteLn('  -$<letter>+|-                              Set an ISPP option');
  WriteLn('  -p<letter>+|-                              Set an ISPP parser option');
  WriteLn('  --no-compression, -nc     Disable compression');
  WriteLn('  --signtool=<name>=<command>, -s<name>=<command> Register a signing command');
  WriteLn('  --no-signing, -ns         Disable signing');
  WriteLn('  --no-signcheck, -nsc       Skip signcheck on source files');
  WriteLn('  --quiet, -q               Suppress status messages');
  WriteLn('  --quiet-progress, -qp     Display progress on an interactive terminal');
  WriteLn('  --messages-jsonl, -mj     Write errors and warnings as JSONL to stderr');
  WriteLn('  --version                 Print the compiler version');
end;

function Run: Integer;
var
  Context: TCompileContext;
  Params: TCompileScriptParamsEx;
  Arg, ShortArg, CompilerPath, Options, ScriptName, SourcePath: String;
  I, ArgumentCount: Integer;
  BuildPublicKey, Definitions, IncludeDirs, IncludeFiles, Value, AssetPath: String;
  PreprocessorOptions, ParserOptions: TOptions;
  {$IFDEF MSWINDOWS}
  HandlerInstalled: Boolean;
  {$ELSE}
  Action, PreviousAction: SigActionRec;
  HandlerInstalled: Boolean;
  {$ENDIF}

  procedure AddOption(const Option: String);
  begin
    Options := Options + Option + #0;
  end;

  procedure RejectSinglePrefixLongOption;
  const
    LongOptions: array[0..11] of String = ('output', 'output-dir', 'output-filename',
      'signtool', 'define', 'include-dirs', 'include', 'inline-start', 'inline-end', 'verbose',
      'build-public-key', 'compiler-path');
  var
    Name, OptionName: String;
    EqualsPosition: Integer;
  begin
    EqualsPosition := Pos('=', ShortArg);
    if EqualsPosition = 0 then
      Exit;
    Name := LowerCase(Copy(ShortArg, 1, EqualsPosition - 1));
    for OptionName in LongOptions do
      if Name = OptionName then
        CommandLineError('Invalid option: ' + Arg + ' (did you mean --' +
          Name + Copy(ShortArg, EqualsPosition, MaxInt) + '?)');
  end;

  function GetOptionValue(const LongName, ShortName: String): Boolean;
  var
    Prefix: String;
  begin
    Prefix := '--' + LongName + '=';
    if Pos(Prefix, Arg) = 1 then
      Value := Copy(Arg, Length(Prefix) + 1, MaxInt)
    else if (ShortArg <> '') and
       (InnoCompareText(Copy(ShortArg, 1, Length(ShortName)), ShortName) = 0) then
      Value := Copy(ShortArg, Length(ShortName) + 1, MaxInt)
    else
      Exit(False);
    Result := True;
  end;

  function GetISPPArgument(const LongName, ShortName: String): Boolean;
  begin
    Result := GetOptionValue(LongName, ShortName);
    if Result and ((Value = '') or (Pos(#1, Value) <> 0)) then
      CommandLineError('Invalid ISPP argument: ' + Arg);
  end;

  function HasFlag(const LongName, ShortName: String): Boolean;
  begin
    Result := (Arg = '--' + LongName) or
      ((ShortName <> '') and (InnoCompareText(ShortArg, ShortName) = 0));
  end;

  procedure SetISPPOption(var Target: TOptions);
  begin
    if (Length(Arg) <> 4) or not (UpCase(Arg[3]) in ['A'..'Z']) or
       not (Arg[4] in ['+', '-']) then
      CommandLineError('Invalid ISPP option: ' + Arg);
    SetOption(Target, Arg[3], Arg[4] = '+');
  end;

  function EncodeOptions(const Target: TOptions): String;
  var
    Index: TOptionID;
  begin
    Result := '';
    for Index := 0 to 25 do
      if Index in Target then
        Result := Result + WideChar(Ord('a') + Index);
  end;

begin
  Options := '';
  BuildPublicKey := '';
  IncludeDirs := '';
  IncludeFiles := '';
  ScriptName := '';
  Context := Default(TCompileContext);
  Params := Default(TCompileScriptParamsEx);
  Definitions := 'ISCC_INVOKED'#1'ISPPCC_INVOKED'#1 {$IFDEF UNIX}+'__UNIX__'#1{$ENDIF};
  PreprocessorOptions := [];
  SetOption(PreprocessorOptions, 'C', True);
  SetOption(PreprocessorOptions, 'E', True);
  ParserOptions := [];
  SetOption(ParserOptions, 'B', True);
  SetOption(ParserOptions, 'P', True);
  ArgumentCount := {$IFDEF MSWINDOWS}NewParamCount{$ELSE}ParamCount{$ENDIF};
  for I := 1 to ArgumentCount do begin
    Arg := GetArgument(I);
    ShortArg := GetShortArgument(Arg);
    if HasFlag('messages-jsonl', 'mj') then begin
      MessagesJsonl := True;
      SetTextCodePage(StdErr, CP_UTF8);
      Break;
    end;
  end;
  for I := 1 to ArgumentCount do begin
    Arg := GetArgument(I);
    ShortArg := GetShortArgument(Arg);
    RejectSinglePrefixLongOption;
    if HasFlag('messages-jsonl', 'mj') then
      Continue;
    if HasFlag('help', '?') or HasFlag('help', 'h') then begin
      Usage;
      Exit(0);
    end else if HasFlag('version', '') then begin
      WriteLn(UTF8Encode(String(ISGetVersion^.Version)));
      Exit(0);
    end else if HasFlag('quiet', 'q') then
      Context.Quiet := True
    else if HasFlag('quiet-progress', 'qp') then begin
      Context.Quiet := True;
      Context.ShowProgress := True;
    end else if HasFlag('no-compression', 'nc') then
      AddOption('NoCompression=yes')
    else if GetOptionValue('signtool', 's') then begin
      if (Pos('=', Value) <= 1) or (Pos('=', Value) = Length(Value)) then
        CommandLineError('Expected --signtool=<name>=<command>');
      AddOption('SignTool-' + Value);
    end else if HasFlag('no-signing', 'ns') then
      AddOption('NoSigning=yes')
    else if HasFlag('no-signcheck', 'nsc') then
      AddOption('NoSignCheck=yes')
    else if HasFlag('no-ide-signtools', 'ni') then begin
      { The native compiler uses explicitly supplied signing commands }
    end else if HasFlag('preprocess', 'e') then begin
      Context.Preprocess := True;
      AddOption('PreprocessOnly=yes');
    end else if HasFlag('output=yes', 'o+') then
      AddOption('Output=yes')
    else if HasFlag('output=no', 'o-') then
      AddOption('Output=no')
    else if GetOptionValue('output-dir', 'o') then
      AddOption('OutputDir=' + Value)
    else if GetOptionValue('output-filename', 'f') then
      AddOption('OutputBaseFilename=' + Value)
    else if Pos('--build-public-key=', Arg) = 1 then begin
      if BuildPublicKey <> '' then
        CommandLineError('Specify --build-public-key only once');
      BuildPublicKey := Copy(Arg, Length('--build-public-key=') + 1, MaxInt);
      if BuildPublicKey = '' then
        CommandLineError('Expected a path for --build-public-key');
    end else if Pos('--compiler-path=', Arg) = 1 then
      CompilerPath := Copy(Arg, Length('--compiler-path=') + 1, MaxInt)
    else if GetISPPArgument('define', 'D') then
      Definitions := Definitions + Value + #1
    else if GetISPPArgument('include-dirs', 'I') then
      IncludeDirs := IncludeDirs + ';' + Value
    else if GetISPPArgument('include', 'J') then
      IncludeFiles := IncludeFiles + Value + #1
    else if GetOptionValue('inline-start', '{#') then begin
      if Value <> '' then
        AddOption('ISPP:InlineStart=' + Value);
    end else if GetOptionValue('inline-end', '}') then begin
      if Value <> '' then
        AddOption('ISPP:InlineEnd=' + Value);
    end else if GetOptionValue('verbose', 'v') then begin
      if Value <> '' then
        AddOption('ISPP:VerboseLevel=' + Value);
    end else if Pos('$', ShortArg) = 1 then
      SetISPPOption(PreprocessorOptions)
    else if (ShortArg <> '') and (UpCase(ShortArg[1]) = 'P') then
      SetISPPOption(ParserOptions)
    else if (Arg = '-') or ((Arg <> '') and (Arg[1] <> '-') and (ShortArg = '')) then begin
      if ScriptName <> '' then
        CommandLineError('You may not specify more than one script filename.');
      ScriptName := Arg;
    end else
      CommandLineError('Invalid argument: ' + Arg);
  end;
  if ScriptName = '' then begin
    if MessagesJsonl then
      WriteDiagnostic('error', '', 'No script filename specified.')
    else
      Usage;
    Exit(isceInvalidParam);
  end;

  Context.ShowProgress := Context.ShowProgress and not Context.Preprocess and (ProgressWidth > 0);
  if BuildPublicKey <> '' then
    LoadBuildPublicKey(BuildPublicKey);

  if ScriptName = '-' then begin
    Context.ScriptFilename := '<stdin>';
    {$IFDEF MSWINDOWS}
    SourcePath := PathExpand('.');
    Context.Script := TStdinScriptReader.CreateWithExistingHandle(GetStdHandle(STD_INPUT_HANDLE));
    {$ELSE}
    SourcePath := UTF8Decode(GetCurrentDir);
    Context.Script := TStdinScriptReader.CreateWithExistingHandle(0);
    {$ENDIF}
    Context.Script.CodePage := 65001;
  end else begin
    {$IFDEF MSWINDOWS}
    ScriptName := PathExpand(ScriptName);
    SourcePath := PathExtractPath(ScriptName);
    {$ELSE}
    ScriptName := UTF8Decode(ExpandFileName(UTF8Encode(ScriptName)));
    SourcePath := UTF8Decode(ExtractFilePath(UTF8Encode(ScriptName)));
    {$ENDIF}
    Context.ScriptFilename := ScriptName;
    try
      Context.Script := TTextFileReader.Create(ScriptName, fdOpenExisting, faRead, fsRead);
    except
      on E: Exception do begin
        WriteDiagnostic('error', Context.ScriptFilename, String(E.Message));
        Exit(isceCompileFailure);
      end;
    end;
  end;
  try
    Params.Size := SizeOf(Params);
    Params.SourcePath := PChar(SourcePath);
    if CompilerPath <> '' then
      Params.CompilerPath := PChar(CompilerPath);
    Params.CallbackProc := @CompilerCallback;
    Params.AppData := NativeInt(@Context);
    AddOption('ISPP:Definitions=' + Definitions);
    AddOption('ISPP:Options=' + EncodeOptions(PreprocessorOptions));
    AddOption('ISPP:ParserOptions=' + EncodeOptions(ParserOptions));
    if IncludeDirs <> '' then begin
      AssetPath := CompilerPath;
      if AssetPath = '' then
        AssetPath := {$IFDEF MSWINDOWS}PathExtractDir(NewParamStr(0)){$ELSE}
          ExtractFileDir(ExpandFileName(ParamStr(0))){$ENDIF};
      AddOption('ISPP:IncludePath=' + AssetPath + IncludeDirs);
    end;
    if IncludeFiles <> '' then
      AddOption('ISPP:IncludeFiles=' + IncludeFiles);
    Params.Options := PChar(Options);
    if ScriptName = '-' then
      ScriptName := '';
    {$IFDEF MSWINDOWS}
    HandlerInstalled := SetConsoleCtrlHandler(@InterruptHandler, True);
    {$ELSE}
    Action := Default(SigActionRec);
    Action.sa_handler := SigActionHandler(@InterruptHandler);
    fpSigEmptySet(Action.sa_mask);
    Action.sa_flags := SA_RESTART;
    HandlerInstalled := fpSigAction(SIGINT, @Action, @PreviousAction) = 0;
    {$ENDIF}
    try
      Result := ISCompileScript(Params, False, ScriptName);
      if Context.Cancelled and (Result = isceCompileFailure) then begin
        EndProgress(Context);
        WriteDiagnostic('error', Context.ScriptFilename, 'Compilation cancelled.');
      end;
    finally
      if HandlerInstalled then
        {$IFDEF MSWINDOWS}
        SetConsoleCtrlHandler(@InterruptHandler, False);
        {$ELSE}
        fpSigAction(SIGINT, @PreviousAction, nil);
        {$ENDIF}
    end;
  finally
    EndProgress(Context);
    Context.Script.Free;
  end;
end;

begin
  {$IFDEF MSWINDOWS}
  { FPC's RTL exceptions and string containers use AnsiString internally }
  SetMultiByteConversionCodePage(CP_UTF8);
  {$ENDIF}
  try
    ExitCode := Run;
  except
    on E: Exception do begin
      WriteDiagnostic('error', '', String(E.Message));
      ExitCode := isceCompileFailure;
    end;
  end;
end.
