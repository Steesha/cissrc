unit Compiler.ExeUpdateFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  PE header and resource update functions used by the compiler only
}

interface

uses
  {$IFDEF MSWINDOWS} Windows, {$ELSE} Shared.PlatformTypes, {$ENDIF} SysUtils, Shared.FileClass, Shared.VerInfoFunc, Shared.Struct, Shared.FPCStringUtils;

type
  TUpdateIconsAndStyleFile = (uisfSetup, uisfSetupCustomStyle, uisfSetupLdr);
  TUpdateIconsAndStyleOperation = (uisoIcoFileName, uisoWizardDarkStyle, uisoStyleFileName, uisoStyleFileNameDynamicDark, uisoDone);
  TOnUpdateIconsAndStyle = procedure(const Operation: TUpdateIconsAndStyleOperation) of object;

  EResUpdateError = class(Exception)
  private
    FErrorCode: DWORD;
  public
    property ErrorCode: DWORD read FErrorCode;
  end;

function ReadSignatureAndChecksumFields(const F: TCustomFile;
  var ASignatureAddress, ASignatureSize, AChecksum: DWORD): Boolean;
function SeekToResourceData(const F: TCustomFile; const ResType, ResId: Cardinal): Cardinal;
function UpdateSignatureAndChecksumFields(const F: TCustomFile;
  const ASignatureAddress, ASignatureSize, AChecksum: DWORD): Boolean;
  
procedure UpdateSetupPEHeaderFields(const F: TCustomFile;
  const IsTSAware, IsDEPCompatible, IsASLRCompatible: Boolean);
procedure UpdateIconsAndStyle(const FileName: String; const Uisf: TUpdateIconsAndStyleFile; const IcoFileName: String;
  const WizardDarkStyle: TSetupWizardDarkStyle; const StyleFileName, StyleFileNameDynamicDark: String;
  const OnUpdateIconsAndStyle: TOnUpdateIconsAndStyle);
procedure UpdateVersionInfo(const F: TCustomFile;
  const NewBinaryFileVersion, NewBinaryProductVersion: TFileVersionNumbers;
  const NewCompanyName, NewFileDescription, NewTextFileVersion, NewLegalCopyright,
  NewProductName, NewTextProductVersion, NewOriginalFileName: String;
  const SetFileVersionAndDescription: Boolean);

implementation

uses
  Math{$IFDEF FPC}, Classes, Resource, WinPEImageReader, CoffWriter{$ENDIF};

const
  {$IFNDEF MSWINDOWS}
  IMAGE_FILE_MACHINE_AMD64 = $8664;
  ERROR_INVALID_DATA = 13;
  RT_VERSION = 16;
  {$ENDIF}
  IMAGE_NT_SIGNATURE = $00004550;
  IMAGE_NT_OPTIONAL_HDR32_MAGIC = $10b;
  IMAGE_NT_OPTIONAL_HDR64_MAGIC = $20b;
  IMAGE_NUMBEROF_DIRECTORY_ENTRIES = 16;
  IMAGE_SIZEOF_SHORT_NAME = 8;
  IMAGE_DIRECTORY_ENTRY_RESOURCE = 2;
  IMAGE_DIRECTORY_ENTRY_SECURITY = 4;

type
  PImageFileHeader = ^TImageFileHeader;
  TImageFileHeader = packed record
    Machine: Word;
    NumberOfSections: Word;
    TimeDateStamp: DWORD;
    PointerToSymbolTable: DWORD;
    NumberOfSymbols: DWORD;
    SizeOfOptionalHeader: Word;
    Characteristics: Word;
  end;
  PImageDataDirectory = ^TImageDataDirectory;
  TImageDataDirectory = record
    VirtualAddress: DWORD;
    Size: DWORD;
  end;
  TDataDirectory = packed array[0..IMAGE_NUMBEROF_DIRECTORY_ENTRIES-1] of TImageDataDirectory;
  PImageOptionalHeader = ^TImageOptionalHeader;
  TImageOptionalHeader = packed record
    { Standard fields. }
    Magic: Word;
    MajorLinkerVersion: Byte;
    MinorLinkerVersion: Byte;
    SizeOfCode: DWORD;
    SizeOfInitializedData: DWORD;
    SizeOfUninitializedData: DWORD;
    AddressOfEntryPoint: DWORD;
    BaseOfCode: DWORD;
    BaseOfData: DWORD;
    { NT additional fields. }
    ImageBase: DWORD;
    SectionAlignment: DWORD;
    FileAlignment: DWORD;
    MajorOperatingSystemVersion: Word;
    MinorOperatingSystemVersion: Word;
    MajorImageVersion: Word;
    MinorImageVersion: Word;
    MajorSubsystemVersion: Word;
    MinorSubsystemVersion: Word;
    Win32VersionValue: DWORD;
    SizeOfImage: DWORD;
    SizeOfHeaders: DWORD;
    CheckSum: DWORD;
    Subsystem: Word;
    DllCharacteristics: Word;
    SizeOfStackReserve: DWORD;
    SizeOfStackCommit: DWORD;
    SizeOfHeapReserve: DWORD;
    SizeOfHeapCommit: DWORD;
    LoaderFlags: DWORD;
    NumberOfRvaAndSizes: DWORD;
    DataDirectory: TDataDirectory;
  end;
  PImageOptionalHeader64 = ^TImageOptionalHeader64;
  TImageOptionalHeader64 = packed record
    { Standard fields. }
    Magic: Word;
    MajorLinkerVersion: Byte;
    MinorLinkerVersion: Byte;
    SizeOfCode: DWORD;
    SizeOfInitializedData: DWORD;
    SizeOfUninitializedData: DWORD;
    AddressOfEntryPoint: DWORD;
    BaseOfCode: DWORD;
    { NT additional fields. }
    ImageBase: Int64;
    SectionAlignment: DWORD;
    FileAlignment: DWORD;
    MajorOperatingSystemVersion: Word;
    MinorOperatingSystemVersion: Word;
    MajorImageVersion: Word;
    MinorImageVersion: Word;
    MajorSubsystemVersion: Word;
    MinorSubsystemVersion: Word;
    Win32VersionValue: DWORD;
    SizeOfImage: DWORD;
    SizeOfHeaders: DWORD;
    CheckSum: DWORD;
    Subsystem: Word;
    DllCharacteristics: Word;
    SizeOfStackReserve: Int64;
    SizeOfStackCommit: Int64;
    SizeOfHeapReserve: Int64;
    SizeOfHeapCommit: Int64;
    LoaderFlags: DWORD;
    NumberOfRvaAndSizes: DWORD;
    DataDirectory: TDataDirectory;
  end;
  TISHMisc = packed record
    case Integer of
      0: (PhysicalAddress: DWORD);
      1: (VirtualSize: DWORD);
  end;
  PImageSectionHeader = ^TImageSectionHeader;
  TImageSectionHeader = packed record
    Name: packed array[0..IMAGE_SIZEOF_SHORT_NAME-1] of Byte;
    Misc: TISHMisc;
    VirtualAddress: DWORD;
    SizeOfRawData: DWORD;
    PointerToRawData: DWORD;
    PointerToRelocations: DWORD;
    PointerToLinenumbers: DWORD;
    NumberOfRelocations: Word;
    NumberOfLinenumbers: Word;
    Characteristics: DWORD;
  end;
  TImageResourceDirectory = packed record
    Characteristics: DWORD;
    TimeDateStamp: DWORD;
    MajorVersion: Word;
    MinorVersion: Word;
    NumberOfNamedEntries: Word;
    NumberOfIdEntries: Word;
  end;
  TImageResourceDirectoryEntry = packed record
    Id: DWORD;
    Offset: DWORD;
  end;
  TImageResourceDataEntry = packed record
    OffsetToData: DWORD;
    Size: DWORD;
    CodePage: DWORD;
    Reserved: DWORD;
  end;

procedure Error(const Msg: String);
begin
  raise Exception.Create(ToNativeText('Resource update error: ' + Msg));
end;

function SeekToPEHeader(const F: TCustomFile): Boolean;
var
  DosHeader: packed record
    Sig: array[0..1] of AnsiChar;
    Other: array[0..57] of Byte;
    PEHeaderOffset: LongWord;
  end;
  Sig: DWORD;
begin
  Result := False;
  F.Seek(0);
  if F.Read(DosHeader, SizeOf(DosHeader)) = SizeOf(DosHeader) then begin
    if (DosHeader.Sig[0] = 'M') and (DosHeader.Sig[1] = 'Z') and
       (DosHeader.PEHeaderOffset <> 0) then begin
      F.Seek(DosHeader.PEHeaderOffset);
      if F.Read(Sig, SizeOf(Sig)) = SizeOf(Sig) then
        if Sig = IMAGE_NT_SIGNATURE then
          Result := True;
    end;
  end;
end;

type
  TOptionalHeader = (ohNone, oh32, oh64);

function SeekToAndReadPEOptionalHeader(const F: TCustomFile;
  var OptHeader32: TImageOptionalHeader; var OptHeader64: TImageOptionalHeader64;
  var OptHeaderOffset: Int64): TOptionalHeader;
var
  Header: TImageFileHeader;
begin
  Result := ohNone;
  if SeekToPEHeader(F) then begin
    if (F.Read(Header, SizeOf(Header)) = SizeOf(Header)) and
       ((Header.SizeOfOptionalHeader = SizeOf(OptHeader32)) or
        (Header.SizeOfOptionalHeader = SizeOf(OptHeader64))) then begin
      OptHeaderOffset := F.Position;
      if Header.SizeOfOptionalHeader = SizeOf(OptHeader32) then begin
        if (F.Read(OptHeader32, SizeOf(OptHeader32)) = SizeOf(OptHeader32)) and
           (OptHeader32.Magic = IMAGE_NT_OPTIONAL_HDR32_MAGIC) then
          Result := oh32;
      end else begin
        if (F.Read(OptHeader64, SizeOf(OptHeader64)) = SizeOf(OptHeader64)) and
           (OptHeader64.Magic = IMAGE_NT_OPTIONAL_HDR64_MAGIC) then
          Result := oh64;
      end;
    end;
  end;
end;

procedure FindResourceSection(const F: TCustomFile;
  var SectionVirtualAddr, SectionPhysOffset, SectionPhysSize: Cardinal);
var
  PEHeader: TImageFileHeader;
  PEOptHeader: TImageOptionalHeader;
  PEOptHeader64: TImageOptionalHeader64;
  PESectionHeader: TImageSectionHeader;
  PE32, PE32Plus: Boolean;
  DataDirectory: TDataDirectory;
  I: Integer;
  OffsetInSection: Cardinal;
begin
  if not SeekToPEHeader(F) then
    Error('File isn''t a PE file');

  F.ReadBuffer(PEHeader, SizeOf(PEHeader));
  PE32 := PEHeader.SizeOfOptionalHeader = SizeOf(PEOptHeader);
  PE32Plus := PEHeader.SizeOfOptionalHeader = SizeOf(PEOptHeader64);
  if not PE32 and not PE32Plus then
    Error('File isn''t a PE file (3)');

  if PE32 then begin
    F.ReadBuffer(PEOptHeader, SizeOf(PEOptHeader));
    if PEOptHeader.Magic <> IMAGE_NT_OPTIONAL_HDR32_MAGIC then
      Error('File isn''t a PE file (4)');
    if PEOptHeader.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_RESOURCE then
      Error('No resource data directory');
    DataDirectory := PEOptHeader.DataDirectory;
  end else begin
    F.ReadBuffer(PEOptHeader64, SizeOf(PEOptHeader64));
    if PEOptHeader64.Magic <> IMAGE_NT_OPTIONAL_HDR64_MAGIC then
      Error('File isn''t a PE file (5)');
    if PEOptHeader64.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_RESOURCE then
      Error('No resource data directory');
    DataDirectory := PEOptHeader64.DataDirectory;
  end;

  { Scan section headers for resource section }
  if (DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE].VirtualAddress = 0) or
     (DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE].Size = 0) then
    Error('No resources (1)');
  SectionVirtualAddr := DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE].VirtualAddress;
  for I := 0 to PEHeader.NumberOfSections-1 do begin
    F.ReadBuffer(PESectionHeader, SizeOf(PESectionHeader));
    if SectionVirtualAddr < PESectionHeader.VirtualAddress then
      Continue;
    OffsetInSection := SectionVirtualAddr - PESectionHeader.VirtualAddress;
    if OffsetInSection >= PESectionHeader.SizeOfRawData then
      Continue;
    SectionPhysSize := PESectionHeader.SizeOfRawData - OffsetInSection;
    if (PESectionHeader.PointerToRawData = 0) or
       (Int64(PESectionHeader.PointerToRawData) + PESectionHeader.SizeOfRawData > F.Size) or
       (Int64(PESectionHeader.PointerToRawData) + OffsetInSection > High(Cardinal)) or
       (DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE].Size > SectionPhysSize) then
      Error('Invalid resource section bounds');
    SectionPhysOffset := PESectionHeader.PointerToRawData + OffsetInSection;
    Exit;
  end;
  Error('No resources (2)');
end;

function FindResOffset(const F: TCustomFile; const SectionEnd: Int64; const AnyId: Boolean;
  const Id: Cardinal; const FindSubdir: Boolean; var Offset: Cardinal): Boolean;
var
  Dir: TImageResourceDirectory;
  Entry: TImageResourceDirectoryEntry;
  I: Integer;
begin
  if SectionEnd - F.Position < SizeOf(Dir) then
    Error('Truncated resource directory');
  F.ReadBuffer(Dir, SizeOf(Dir));
  if (Integer(Dir.NumberOfNamedEntries) + Dir.NumberOfIdEntries) * SizeOf(Entry) >
     SectionEnd - F.Position then
    Error('Truncated resource directory entries');
  { Skip over named entries }
  for I := 0 to Dir.NumberOfNamedEntries-1 do
    F.ReadBuffer(Entry, SizeOf(Entry));
  { Now process ID entries }
  Result := False;
  for I := 0 to Dir.NumberOfIdEntries-1 do begin
    F.ReadBuffer(Entry, SizeOf(Entry));
    if (AnyId or (Entry.Id = Id)) and
       ((Entry.Offset and $80000000 <> 0) = FindSubdir) then begin
      Offset := Entry.Offset and $7FFFFFFF;
      Result := True;
      Break;
    end;
  end;
end;

function SeekToResourceData(const F: TCustomFile; const ResType, ResId: Cardinal): Cardinal;
{ Seeks to the specified resource's data, and returns its size. Raises an
  exception if the resource cannot be found. }
var
  SectionVirtualAddr, SectionPhysOffset, SectionPhysSize, Ofs: Cardinal;
  DataEntry: TImageResourceDataEntry;
  SectionEnd: Int64;
begin
  FindResourceSection(F, SectionVirtualAddr, SectionPhysOffset, SectionPhysSize);

  SectionEnd := Int64(SectionPhysOffset) + SectionPhysSize;
  { Scan the resource directory }
  F.Seek(SectionPhysOffset);
  if not FindResOffset(F, SectionEnd, False, ResType, True, Ofs) then
    Error('Can''t find resource (1)');
  F.Seek(Int64(SectionPhysOffset) + Ofs);
  if not FindResOffset(F, SectionEnd, False, ResId, True, Ofs) then
    Error('Can''t find resource (2)');
  F.Seek(Int64(SectionPhysOffset) + Ofs);
  if not FindResOffset(F, SectionEnd, True, 0, False, Ofs) then
    Error('Can''t find resource (3).');
  F.Seek(Int64(SectionPhysOffset) + Ofs);
  if SectionEnd - F.Position < SizeOf(DataEntry) then
    Error('Truncated resource data entry');
  F.ReadBuffer(DataEntry, SizeOf(DataEntry));

  { Sanity check: DataEntry.OffsetToData is an RVA. It's technically possible
    for the RVA to point to a different section, but we don't support that. }
  if Cardinal(DataEntry.OffsetToData) < SectionVirtualAddr then
    Error('Invalid resource (1)');
  if DataEntry.OffsetToData - SectionVirtualAddr + Int64(DataEntry.Size) > SectionPhysSize then
    Error('Invalid resource (2)');

  { Seek to the resource }
  F.Seek(Int64(SectionPhysOffset) + (DataEntry.OffsetToData - SectionVirtualAddr));
  Result := DataEntry.Size;
end;

function ReadSignatureAndChecksumFields(const F: TCustomFile;
  var ASignatureAddress, ASignatureSize, AChecksum: DWORD): Boolean;
{ Reads the signature and checksum fields in the specified file's header.
  If the file is not a valid PE32 or PE32+ executable, False is returned. }
var
  OptHeader32: TImageOptionalHeader;
  OptHeader64: TImageOptionalHeader64;
  OptHeaderOffset: Int64;
  OptHeader: TOptionalHeader;
begin
  OptHeader := SeekToAndReadPEOptionalHeader(F, OptHeader32, OptHeader64, OptHeaderOffset);
  Result := OptHeader <> ohNone;
  if Result then begin
    if OptHeader = oh32 then begin
      ASignatureAddress := OptHeader32.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress;
      ASignatureSize := OptHeader32.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].Size;
      AChecksum := OptHeader32.CheckSum;
    end else begin
      ASignatureAddress := OptHeader64.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress;
      ASignatureSize := OptHeader64.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].Size;
      AChecksum := OptHeader64.CheckSum;
    end;
  end;
end;

function UpdateSignatureAndChecksumFields(const F: TCustomFile;
  const ASignatureAddress, ASignatureSize, AChecksum: DWORD): Boolean;
{ Sets the signature and checksum fields in the specified file's header.
  If the file is not a valid PE32 or PE32+ executable, False is returned. }
var
  OptHeader32: TImageOptionalHeader;
  OptHeader64: TImageOptionalHeader64;
  OptHeaderOffset: Int64;
  OptHeader: TOptionalHeader;
begin
  OptHeader := SeekToAndReadPEOptionalHeader(F, OptHeader32, OptHeader64, OptHeaderOffset);
  Result := OptHeader <> ohNone;
  if Result then begin
    F.Seek(OptHeaderOffset);
    if OptHeader = oh32 then begin
      OptHeader32.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress := ASignatureAddress;
      OptHeader32.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].Size := ASignatureSize;
      OptHeader32.CheckSum := AChecksum;
      F.WriteBuffer(OptHeader32, SizeOf(OptHeader32));
    end else begin
      OptHeader64.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress := ASignatureAddress;
      OptHeader64.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].Size := ASignatureSize;
      OptHeader64.CheckSum := AChecksum;
      F.WriteBuffer(OptHeader64, SizeOf(OptHeader64));
    end;
  end;
end;

procedure UpdateSetupPEHeaderFields(const F: TCustomFile;
  const IsTSAware, IsDEPCompatible, IsASLRCompatible: Boolean);
const
  IMAGE_DLLCHARACTERISTICS_HIGH_ENTROPY_VA = $0020;
  IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE = $0040;
  IMAGE_DLLCHARACTERISTICS_NX_COMPAT = $0100;
  IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE = $8000;
  OffsetOfDllCharacteristics = $46; { Valid for both PE32 and PE32+ }
var
  Header: TImageFileHeader;
  OptMagic, DllChars, OrigDllChars, ASLRFlags: Word;
  PE32, PE32Plus: Boolean;
  Ofs: Int64;
begin
  if SeekToPEHeader(F) then begin
    if (F.Read(Header, SizeOf(Header)) = SizeOf(Header)) then begin
      PE32 := Header.SizeOfOptionalHeader = SizeOf(TImageOptionalHeader);
      PE32Plus := Header.SizeOfOptionalHeader = SizeOf(TImageOptionalHeader64);
      if PE32 or PE32Plus then begin
        Ofs := F.Position;
        if (F.Read(OptMagic, SizeOf(OptMagic)) = SizeOf(OptMagic)) and
           ((PE32 and (OptMagic = IMAGE_NT_OPTIONAL_HDR32_MAGIC)) or
            (PE32Plus and (OptMagic = IMAGE_NT_OPTIONAL_HDR64_MAGIC))) then begin
          { Update DllCharacteristics }
          F.Seek(Ofs + OffsetOfDllCharacteristics);
          if F.Read(DllChars, SizeOf(DllChars)) = SizeOf(DllChars) then begin
            OrigDllChars := DllChars;
            if IsTSAware then
              DllChars := DllChars or IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE
            else
              DllChars := Word(DllChars and not IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE);
            if IsDEPCompatible then
              DllChars := DllChars or IMAGE_DLLCHARACTERISTICS_NX_COMPAT
            else
              DllChars := Word(DllChars and not IMAGE_DLLCHARACTERISTICS_NX_COMPAT);
            ASLRFlags := IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE;
            if Header.Machine = IMAGE_FILE_MACHINE_AMD64 then
              ASLRFlags := ASLRFlags or IMAGE_DLLCHARACTERISTICS_HIGH_ENTROPY_VA;
            if IsASLRCompatible then
              DllChars := DllChars or ASLRFlags
            else
              DllChars := DllChars and not ASLRFlags;
            if DllChars <> OrigDllChars then begin
              F.Seek(Ofs + OffsetOfDllCharacteristics);
              F.WriteBuffer(DllChars, SizeOf(DllChars));
            end;
            Exit;
          end;
        end;
      end;
    end;
  end;
  raise Exception.Create('UpdateSetupPEHeaderFields failed');
end;

procedure ResUpdateError(const Msg: String; const ResourceName: String = ''; const ErrorCode: DWORD = ERROR_INVALID_DATA);
var
  S: String;
  E: EResUpdateError;
begin
  if ResourceName <> '' then
    S := InnoFormat('Resource %s update error: %s', [ResourceName, Msg])
  else
    S := InnoFormat('Resource update error: %s', [Msg]);

  E := EResUpdateError.Create(ToNativeText(S));
  E.FErrorCode := ErrorCode;
  raise E;
end;

{$IFNDEF FPC}
procedure ResUpdateErrorWithLastError(const Msg: String; const ResourceName: String = '');
begin
  const ErrorCode = GetLastError;
  ResUpdateError(Msg + ' (' + InnoIntToStr(ErrorCode) + ')', ResourceName, ErrorCode);
end;

{$ENDIF}

procedure UpdateVersionInfo(const F: TCustomFile;
  const NewBinaryFileVersion, NewBinaryProductVersion: TFileVersionNumbers;
  const NewCompanyName, NewFileDescription, NewTextFileVersion, NewLegalCopyright,
  NewProductName, NewTextProductVersion, NewOriginalFileName: String;
  const SetFileVersionAndDescription: Boolean);

  function WideStrsEqual(P1, P2: PWideChar): Boolean;

    function WideUpCase(C: WideChar): WideChar;
    begin
      Result := C;
      if (Result >= 'a') and (Result <= 'z') then
        Dec(Result, Ord('a') - Ord('A'));
    end;

  begin
    while True do begin
      if WideUpCase(P1^) <> WideUpCase(P2^) then begin
        Result := False;
        Exit;
      end;
      if P1^ = #0 then
        Break;
      Inc(P1);
      Inc(P2);
    end;
    Result := True;
  end;

  procedure BumpToDWordBoundary(var P: Pointer);
  begin
    if NativeUInt(P) and 3 <> 0 then
      NativeUInt(P) := (NativeUInt(P) or 3) + 1;
  end;

  function BoundedWideLength(const Value: PWideChar; const Limit: Pointer): NativeInt;
  var
    Cursor: PWideChar;
  begin
    Cursor := Value;
    while NativeInt(PByte(Limit) - PByte(Cursor)) >= SizeOf(WideChar) do begin
      if Cursor^ = #0 then
        Exit(Cursor - Value);
      Inc(Cursor);
    end;
    ResUpdateError('Unterminated version resource string');
    Result := 0;
  end;

  function QueryValue(P, Limit: Pointer; Path: PWideChar; var Buf: Pointer;
    var BufLen: Cardinal; var ValueEnd: Pointer): Boolean;
  var
    EndP: Pointer;
    BlockLength, ValueLength: Word;
    KeyLength: NativeInt;
  begin
    Result := False;
    if NativeInt(PByte(Limit) - PByte(P)) < 3 * SizeOf(Word) then
      ResUpdateError('Truncated version resource block');
    BlockLength := PWord(P)^;
    if (BlockLength < 3 * SizeOf(Word)) or (BlockLength > PByte(Limit) - PByte(P)) then
      ResUpdateError('Invalid version resource block length');
    EndP := PByte(P) + BlockLength;
    Inc(PWord(P));
    ValueLength := PWord(P)^;
    Inc(PWord(P), 2);
    KeyLength := BoundedWideLength(PWideChar(P), EndP);
    if not WideStrsEqual(PWideChar(P), Path) then
      Exit;

    Inc(PWideChar(P), KeyLength + 1);
    BumpToDWordBoundary(P);
    Inc(Path, StrLen(Path) + 1);
    if PByte(P) > PByte(EndP) then
      ResUpdateError('Invalid version resource value offset');
    if Path^ = #0 then begin
      Buf := P;
      BufLen := ValueLength;
      ValueEnd := EndP;
      Exit(True);
    end;

    { Container value lengths are byte counts. String leaves are handled above. }
    if ValueLength > PByte(EndP) - PByte(P) then
      ResUpdateError('Invalid version resource value length');
    Inc(PByte(P), ValueLength);
    BumpToDWordBoundary(P);
    while PByte(P) < PByte(EndP) do begin
      if QueryValue(P, EndP, Path, Buf, BufLen, ValueEnd) then
        Exit(True);
      Inc(PByte(P), PWord(P)^);
      BumpToDWordBoundary(P);
    end;
  end;

  procedure ReplaceWithRealCopyrightSymbols(const Value: PWideChar);
  var
    Len, I, J: Integer;
  begin
    Len := StrLen(Value);
    for I := 0 to Len-3 do begin
      if (Value[I] = '(') and (Value[I+1] = 'C') and (Value[I+2] = ')') then begin
        Value[I] := WideChar($00A9);
        { Shift back two characters }
        for J := I+1 to Len-3 do
          Value[J] := Value[J+2];
        Value[Len-2] := ' ';
        Value[Len-1] := ' ';
      end;
    end;
  end;

  procedure UpdateStringValue(P, Limit: Pointer; const Path: PWideChar; NewValue: String);
  var
    Value: PWideChar;
    ValueLen: Cardinal;
    ValueEnd: Pointer;
    CharCount: NativeInt;
  begin
    if not QueryValue(P, Limit, Path, Pointer(Value), ValueLen, ValueEnd) then
      ResUpdateError('Unexpected version resource format (1)');
    CharCount := Min(Length(NewValue), BoundedWideLength(Value, ValueEnd));
    if CharCount > 0 then
      Move(Pointer(NewValue)^, Value^, CharCount * SizeOf(Char));
    ReplaceWithRealCopyrightSymbols(Value);
  end;

  procedure UpdateFixedFileInfo(P, Limit: Pointer; const Path: PWideChar;
    const NewFileVersion, NewProductVersion: TFileVersionNumbers;
    const SetFileVersion: Boolean);
  var
    FixedFileInfo: ^TVSFixedFileInfo;
    ValueLen: Cardinal;
    ValueEnd: Pointer;
  begin
    if not QueryValue(P, Limit, Path, Pointer(FixedFileInfo), ValueLen, ValueEnd) or
       (ValueLen < SizeOf(TVSFixedFileInfo)) or
       (PByte(ValueEnd) - PByte(FixedFileInfo) < SizeOf(TVSFixedFileInfo)) then
      ResUpdateError('Unexpected version resource format (2)');
    if FixedFileInfo.dwSignature <> $FEEF04BD then
      ResUpdateError('Unexpected version resource format (3)');
    if SetFileVersion then begin
      FixedFileInfo.dwFileVersionLS := NewFileVersion.LS;
      FixedFileInfo.dwFileVersionMS := NewFileVersion.MS;
    end;
    FixedFileInfo.dwProductVersionLS := NewProductVersion.LS;
    FixedFileInfo.dwProductVersionMS := NewProductVersion.MS;
  end;

var
  ResSize: Cardinal;
  VersRes, ResourceEnd: Pointer;
  ResOffset: Int64;
begin
  { Locate the resource }
  ResSize := SeekToResourceData(F, Cardinal(RT_VERSION), 1);
  ResOffset := F.Position;
  if ResSize < 3 * SizeOf(Word) then
    ResUpdateError('Truncated version resource');

  GetMem(VersRes, ResSize);
  try
    { Read the resource }
    F.ReadBuffer(VersRes^, ResSize);
    ResourceEnd := PByte(VersRes) + ResSize;

    { Update the resource }
    UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'CompanyName'#0, NewCompanyName);
    if SetFileVersionAndDescription then begin
      UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'FileDescription'#0, NewFileDescription);
      UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'FileVersion'#0, NewTextFileVersion);
    end;
    UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'LegalCopyright'#0, NewLegalCopyright);
    UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'ProductName'#0, NewProductName);
    UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'OriginalFileName'#0, NewOriginalFileName);
    UpdateStringValue(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0'StringFileInfo'#0'000004b0'#0'ProductVersion'#0, NewTextProductVersion);
    UpdateFixedFileInfo(VersRes, ResourceEnd, 'VS_VERSION_INFO'#0, NewBinaryFileVersion, NewBinaryProductVersion, SetFileVersionAndDescription);

    { Write the updated resource }
    F.Seek(ResOffset);
    F.WriteBuffer(VersRes^, ResSize);
  finally
    FreeMem(VersRes);
  end;
end;

{$IFNDEF FPC}
function EnumLangsFunc(M: HMODULE; lpType, lpName: PAnsiChar; wLanguage: Word; lParam: IntPtr): BOOL; stdcall;
begin
  PWord(lParam)^ := wLanguage;
  Result := False;
end;

function GetResourceLanguage(M: HMODULE; lpType, lpName: PChar; var wLanguage: Word): Boolean;
begin
  wLanguage := 0;
  EnumResourceLanguages(M, lpType, lpName, @EnumLangsFunc, IntPtr(@wLanguage));
  Result := True;
end;

procedure UpdateIconsAndStyle(const FileName: String; const Uisf: TUpdateIconsAndStyleFile; const IcoFileName: String;
  const WizardDarkStyle: TSetupWizardDarkStyle; const StyleFileName, StyleFileNameDynamicDark: String;
  const OnUpdateIconsAndStyle: TOnUpdateIconsAndStyle);
type
  PIcoItemHeader = ^TIcoItemHeader;
  TIcoItemHeader = packed record
    Width: Byte;
    Height: Byte;
    Colors: Byte;
    Reserved: Byte;
    Planes: Word;
    BitCount: Word;
    ImageSize: DWORD;
  end;
  PIcoItem = ^TIcoItem;
  TIcoItem = packed record
    Header: TIcoItemHeader;
    Offset: DWORD;
  end;
  PIcoHeader = ^TIcoHeader;
  TIcoHeader = packed record
    Reserved: Word;
    Typ: Word;
    ItemCount: Word;
    Items: array [0..MaxInt shr 4 - 1] of TIcoItem;
  end;
  PGroupIconDirItem = ^TGroupIconDirItem;
  TGroupIconDirItem = packed record
    Header: TIcoItemHeader;
    Id: Word;
  end;
  PGroupIconDir = ^TGroupIconDir;
  TGroupIconDir = packed record
    Reserved: Word;
    Typ: Word;
    ItemCount: Word;
    Items: array [0..MaxInt shr 4 - 1] of TGroupIconDirItem;
  end;

  procedure TriggerOnUpdateIconsAndStyle(const Operation: TUpdateIconsAndStyleOperation);
  begin
    if Assigned(OnUpdateIconsAndStyle) then
      OnUpdateIconsAndStyle(Operation);
  end;

  function LoadFileIntoMemory(const FileName: String; var P: Pointer): Cardinal;
  begin
    const F = TFile.Create(FileName, fdOpenExisting, faRead, fsRead);
    try
      const N = F.CappedSize;
      if Cardinal(N) > Cardinal($100000) then  { sanity check }
        ResUpdateError('File is too large', '', ERROR_INVALID_PARAMETER);
      GetMem(P, N);
      try
        F.ReadBuffer(P^, N);
      except
        FreeMem(P);
        raise;
      end;
      Result := N;
    finally
      F.Free;
    end;
  end;

  function IsValidIcon(P: Pointer; Size: Cardinal): Boolean;
  var
    ItemCount: Cardinal;
  begin
    Result := False;
    if Size < Cardinal(SizeOf(Word) * 3) then
      Exit;
    if (PAnsiChar(P)[0] = 'M') and (PAnsiChar(P)[1] = 'Z') then
      Exit;
    ItemCount := PIcoHeader(P).ItemCount;
    if Size < Cardinal((SizeOf(Word) * 3) + (ItemCount * SizeOf(TIcoItem))) then
      Exit;
    P := @PIcoHeader(P).Items;
    while ItemCount > Cardinal(0) do begin
      if (Cardinal(PIcoItem(P).Offset + PIcoItem(P).Header.ImageSize) < Cardinal(PIcoItem(P).Offset)) or
         (Cardinal(PIcoItem(P).Offset + PIcoItem(P).Header.ImageSize) > Cardinal(Size)) then
        Exit;
      Inc(PIcoItem(P));
      Dec(ItemCount);
    end;
    Result := True;
  end;

  function LoadResourcePointer(const M: HMODULE; const ResourceType, ResourceName: PChar;
    const WantSize: Boolean; out Size: DWORD): Pointer; overload;
  begin
    var R := FindResource(M, ResourceName, ResourceType);
    if R = 0 then
      ResUpdateErrorWithLastError('FindResource failed (1)', ResourceName);
    if WantSize then begin
      Size := SizeofResource(M, R);
      if Size = 0 then
        ResUpdateErrorWithLastError('SizeofResource failed (1)', ResourceName);
    end;
    var Res := LoadResource(M, R);
    if Res = 0 then
      ResUpdateErrorWithLastError('LoadResource failed (1)', ResourceName);
    Result := LockResource(Res);
    if Result = nil then
      ResUpdateErrorWithLastError('LockResource failed (1)', ResourceName);
  end;

  function LoadResourcePointer(const M: HMODULE; const ResourceType, ResourceName: PChar): Pointer; overload;
  begin
    var Dummy: DWORD;
    Result := LoadResourcePointer(M, ResourceType, ResourceName, False, Dummy);
  end;

  procedure DeleteResource(const H: THandle; const M: HMODULE; const ResourceType, ResourceName: PChar);
  var
    wLanguage: Word;
  begin
    if not GetResourceLanguage(M, ResourceType, ResourceName, wLanguage) then
      ResUpdateError('GetResourceLanguage failed (1)', ResourceName);
    if not UpdateResource(H, ResourceType, ResourceName, wLanguage, nil, 0) then
      ResUpdateErrorWithLastError('UpdateResource failed (1)', ResourceName);
  end;

  procedure DeleteResourceIfExists(const H: THandle; const M: HMODULE; const ResourceType, ResourceName: PChar);
  begin
    if FindResource(M, ResourceName, ResourceType) <> 0 then
      DeleteResource(H, M, ResourceType, ResourceName);
  end;

  procedure RenameResource(const H: THandle; const M: HMODULE; const ResourceType, OldResourceName, NewResourceName: PChar);
  var
    Size: DWORD;
    P: Pointer;
    wLanguage: Word;
  begin
    { Load the resource }
    P := LoadResourcePointer(M, ResourceType, OldResourceName, True, Size);

    { Create a copy resource with the new name }
    if not GetResourceLanguage(M, ResourceType, OldResourceName, wLanguage) then
      ResUpdateError('GetResourceLanguage failed (2)', OldResourceName);
    if not UpdateResource(H, ResourceType, NewResourceName, wLanguage, P, Size) then
      ResUpdateErrorWithLastError('UpdateResource failed (2)', NewResourceName);

    { Delete the old resource }
    if not UpdateResource(H, ResourceType, OldResourceName, wLanguage, nil, 0) then
      ResUpdateErrorWithLastError('UpdateResource failed (3)', OldResourceName);
 end;

  function DeleteIcon(const H: THandle; const M: HMODULE; const ResourceName: PChar): PGroupIconDir;
  var
    GroupIconDir: PGroupIconDir;
    I: Integer;
    wLanguage: Word;
  begin
    { Load the group icon resource }
    GroupIconDir := LoadResourcePointer(M, RT_GROUP_ICON, ResourceName);

    { Delete the group icon resource }
    DeleteResource(H, M, RT_GROUP_ICON, ResourceName);

    { Delete the icon resources that belonged to the group }
    for I := 0 to GroupIconDir.ItemCount-1 do begin
      if not GetResourceLanguage(M, RT_ICON, MakeIntResource(GroupIconDir.Items[I].Id), wLanguage) then
        ResUpdateError('GetResourceLanguage failed (3)', ResourceName);
      if not UpdateResource(H, RT_ICON, MakeIntResource(GroupIconDir.Items[I].Id), wLanguage, nil, 0) then
        ResUpdateErrorWithLastError('UpdateResource failed (4)', ResourceName);
    end;

    Result := GroupIconDir;
  end;

  function DeleteIconIfExists(const H: THandle; const M: HMODULE; const ResourceName: PChar): PGroupIconDir;
  begin
    if FindResource(M, ResourceName, RT_GROUP_ICON) <> 0 then
      Result := DeleteIcon(H, M, ResourceName)
    else
      Result := nil;
  end;

  function RenameIconWithOverwrite(const H: THandle; const M: HMODULE; const OldResourceName, NewResourceName: PChar): PGroupIconDir;
  var
    GroupIconDir: PGroupIconDir;
    GroupIconDirSize: DWORD;
    wLanguage: Word;
  begin
    DeleteIconIfExists(H, M, NewResourceName);

    { Load the group icon resource }
    GroupIconDir := LoadResourcePointer(M, RT_GROUP_ICON, OldResourceName);

    GroupIconDirSize := Sizeof(Word)*3 + GroupIconDir.ItemCount*Sizeof(TGroupIconDirItem);

    { Create a copy group icon resource with the new name - existing icon resources will belong to
      it automatically }
    if not GetResourceLanguage(M, RT_GROUP_ICON, OldResourceName, wLanguage) then
      ResUpdateError('GetResourceLanguage failed (4)', OldResourceName);
    if not UpdateResource(H, RT_GROUP_ICON, NewResourceName, wLanguage, GroupIconDir, GroupIconDirSize) then
      ResUpdateErrorWithLastError('UpdateResource failed (5)', NewResourceName);

    { Delete the old group icon resource }
    if not UpdateResource(H, RT_GROUP_ICON, OldResourceName, wLanguage, nil, 0) then
      ResUpdateErrorWithLastError('UpdateResource failed (6)', OldResourceName);

    Result := GroupIconDir;
  end;

  function GetWindowsModernDarkStyleName(const M: HMODULE): PChar;
  begin
    { Which one is present depends on the .dproj, see README.md }
    Result := 'WINDOWSMODERNDARKSE';
    if FindResource(M, Result, 'VCLSTYLE') = 0 then
      Result := 'WINDOWSMODERNDARK';
  end;

  function HandleBuiltinStyle(const M: HMODULE; const StyleFileName: String; var Vsf: Pointer; var VsfSize: Cardinal; const Dark: Boolean): Boolean;
  begin
    { Also see DeleteResource calls below }
    var StyleName: PChar := nil;
    if InnoSameText(StyleFileName, 'builtin:polar') then begin
      if Dark then
        StyleName := 'WINDOWSPOLARDARK'
      else
        StyleName := 'WINDOWSPOLARLIGHT';
    end else if InnoSameText(StyleFileName, 'builtin:windows11') then begin
      if Dark then
        StyleName := GetWindowsModernDarkStyleName(M)
      else
        StyleName := 'WINDOWSMODERNLIGHT';
    end else if InnoSameText(StyleFileName, 'builtin:slate') then
      StyleName := 'SLATECLASSICO'
    else if InnoSameText(StyleFileName, 'builtin:stellar') then
      StyleName := 'STELLAR'
    else if InnoSameText(StyleFileName, 'builtin:zircon') then
      StyleName := 'ZIRCON';
    Result := StyleName <> nil;
    if Result then
      Vsf := LoadResourcePointer(M, 'VCLSTYLE', StyleName, True, VsfSize)
  end;

var
  H: THandle;
  M: HMODULE;
  OldGroupIconDir, NewGroupIconDir: PGroupIconDir;
  I: Integer;
begin
  var Ico: PIcoHeader := nil;
  var Vsf := nil;
  var ShouldFreeVsf := False;
  var VsfDynamicDark := nil;
  var ShouldFreeVsfDynamicDark := False;

  try
    if IcoFileName <> '' then begin
      TriggerOnUpdateIconsAndStyle(uisoIcoFileName);

      { Load the icons }
      var P: Pointer;
      const IcoSize = LoadFileIntoMemory(IcoFileName, P);
      Ico := P;

      { Ensure the icon is valid }
      if not IsValidIcon(Ico, IcoSize) then
        ResUpdateError('Icon file is invalid', '', ERROR_INVALID_PARAMETER);
    end;

    { Update the resources }
    var ChangedMainIcon := False;
    H := BeginUpdateResource(PChar(FileName), False);
    if H = 0 then
      ResUpdateErrorWithLastError('BeginUpdateResource failed (1)');
    try
      M := LoadLibraryEx(PChar(FileName), 0, LOAD_LIBRARY_AS_DATAFILE);
      if M = 0 then
        ResUpdateErrorWithLastError('LoadLibraryEx failed (1)');
      try
        { Load the styles. Could be checked using TStyleManager.IsValidStyle but that requires using VCL units. }
        var VsfSize: Cardinal := 0;
        if StyleFileName <> '' then begin
          TriggerOnUpdateIconsAndStyle(uisoStyleFileName);
          if not HandleBuiltinStyle(M, StyleFileName, Vsf, VsfSize, WizardDarkStyle = wdsDark) then begin
            VsfSize := LoadFileIntoMemory(StyleFileName, Vsf);
            ShouldFreeVsf := True;
          end;
        end;

        var VsfSizeDynamicDark: Cardinal := 0;
        if StyleFileNameDynamicDark <> '' then begin
          TriggerOnUpdateIconsAndStyle(uisoStyleFileNameDynamicDark);
          if not HandleBuiltinStyle(M, StyleFileNameDynamicDark, VsfDynamicDark, VsfSizeDynamicDark, True) then begin
            VsfSizeDynamicDark := LoadFileIntoMemory(StyleFileNameDynamicDark, VsfDynamicDark);
            ShouldFreeVsfDynamicDark := True;
          end;
        end;

        { All of the following changes must be independent because updates are not immediate. For
          example, if you call DeleteIcon followed by FindResource then resource will still be found,
          until you call EndUpdateResource *and* reload the file using LoadLibrary }

        if IcoFileName <> '' then begin
          TriggerOnUpdateIconsAndStyle(uisoIcoFileName);

          const ResourceName = 'MAINICON';

          { Delete default icons }
          OldGroupIconDir := DeleteIcon(H, M, PChar(ResourceName));
          DeleteIconIfExists(H, M, PChar(ResourceName + '_DARK'));

          { Build the new group icon resource }
          const NewGroupIconDirSize: DWORD = 3*SizeOf(Word)+Ico.ItemCount*SizeOf(TGroupIconDirItem);
          GetMem(NewGroupIconDir, NewGroupIconDirSize);
          try
            { Build the new group icon resource }
            NewGroupIconDir.Reserved := OldGroupIconDir.Reserved;
            NewGroupIconDir.Typ := OldGroupIconDir.Typ;
            NewGroupIconDir.ItemCount := Ico.ItemCount;
            for I := 0 to NewGroupIconDir.ItemCount-1 do begin
              NewGroupIconDir.Items[I].Header := Ico.Items[I].Header;
              const Id = I+100; //start at 100 to avoid overwriting other icons that may exist
              if Id > High(Word) then
                ResUpdateError('UpdateResource failed (7)', ResourceName);
              NewGroupIconDir.Items[I].Id := Word(Id);
            end;

            { Update 'MAINICON' }
            for I := 0 to NewGroupIconDir.ItemCount-1 do
              if not UpdateResource(H, RT_ICON, MakeIntResource(NewGroupIconDir.Items[I].Id), 1033, Pointer(PByte(Ico) + Ico.Items[I].Offset), Ico.Items[I].Header.ImageSize) then
                ResUpdateErrorWithLastError('UpdateResource failed (8)', ResourceName);

            { Update the icons }
            if not UpdateResource(H, RT_GROUP_ICON, 'MAINICON', 1033, NewGroupIconDir, NewGroupIconDirSize) then
              ResUpdateErrorWithLastError('UpdateResource failed (9)', ResourceName);

            ChangedMainIcon := True;
          finally
            FreeMem(NewGroupIconDir);
          end;
        end else begin
          if WizardDarkStyle <> wdsDynamic then begin
            TriggerOnUpdateIconsAndStyle(uisoWizardDarkStyle);
            if WizardDarkStyle = wdsLight then begin
              { Forced light: remove dark main icon }
              DeleteIconIfExists(H, M, 'MAINICON_DARK')
            end else begin
              { Forced dark: rename dark main icon to be the regular main icon }
              RenameIconWithOverwrite(H, M, 'MAINICON_DARK', 'MAINICON');
              ChangedMainIcon := True;
            end;
          end; { Else keep both main icons }
        end;

        if Uisf in [uisfSetup, uisfSetupCustomStyle] then begin
          const DeleteUninstallIcon = IcoFileName <> '';
          if DeleteUninstallIcon then begin
            TriggerOnUpdateIconsAndStyle(uisoIcoFileName);
            { Make UninstallProgressForm use the custom icon }
            DeleteIcon(H, M, 'Z_UNINSTALLICON');
            DeleteIconIfExists(H, M, 'Z_UNINSTALLICON_DARK');
          end;
          if WizardDarkStyle <> wdsDynamic then begin
            TriggerOnUpdateIconsAndStyle(uisoWizardDarkStyle);
            { Unlike for MAINICON (for which we don't have the choice) here it always uses DeleteIcon
              instead of also using RenameIcon, to avoid issues with Windows' icon cache }
            var Postfix := '';
            if WizardDarkStyle = wdsLight then
              Postfix := '_DARK';
            { Delete the icons we don't need: either the light ones or the dark ones }
            DeleteIconIfExists(H, M, PChar('Z_GROUPICON' + Postfix));
            if not DeleteUninstallIcon then
              DeleteIconIfExists(H, M, PChar('Z_UNINSTALLICON' + Postfix));
          end;

          if Uisf = uisfSetupCustomStyle then begin
            if Vsf <> nil then begin
              TriggerOnUpdateIconsAndStyle(uisoStyleFileName);
              { Add the regular custom style, used by forced light, forced dark and dynamic light }
              if not UpdateResource(H, 'VCLSTYLE', 'MYSTYLE1', 1033, Vsf, VsfSize) then
                ResUpdateErrorWithLastError('UpdateResource failed (10)', 'MYSTYLE1');
            end;

            if VsfDynamicDark <> nil then begin
              TriggerOnUpdateIconsAndStyle(uisoStyleFileNameDynamicDark);
              { Add the dark custom style, used by dynamic dark only }
              if not UpdateResource(H, 'VCLSTYLE', 'MYSTYLE1_DARK', 1033, VsfDynamicDark, VsfSizeDynamicDark) then
                ResUpdateErrorWithLastError('UpdateResource failed (11)', 'MYSTYLE1_DARK');
            end;

            { See if we need to keep the built-in dark style }
            const WindowsModernDarkStyleName = GetWindowsModernDarkStyleName(M);
            if (Vsf = nil) and (WizardDarkStyle = wdsDark) then begin
              TriggerOnUpdateIconsAndStyle(uisoWizardDarkStyle);
              { Forced dark without a custom style: make the built-in dark style the regular one }
              RenameResource(H, M, 'VCLSTYLE', WindowsModernDarkStyleName, 'MYSTYLE1');
            end else if (VsfDynamicDark = nil) and (WizardDarkStyle = wdsDynamic) then begin
              TriggerOnUpdateIconsAndStyle(uisoWizardDarkStyle);
              { Dynamic without a custom dark style: make the built-in dark style the dark one }
              RenameResource(H, M, 'VCLSTYLE', WindowsModernDarkStyleName, 'MYSTYLE1_DARK');
            end else begin
              TriggerOnUpdateIconsAndStyle(uisoWizardDarkStyle);
              { Forced dark with a custom style: delete the built-in dark style
                Or, dynamic with a custom dark style: same
                Or, forced light with or without a custom style: same
                Note: forced light without a custom style doesn't actually use SetupCustomStyle.e32/64 at the moment so won't get here }
              DeleteResource(H, M, 'VCLSTYLE', WindowsModernDarkStyleName);
            end;

            { Delete additional styles - they are handled above. Stellar and
              Zircon are allowed to be missing to support the Community Edition. }
            DeleteResource(H, M, 'VCLSTYLE', 'WINDOWSMODERNLIGHT');
            DeleteResource(H, M, 'VCLSTYLE', 'WINDOWSPOLARLIGHT');
            DeleteResource(H, M, 'VCLSTYLE', 'WINDOWSPOLARDARK');
            DeleteResource(H, M, 'VCLSTYLE', 'SLATECLASSICO');
            DeleteResourceIfExists(H, M, 'VCLSTYLE', 'STELLAR');
            DeleteResourceIfExists(H, M, 'VCLSTYLE', 'ZIRCON');
          end;
        end;

        TriggerOnUpdateIconsAndStyle(uisoDone);
      finally
        FreeLibrary(M);
      end;
    except
      EndUpdateResource(H, True);  { discard changes }
      raise;
    end;
    if not EndUpdateResource(H, False) then
      if ChangedMainIcon then { Only allow errors (likely from faulty AV software) if the update actually is important }
        ResUpdateErrorWithLastError('EndUpdateResource failed, try excluding the Output folder from your antivirus software');
  finally
    if ShouldFreeVsfDynamicDark then
      FreeMem(VsfDynamicDark);
    if ShouldFreeVsf then
      FreeMem(Vsf);
    if Ico <> nil then
      FreeMem(Ico);
  end;
end;

{$ELSE}
type
  TPEResourceWriter = class(TCoffResourceWriter)
  public
    procedure WriteSection(const Resources: TResources; const Stream: TMemoryStream;
      const VirtualAddress: Cardinal; out DataOffset, DataSize: Cardinal);
  end;

procedure TPEResourceWriter.WriteSection(const Resources: TResources; const Stream: TMemoryStream;
  const VirtualAddress: Cardinal; out DataOffset, DataSize: Cardinal);
var
  Section: TImageSectionHeader;
  I: Integer;
  Offset, Address: Cardinal;
begin
  Resources.WriteToStream(Stream, Self);
  Stream.Position := SizeOf(TImageFileHeader);
  Stream.ReadBuffer(Section, SizeOf(Section));
  DataOffset := Section.PointerToRawData;
  DataSize := Section.SizeOfRawData;
  if (Int64(DataOffset) + DataSize > Stream.Size) or (DataSize < SizeOf(Address)) then
    Error('Invalid generated resource section');
  for I := 0 to fRelocations.Count - 1 do begin
    Offset := fRelocations[I]^.VirtualAddress;
    if Offset > DataSize - SizeOf(Address) then
      Error('Invalid generated resource relocation');
    Stream.Position := Int64(DataOffset) + Offset;
    Stream.ReadBuffer(Address, SizeOf(Address));
    if (Address >= DataSize) or (Address > High(Cardinal) - VirtualAddress) then
      Error('Invalid generated resource address');
    Inc(Address, VirtualAddress);
    Stream.Position := Int64(DataOffset) + Offset;
    Stream.WriteBuffer(Address, SizeOf(Address));
  end;
end;

procedure AppendPEResourceSection(const Filename: String; const Resources: TResources);
var
  F: TFile;
  Writer: TPEResourceWriter;
  Stream: TMemoryStream;
  Header: TImageFileHeader;
  Optional32: TImageOptionalHeader;
  Optional64: TImageOptionalHeader64;
  Section, NewSection: TImageSectionHeader;
  Directory: ^TDataDirectory;
  FileAlignment, SectionAlignment, HeaderSize, FirstRawOffset: Cardinal;
  HeaderOffset, NewHeaderOffset: Int64;
  VirtualEnd, NewImageSize: Int64;
  DataOffset, DataSize, ZeroCount: Cardinal;
  I: Integer;
  Zeros: TBytes;

  function Align(const Value: Int64; const Alignment: Cardinal): Cardinal;
  var
    Aligned: Int64;
  begin
    if (Alignment = 0) or (Alignment > 65536) or (Alignment and (Alignment - 1) <> 0) then
      Error('Invalid PE alignment');
    Aligned := (Value + Alignment - 1) and not Int64(Alignment - 1);
    if (Value < 0) or (Aligned > High(Cardinal)) then
      Error('PE resource section exceeds the image size limit');
    Result := Aligned;
  end;

begin
  { Resource streams may still read from the original file during the append }
  F := TFile.Create(Filename, fdOpenExisting, faReadWrite, fsRead);
  try
    if not SeekToPEHeader(F) then
      Error('Invalid PE header');
    HeaderOffset := F.Position;
    F.ReadBuffer(Header, SizeOf(Header));
    if Header.SizeOfOptionalHeader = SizeOf(Optional32) then begin
      F.ReadBuffer(Optional32, SizeOf(Optional32));
      if (Optional32.Magic <> IMAGE_NT_OPTIONAL_HDR32_MAGIC) or
         (Optional32.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_SECURITY) then
        Error('Invalid PE32 optional header');
      Directory := @Optional32.DataDirectory;
      FileAlignment := Optional32.FileAlignment;
      SectionAlignment := Optional32.SectionAlignment;
      HeaderSize := Optional32.SizeOfHeaders;
      VirtualEnd := Optional32.SizeOfImage;
    end else if Header.SizeOfOptionalHeader = SizeOf(Optional64) then begin
      F.ReadBuffer(Optional64, SizeOf(Optional64));
      if (Optional64.Magic <> IMAGE_NT_OPTIONAL_HDR64_MAGIC) or
         (Optional64.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_SECURITY) then
        Error('Invalid PE32+ optional header');
      Directory := @Optional64.DataDirectory;
      FileAlignment := Optional64.FileAlignment;
      SectionAlignment := Optional64.SectionAlignment;
      HeaderSize := Optional64.SizeOfHeaders;
      VirtualEnd := Optional64.SizeOfImage;
    end else
      Error('Unsupported PE optional header');
    if (Directory^[IMAGE_DIRECTORY_ENTRY_SECURITY].Size <> 0) or
       (Directory^[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress <> 0) then
      Error('Cannot replace resources in an Authenticode-signed template');

    FirstRawOffset := HeaderSize;
    for I := 1 to Header.NumberOfSections do begin
      F.ReadBuffer(Section, SizeOf(Section));
      if Section.SizeOfRawData <> 0 then
        FirstRawOffset := Min(FirstRawOffset, Section.PointerToRawData);
      VirtualEnd := Max(VirtualEnd, Int64(Section.VirtualAddress) +
        Max(Section.Misc.VirtualSize, Section.SizeOfRawData));
    end;
    NewHeaderOffset := F.Position;
    if (Header.NumberOfSections >= 96) or (NewHeaderOffset + SizeOf(NewSection) > FirstRawOffset) or
       (NewHeaderOffset + SizeOf(NewSection) > F.Size) then
      Error('PE has no room for an additional resource section header');

    NewSection := Default(TImageSectionHeader);
    Move(PAnsiChar(AnsiString('.innorsc'))^, NewSection.Name, SizeOf(NewSection.Name));
    NewSection.VirtualAddress := Align(VirtualEnd, SectionAlignment);
    NewSection.PointerToRawData := Align(F.Size, FileAlignment);
    NewSection.Characteristics := $40000040; { Readable initialized data }

    Writer := TPEResourceWriter.Create;
    try
      Stream := TMemoryStream.Create;
      try
        Writer.WriteSection(Resources, Stream, NewSection.VirtualAddress, DataOffset, DataSize);
        NewSection.Misc.VirtualSize := DataSize;
        NewSection.SizeOfRawData := Align(DataSize, FileAlignment);
        NewImageSize := Align(Int64(NewSection.VirtualAddress) +
          Max(DataSize, NewSection.SizeOfRawData), SectionAlignment);
        if Int64(NewSection.PointerToRawData) + NewSection.SizeOfRawData > High(Cardinal) then
          Error('PE resource section exceeds the file size limit');
        SetLength(Zeros, FileAlignment);
        ZeroCount := NewSection.PointerToRawData - F.Size;
        F.Seek(F.Size);
        if ZeroCount <> 0 then
          F.WriteBuffer(Zeros[0], ZeroCount);
        F.WriteBuffer((PByte(Stream.Memory) + DataOffset)^, DataSize);
        ZeroCount := NewSection.SizeOfRawData - DataSize;
        if ZeroCount <> 0 then
          F.WriteBuffer(Zeros[0], ZeroCount);
      finally
        Stream.Free;
      end;
    finally
      Writer.Free;
    end;

    Inc(Header.NumberOfSections);
    Directory^[IMAGE_DIRECTORY_ENTRY_RESOURCE].VirtualAddress := NewSection.VirtualAddress;
    Directory^[IMAGE_DIRECTORY_ENTRY_RESOURCE].Size := DataSize;
    F.Seek(HeaderOffset);
    F.WriteBuffer(Header, SizeOf(Header));
    if Header.SizeOfOptionalHeader = SizeOf(Optional32) then begin
      Optional32.SizeOfImage := NewImageSize;
      Inc(Optional32.SizeOfInitializedData, NewSection.SizeOfRawData);
      Optional32.CheckSum := 0;
      F.WriteBuffer(Optional32, SizeOf(Optional32));
    end else begin
      Optional64.SizeOfImage := NewImageSize;
      Inc(Optional64.SizeOfInitializedData, NewSection.SizeOfRawData);
      Optional64.CheckSum := 0;
      F.WriteBuffer(Optional64, SizeOf(Optional64));
    end;
    F.Seek(NewHeaderOffset);
    F.WriteBuffer(NewSection, SizeOf(NewSection));
  finally
    F.Free;
  end;
end;

type
  TResourceInputStream = class(THandleStream)
  private
    FFile: TFile;
  public
    constructor Create(const Filename: String; const Sharing: TFileSharing);
    destructor Destroy; override;
  end;

constructor TResourceInputStream.Create(const Filename: String; const Sharing: TFileSharing);
begin
  FFile := TFile.Create(Filename, fdOpenExisting, faRead, Sharing);
  inherited Create(FFile.Handle);
end;

destructor TResourceInputStream.Destroy;
begin
  FFile.Free;
  inherited;
end;

procedure RebuildPEIconsAndStyles(const Filename, IconFilename, StyleFilename, DarkStyleFilename: String;
  const Uisf: TUpdateIconsAndStyleFile; const WizardDarkStyle: TSetupWizardDarkStyle;
  const OnUpdateIconsAndStyle: TOnUpdateIconsAndStyle);
const
  IconType = 3;
  GroupIconType = 14;
  Language = 1033;
type
  TIcoHeader = packed record
    Reserved, Kind, Count: Word;
  end;
  TIcoEntry = packed record
    Width, Height, Colors, Reserved: Byte;
    Planes, BitCount: Word;
    Size, Offset: Cardinal;
  end;
var
  Input, Icon: TStream;
  Reader: TWinPEImageResourceReader;
  Resources, Original: TResources;
  Header: TIcoHeader;
  Entries: array of TIcoEntry;
  Entry: TIcoEntry;
  Group, Image, Existing: TAbstractResource;
  TypeDesc, NameDesc: TResourceDesc;
  ImageId: Word;
  UsedIds: array[Word] of Boolean;
  I: Integer;
  Name, UnusedGroup: String;

  function AddResource(const ResourceType, ResourceName: TResourceDesc; const LangId: Word): TAbstractResource;
  begin
    Result := TGenericResource.Create(ResourceType, ResourceName);
    try
      Result.LangID := LangId;
      Resources.Add(Result);
    except
      Result.Free;
      raise;
    end;
  end;

  function FindBuiltinStyle(const Preset: String; const Dark: Boolean): TAbstractResource;
  var
    PrimaryName, FallbackName: String;
    Candidate: TAbstractResource;
    Index: Integer;
    CandidateName: String;
  begin
    FallbackName := '';
    if InnoSameText(Preset, 'builtin:polar') then begin
      if Dark then
        PrimaryName := 'WINDOWSPOLARDARK'
      else
        PrimaryName := 'WINDOWSPOLARLIGHT';
    end else if InnoSameText(Preset, 'builtin:windows11') then begin
      if Dark then begin
        PrimaryName := 'WINDOWSMODERNDARKSE';
        FallbackName := 'WINDOWSMODERNDARK';
      end else
        PrimaryName := 'WINDOWSMODERNLIGHT';
    end else if InnoSameText(Preset, 'builtin:slate') then
      PrimaryName := 'SLATECLASSICO'
    else if InnoSameText(Preset, 'builtin:stellar') then
      PrimaryName := 'STELLAR'
    else if InnoSameText(Preset, 'builtin:zircon') then
      PrimaryName := 'ZIRCON'
    else
      Error('Unknown built-in wizard style: ' + Preset);

    Result := nil;
    for Index := 0 to Integer(Original.Count) - 1 do begin
      Candidate := Original[Index];
      if (Candidate._Type.DescType <> dtName) or (FromNativeText(Candidate._Type.Name) <> ('VCLSTYLE')) or
         (Candidate.Name.DescType <> dtName) then
        Continue;
      CandidateName := UTF8Decode(Candidate.Name.Name);
      if CandidateName = PrimaryName then
        Exit(Candidate);
      if (FallbackName <> '') and (CandidateName = FallbackName) then
        Result := Candidate;
    end;
    if Result = nil then
      Error('Built-in wizard style resource is unavailable: ' + Preset);
  end;

  procedure AddStyle(const StylePath, ResourceName: String; const Dark: Boolean;
    const Operation: TUpdateIconsAndStyleOperation);
  var
    InputStyle, OwnedStyle: TStream;
    StyleType, StyleName: TResourceDesc;
    StyleResource: TAbstractResource;
  begin
    if StylePath = '' then
      Exit;
    if Assigned(OnUpdateIconsAndStyle) then
      OnUpdateIconsAndStyle(Operation);
    OwnedStyle := nil;
    if Pos('builtin:', LowerCase(StylePath)) = 1 then
      InputStyle := FindBuiltinStyle(StylePath, Dark).RawData
    else begin
      OwnedStyle := TResourceInputStream.Create(StylePath, fsRead);
      InputStyle := OwnedStyle;
    end;
    try
      if (InputStyle.Size = 0) or (InputStyle.Size > High(Integer)) then
        Error('Invalid wizard style file size');
      StyleType := TResourceDesc.Create('VCLSTYLE');
      try
        StyleName := TResourceDesc.Create(UTF8Encode(ResourceName));
        try
          StyleResource := AddResource(StyleType, StyleName, Language);
          InputStyle.Position := 0;
          StyleResource.RawData.CopyFrom(InputStyle, InputStyle.Size);
        finally
          StyleName.Free;
        end;
      finally
        StyleType.Free;
      end;
    finally
      OwnedStyle.Free;
    end;
  end;

begin
  Icon := nil;
  try
    if IconFilename <> '' then begin
      if Assigned(OnUpdateIconsAndStyle) then
        OnUpdateIconsAndStyle(uisoIcoFileName);
      Icon := TResourceInputStream.Create(IconFilename, fsRead);
      Icon.ReadBuffer(Header, SizeOf(Header));
      if (Header.Reserved <> 0) or (Header.Kind <> 1) or (Header.Count = 0) or
         (Int64(Header.Count) * SizeOf(Entry) > Icon.Size - SizeOf(Header)) then
        Error('Invalid ICO header');
      SetLength(Entries, Header.Count);
      Icon.ReadBuffer(Entries[0], Length(Entries) * SizeOf(Entry));
      for Entry in Entries do
        if (Entry.Size = 0) or (Entry.Offset < SizeOf(Header) + Length(Entries) * SizeOf(Entry)) or
           (Int64(Entry.Offset) + Entry.Size > Icon.Size) then
          Error('Invalid ICO image bounds');
    end;

    Input := TResourceInputStream.Create(Filename, fsReadWrite);
    try
      Original := TResources.Create;
      try
        Reader := TWinPEImageResourceReader.Create;
        try
          Original.LoadFromStream(Input, Reader);
        finally
          Reader.Free;
        end;
        Resources := TResources.Create;
        try
          FillChar(UsedIds, SizeOf(UsedIds), 0);
          UnusedGroup := '';
          if WizardDarkStyle = wdsLight then
            UnusedGroup := 'Z_GROUPICON_DARK'
          else if WizardDarkStyle = wdsDark then
            UnusedGroup := 'Z_GROUPICON';
          for I := 0 to Integer(Original.Count) - 1 do begin
            Existing := Original[I];
            if ((StyleFilename <> '') or (DarkStyleFilename <> '')) and
               (Existing._Type.DescType = dtName) and (FromNativeText(Existing._Type.Name) = ('VCLSTYLE')) then begin
              if (Existing.Name.DescType <> dtName) or
                 ((FromNativeText(Existing.Name.Name) <> ('MYSTYLE1')) and (FromNativeText(Existing.Name.Name) <> ('MYSTYLE1_DARK'))) or
                 ((FromNativeText(Existing.Name.Name) = ('MYSTYLE1')) and (StyleFilename <> '')) or
                 ((FromNativeText(Existing.Name.Name) = ('MYSTYLE1_DARK')) and (DarkStyleFilename <> '')) then
                Continue;
            end;
            if (Icon <> nil) and (Existing._Type.DescType = dtID) and
               (Existing._Type.ID = GroupIconType) and
               (Existing.Name.DescType = dtName) then begin
              Name := UTF8Decode(Existing.Name.Name);
              if (Name = 'MAINICON') or (Name = 'MAINICON_DARK') or
                 ((Uisf = uisfSetup) and ((Name = 'Z_UNINSTALLICON') or
                  (Name = 'Z_UNINSTALLICON_DARK') or (Name = UnusedGroup))) then
                Continue;
            end;
            if (Existing._Type.DescType = dtID) and (Existing._Type.ID = IconType) and
               (Existing.Name.DescType = dtID) and (Existing.Name.ID <= High(Word)) then
              UsedIds[Existing.Name.ID] := True;
            Image := AddResource(Existing._Type, Existing.Name, Existing.LangID);
            Image.CodePage := Existing.CodePage;
            if Existing.DataSize <> 0 then begin
              Existing.RawData.Position := 0;
              Image.RawData.CopyFrom(Existing.RawData, Existing.DataSize);
            end;
          end;

          if Icon <> nil then begin
            TypeDesc := TResourceDesc.Create(TResID(GroupIconType));
            try
              NameDesc := TResourceDesc.Create('MAINICON');
              try
                Group := AddResource(TypeDesc, NameDesc, Language);
                Group.RawData.WriteBuffer(Header, SizeOf(Header));
                TypeDesc.ID := IconType;
                ImageId := 0;
                for Entry in Entries do begin
                  repeat
                    if ImageId = High(Word) then
                      Error('No unused PE icon resource IDs');
                    Inc(ImageId);
                  until not UsedIds[ImageId];
                  NameDesc.ID := ImageId;
                  Image := AddResource(TypeDesc, NameDesc, Language);
                  Icon.Position := Entry.Offset;
                  Image.RawData.CopyFrom(Icon, Entry.Size);
                  Group.RawData.WriteBuffer(Entry, SizeOf(Entry) - SizeOf(Entry.Offset));
                  Group.RawData.WriteBuffer(ImageId, SizeOf(ImageId));
                end;
              finally
                NameDesc.Free;
              end;
            finally
              TypeDesc.Free;
            end;
          end;
          AddStyle(StyleFilename, 'MYSTYLE1', WizardDarkStyle = wdsDark, uisoStyleFileName);
          AddStyle(DarkStyleFilename, 'MYSTYLE1_DARK', True, uisoStyleFileNameDynamicDark);
          AppendPEResourceSection(Filename, Resources);
        finally
          Resources.Free;
        end;
      finally
        Original.Free;
      end;
    finally
      Input.Free;
    end;
  finally
    Icon.Free;
  end;
end;

procedure UpdateIconsAndStyle(const FileName: String; const Uisf: TUpdateIconsAndStyleFile; const IcoFileName: String;
  const WizardDarkStyle: TSetupWizardDarkStyle; const StyleFileName, StyleFileNameDynamicDark: String;
  const OnUpdateIconsAndStyle: TOnUpdateIconsAndStyle);
const
  GroupIconType = 14;
  SubdirectoryFlag = Cardinal($80000000);
type
  PDirectory = ^TImageResourceDirectory;
  PEntry = ^TImageResourceDirectoryEntry;
var
  F: TFile;
  SectionRVA, SectionOffset, SectionSize, GroupOffset: Cardinal;
  Section: TBytes;
  Group: PDirectory;
  Main, Dark: Integer;
  Suffix: String;

  procedure Notify(const Operation: TUpdateIconsAndStyleOperation);
  begin
    if Assigned(OnUpdateIconsAndStyle) then
      OnUpdateIconsAndStyle(Operation);
  end;

  function GroupEntry(const Index: Integer): PEntry;
  begin
    Result := PEntry(PByte(Group) + SizeOf(TImageResourceDirectory) + Index * SizeOf(TImageResourceDirectoryEntry));
  end;

  function FindGroup(const Name: String): Integer;
  var
    I: Integer;
    NameOffset: Cardinal;
    NameLength: Word;
  begin
    for I := 0 to Group^.NumberOfNamedEntries - 1 do begin
      NameOffset := GroupEntry(I)^.Id;
      if NameOffset and SubdirectoryFlag = 0 then
        Error('Invalid icon group name');
      NameOffset := NameOffset and not SubdirectoryFlag;
      if Int64(NameOffset) + SizeOf(NameLength) > SectionSize then
        Error('Truncated icon group name');
      Move(Section[NameOffset], NameLength, SizeOf(NameLength));
      Inc(NameOffset, SizeOf(NameLength));
      if Int64(NameOffset) + Int64(NameLength) * SizeOf(WideChar) > SectionSize then
        Error('Truncated icon group name');
      if (NameLength = Length(Name)) and
         CompareMem(Pointer(Name), @Section[NameOffset], NameLength * SizeOf(WideChar)) then
        Exit(I);
    end;
    Result := -1;
  end;

  procedure RemoveGroup(const Index: Integer);
  var
    Remaining: Integer;
  begin
    if Index < 0 then
      Exit;
    Remaining := Integer(Group^.NumberOfNamedEntries) + Group^.NumberOfIdEntries - Index - 1;
    if Remaining > 0 then
      Move(GroupEntry(Index + 1)^, GroupEntry(Index)^, Remaining * SizeOf(TImageResourceDirectoryEntry));
    Dec(Group^.NumberOfNamedEntries);
  end;

begin
  if (IcoFileName = '') and (WizardDarkStyle <> wdsDynamic) then begin
    Notify(uisoWizardDarkStyle);
    F := TFile.Create(FileName, fdOpenExisting, faReadWrite, fsNone);
    try
      FindResourceSection(F, SectionRVA, SectionOffset, SectionSize);
      F.Seek(SectionOffset);
      if not FindResOffset(F, Int64(SectionOffset) + SectionSize, False,
        GroupIconType, True, GroupOffset) then
        Error('No icon groups');
      if Int64(GroupOffset) + SizeOf(TImageResourceDirectory) > SectionSize then
        Error('Truncated icon group directory');
      SetLength(Section, SectionSize);
      F.Seek(SectionOffset);
      F.ReadBuffer(Section[0], SectionSize);
      Group := PDirectory(@Section[GroupOffset]);
      if Int64(GroupOffset) + SizeOf(TImageResourceDirectory) +
         (Integer(Group^.NumberOfNamedEntries) + Group^.NumberOfIdEntries) *
         SizeOf(TImageResourceDirectoryEntry) > SectionSize then
        Error('Truncated icon group entries');

      Dark := FindGroup('MAINICON_DARK');
      if WizardDarkStyle = wdsDark then begin
        Main := FindGroup('MAINICON');
        if (Main < 0) or (Dark < 0) then
          Error('Missing light or dark main icon');
        GroupEntry(Main)^.Offset := GroupEntry(Dark)^.Offset;
      end;
      RemoveGroup(Dark);

      if Uisf = uisfSetup then begin
        Suffix := '';
        if WizardDarkStyle = wdsLight then
          Suffix := '_DARK';
        RemoveGroup(FindGroup('Z_GROUPICON' + Suffix));
        RemoveGroup(FindGroup('Z_UNINSTALLICON' + Suffix));
      end;

      F.Seek(SectionOffset);
      F.WriteBuffer(Section[0], SectionSize);
    finally
      F.Free;
    end;
  end;
  if (IcoFileName <> '') or (StyleFileName <> '') or (StyleFileNameDynamicDark <> '') then
    RebuildPEIconsAndStyles(Filename, IcoFileName, StyleFileName, StyleFileNameDynamicDark,
      Uisf, WizardDarkStyle, OnUpdateIconsAndStyle);
  Notify(uisoDone);
end;

{$ENDIF}

end.
