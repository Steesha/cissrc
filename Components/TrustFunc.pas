unit TrustFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Trust support functions using ISSigFunc and key texts from TrustFunc.AllowedPublicKeys.inc

  In Inno Setup these functions are only used by ISIDE, ISCC, and ISCmplr. Verification of
  the user's files by ISCmplr and Setup is done by calling ISSigFunc directly and uses the
  user's key texts.
}

{.$DEFINE TRUSTALL}

{$IFDEF FPC}{$MODESWITCH NESTEDPROCVARS}{$ENDIF}

interface

uses
  Classes;

type
  TCheckFileTrustOption = (cftoKeepOpen, cftoTrustAllOnDebug);
  TCheckFileTrustOptions = set of TCheckFileTrustOption;
  TLoadTrustedLibraryOption = (ltloTrustAllOnDebug);
  TLoadTrustedLibraryOptions = set of TLoadTrustedLibraryOption;

function CheckFileTrust(const Filename: String; const Options: TCheckFileTrustOptions): TFileStream;
{$IFDEF FPC}
procedure LoadBuildPublicKey(const Filename: String);
{$ENDIF}
{$IFDEF MSWINDOWS}
function LoadTrustedLibrary(const Filename: String; const Options: TLoadTrustedLibraryOptions): HMODULE;
{$ENDIF}

implementation

uses
  {$IFDEF MSWINDOWS} Windows, {$ENDIF} SysUtils
  {$IFNDEF TRUSTALL}, ECDSA, SHA256, ISSigFunc, PathFunc {$ENDIF};

{$IFDEF FPC}
{$IFNDEF TRUSTALL}
var
  BuildPublicKey: TECDSAPublicKey;
  HasBuildPublicKey: Boolean;
{$ENDIF}

procedure LoadBuildPublicKey(const Filename: String);
{$IFNDEF TRUSTALL}
var
  KeyText: String;
  PublicKey: TECDSAPublicKey;
{$ENDIF}
begin
  {$IFDEF TRUSTALL}
  raise Exception.Create('Build public keys require template verification');
  {$ELSE}
  KeyText := ISSigLoadTextFromFile(Filename);
  try
    if ISSigParsePublicKeyText(KeyText, PublicKey) <> ikrSuccess then
      raise Exception.Create('Invalid ISSig build public key');
    BuildPublicKey := PublicKey;
    HasBuildPublicKey := True;
  finally
    ISSigWipeString(KeyText);
  end;
  {$ENDIF}
end;
{$ENDIF}

{$IFDEF MSWINDOWS}

function Win32ErrorString(ErrorCode: Cardinal): String;
{ Like SysErrorMessage but also passes the FORMAT_MESSAGE_IGNORE_INSERTS flag
  which allows the function to succeed on errors like 129 }
var
  Buffer: array[0..1023] of Char;
  Len: Integer;
begin
  Len := FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM or
    FORMAT_MESSAGE_IGNORE_INSERTS or FORMAT_MESSAGE_ARGUMENT_ARRAY, nil,
    ErrorCode, 0, @Buffer[0], SizeOf(Buffer) div SizeOf(Buffer[0]), nil);
  while (Len > 0) and ((Buffer[Len-1] <= ' ') or (Buffer[Len-1] = '.')) do
    Dec(Len);
  SetString(Result, Buffer, Len);
end;

{$ENDIF}

function CheckFileTrust(const Filename: String; const Options: TCheckFileTrustOptions): TFileStream;
{$IFNDEF TRUSTALL}

  procedure SigFileMissing(const Filename, SigFilename: String);
  begin
    raise Exception.CreateFmt('Signature file "%s" does not exist', [SigFilename]);
  end;

  procedure SigVerificationFailed(const Filename, SigFilename: String;
    const VerifyResult: TISSigVerifySignatureResult);
  begin
    raise Exception.CreateFmt('Signature file "%s" is not valid', [SigFilename]);
  end;

{$ENDIF}
var
  {$IFDEF MSWINDOWS}
  Attr: Cardinal;
  {$ENDIF}
  {$IFNDEF TRUSTALL}
  AllowedKeys: array of TECDSAKey;
  ExpectedFileName, ActualFileName, AllowedPublicKey1Text, AllowedPublicKey2Text: String;
  ExpectedFileSize: Int64;
  ExpectedFileHash: TSHA256Digest;
  Key1, Key2: TECDSAKey;
  {$IFDEF FPC}
  BuildKey: TECDSAKey;
  {$ENDIF}
  F: TFileStream;
  {$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Attr := GetFileAttributesW(PChar(Filename));
  if Attr = INVALID_FILE_ATTRIBUTES then
    raise Exception.Create(Win32ErrorString(GetLastError));
  if Attr and faDirectory <> 0 then
    raise Exception.Create(Win32ErrorString(ERROR_FILE_NOT_FOUND));
  {$ELSE}
  if not FileExists(UTF8Encode(Filename)) then
    raise EFOpenError.CreateFmt('File "%s" does not exist', [Filename]);
  {$ENDIF}
{$IFNDEF TRUSTALL}
{$IFDEF DEBUG}
  if cftoTrustAllOnDebug in Options then
    Exit(nil);
{$ENDIF}
  {$I TrustFunc.AllowedPublicKeys.inc}
  Key1 := nil;
  Key2 := nil;
  {$IFDEF FPC}
  BuildKey := nil;
  {$ENDIF}
  try
    { Import keys }
    Key1 := TECDSAKey.Create;
    if ISSigImportKeyText(Key1, AllowedPublicKey1Text, False) <> ikrSuccess then
      raise Exception.Create('ISSigImportKeyText failed');
    if AllowedPublicKey2Text <> '' then begin
      Key2 := TECDSAKey.Create;
      if ISSigImportKeyText(Key2, AllowedPublicKey2Text, False) <> ikrSuccess then
        raise Exception.Create('ISSigImportKeyText failed');
    end;

    if Key2 <> nil then
      AllowedKeys := [Key1, Key2]
    else
      AllowedKeys := [Key1];

    {$IFDEF FPC}
    if HasBuildPublicKey then begin
      BuildKey := TECDSAKey.Create;
      BuildKey.ImportPublicKey(BuildPublicKey);
      SetLength(AllowedKeys, Length(AllowedKeys) + 1);
      AllowedKeys[High(AllowedKeys)] := BuildKey;
    end;
    {$ENDIF}

    { Verify signature }
    if not ISSigVerifySignature(Filename, AllowedKeys, ExpectedFileName, ExpectedFileSize, ExpectedFileHash,
      nil, SigFileMissing,
      SigVerificationFailed) then
      raise Exception.Create('Unexpected ISSigVerifySignature result');
  finally
    {$IFDEF FPC}
    BuildKey.Free;
    {$ENDIF}
    Key2.Free;
    Key1.Free;
  end;
  
  { Verify file, keeping open afterwards if requested
    Also see Setup.ScriptFunc's ISSigVerify which can also keep open afterwards }
  {$IFDEF MSWINDOWS}
  ActualFileName := PathExtractName(Filename);
  {$ELSE}
  ActualFileName := UTF8Decode(ExtractFileName(UTF8Encode(Filename)));
  {$ENDIF}
  if (ExpectedFileName <> '') and not PathSame(ActualFileName, ExpectedFileName) then
    raise Exception.CreateFmt('File "%s" is not trusted (incorrect name).', [Filename]);
  F := TFileStream.Create({$IFDEF FPC}UTF8Encode(Filename){$ELSE}Filename{$ENDIF}, fmOpenRead or fmShareDenyWrite);
  try
    if F.Size <> ExpectedFileSize then
      raise Exception.CreateFmt('File "%s" is not trusted (incorrect size).', [Filename]);
    if not SHA256DigestsEqual(ISSigCalcStreamHash(F), ExpectedFileHash) then
      raise Exception.CreateFmt('File "%s" is not trusted (incorrect hash).', [Filename]);
  except
    FreeAndNil(F);
    raise;
  end;
  if not (cftoKeepOpen in Options) then
    FreeAndNil(F);

  Result := F;
{$ELSE}
  Result := nil;
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
function DoLoadLibrary(const Filename: String): HMODULE;
begin
  Result := SafeLoadLibrary(PChar(Filename), SEM_NOOPENFILEERRORBOX);
  if Result = 0 then
    raise Exception.Create(Win32ErrorString(GetLastError));
end;

function LoadTrustedLibrary(const Filename: String; const Options: TLoadTrustedLibraryOptions): HMODULE;
var
  CheckFileTrustOptions: TCheckFileTrustOptions;
  F: TFileStream;
begin
  CheckFileTrustOptions := [cftoKeepOpen];
  if ltloTrustAllOnDebug in Options then
    Include(CheckFileTrustOptions, cftoTrustAllOnDebug);
  F := CheckFileTrust(Filename, CheckFileTrustOptions);
  try
    Result := DoLoadLibrary(Filename);
  finally
    F.Free;
  end;
end;

{$ENDIF}

end.
