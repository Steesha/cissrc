unit Shared.FileClass;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  TFile class
  Better than File and TFileStream in that does more extensive error checking
  and uses descriptive, localized system error messages.

  TTextFileReader and TTextFileWriter support ANSI and UTF8 textfiles.
}

interface

uses
  {$IFDEF UNIX} Shared.PlatformTypes, {$ELSE} Windows, {$ENDIF} SysUtils, Shared.FPCStringUtils;

type
  TFileCreateDisposition = (fdCreateAlways, fdCreateNew, fdOpenExisting,
    fdOpenAlways, fdTruncateExisting);
  TFileAccess = (faRead, faWrite, faReadWrite);
  TFileSharing = (fsNone, fsRead, fsWrite, fsReadWrite);

  TCustomFile = class
  private
    function GetCappedSize: Cardinal;
  protected
    function GetPosition: Int64; virtual; abstract;
    function GetSize: Int64; virtual; abstract;
  public
    class procedure RaiseError(ErrorCode: DWORD); static;
    class procedure RaiseLastError; static;
    function Read(var Buffer; Count: Cardinal): Cardinal; virtual; abstract;
    procedure ReadBuffer(var Buffer; Count: Cardinal);
    procedure Seek(Offset: Int64); virtual; abstract;
    procedure WriteAnsiString(const S: AnsiString);
    procedure WriteBuffer(const Buffer; Count: Cardinal); virtual; abstract;
    property CappedSize: Cardinal read GetCappedSize;
    property Position: Int64 read GetPosition;
    property Size: Int64 read GetSize;
  end;

  TFile = class(TCustomFile)
  private
    FHandle: THandle;
    FHandleCreated: Boolean;
    function GetCanSeek: Boolean;
  protected
    function CreateHandle(const AFilename: String;
      ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
      ASharing: TFileSharing): THandle; virtual;
    function GetPosition: Int64; override;
    property CanSeek: Boolean read GetCanSeek;
    function GetSize: Int64; override;
  public
    constructor Create(const AFilename: String;
      ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
      ASharing: TFileSharing);
    constructor CreateDuplicate(const ASourceFile: TFile);
    constructor CreateWithExistingHandle(const AHandle: THandle);
    destructor Destroy; override;
    function Read(var Buffer; Count: Cardinal): Cardinal; override;
    procedure Seek(Offset: Int64); override;
    procedure SeekToEnd;
    procedure Truncate;
    procedure WriteBuffer(const Buffer; Count: Cardinal); override;
    property Handle: THandle read FHandle;
  end;

  TMemoryFile = class(TCustomFile)
  private
    FMemory: Pointer;
    FSize: Cardinal;
    FPosition: Int64;
    function ClipCount(DesiredCount: Cardinal): Cardinal;
  protected
    procedure AllocMemory(const ASize: Cardinal);
    function GetPosition: Int64; override;
    function GetSize: Int64; override;
  public
    constructor Create(const AFilename: String);
    constructor CreateFromMemory(const ASource; const ASize: Cardinal);
    destructor Destroy; override;
    function Read(var Buffer; Count: Cardinal): Cardinal; override;
    procedure Seek(Offset: Int64); override;
    procedure WriteBuffer(const Buffer; Count: Cardinal); override;
    property Memory: Pointer read FMemory;
  end;

  TTextFileReader = class(TFile)
  private
    FBufferOffset, FBufferSize: Cardinal;
    FEof: Boolean;
    FAllowInvalidChars: Boolean;
    FBuffer: array[0..4095] of AnsiChar;
    FSawFirstLine: Boolean;
    FCodePage: Word;
    function GetCanDetectUTF8WithoutBOM: Boolean;
    function GetEof: Boolean;
    procedure FillBuffer;
  public
    function ReadLine: String;
    property AllowInvalidChars: Boolean read FAllowInvalidChars write FAllowInvalidChars;
    property CanDetectUTF8WithoutBOM: Boolean read GetCanDetectUTF8WithoutBOM;
    property CodePage: Word read FCodePage write FCodePage;
    property Eof: Boolean read GetEof;
  end;

  TTextFileWriter = class(TFile)
  private
    FSeekedToEnd: Boolean;
    FUTF8WithoutBOM: Boolean;
    procedure DoWrite(const S: RawByteString; const UTF8: Boolean);
  protected
    function CreateHandle(const AFilename: String;
      ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
      ASharing: TFileSharing): THandle; override;
  public
    property UTF8WithoutBOM: Boolean read FUTF8WithoutBOM write FUTF8WithoutBOM;
    procedure Write(const S: String);
    procedure WriteLine(const S: String);
    procedure WriteAnsi(const S: AnsiString);
    procedure WriteAnsiLine(const S: AnsiString);
  end;

  EFileError = class(Exception)
  private
    FErrorCode: DWORD;
  public
    property ErrorCode: DWORD read FErrorCode write FErrorCode;
  end;

type
  TDetectedEncoding = (etUSASCII, etUTF8, etOther);

function DetectUTF8Encoding(const S: AnsiString): TDetectedEncoding;

implementation

uses
  {$IFDEF UNIX} BaseUnix, {$ENDIF}
  UnsignedFunc;

{$IF Defined(FPC) and Defined(MSWINDOWS)}
function SetFilePointerEx(hFile: THandle; Distance: Int64; NewPosition: PInt64;
  MoveMethod: DWORD): BOOL; stdcall; external kernel32 name 'SetFilePointerEx';
function GetFileSizeEx(hFile: THandle; out FileSize: Int64): BOOL;
  stdcall; external kernel32 name 'GetFileSizeEx';
{$IFEND}

const
  SGenericIOError = 'File I/O error %d';
  {$IFDEF UNIX}
  ERROR_HANDLE_EOF = 38;
  ERROR_NEGATIVE_SEEK = 131;
  ERROR_WRITE_FAULT = 29;
  ERROR_NO_UNICODE_TRANSLATION = 1113;
  CP_UTF8 = 65001;
  {$ENDIF}

function DetectUTF8Encoding(const S: AnsiString): TDetectedEncoding;
var
  I, J, Extra: Integer;
  C, Minimum: Cardinal;
begin
  Result := etUSASCII;
  I := 1;
  while I <= Length(S) do begin
    C := Byte(S[I]);
    Inc(I);
    if C < $80 then
      Continue;
    Result := etUTF8;
    if (C >= $c2) and (C <= $df) then begin
      Extra := 1; Minimum := $80; C := C and $1f;
    end else if (C >= $e0) and (C <= $ef) then begin
      Extra := 2; Minimum := $800; C := C and $f;
    end else if (C >= $f0) and (C <= $f4) then begin
      Extra := 3; Minimum := $10000; C := C and $7;
    end else
      Exit(etOther);
    if Length(S) - I + 1 < Extra then
      Exit(etOther);
    for J := 1 to Extra do begin
      if (Byte(S[I]) and $c0) <> $80 then
        Exit(etOther);
      C := (C shl 6) or (Byte(S[I]) and $3f);
      Inc(I);
    end;
    if (C < Minimum) or (C > $10ffff) or ((C >= $d800) and (C <= $dfff)) then
      Exit(etOther);
  end;
end;

function FileErrorMessage(const ErrorCode: DWORD): String;
{$IFNDEF UNIX}
var
  Buffer: array[0..1023] of Char;
  Len: Cardinal;
{$ENDIF}
begin
  {$IFDEF UNIX}
  case ErrorCode of
    ERROR_HANDLE_EOF: Result := 'Reached end of file';
    ERROR_NEGATIVE_SEEK: Result := 'Cannot seek to a negative position';
    ERROR_WRITE_FAULT: Result := 'Cannot write to the file';
    ERROR_NO_UNICODE_TRANSLATION: Result := 'Invalid character encoding';
  else
    Result := InnoFormat(SGenericIOError, [ErrorCode]);
  end;
  {$ELSE}
  Len := FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM or
    FORMAT_MESSAGE_IGNORE_INSERTS or FORMAT_MESSAGE_ARGUMENT_ARRAY, nil,
    ErrorCode, 0, PWideChar(@Buffer[0]), Length(Buffer), nil);
  while (Len > 0) and ((Buffer[Len-1] <= ' ') or (Buffer[Len-1] = '.')) do
    Dec(Len);
  SetString(Result, Buffer, Len);
  {$ENDIF}
end;

{ TCustomFile }

function TCustomFile.GetCappedSize: Cardinal;
{ Like GetSize, but capped at $7FFFFFFF }
var
  LSize: Int64;
begin
  LSize := GetSize;
  if LSize > High(Int32) then
    Result := High(Int32)
  else
    Result := Cardinal(LSize);
end;

class procedure TCustomFile.RaiseError(ErrorCode: DWORD);
var
  S: String;
  E: EFileError;
begin
  S := FileErrorMessage(ErrorCode);
  if Length(S) = 0 then begin
    { In case there was no text for the error code. Shouldn't get here under
      normal circumstances. }
    S := InnoFormat(SGenericIOError, [ErrorCode]);
  end;
  E := EFileError.Create(ToNativeText(S));
  E.FErrorCode := ErrorCode;
  raise E;
end;

class procedure TCustomFile.RaiseLastError;
{$IFDEF UNIX}
var
  Code: Integer;
  E: EFileError;
{$ENDIF}
begin
  {$IFDEF UNIX}
  Code := fpGetErrNo;
  E := EFileError.Create(SysErrorMessage(Code));
  case Code of
    ESysENOENT: E.ErrorCode := 2;
    ESysENOTDIR: E.ErrorCode := 3;
    ESysEACCES, ESysEPERM, ESysEISDIR: E.ErrorCode := 5;
    ESysEBADF: E.ErrorCode := 6;
    ESysEROFS: E.ErrorCode := 19;
    ESysENOSPC: E.ErrorCode := 112;
    ESysEEXIST: E.ErrorCode := 183;
    ESysEBUSY, ESysETXTBSY, ESysEAGAIN: E.ErrorCode := 32;
  else
    E.ErrorCode := 31;
  end;
  raise E;
  {$ELSE}
  RaiseError(GetLastError);
  {$ENDIF}
end;

procedure TCustomFile.ReadBuffer(var Buffer; Count: Cardinal);
var
  Destination: PByte;
  BytesRead: Cardinal;
begin
  Destination := @Buffer;
  while Count > 0 do begin
    BytesRead := Read(Destination^, Count);
    if BytesRead = 0 then
      RaiseError(ERROR_HANDLE_EOF);
    Inc(Destination, BytesRead);
    Dec(Count, BytesRead);
  end;
end;

procedure TCustomFile.WriteAnsiString(const S: AnsiString);
begin
  if Length(S) > 0 then
    WriteBuffer(S[1], ULength(S));
end;

{$IFDEF UNIX}
{$I Shared.FileClass.Native.inc}
{$ELSE}
{ TFile }

constructor TFile.Create(const AFilename: String;
  ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
  ASharing: TFileSharing);
begin
  inherited Create;
  FHandle := CreateHandle(AFilename, ACreateDisposition, AAccess, ASharing);
  if (FHandle = 0) or (FHandle = INVALID_HANDLE_VALUE) then
    RaiseLastError;
  FHandleCreated := True;
end;

constructor TFile.CreateDuplicate(const ASourceFile: TFile);
var
  LHandle: THandle;
begin
  inherited Create;
  if not DuplicateHandle(GetCurrentProcess, ASourceFile.Handle,
     GetCurrentProcess, @LHandle, 0, False, DUPLICATE_SAME_ACCESS) then
    RaiseLastError;
  FHandle := LHandle;  { assign only on success }
  FHandleCreated := True;
end;

constructor TFile.CreateWithExistingHandle(const AHandle: THandle);
begin
  inherited Create;
  FHandle := AHandle;
end;

destructor TFile.Destroy;
begin
  if FHandleCreated then
    CloseHandle(FHandle);
  inherited;
end;

function TFile.CreateHandle(const AFilename: String;
  ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
  ASharing: TFileSharing): THandle;
const
  AccessFlags: array[TFileAccess] of DWORD =
    (GENERIC_READ, GENERIC_WRITE, GENERIC_READ or GENERIC_WRITE);
  SharingFlags: array[TFileSharing] of DWORD =
    (0, FILE_SHARE_READ, FILE_SHARE_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE);
  Disps: array[TFileCreateDisposition] of DWORD =
    (CREATE_ALWAYS, CREATE_NEW, OPEN_EXISTING, OPEN_ALWAYS, TRUNCATE_EXISTING);
begin
  Result := CreateFileW(PWideChar(AFilename), AccessFlags[AAccess],
    SharingFlags[ASharing], nil, Disps[ACreateDisposition],
    FILE_ATTRIBUTE_NORMAL, 0);
end;

function TFile.GetPosition: Int64;
begin
  if not SetFilePointerEx(FHandle, 0, @Result, FILE_CURRENT) then
    RaiseLastError;
end;

function TFile.GetCanSeek: Boolean;
var
  FileType: DWORD;
begin
  { Seek/GetPosition use SetFilePointerEx, which requires a GetFileType check first, see
    https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfilepointerex }
  FileType := GetFileType(FHandle);
  if (FileType = FILE_TYPE_UNKNOWN) and (GetLastError <> NO_ERROR) then
    RaiseLastError;
  Result := (FileType = FILE_TYPE_DISK);
end;

function TFile.GetSize: Int64;
begin
  if not GetFileSizeEx(FHandle, Result) then
    RaiseLastError;
end;

function TFile.Read(var Buffer; Count: Cardinal): Cardinal;
begin
  if not ReadFile(FHandle, Buffer, Count, DWORD(Result), nil) then
    if FHandleCreated or (GetLastError <> ERROR_BROKEN_PIPE) then
      RaiseLastError;
end;

procedure TFile.Seek(Offset: Int64);
begin
  if not SetFilePointerEx(FHandle, Offset, nil, FILE_BEGIN) then
    RaiseLastError;
end;

procedure TFile.SeekToEnd;
begin
  if not SetFilePointerEx(FHandle, 0, nil, FILE_END) then
    RaiseLastError;
end;

procedure TFile.Truncate;
begin
  if not SetEndOfFile(FHandle) then
    RaiseLastError;
end;

procedure TFile.WriteBuffer(const Buffer; Count: Cardinal);
var
  BytesWritten: DWORD;
begin
  if not WriteFile(FHandle, Buffer, Count, BytesWritten, nil) then
    RaiseLastError;
  if BytesWritten <> Count then begin
    { I'm not aware of any case where WriteFile will return True but a short
      BytesWritten count. (An out-of-disk-space condition causes False to be
      returned.) But if that does happen, raise a generic-sounding localized
      "The system cannot write to the specified device" error. }
    RaiseError(ERROR_WRITE_FAULT);
  end;
end;

{$ENDIF}

{ TMemoryFile }

constructor TMemoryFile.Create(const AFilename: String);
var
  F: TFile;
begin
  inherited Create;
  F := TFile.Create(AFilename, fdOpenExisting, faRead, fsRead);
  try
    AllocMemory(F.CappedSize);
    F.ReadBuffer(FMemory^, FSize);
  finally
    F.Free;
  end;
end;

constructor TMemoryFile.CreateFromMemory(const ASource; const ASize: Cardinal);
begin
  inherited Create;
  AllocMemory(ASize);
  UMove(ASource, FMemory^, FSize);
end;

destructor TMemoryFile.Destroy;
begin
  if Assigned(FMemory) then
    FreeMem(FMemory);
  inherited;
end;

procedure TMemoryFile.AllocMemory(const ASize: Cardinal);
begin
  if ASize = 0 then
    GetMem(FMemory, 1)
  else
    GetMem(FMemory, ASize);
  if FMemory = nil then
    OutOfMemoryError;
  FSize := ASize;
end;

function TMemoryFile.ClipCount(DesiredCount: Cardinal): Cardinal;
var
  BytesLeft: Cardinal;
begin
  { First check if FPosition is already past FSize, so the subtraction below
    won't underflow. And to be extra safe, make sure FPosition isn't negative
    (even though Seek already checks for that). }
  if FPosition >= FSize then begin
    Result := 0;
    Exit;
  end;
  if FPosition < 0 then
    RaiseError(ERROR_NEGATIVE_SEEK);

  BytesLeft := FSize - Cardinal(FPosition);
  if DesiredCount > BytesLeft then
    Result := BytesLeft
  else
    Result := DesiredCount;
end;

function TMemoryFile.GetPosition: Int64;
begin
  Result := FPosition;
end;

function TMemoryFile.GetSize: Int64;
begin
  Result := FSize;
end;

function TMemoryFile.Read(var Buffer; Count: Cardinal): Cardinal;
begin
  Result := ClipCount(Count);
  if Result <> 0 then begin
    UMove((PByte(FMemory) + Cardinal(FPosition))^, Buffer, Result);
    Inc(FPosition, Result);
  end;
end;

procedure TMemoryFile.Seek(Offset: Int64);
begin
  if Offset < 0 then
    RaiseError(ERROR_NEGATIVE_SEEK);
  FPosition := Offset;
end;

procedure TMemoryFile.WriteBuffer(const Buffer; Count: Cardinal);
begin
  if ClipCount(Count) <> Count then
    RaiseError(ERROR_HANDLE_EOF);
  if Count <> 0 then begin
    UMove(Buffer, (PByte(FMemory) + Cardinal(FPosition))^, Count);
    Inc(FPosition, Count);
  end;
end;

{ TTextFileReader }

procedure TTextFileReader.FillBuffer;
begin
  if (FBufferOffset < FBufferSize) or FEof then
    Exit;
  FBufferSize := Read(FBuffer, SizeOf(FBuffer));
  FBufferOffset := 0;
  if FBufferSize = 0 then
    FEof := True;
end;

function TTextFileReader.GetCanDetectUTF8WithoutBOM: Boolean;
begin
  { DoReadLine requires Seek support to detect BOM-less UTF-8 }
  Result := CanSeek;
end;

function TTextFileReader.GetEof: Boolean;
begin
  FillBuffer;
  Result := FEof;
end;

function TTextFileReader.ReadLine: String;
var
  SrcStr: AnsiString;
  {$IFDEF UNIX}
  Encoded: RawByteString;
  {$ELSE}
  MBFlags: DWORD;
  DestLen, WrittenLen: Integer;
  DestStr: UnicodeString;
  {$ENDIF}

  function DoReadLine: AnsiString;
  var
    I, L: Cardinal;
    S, S2: AnsiString;
    OldPosition: Int64;
    CappedSize: Cardinal;
  begin
    S := '';
    while True do begin
      FillBuffer;
      if FEof then begin
        { End of file reached }
        if Length(S) = 0 then begin
          { If nothing was read (i.e. we were already at EOF), raise localized
            "Reached end of file" error }
          RaiseError(ERROR_HANDLE_EOF);
        end;
        Break;
      end;

      I := FBufferOffset;
      while I < FBufferSize do begin
        if FBuffer[I] in [#10, #13] then
          Break;
        Inc(I);
      end;
      L := ULength(S);
      if Integer(L + (I - FBufferOffset)) < 0 then
        OutOfMemoryError;
      SetLength(S, L + (I - FBufferOffset));
      if I > FBufferOffset then
        UMove(FBuffer[FBufferOffset], S[L+1], I - FBufferOffset);
      FBufferOffset := I;

      if FBufferOffset < FBufferSize then begin
        { End of line reached }
        Inc(FBufferOffset);
        if FBuffer[FBufferOffset-1] = #13 then begin
          { Skip #10 if it follows #13 }
          FillBuffer;
          if (FBufferOffset < FBufferSize) and (FBuffer[FBufferOffset] = #10) then
            Inc(FBufferOffset);
        end;
        Break;
      end;
    end;

    if not FSawFirstLine then begin
      { Check for a UTF8 BOM at the start and if not found then check entire file }
      if (Length(S) > 2) and (Ord(S[1]) = $EF) and (Ord(S[2]) = $BB) and (Ord(S[3]) = $BF) then begin
        Delete(S, 1, 3);
        FCodePage := CP_UTF8;
      end else if CanSeek then begin
        { Detect BOM-less UTF8, also see GetCanDetectUTF8WithoutBOM }
        OldPosition := GetPosition;
        try
          CappedSize := GetCappedSize; //can't be 0
          Seek(0);
          SetLength(S2, CappedSize);
          SetLength(S2, Read(S2[1], CappedSize));
          if DetectUTF8Encoding(S2) in [etUSASCII, etUTF8] then
            FCodePage := CP_UTF8;
        finally
          Seek(OldPosition);
        end;
      end;
      FSawFirstLine := True;
    end;

    Result := S;
  end;

begin
  SrcStr := DoReadLine;
  if Length(SrcStr) = 0 then
    Exit('');

  {$IFDEF UNIX}
  if FCodePage = CP_UTF8 then begin
    if not FAllowInvalidChars and (DetectUTF8Encoding(SrcStr) = etOther) then
      RaiseError(ERROR_NO_UNICODE_TRANSLATION);
    Result := UTF8Decode(SrcStr);
  end else begin
    Encoded := SrcStr;
    if FCodePage = 0 then
      SetCodePage(Encoded, 1252, False)
    else
      SetCodePage(Encoded, FCodePage, False);
    Result := UnicodeString(Encoded);
  end;
  {$ELSE}
  MBFlags := MB_ERR_INVALID_CHARS;
  if FAllowInvalidChars then
    MBFlags := 0;

  DestLen := MultiByteToWideChar(FCodePage, MBFlags, Pointer(SrcStr),
    Length(SrcStr), nil, 0);
  if DestLen = 0 then
    RaiseLastError;
  { Return value should never be negative, but check anyway }
  if DestLen < 0 then
    RaiseError(ERROR_NO_UNICODE_TRANSLATION);

  SetLength(DestStr, DestLen);
  WrittenLen := MultiByteToWideChar(FCodePage, MBFlags, Pointer(SrcStr),
    Length(SrcStr), Pointer(DestStr), DestLen);
  { Return value should always be the same as the first call }
  if WrittenLen = 0 then
    RaiseLastError;
  if WrittenLen <> DestLen then
    RaiseError(ERROR_NO_UNICODE_TRANSLATION);

  Result := DestStr;
  {$ENDIF}
end;

{ TTextFileWriter }

function TTextFileWriter.CreateHandle(const AFilename: String;
  ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
  ASharing: TFileSharing): THandle;
begin
  { faWrite access isn't enough; we need faReadWrite access since the Write
    method may read. No, we don't have to do this automatically, but it helps
    keep it from being a 'leaky abstraction'. }
  if AAccess = faWrite then
    AAccess := faReadWrite;
  Result := inherited CreateHandle(AFilename, ACreateDisposition, AAccess,
    ASharing);
end;

procedure TTextFileWriter.DoWrite(const S: RawByteString; const UTF8: Boolean);
{ Writes a string to the file, seeking to the end first if necessary }
const
  CRLF: array[0..1] of AnsiChar = (#13, #10);
  UTF8BOM: array[0..2] of AnsiChar = (#$EF, #$BB, #$BF);
var
  C: AnsiChar;
  LSize: Int64;
begin
  if not FSeekedToEnd then begin
    LSize := GetSize;
    if LSize <> 0 then begin
      { File is not empty. Figure out if we have to append a line break. }
      Seek(LSize - SizeOf(C));
      ReadBuffer(C, SizeOf(C));
      case C of
        #10: ;  { do nothing - file ends in LF or CRLF }
        #13: begin
            { If the file ends in CR, make it into CRLF }
            C := #10;
            WriteBuffer(C, SizeOf(C));
          end;
      else
        { Otherwise, append CRLF }
        WriteBuffer(CRLF, SizeOf(CRLF));
      end;
    end else if UTF8 and not FUTF8WithoutBOM then
      WriteBuffer(UTF8BOM, SizeOf(UTF8BOM));
    FSeekedToEnd := True;
  end;
  if Length(S) > 0 then
    WriteBuffer(Pointer(S)^, ULength(S));
end;

procedure TTextFileWriter.Write(const S: String);
begin
  DoWrite(Utf8Encode(S), True);
end;

procedure TTextFileWriter.WriteLine(const S: String);
begin
  Write(S + #13#10);
end;

procedure TTextFileWriter.WriteAnsi(const S: AnsiString);
begin
  DoWrite(S, False);
end;

procedure TTextFileWriter.WriteAnsiLine(const S: AnsiString);
begin
  WriteAnsi(S);
  WriteAnsi(#13#10);
end;

end.
