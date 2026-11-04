program ISSigTool;

{$IFDEF FPC}{$MODESWITCH NESTEDPROCVARS}{$ENDIF}

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  "issigtool" utility
}

uses
  {$IFDEF MSWINDOWS}
  SafeDLLPath in '..\Components\SafeDLLPath.pas',
  {$ELSE}
  cwstring,
  {$ENDIF}
  SysUtils,
  Classes,
  {$IFDEF MSWINDOWS}Windows,{$ELSE}BaseUnix,{$ENDIF}
  PathFunc in '..\Components\PathFunc.pas',
  SHA256 in '..\Components\SHA256.pas',
  ECDSA in '..\Components\ECDSA.pas',
  StringScanner in '..\Components\StringScanner.pas',
  ISSigFunc in '..\Components\ISSigFunc.pas',
  {$IFDEF MSWINDOWS}Shared.CommonFunc in 'Src\Shared.CommonFunc.pas',{$ENDIF}
  Shared.FileClass in 'Src\Shared.FileClass.pas',
  UnsignedFunc in '..\Components\UnsignedFunc.pas', Shared.FPCStringUtils;

{$IFDEF MSWINDOWS}
{$APPTYPE CONSOLE}
{$SETPEOSVERSION 6.1}
{$SETPESUBSYSVERSION 6.1}
{$WEAKLINKRTTI ON}

{$IFDEF INNO_SOURCE_RESOURCES}
{$I ConsoleApp.manifest.inc}
{$ELSE}
{$R Res\ConsoleApp.manifest.res}
{$ENDIF}
{$IFNDEF FPC}{$R Res\ISSigTool.versionandicon.res}{$ENDIF}
{$ENDIF}

var
  Options: record
    KeyFile: String;
    AllowOverwrite, Quiet: Boolean;
  end;

  {$IFDEF MSWINDOWS}
  StdOutHandle, StdErrHandle: THandle;
  StdOutHandleIsConsole, StdErrHandleIsConsole: Boolean;
  Mode: DWORD;
  {$ENDIF}

function ToolFileExists(const Name: String): Boolean;
begin
  Result := {$IFDEF MSWINDOWS}NewFileExists(Name){$ELSE}FileExists(UTF8Encode(Name)){$ENDIF};
end;

function ToolExtractName(const Name: String): String;
begin
  Result := {$IFDEF MSWINDOWS}PathExtractName(Name){$ELSE}UTF8Decode(ExtractFileName(UTF8Encode(Name))){$ENDIF};
end;

procedure RaiseFatalError(const Msg: String);
begin
  raise Exception.Create({$IFDEF FPC}UTF8Encode(Msg){$ELSE}Msg{$ENDIF});
end;

procedure RaiseFatalErrorFmt(const Msg: String; const Args: array of const);
begin
  {$IFDEF FPC}
  RaiseFatalError(UnicodeFormat(Msg, Args));
  {$ELSE}
  raise Exception.CreateFmt(Msg, Args);
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
procedure Print(const Handle: THandle; const HandleIsConsole: Boolean;
  S: String; const IncludeNewLine: Boolean); overload;
var
  CharsWritten: DWORD;
  Utf8S: UTF8String;
  BytesWritten: DWORD;
begin
  if IncludeNewLine then
    S := S + #13#10;

  if HandleIsConsole then begin

    WriteConsole(Handle, @S[1], ULength(S), CharsWritten, nil);
  end else begin
    Utf8S := Utf8Encode(S);

    WriteFile(Handle, Utf8S[1], ULength(Utf8S), BytesWritten, nil);
  end;
end;

{$ENDIF}

procedure Print(const S: String; const IncludeNewLine: Boolean = True); overload;
begin
  {$IFDEF MSWINDOWS}
  Print(StdOutHandle, StdOutHandleIsConsole, S, IncludeNewLine);
  {$ELSE}
  if IncludeNewLine then
    WriteLn(Output, UTF8Encode(S))
  else
    Write(Output, UTF8Encode(S));
  {$ENDIF}
end;

procedure PrintErrOutput(const S: String; const IncludeNewLine: Boolean = True); overload;
begin
  {$IFDEF MSWINDOWS}
  Print(StdErrHandle, StdErrHandleIsConsole, S, IncludeNewLine);
  {$ELSE}
  if IncludeNewLine then
    WriteLn(StdErr, UTF8Encode(S))
  else
    Write(StdErr, UTF8Encode(S));
  {$ENDIF}
end;

procedure PrintUnlessQuiet(const S: String;
  const IncludeNewLine: Boolean = True);
begin
  if not Options.Quiet then
    Print(S, IncludeNewLine);
end;

procedure PrintFmtUnlessQuiet(const S: String; const Args: array of const;
  const IncludeNewLine: Boolean = True);
begin
  if not Options.Quiet then
    Print({$IFDEF FPC}UnicodeFormat{$ELSE}Format{$ENDIF}(S, Args), IncludeNewLine);
end;

function CalcFileHash(const AFile: TFile): TSHA256Digest;
var
  Buf: array[0..$FFFF] of Byte;
  Context: TSHA256Context;
  BytesRead: Cardinal;
begin

  SHA256Init(Context);
  while True do begin
    BytesRead := AFile.Read(Buf, SizeOf(Buf));
    if BytesRead = 0 then
      Break;
    SHA256Update(Context, Buf, BytesRead);
  end;
  Result := SHA256Final(Context);
end;

procedure ImportKey(const AKey: TECDSAKey; const ANeedPrivateKey: Boolean);
var
  KeyText: String;
  ImportResult: TISSigImportKeyResult;
begin

  try
    KeyText := ISSigLoadTextFromFile(Options.KeyFile);
    ImportResult := ISSigImportKeyText(AKey, KeyText, ANeedPrivateKey);
    if ImportResult <> ikrSuccess then begin
      case ImportResult of
        ikrMalformed:
          RaiseFatalError('Key file is malformed');
        ikrNotPrivateKey:
          RaiseFatalError('Key file must be a private key when signing');
      end;
      RaiseFatalError('Unknown import key result');
    end;
  finally
    ISSigWipeString(KeyText);
  end;
end;

procedure CommandExportPublicKey(const AFilename: String);
var
  Key: TECDSAKey;
  PublicKeyText: String;
  ExistingText: String;
begin
  Key := TECDSAKey.Create;
  try
    ImportKey(Key, False);

    ISSigExportPublicKeyText(Key, PublicKeyText);

    if ToolFileExists(AFilename) then begin

      try
        ExistingText := ISSigLoadTextFromFile(AFilename);
        if ExistingText = PublicKeyText then begin
          PrintFmtUnlessQuiet('%s: ', [AFilename], False);
          PrintUnlessQuiet('public key unchanged');
          Exit;
        end else if not Options.AllowOverwrite then
          RaiseFatalError('File already exists');
      finally
        { Just in case the existing file is a private key file }
        ISSigWipeString(ExistingText);
      end;
    end;

    ISSigSaveTextToFile(AFilename, PublicKeyText);
    PrintFmtUnlessQuiet('%s: ', [AFilename], False);
    PrintUnlessQuiet('public key written');
  finally
    Key.Free;
  end;
end;

{$IFNDEF MSWINDOWS}
function MakePrivateTempFile(const Template: PAnsiChar): Integer; cdecl; external 'c' name 'mkstemp';

procedure SavePrivateKey(const Filename, KeyText: String);
var
  Path, TempName, Bytes: UTF8String;
  Handle: Integer;
  Stream: THandleStream;
begin
  Path := UTF8Encode(Filename);
  TempName := ToNativeText(FromNativeText(Path) + '.XXXXXX');
  UniqueString(TempName);
  Handle := MakePrivateTempFile(PAnsiChar(TempName));
  if Handle = -1 then
    RaiseLastOSError(fpGetErrno);
  try
    try
      Bytes := UTF8Encode(KeyText);
      try
        Stream := THandleStream.Create(Handle);
        try
          Stream.WriteBuffer(Bytes[1], Length(Bytes));
        finally
          Stream.Free;
        end;
      finally
        if Length(Bytes) <> 0 then
          FillChar(Bytes[1], Length(Bytes), 0);
      end;
    finally
      if fpClose(Handle) <> 0 then
        RaiseLastOSError(fpGetErrno);
    end;
    if Options.AllowOverwrite then begin
      if fpRename(PAnsiChar(TempName), PAnsiChar(Path)) <> 0 then
        RaiseLastOSError(fpGetErrno);
    end else if fpLink(PAnsiChar(TempName), PAnsiChar(Path)) <> 0 then
      RaiseLastOSError(fpGetErrno);
  finally
    fpUnlink(PAnsiChar(TempName));
  end;
end;
{$ENDIF}

procedure CommandGeneratePrivateKey;
var
  Key: TECDSAKey;
  PrivateKeyText: String;
begin
  if not Options.AllowOverwrite and ToolFileExists(Options.KeyFile) then
    RaiseFatalError('File already exists');

  PrintFmtUnlessQuiet('%s: ', [Options.KeyFile], False);

  Key := TECDSAKey.Create;
  try
    Key.GenerateKeyPair;

    try
      ISSigExportPrivateKeyText(Key, PrivateKeyText);
      {$IFDEF MSWINDOWS}ISSigSaveTextToFile{$ELSE}SavePrivateKey{$ENDIF}(Options.KeyFile, PrivateKeyText);
      PrintUnlessQuiet('private key written');
    finally
      ISSigWipeString(PrivateKeyText);
    end;
  finally
    Key.Free;
  end;
end;

procedure SignSingleFile(const AKey: TECDSAKey; const AFilename: String);
var
  FileName: String;
  FileSize: Int64;
  FileHash: TSHA256Digest;
  F: TFile;
  ExistingFileName: String;
  ExistingFileSize: Int64;
  ExistingFileHash: TSHA256Digest;
  SigText: String;
  Verified: Boolean;
begin
  PrintFmtUnlessQuiet('%s: ', [AFilename], False);

  FileName := ToolExtractName(AFilename);

  F := TFile.Create(AFilename, fdOpenExisting, faRead, fsRead);
  try
    FileSize := F.Size;
    FileHash := CalcFileHash(F);
  finally
    F.Free;
  end;

  { ECDSA signature output is non-deterministic: signing the same hash with
    the same key produces a totally different signature each time. To avoid
    unnecessary alterations to the "sig-r" and "sig-s" values when a file is
    being re-signed but its contents haven't changed, we attempt to load and
    verify the existing .issig file. If the existing values exactly match
    what we would have written, then we skip creation of a new .issig file.
    Note that "file-name" is compared case-sensitively here because we don't
    want to impede the user's ability to correct case mistakes. }

  Verified := ISSigVerifySignature(AFilename, [AKey],
    ExistingFileName, ExistingFileSize, ExistingFileHash, nil, nil, nil);

  if Verified and (FileName = ExistingFileName) and (FileSize = ExistingFileSize) and
     SHA256DigestsEqual(FileHash, ExistingFileHash) then begin
    PrintUnlessQuiet('signature unchanged');
    Exit;
  end;

  SigText := ISSigCreateSignatureText(AKey, FileName, FileSize, FileHash);
  ISSigSaveTextToFile(AFilename + ISSigExt, SigText);
  PrintUnlessQuiet('signature written');
end;

procedure CommandSign(const AFilenames: TStringList);
var
  Key: TECDSAKey;
  CurFilename: {$IFDEF MSWINDOWS}String{$ELSE}AnsiString{$ENDIF};
begin
  Key := TECDSAKey.Create;
  try
    ImportKey(Key, True);

    for CurFilename in AFilenames do
      SignSingleFile(Key, {$IFDEF MSWINDOWS}CurFilename{$ELSE}UTF8Decode(CurFilename){$ENDIF});
  finally
    Key.Free;
  end;
end;

function VerifySingleFile(const AKey: TECDSAKey; const AFilename: String): Boolean;
var
  ExpectedFileName: String;
  ExpectedFileSize: Int64;
  ExpectedFileHash: TSHA256Digest;
  F: TFile;
  ActualFileHash: TSHA256Digest;
  procedure ReportMissingFile(const Filename: String);
  begin
    PrintUnlessQuiet('MISSINGFILE (File does not exist)');
  end;

  procedure ReportMissingSignature(const Filename, SigFilename: String);
  begin
    PrintUnlessQuiet('MISSINGSIGFILE (Signature file does not exist)');
  end;

  procedure ReportBadSignature(const Filename, SigFilename: String; const VerifyResult: TISSigVerifySignatureResult);
  begin
    case VerifyResult of
      vsrMalformed, vsrBad:
        PrintUnlessQuiet('BADSIGFILE (Signature file is not valid)');
      vsrKeyNotFound:
        PrintUnlessQuiet('UNKNOWNKEY (Incorrect key ID)');
    else
      RaiseFatalError('Unknown verify result');
    end;
  end;
begin
  Result := False;
  PrintFmtUnlessQuiet('%s: ', [AFilename], False);

  if not ISSigVerifySignature(AFilename, [AKey], ExpectedFileName, ExpectedFileSize, ExpectedFileHash,
    ReportMissingFile, ReportMissingSignature, ReportBadSignature
  ) then
    Exit;

  if (ExpectedFileName <> '') and
     not {$IFDEF MSWINDOWS}PathSame{$ELSE}UnicodeSameText{$ENDIF}(ToolExtractName(AFilename), ExpectedFileName) then begin
    PrintUnlessQuiet('WRONGNAME (File name is incorrect)');
    Exit;
  end;

  F := TFile.Create(AFilename, fdOpenExisting, faRead, fsRead);
  try
    if F.Size <> ExpectedFileSize then begin
      PrintUnlessQuiet('WRONGSIZE (File size is incorrect)');
      Exit;
    end;
    ActualFileHash := CalcFileHash(F);
    if not SHA256DigestsEqual(ActualFileHash, ExpectedFileHash) then begin
      PrintUnlessQuiet('WRONGHASH (File hash is incorrect)');
      Exit;
    end;
  finally
    F.Free;
  end;

  PrintUnlessQuiet('OK');
  Result := True;
end;

function CommandVerify(const AFilenames: TStringList): Boolean;
var
  Key: TECDSAKey;
  CurFilename: {$IFDEF MSWINDOWS}String{$ELSE}AnsiString{$ENDIF};
begin
  Key := TECDSAKey.Create;
  try
    ImportKey(Key, False);

    Result := True;
    for CurFilename in AFilenames do
      if not VerifySingleFile(Key, {$IFDEF MSWINDOWS}CurFilename{$ELSE}UTF8Decode(CurFilename){$ENDIF}) then
        Result := False;
  finally
    Key.Free;
  end;
end;

procedure ShowUsage;
begin
  PrintErrOutput('Inno Setup Signature Tool');
  PrintErrOutput('Copyright (C) 1997-2026 Jordan Russell. All rights reserved.');
  PrintErrOutput('Portions Copyright (C) 2000-2026 Martijn Laan. All rights reserved.');
  PrintErrOutput('https://www.innosetup.com');
  PrintErrOutput('');
  PrintErrOutput('Usage:  issigtool [options] sign <filenames>');
  PrintErrOutput('or to verify:  issigtool [options] verify <filenames>');
  PrintErrOutput('or to export the public key:  issigtool [options] export-public-key <filename>');
  PrintErrOutput('or to generate a new private key:  issigtool [options] generate-private-key');
  PrintErrOutput('Options:');
  PrintErrOutput('  --key-file=<filename> Specifies the private key filename (overrides ISSIGTOOL_KEY_FILE environment variable)');
  PrintErrOutput('  --allow-overwrite, -o Allow to overwrite existing files');
  PrintErrOutput('  --quiet, -q           Suppresses status messages that are normally printed to standard output');
  PrintErrOutput('  --help, -?            Prints this information');
  PrintErrOutput('');
end;

procedure Go;
var
  ArgList: TStringList;
  InitialArgListCount: Integer;
  J: Integer;
  S: String;
  Command: String;
  I: Integer;
begin
  ArgList := TStringList.Create;
  try
    {$IFDEF MSWINDOWS}
    for I := 1 to NewParamCount do
      ArgList.Add(NewParamStr(I));
    {$ELSE}
    for I := 1 to ParamCount do
      ArgList.Add(ToNativeText(ParamStr(I)));
    {$ENDIF}

    InitialArgListCount := ArgList.Count;
    J := 0;
    while J < ArgList.Count do begin
      S := {$IFDEF MSWINDOWS}ArgList[J]{$ELSE}UTF8Decode(ArgList[J]){$ENDIF};
      if (Length(S) > 0) and (S[1] = '-') then begin
        if (S = '--help') or (S = '-?') then begin
          ShowUsage;
          if InitialArgListCount <> 1 then
            RaiseFatalErrorFmt('"%s" option cannot be combined with other arguments', [S]);
          Exit;
        end else if (S = '--allow-overwrite') or (S = '-o') then begin
          Options.AllowOverwrite := True;
        end else if (S = '--quiet') or (S = '-q') then begin
          Options.Quiet := True;
        end else if Pos('--key-file=', S) = 1 then begin
          Options.KeyFile := Copy(S, Length('--key-file=') + 1, MaxInt);
          if Options.KeyFile = '' then
            RaiseFatalErrorFmt('"%s" option requires a value', [S]);
        end else
          RaiseFatalErrorFmt('Unknown option "%s"', [S]);
        ArgList.Delete(J);
      end else begin
        if S = '' then
          RaiseFatalError('Empty arguments not allowed');
        Inc(J);
      end;
    end;

    if ArgList.Count = 0 then begin
      ShowUsage;
      RaiseFatalError('Missing command argument');
    end;
    Command := {$IFDEF MSWINDOWS}ArgList[0]{$ELSE}UTF8Decode(ArgList[0]){$ENDIF};
    ArgList.Delete(0);

    if Options.KeyFile = '' then begin
      Options.KeyFile := {$IFDEF MSWINDOWS}GetEnv('ISSIGTOOL_KEY_FILE'){$ELSE}GetEnvironmentVariable('ISSIGTOOL_KEY_FILE'){$ENDIF};
      if Options.KeyFile = '' then
        RaiseFatalError('"--key-file=" option must be specified, ' +
          'or set the ISSIGTOOL_KEY_FILE environment variable');
    end;

    if Command = 'export-public-key' then begin
      if ArgList.Count = 0 then
        RaiseFatalError('Missing filename argument')
      else if ArgList.Count <> 1 then
        RaiseFatalError('Too many arguments');
      CommandExportPublicKey({$IFDEF MSWINDOWS}ArgList[0]{$ELSE}UTF8Decode(ArgList[0]){$ENDIF});
    end else if Command = 'generate-private-key' then begin
      if ArgList.Count <> 0 then
        RaiseFatalError('Too many arguments');
      CommandGeneratePrivateKey;
    end else if Command = 'sign' then begin
      if ArgList.Count = 0 then
        RaiseFatalError('Missing filename argument(s)');
      CommandSign(ArgList);
    end else if Command = 'verify' then begin
      if ArgList.Count = 0 then
        RaiseFatalError('Missing filename argument(s)');
      if not CommandVerify(ArgList) then
        Halt(1);
    end else
      RaiseFatalErrorFmt('Unknown command "%s"', [Command]);
  finally
    ArgList.Free;
  end;
end;

begin
  {$IF Defined(DEBUG) and not Defined(FPC)}
  ReportMemoryLeaksOnShutdown := True;
  {$IFEND}

  {$IFDEF MSWINDOWS}
  StdOutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  StdErrHandle := GetStdHandle(STD_ERROR_HANDLE);
  StdOutHandleIsConsole := GetConsoleMode(StdOutHandle, Mode);
  StdErrHandleIsConsole := GetConsoleMode(StdErrHandle, Mode);
  {$ENDIF}
  try
    Go;
  except
    PrintErrOutput('issigtool fatal error: ' + {$IFDEF MSWINDOWS}GetExceptMessage{$ELSE}UTF8Decode(Exception(ExceptObject).Message){$ENDIF});
    Halt(2);
  end;
end.
