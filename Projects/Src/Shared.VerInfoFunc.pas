unit Shared.VerInfoFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Version info functions
}

interface

uses
  {$IFDEF MSWINDOWS} Windows, {$ENDIF} SysUtils;

type
  {$IFNDEF MSWINDOWS}
  TVSFixedFileInfo = packed record
    dwSignature, dwStrucVersion: Cardinal;
    dwFileVersionMS, dwFileVersionLS: Cardinal;
    dwProductVersionMS, dwProductVersionLS: Cardinal;
    dwFileFlagsMask, dwFileFlags, dwFileOS, dwFileType, dwFileSubtype: Cardinal;
    dwFileDateMS, dwFileDateLS: Cardinal;
  end;
  {$ENDIF}

  TFileVersionNumbers = record
    MS, LS: UInt32;
  end;

function GetVersionInfo(const Filename: String; var VersionInfo: TVSFixedFileInfo): Boolean;
function GetVersionNumbers(const Filename: String; var VersionNumbers: TFileVersionNumbers): Boolean;
{$IFNDEF MSWINDOWS}
function GetVersionString(const Filename, Name: String; const HasTranslation: Boolean;
  const Translation: Cardinal; out Value: String): Boolean;
{$ENDIF}
function StrToVersionNumbers(const S: String; var Version: TFileVersionNumbers): Boolean;
function VersionNumbersToInt64(const VersionNumbers: TFileVersionNumbers): Int64;

implementation

uses
  {$IFNDEF MSWINDOWS} Classes, Resource, WinPEImageReader, {$ENDIF}
  Shared.FPCStringUtils;

{$IFDEF MSWINDOWS}
function GetVersionInfo(const Filename: String;
  var VersionInfo: TVSFixedFileInfo): Boolean;
var
  VersionHandle, VersionSize: DWORD;
  VersionBuf: PChar;
  VerInfo: PVSFixedFileInfo;
  VerInfoSize: UINT;
begin
  Result := False;

  VersionSize := GetFileVersionInfoSizeW(PChar(Filename), VersionHandle);
  if VersionSize > 0 then begin
    GetMem(VersionBuf, VersionSize);
    try
      if GetFileVersionInfoW(PChar(Filename), VersionHandle, VersionSize, VersionBuf) then begin
        if VerQueryValueW(VersionBuf, '\', Pointer(VerInfo), VerInfoSize) and
           (VerInfoSize >= SizeOf(TVSFixedFileInfo)) then begin
          VersionInfo := VerInfo^;
          Result := True;
        end;
      end;
    finally
      FreeMem(VersionBuf);
    end;
  end;
end;
{$ELSE}
function LoadVersionResource(const Filename: String): TBytes;
var
  Input: TFileStream;
  Resources: TResources;
  Reader: TWinPEImageResourceReader;
  Entry: TAbstractResource;
  Data: TStream;
begin
  Result := nil;
  try
    Input := TFileStream.Create(UTF8Encode(Filename), fmOpenRead or fmShareDenyNone);
    try
      Resources := TResources.Create;
      try
        Reader := TWinPEImageResourceReader.Create;
        try
          Resources.LoadFromStream(Input, Reader);
        finally
          Reader.Free;
        end;
        Entry := Resources.Find(TResID(RT_VERSION), TResID(1));
        if Entry = nil then
          Exit;
        Data := Entry.RawData;
        if (Data.Size < 6) or (Data.Size > High(Word) + 3) then
          Exit;
        SetLength(Result, Data.Size);
        Data.Position := 0;
        Data.ReadBuffer(Result[0], Length(Result));
      finally
        Resources.Free;
      end;
    finally
      Input.Free;
    end;
  except
    on E: Exception do begin
      if E is EOutOfMemory then
        raise;
      Result := nil;
    end;
  end;
end;

type
  TVersionBlock = record
    Key: String;
    ValueStart, ValueSize, ChildrenStart, EndOffset: Integer;
  end;

function ReadVersionBlock(const Data: TBytes; const Offset, Limit: Integer;
  out Block: TVersionBlock): Boolean;
var
  KeyEnd, ValueType: Integer;
begin
  if Limit - Offset < 6 then
    Exit(False);
  Block.EndOffset := Offset + (Data[Offset] or (Data[Offset + 1] shl 8));
  if (Block.EndOffset < Offset + 8) or (Block.EndOffset > Limit) then
    Exit(False);
  Block.ValueSize := Data[Offset + 2] or (Data[Offset + 3] shl 8);
  ValueType := Data[Offset + 4] or (Data[Offset + 5] shl 8);
  if ValueType > 1 then
    Exit(False);
  Block.ValueSize := Block.ValueSize shl ValueType;
  KeyEnd := Offset + 6;
  while KeyEnd + 2 <= Block.EndOffset do begin
    if (Data[KeyEnd] = 0) and (Data[KeyEnd + 1] = 0) then begin
      SetString(Block.Key, PWideChar(@Data[Offset + 6]), (KeyEnd - Offset - 6) div 2);
      Block.ValueStart := (KeyEnd + 5) and not 3;
      if Block.ValueSize > Block.EndOffset - Block.ValueStart then begin
        if Block.ValueSize <> 0 then
          Exit(False);
      end;
      Block.ChildrenStart := (Block.ValueStart + Block.ValueSize + 3) and not 3;
      Exit(True);
    end;
    Inc(KeyEnd, 2);
  end;
  Result := False;
end;

function FindVersionChild(const Data: TBytes; const Parent: TVersionBlock;
  const Key: String; out Child: TVersionBlock): Boolean;
var
  Offset: Integer;
begin
  Offset := Parent.ChildrenStart;
  while ReadVersionBlock(Data, Offset, Parent.EndOffset, Child) do begin
    if InnoSameText(Child.Key, Key) then
      Exit(True);
    Offset := (Child.EndOffset + 3) and not 3;
  end;
  Result := False;
end;

function GetVersionInfo(const Filename: String;
  var VersionInfo: TVSFixedFileInfo): Boolean;
var
  Data: TBytes;
  Root: TVersionBlock;
  Info: TVSFixedFileInfo;
begin
  Data := LoadVersionResource(Filename);
  if not ReadVersionBlock(Data, 0, Length(Data), Root) or
     (Root.Key <> 'VS_VERSION_INFO') or (Root.ValueSize < SizeOf(Info)) then
    Exit(False);
  Move(Data[Root.ValueStart], Info, SizeOf(Info));
  Result := Info.dwSignature = $FEEF04BD;
  if Result then
    VersionInfo := Info;
end;

function GetVersionString(const Filename, Name: String; const HasTranslation: Boolean;
  const Translation: Cardinal; out Value: String): Boolean;
var
  Data: TBytes;
  Root, Strings, Vars, Translations: TVersionBlock;
  Offset: Integer;

  function ReadTranslation(const Language, CodePage: Word): Boolean;
  var
    Table, Entry: TVersionBlock;
    LengthInChars: Integer;
  begin
    if not FindVersionChild(Data, Strings, InnoIntToHex(Language, 4) + InnoIntToHex(CodePage, 4), Table) or
       not FindVersionChild(Data, Table, Name, Entry) or (Entry.ValueSize < 2) or
       Odd(Entry.ValueSize) then
      Exit(False);
    LengthInChars := Entry.ValueSize div 2 - 1;
    if (Data[Entry.ValueStart + LengthInChars * 2] <> 0) or
       (Data[Entry.ValueStart + LengthInChars * 2 + 1] <> 0) then
      Exit(False);
    SetString(Value, PWideChar(@Data[Entry.ValueStart]), LengthInChars);
    Result := True;
  end;

begin
  Data := LoadVersionResource(Filename);
  if not ReadVersionBlock(Data, 0, Length(Data), Root) or
     (Root.Key <> 'VS_VERSION_INFO') or
     not FindVersionChild(Data, Root, 'StringFileInfo', Strings) then
    Exit(False);
  if HasTranslation then
    Exit(ReadTranslation(Word(Translation), Word(Translation shr 16)));
  if not FindVersionChild(Data, Root, 'VarFileInfo', Vars) or
     not FindVersionChild(Data, Vars, 'Translation', Translations) then
    Exit(False);
  Offset := Translations.ValueStart;
  while Offset + 4 <= Translations.ValueStart + Translations.ValueSize do begin
    if ReadTranslation(Data[Offset] or (Data[Offset + 1] shl 8),
       Data[Offset + 2] or (Data[Offset + 3] shl 8)) then
      Exit(True);
    Inc(Offset, 4);
  end;
  Result := False;
end;
{$ENDIF}

function GetVersionNumbers(const Filename: String;
  var VersionNumbers: TFileVersionNumbers): Boolean;
var
  VerInfo: TVSFixedFileInfo;
begin
  Result := GetVersionInfo(Filename, VerInfo);
  if Result then begin
    VersionNumbers.MS := VerInfo.dwFileVersionMS;
    VersionNumbers.LS := VerInfo.dwFileVersionLS;
  end;
end;

function StrToVersionNumbers(const S: String; var Version: TFileVersionNumbers): Boolean;

  function SplitNextNumber(var Z: String): UInt16;
  var
    I, N: Integer;
  begin
    if Trim(Z) <> '' then begin
      I := Pos('.', Z);
      if I = 0 then
        I := Length(Z)+1;
      N := InnoStrToInt(Trim(Copy(Z, 1, I-1)));
      if (N < Low(UInt16)) or (N > High(UInt16)) then
        Abort;
      Result := UInt16(N);
      Z := Copy(Z, I+1, Maxint);
    end else
      Result := 0;
  end;

var
  Z: String;
  W: Word;
begin
  try
    Z := S;
    W := SplitNextNumber(Z);
    Version.MS := (UInt32(W) shl 16) or SplitNextNumber(Z);
    W := SplitNextNumber(Z);
    Version.LS := (UInt32(W) shl 16) or SplitNextNumber(Z);
    Result := True;
  except
    Result := False;
  end;
end;

function VersionNumbersToInt64(const VersionNumbers: TFileVersionNumbers): Int64;
begin
  Result := Int64((UInt64(VersionNumbers.MS) shl 32) or VersionNumbers.LS);
end;

end.
