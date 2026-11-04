unit Setup.UninstallLog;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Uninstall log records and on-disk format
}

interface

uses
  {$IFDEF MSWINDOWS}Windows, Shared.CommonFunc, {$ENDIF} SysUtils, Shared.FileClass;

const
  HighestSupportedHeaderVersion = 1055;
  { Each time the format of the uninstall log changes, HighestSupportedHeaderVersion
    must be incremented, even if the change seems backward compatible (such as
    adding a new flag, or using one of the Reserved slots). When this happens, the
    file version number of Setup must also be incremented to match (51.x).

    The file version number (but not HighestSupportedHeaderVersion) must also be
    incremented when an improvement or bugfix to Uninstall is made. Failing to do
    so can cause older installers to replace the uninstaller .exe with an older
    and inferior version. Next time HighestSupportedHeaderVersion is incremented
    (along with the file version number), it should 'jump' ahead so both numbers
    are in sync again. While technically not required, this approach keeps things
    more sensible.

    Adding [Code] functions does not require bumping the file version number as a
    utCompiledCode record is associated with one specific SetupBinVersion number.

    If you want to customize the uninstall log but maintain compatibility with
    official Inno Setup releases, you should NOT do any of the above. Instead, it's
    recommended to use the "utUserDefined" log entry type if you wish to implement
    your own custom uninstall log entries; see below for more information. }

type
  TUninstallRecTyp = type Word;
const
  { Values for TUninstallRecTyp.
    If you wish to define your own custom uninstall entry type, you should use
    "utUserDefined". (Do NOT define your own ut* constants; this could cause
    incompatibilities with future Inno Setup releases.) The first field in a
    utUserDefined record must be a string which specifies a unique name for
    the record type. Example:
    UninstLog.Add(utUserDefined, ['MyRecordType', ... ], 0);
 }
  utUserDefined          = $01;
  utStartInstall         = $10;
  utEndInstall           = $11;
  utCompiledCode         = $20; { SetupBinVersion as ExtraData, or-ed with $80000000 on Win64 }
  utRun                  = $80;
  utDeleteDirOrFiles     = $81;
  utDeleteFile           = $82;
  utDeleteGroupOrItem    = $83;
  utIniDeleteEntry       = $84;
  utIniDeleteSection     = $85;
  utRegDeleteEntireKey   = $86;
  utRegClearValue        = $87;
  utRegDeleteKeyIfEmpty  = $88;
  utRegDeleteValue       = $89;
  utDecrementSharedCount = $8A;
  utRefreshFileAssoc     = $8B;
  utMutexCheck           = $8C;

  { Flags on ExtraData }
  utRun_NoWait = 1;
  utRun_WaitUntilIdle = 2;
  utRun_ShellExec = 4;
  utRun_RunMinimized = 8;
  utRun_RunMaximized = 16;
  utRun_SkipIfDoesntExist = 32;
  utRun_RunHidden = 64;
  utRun_ShellExecRespectWaitFlags = 128;
  utRun_Is64Bit = 256;
  utRun_DontLogParameters = 512;
  utRun_LogOutput = 1024;
  utDeleteFile_ExistedBeforeInstall = 1;
  utDeleteFile_Extra = 2;
  utDeleteFile_IsFont = 4;
  utDeleteFile_SharedFile = 8;
  utDeleteFile_RegisteredServer = 16;
  utDeleteFile_CallChangeNotify = 32;
  utDeleteFile_RegisteredTypeLib = 64;
  utDeleteFile_RestartDelete = 128;
  utDeleteFile_RemoveReadOnly = 256;
  utDeleteFile_NoSharedFilePrompt = 512;
  utDeleteFile_SharedFileIn64BitKey = 1024;
  utDeleteFile_Is64Bit = 2048;
  utDeleteFile_GacInstalled = 4096;
  utDeleteFile_PerUserFont = 8192;
  utDeleteFile_RegisteredWithOppositeBitness = 16384;
  utDeleteDirOrFiles_Extra = 1;
  utDeleteDirOrFiles_IsDir = 2;
  utDeleteDirOrFiles_DeleteFiles = 4;
  utDeleteDirOrFiles_DeleteSubdirsAlso = 8;
  utDeleteDirOrFiles_CallChangeNotify = 16;
  utDeleteDirOrFiles_Is64Bit = 32;
  utIniDeleteSection_OnlyIfEmpty = 1;
  utReg_KeyHandleMask = $80FFFFFF; 
  utReg_64BitKey = $01000000;
  utDecrementSharedCount_64BitKey = 1;

type
  TUninstallRecExtraData = type UInt32;

  PUninstallRec = ^TUninstallRec;
  TUninstallRec = record
    Prev, Next: PUninstallRec;
    ExtraData: TUninstallRecExtraData;
    DataSize: Cardinal;
    Typ: TUninstallRecTyp;
    Data: array[0..$6FFFFFFF] of Byte;  { *must* be last field }
  end;

  PUninstallLogFlags = ^TUninstallLogFlags;
  TUninstallLogFlags = set of (ufAdminInstalled, ufDontCheckRecCRCs,
    ufDoNotUse0, ufAlwaysRestart, ufChangesEnvironment, ufWin64,
    ufPowerUserInstalled, ufAdminInstallMode,
    ufDoNotUse1, ufDoNotUse2, ufDoNotUse3, ufDoNotUse4, ufDoNotUse5,
    { ^ these and also ufDoNotUse0 cannot be used again, were used for ufWizardModern,
        ufWizardDarkStyleDark, ufWizardDarkStyleDynamic, ufWizardBorderStyled,
        ufWizardLightButtonsUnstyled, and ufWizardKeepAspectRatio }
    ufRedirectionGuard);

  TUninstallLog = class
  private
    FList, FLastList: PUninstallRec;
    class function AllocRec(const Typ: TUninstallRecTyp;
      const ExtraData: TUninstallRecExtraData;
      const DataSize: Cardinal): PUninstallRec; static;
    procedure InternalAdd(const NewRec: PUninstallRec);
  protected
    FCount: Integer;
    function Delete(const Rec: PUninstallRec): PUninstallRec;
  public
    InstallMode64Bit: Boolean;
    AppId, AppName: String;
    NeedRestart: Boolean;
    Flags: TUninstallLogFlags;
    Version: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Typ: TUninstallRecTyp; const Data: array of String;
      const ExtraData: TUninstallRecExtraData);
    {$IFDEF MSWINDOWS}
    procedure AddReg(const Typ: TUninstallRecTyp; const RegView: TRegView;
      const RootKey: HKEY; const Data: array of String);
    {$ENDIF}
    function CanAppend(const Filename: String;
      var ExistingFlags: TUninstallLogFlags): Boolean; overload;
    function CanAppend(const Filename: String): Boolean; overload;
    procedure Clear;
    class function ExtractRecData(const Rec: PUninstallRec;
      var Data: array of String): Integer; static;
    function ExtractLatestRecData(const Typ: TUninstallRecTyp;
      const ExtraData: TUninstallRecExtraData; var Data: array of String): Boolean;
    procedure Load(const F: TFile; const Filename: String);
    class function WriteSafeHeaderString(Dest: PAnsiChar; const Source: String;
     MaxDestBytes: Cardinal): Cardinal; static;
    class function ReadSafeHeaderString(const Source: AnsiString): String; static;
    procedure Save(const Filename: String;
      const Append, UpdateUninstallLogAppName: Boolean);
    property List: PUninstallRec read FList;
    property LastList: PUninstallRec read FLastList;
  end;

function ReadUninstallLogFlags(const F: TFile; const Filename: String): TUninstallLogFlags;

implementation

uses
  {$IF Defined(MSWINDOWS) and Defined(SETUPPROJ)}
  Shared.SetupMessageIDs, SetupLdrAndSetup.Messages, {$IFEND}
  {$IFDEF UNIX}Unix, {$ENDIF}
  UnsignedFunc, Shared.Struct, Compression.Base;

procedure InternalError(const Id: String);
begin
  {$IF Defined(MSWINDOWS) and Defined(SETUPPROJ)}
  raise Exception.Create(FmtSetupMessage1(msgErrorInternal2, Id));
  {$ELSE}
  raise Exception.Create({$IFDEF FPC}UTF8Encode({$ENDIF}'Internal uninstall log error: ' + Id{$IFDEF FPC}){$ENDIF});
  {$ENDIF}
end;

procedure CorruptLog(const Filename: String);
begin
  {$IF Defined(MSWINDOWS) and Defined(SETUPPROJ)}
  raise Exception.Create(FmtSetupMessage1(msgUninstallDataCorrupted, Filename));
  {$ELSE}
  raise Exception.Create({$IFDEF FPC}UTF8Encode({$ENDIF}'Corrupt uninstall log: ' + Filename{$IFDEF FPC}){$ENDIF});
  {$ENDIF}
end;

type
  { Note: TUninstallLogHeader should stay <= 512 bytes in size, so that it
    fits into a single disk sector and can be written atomically.
    Do not add "non-sticky" appearance flags and fields that are set only
    by the latest installer. Add these to TMessagesLangOptions instead. }
  TUninstallLogHeader = packed record
    ID: TUninstallLogID;
    AppId: array[0..127] of AnsiChar;
    AppName: array[0..127] of AnsiChar;
    Version, NumRecs: Integer;
    EndOffset: UInt32;
    Flags: Integer;
    DoNotUse0, DoNotUse1: Integer; { cannot be used again, were used for WizardSizePercentX and WizardSizePercentY }
    Reserved: array[0..24] of Integer;  { reserved for future use }
    CRC: Longint;
  end;
  TUninstallCrcHeader = packed record
    Size, NotSize: Cardinal;
    CRC: Longint;
  end;
  TUninstallFileRec = packed record
    Typ: TUninstallRecTyp;
    ExtraData: TUninstallRecExtraData;
    DataSize: Cardinal;
  end;

procedure ReadUninstallLogHeader(const F: TFile; const Filename: String;
  var Header: TUninstallLogHeader; var Header64Bit: Boolean);

  procedure Corrupt;
  begin
    CorruptLog(Filename);
  end;

begin
  F.Seek(0);
  if F.Read(Header, SizeOf(Header)) <> SizeOf(Header) then
    Corrupt;
  if (Header.CRC <> $11111111) and
      { ^ for debugging purposes, you can change the CRC field in the file to
        $11111111 to disable CRC checking on the header}
     (Header.CRC <> GetCRC32(Header, SizeOf(Header)-SizeOf(Longint))) then
    Corrupt;
  if Header.ID = UninstallLogID[False] then
    Header64Bit := False
  else if Header.ID = UninstallLogID[True] then
    Header64Bit := True
  else
    Corrupt;
end;

function ReadUninstallLogFlags(const F: TFile; const Filename: String): TUninstallLogFlags;
{ Reads the flags from the header of the open file F. The Filename parameter
  is only used when generating exception error messages. }
var
  Header: TUninstallLogHeader;
  Header64Bit: Boolean;
begin
  ReadUninstallLogHeader(F, Filename, Header, Header64Bit);
  Result := PUninstallLogFlags(@Header.Flags)^;
end;

{ TUninstallLog }

constructor TUninstallLog.Create;
begin
  inherited Create;
  Clear;
end;

destructor TUninstallLog.Destroy;
begin
  Clear;
  inherited Destroy;
end;

class function TUninstallLog.AllocRec(const Typ: TUninstallRecTyp;
  const ExtraData: TUninstallRecExtraData;
  const DataSize: Cardinal): PUninstallRec;
{ Allocates a new PUninstallRec, but does not add it to the list. Returns nil
  if the value of the DataSize parameter is out of range. }
begin
  { Sanity check the size to protect against integer overflows. 128 MB should
    be way more than enough. }
  if DataSize > $08000000 then begin
    Result := nil;
    Exit;
  end;
  Result := AllocMem(NativeInt(Cardinal(@PUninstallRec(nil).Data) + DataSize));
  Result.Typ := Typ;
  Result.ExtraData := ExtraData;
  Result.DataSize := DataSize;
end;

procedure TUninstallLog.InternalAdd(const NewRec: PUninstallRec);
{ Adds a new entry to the uninstall list }
begin
  if List = nil then begin
    FList := NewRec;
    FLastList := List;
  end
  else begin
    LastList^.Next := NewRec;
    NewRec^.Prev := LastList;
    FLastList := NewRec;
  end;
  Inc(FCount);
end;

procedure TUninstallLog.Add(const Typ: TUninstallRecTyp; const Data: array of String;
  const ExtraData: TUninstallRecExtraData);
var
  L, I: Integer;
  Size: Int64;
  Dest: PByte;
  NewRec: PUninstallRec;
begin
  Size := 1;
  for I := 0 to High(Data) do
    Inc(Size, SizeOf(Byte) + SizeOf(Integer) + Int64(Length(Data[I])) * SizeOf(Char));
  if Size > High(Cardinal) then
    InternalError('DataSize range exceeded');
  NewRec := AllocRec(Typ, ExtraData, Cardinal(Size));
  if NewRec = nil then
    InternalError('DataSize range exceeded');

  Dest := @NewRec^.Data[0];
  for I := 0 to High(Data) do begin
    L := Length(Data[I]) * SizeOf(Char);
    Dest^ := $FE;
    Inc(Dest);
    PInteger(Dest)^ := -L;
    Inc(Dest, SizeOf(Integer));
    if L <> 0 then begin
      UMove(Data[I][1], Dest^, L);
      Inc(Dest, L);
    end;
  end;
  Dest^ := $FF;
  InternalAdd(NewRec);

  if Version < HighestSupportedHeaderVersion then
    Version := HighestSupportedHeaderVersion;
end;

{$IFDEF MSWINDOWS}
procedure TUninstallLog.AddReg(const Typ: TUninstallRecTyp;
  const RegView: TRegView; const RootKey: HKEY; const Data: array of String);
{ Adds a new utReg* type entry }
var
  RootKeyUInt32: UInt32;
  ExtraData: TUninstallRecExtraData;
begin
  { If RootKey isn't a predefined key, or has unrecognized garbage in the
    high byte (which we use for our own purposes), reject it }
  RootKeyUInt32 := RegRootKeyToUInt32(RootKey);
  if RootKeyUInt32 = 0 then
    Exit;

  { ExtraData in a utReg* entry consists of a root key value (HKEY_*)
    OR'ed with flag bits in the high byte }
  ExtraData := RootKeyUInt32;
  if RegView in RegViews64Bit then
    ExtraData := ExtraData or utReg_64BitKey;
  Add(Typ, Data, ExtraData);
end;

{$ENDIF}

function TUninstallLog.Delete(const Rec: PUninstallRec): PUninstallRec;
{ Removes Rec from the linked list, then frees it. Returns (what was) the
  previous record, or nil if there is none. }
begin
  Result := Rec.Prev;
  if Assigned(Rec.Prev) then
    Rec.Prev.Next := Rec.Next;
  if Assigned(Rec.Next) then
    Rec.Next.Prev := Rec.Prev;
  if FList = Rec then
    FList := Rec.Next;
  if FLastList = Rec then
    FLastList := Rec.Prev;
  Dec(FCount);
  FreeMem(Rec);
end;

procedure TUninstallLog.Clear;
{ Frees all entries in the uninstall list and clears AppId/AppName/Flags }
begin
  while FLastList <> nil do
    Delete(FLastList);
  FCount := 0;
  AppId := '';
  AppName := '';
  Flags := [];
end;

class function TUninstallLog.ExtractRecData(const Rec: PUninstallRec;
  var Data: array of String): Integer;
var
  L, I: Integer;
  X: PByte;
begin
  for I := 0 to High(Data) do
    Data[I] := '';
  I := 0;
  X := PByte(@Rec^.Data);
  while I <= High(Data) do begin
    case X^ of
      $00..$FC: begin
           L := X^;
           Inc(X);
         end;
      $FD: begin
           Inc(X);
           L := PWord(X)^;
           Inc(X, SizeOf(Word));
         end;
      $FE: begin
           Inc(X);
           L := PInteger(X)^;
           Inc(X, SizeOf(Integer));
         end;
      $FF: Break;
    end;
    if L < 0 then begin
      L := -L;
      SetString(Data[I], PChar(X), L div SizeOf(Char));
    end else if L > 0 then
      SetString(Data[I], PAnsiChar(X), L);
    Inc(X, L);
    Inc(I);
  end;
  Result := I;
end;

function TUninstallLog.ExtractLatestRecData(const Typ: TUninstallRecTyp;
  const ExtraData: TUninstallRecExtraData; var Data: array of String): Boolean;
var
  CurRec: PUninstallRec;
begin
  CurRec := LastList;
  while CurRec <> nil do begin
    if (CurRec^.Typ = Typ) and (CurRec^.ExtraData = ExtraData) then begin
      ExtractRecData(CurRec, Data);
      Result := True;
      Exit;
    end;
    CurRec := CurRec^.Prev;
  end;
  Result := False;
end;

class function TUninstallLog.WriteSafeHeaderString(Dest: PAnsiChar;
 const Source: String; MaxDestBytes: Cardinal): Cardinal;
{ ASCII fields are stored directly. Unicode fields begin with #1 and hold UTF-8.
  Truncation leaves room for the terminator and never splits a UTF-8 sequence. }
var
  Encoded: UTF8String;
  N, I, Count: Cardinal;
  UseMarker: Boolean;
begin
  N := ULength(Source);
  UseMarker := False;
  for I := 1 to N do
    if Ord(Source[I]) > 126 then begin
      UseMarker := True;
      Break;
    end;
  Encoded := UTF8Encode(Source);
  Count := Cardinal(Length(Encoded));
  Result := Count + 1 + Ord(UseMarker);
  if MaxDestBytes = 0 then
    Exit;

  if UseMarker then begin
    if MaxDestBytes = 1 then begin
      Dest^ := #0;
      Exit(1);
    end;
    Dest^ := #1;
    Inc(Dest);
    Dec(MaxDestBytes);
  end;
  if Count >= MaxDestBytes then begin
    Count := MaxDestBytes - 1;
    while (Count > 0) and (Byte(Encoded[Count + 1]) and $C0 = $80) do
      Dec(Count);
  end;
  if Count <> 0 then
    Move(Encoded[1], Dest^, Count);
  Dest[Count] := #0;
  if UseMarker then
    Result := Count + 2;
end;

class function TUninstallLog.ReadSafeHeaderString(const Source: AnsiString): String;
begin
  if (Source <> '') and (Source[1] = #1) then
    Result := UTF8Decode(Copy(Source, 2, Maxint))
  else
    Result := String(Source);
end;

procedure TUninstallLog.Save(const Filename: String;
  const Append, UpdateUninstallLogAppName: Boolean);
{ Saves all undo data to Filename. If Append is True, it appends the current
  undo data to the end of the existing file. When Append is True, it assumes
  compatibility has already been verified with the CanAppend method. }
var
  F: TFile;
  Buffer: array[0..4095] of Byte;
  BufCount: Cardinal;

  procedure Flush;
  var
    CrcHeader: TUninstallCrcHeader;
  begin
    if BufCount <> 0 then begin
      CrcHeader.Size := BufCount;
      CrcHeader.NotSize := not CrcHeader.Size;
      CrcHeader.CRC := GetCRC32(Buffer, BufCount);
      F.WriteBuffer(CrcHeader, SizeOf(CrcHeader));
      F.WriteBuffer(Buffer, BufCount);
      BufCount := 0;
    end;
  end;

  procedure WriteBuf(const Buf; Size: Cardinal);
  var
    P: Pointer;
    S: Cardinal;
  begin
    P := @Buf;
    while Size <> 0 do begin
      S := Size;
      if S > SizeOf(Buffer) - BufCount then
        S := SizeOf(Buffer) - BufCount;
      UMove(P^, Buffer[BufCount], S);
      Inc(BufCount, S);
      if BufCount = SizeOf(Buffer) then
        Flush;
      Inc(PByte(P), S);
      Dec(Size, S);
    end;
  end;

  function GetNonStickyFlags: TUninstallLogFlags;
  begin
    Result := [ufRedirectionGuard];
  end;

var
  Header: TUninstallLogHeader;
  FileRec: TUninstallFileRec;
  CurRec: PUninstallRec;
  NewEndOffset: Int64;
begin
  BufCount := 0;
  if not Append then
    F := TFile.Create(Filename, fdCreateAlways, faReadWrite, fsNone)
  else
    F := TFile.Create(Filename, fdOpenExisting, faReadWrite, fsNone);
  try
    if not Append then begin
      FillChar(Header, SizeOf(Header), 0);
      F.WriteBuffer(Header, SizeOf(Header));
      { Note: It will go back and fill in the correct values later }
    end
    else begin
      F.ReadBuffer(Header, SizeOf(Header));
      F.Seek(Header.EndOffset);
      { If there's anything past EndOffset (only possible if some kind of
        fatal error occurred while updating the file last time), clear it out }
      F.Truncate;
    end;

    CurRec := List;
    while CurRec <> nil do begin
      FileRec.Typ := Ord(CurRec^.Typ);
      FileRec.ExtraData := CurRec^.ExtraData;
      FileRec.DataSize := CurRec^.DataSize;
      WriteBuf(FileRec, SizeOf(FileRec));
      WriteBuf(CurRec^.Data, CurRec^.DataSize);
      if (Header.NumRecs < 0) or (Header.NumRecs >= High(Header.NumRecs)) then
        InternalError('NumRecs range exceeded');
      Inc(Header.NumRecs);

      CurRec := CurRec^.Next;
    end;
    Flush;

    NewEndOffset := F.Position;
    if NewEndOffset > High(UInt32) then
      InternalError('EndOffset range exceeded');
    Header.EndOffset := UInt32(NewEndOffset);
    F.Seek(0);
    Header.ID := UninstallLogID[InstallMode64Bit];
    WriteSafeHeaderString(@Header.AppId[0], AppId, SizeOf(Header.AppId));
    if not Append or UpdateUninstallLogAppName then
      WriteSafeHeaderString(@Header.AppName[0], AppName, SizeOf(Header.AppName));
    if Version > Header.Version then
      Header.Version := Version;
    PUninstallLogFlags(@Header.Flags)^ := PUninstallLogFlags(@Header.Flags)^ -
      GetNonStickyFlags + Flags;
    Header.CRC := GetCRC32(Header, SizeOf(Header)-SizeOf(Longint));
    { Prior to rewriting the header with the new EndOffset value, ensure the
      records we wrote earlier are flushed to disk. This should prevent the
      file from ever becoming corrupted/unreadable in the event the system
      crashes a split second from now. At worst, EndOffset will have the old
      value and any extra bytes past EndOffset will be ignored/discarded when
      the file is read at uninstall time, or appended to the next time Setup
      is run. }
    {$IFDEF MSWINDOWS}
    FlushFileBuffers(F.Handle);
    {$ELSE}
    if fpFsync(F.Handle) <> 0 then
      TFile.RaiseLastError;
    {$ENDIF}
    F.WriteBuffer(Header, SizeOf(Header));
  finally
    F.Free;
  end;
end;

procedure TUninstallLog.Load(const F: TFile; const Filename: String);
{ Loads all undo data from the open file F. The Filename parameter is only
  used when generating exception error messages.
  Note: The position of the file pointer after calling this function is
  undefined. }
var
  Buffer: array[0..4095] of Byte;
  BufPos, BufLeft: Cardinal;
  Header: TUninstallLogHeader;

  procedure Corrupt;
  begin
    CorruptLog(Filename);
  end;

  procedure FillBuffer;
  var
    CrcHeader: TUninstallCrcHeader;
    EndOffset, Ofs: Int64;
  begin
    EndOffset := Header.EndOffset;
    while BufLeft = 0 do begin
      Ofs := F.Position;
      Inc(Ofs, SizeOf(CrcHeader));
      if Ofs > EndOffset then
        Corrupt;
      if F.Read(CrcHeader, SizeOf(CrcHeader)) <> SizeOf(CrcHeader) then
        Corrupt;
      Ofs := F.Position;
      Inc(Ofs, CrcHeader.Size);
      if (CrcHeader.Size <> not CrcHeader.NotSize) or
         (CrcHeader.Size > SizeOf(Buffer)) or
         (Ofs > EndOffset) then
        Corrupt;
      if F.Read(Buffer, CrcHeader.Size) <> CrcHeader.Size then
        Corrupt;
      if not(ufDontCheckRecCRCs in Flags) and
        (CrcHeader.CRC <> GetCRC32(Buffer, CrcHeader.Size)) then
        Corrupt;
      BufPos := 0;
      BufLeft := CrcHeader.Size;
    end;
  end;

  procedure ReadBuf(var Buf; Size: Cardinal);
  var
    P: Pointer;
    S: Cardinal;
  begin
    P := @Buf;
    while Size <> 0 do begin
      if BufLeft = 0 then
        FillBuffer;
      S := Size;
      if S > BufLeft then
        S := BufLeft;
      UMove(Buffer[BufPos], P^, S);
      Inc(BufPos, S);
      Dec(BufLeft, S);
      Inc(PByte(P), S);
      Dec(Size, S);
    end;
  end;

var
  FileRec: TUninstallFileRec;
  I: Integer;
  NewRec: PUninstallRec;
begin
  BufPos := 0;
  BufLeft := 0;

  ReadUninstallLogHeader(F, Filename, Header, InstallMode64Bit);
  if Header.Version > HighestSupportedHeaderVersion then
    {$IF Defined(MSWINDOWS) and Defined(SETUPPROJ)}
    raise Exception.Create(FmtSetupMessage1(msgUninstallUnsupportedVer, Filename));
    {$ELSE}
    raise Exception.Create({$IFDEF FPC}UTF8Encode({$ENDIF}'Unsupported uninstall log version: ' + Filename{$IFDEF FPC}){$ENDIF});
    {$ENDIF}
  AppId := ReadSafeHeaderString(Header.AppId);
  AppName := ReadSafeHeaderString(Header.AppName);
  Flags := PUninstallLogFlags(@Header.Flags)^;

  for I := 1 to Header.NumRecs do begin
    ReadBuf(FileRec, SizeOf(FileRec));
    NewRec := AllocRec(FileRec.Typ, FileRec.ExtraData, FileRec.DataSize);
    if NewRec = nil then
      Corrupt;  { DataSize was out of range }
    try
      ReadBuf(NewRec.Data, NewRec.DataSize);
    except
      FreeMem(NewRec);
      raise;
    end;
    InternalAdd(NewRec);
  end;
end;

function TUninstallLog.CanAppend(const Filename: String;
  var ExistingFlags: TUninstallLogFlags): Boolean;
{ Returns True if Filename is a recognized uninstall log format, and its header
  matches our AppId and InstallMode64Bit settings. When True is returned,
  the existing log's flags are assigned to ExistingFlags. }
var
  F: TFile;
  Header: TUninstallLogHeader;
begin
  Result := False;
  try
    F := TFile.Create(Filename, fdOpenExisting, faRead, fsRead);
    try
      if F.Read(Header, SizeOf(Header)) <> SizeOf(Header) then
        Exit;
      if ((Header.CRC <> $11111111) and
          { ^ for debugging purposes, you can change the CRC field in the file to
            $11111111 to disable CRC checking on the header}
          (Header.CRC <> GetCRC32(Header, SizeOf(Header)-SizeOf(Longint)))) or
         (Header.ID <> UninstallLogID[InstallMode64Bit]) or
         (ReadSafeHeaderString(Header.AppId) <> AppId) then
        Exit;
      ExistingFlags := PUninstallLogFlags(@Header.Flags)^;
      Result := True;
    finally
      F.Free;
    end;
  except
  end;
end;

function TUninstallLog.CanAppend(const Filename: String): Boolean;
var
  ExistingFlags: TUninstallLogFlags;
begin
  Result := CanAppend(Filename, ExistingFlags);
end;

end.
