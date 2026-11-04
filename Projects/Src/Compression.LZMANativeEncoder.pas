unit Compression.LZMANativeEncoder;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  For conditions of distribution and use, see LICENSE.TXT.

  Host-native binding to the source-built islzma encoder
}

interface

uses
  Classes, Compression.Base, Compression.LZMAEncoderProps;

type
  TLZMANativeProgress = procedure(InputBytes, OutputBytes: UInt64) of object;

procedure EncodeNativeLZMA(const Input, Output: TStream; const UseLZMA2: Boolean;
  const Props: TLZMAEncoderProps; const Progress: TLZMANativeProgress = nil);

type
  TLZMACompressorProps = Compression.LZMAEncoderProps.TLZMACompressorProps;

  TLZMACompressor = class(TCustomCompressor)
  private
    FInput: TStream;
    FProps: TLZMAEncoderProps;
    procedure OpenInput;
  protected
    function UseLZMA2: Boolean; virtual;
    procedure DoCompress(const Buffer; Count: Cardinal); override;
    procedure DoFinish; override;
  public
    constructor Create(AWriteProc: TCompressorWriteProc;
      AProgressProc: TCompressorProgressProc; CompressionLevel: Integer;
      ACompressorProps: TCompressorProps); override;
    destructor Destroy; override;
  end;

  TLZMA2Compressor = class(TLZMACompressor)
  protected
    function UseLZMA2: Boolean; override;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}Windows,{$ELSE}BaseUnix,{$ENDIF} SysUtils
  {$IFDEF MSWINDOWS}, PathFunc{$ENDIF};

{$IF not (Defined(MSWINDOWS) and Defined(CPU386))}
{$LINKLIB islzma_native}
{$IFDEF MSWINDOWS}
{$LINKLIB gcc}
{$LINKLIB msvcrt}
{$LINKLIB kernel32}
{$ENDIF}
{$ENDIF}

type
  PInputAdapter = ^TInputAdapter;
  TInputAdapter = record
    Read: function(Adapter: PInputAdapter; Buffer: Pointer; var Size: NativeUInt): Integer; cdecl;
    Stream: TStream;
    Failure: TObject;
  end;

  POutputAdapter = ^TOutputAdapter;
  TOutputAdapter = record
    Write: function(Adapter: POutputAdapter; Buffer: Pointer; Size: NativeUInt): NativeUInt; cdecl;
    Stream: TStream;
    Failure: TObject;
  end;

  PProgressAdapter = ^TProgressAdapter;
  TProgressAdapter = record
    Report: function(Adapter: PProgressAdapter; InputBytes, OutputBytes: UInt64): Integer; cdecl;
    Handler: TLZMANativeProgress;
    Failure: TObject;
  end;

function LZMA_Init(UseLZMA2: Integer; out Handle: Pointer): Integer;
  {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  external {$IF Defined(MSWINDOWS) and Defined(CPU386)}'islzma-native.dll' name 'LZMA_Init3'{$ELSE}name 'LZMA_Init'{$ENDIF};
function LZMA_SetProps(Handle: Pointer; Props: Pointer; PropsSize: NativeUInt): Integer;
  {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  external {$IF Defined(MSWINDOWS) and Defined(CPU386)}'islzma-native.dll' name 'LZMA_SetProps3'{$ELSE}name 'LZMA_SetProps'{$ENDIF};
function LZMA_Encode(Handle: Pointer; Input: PInputAdapter; Output: POutputAdapter;
  Progress: Pointer): Integer; {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  external {$IF Defined(MSWINDOWS) and Defined(CPU386)}'islzma-native.dll' name 'LZMA_Encode3'{$ELSE}name 'LZMA_Encode'{$ENDIF};
function LZMA_End(Handle: Pointer): Integer;
  {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  external {$IF Defined(MSWINDOWS) and Defined(CPU386)}'islzma-native.dll' name 'LZMA_End3'{$ELSE}name 'LZMA_End'{$ENDIF};

function ReadInput(Adapter: PInputAdapter; Buffer: Pointer; var Size: NativeUInt): Integer; cdecl;
var
  Count: LongInt;
begin
  Result := 8; { SZ_ERROR_READ }
  try
    if Adapter^.Failure <> nil then begin
      Size := 0;
      Exit;
    end;
    if Size > NativeUInt(High(LongInt)) then
      Size := High(LongInt);
    Count := Adapter^.Stream.Read(Buffer^, LongInt(Size));
    if Count >= 0 then begin
      Size := NativeUInt(Count);
      Exit(0);
    end;
  except
    Adapter^.Failure := TObject(AcquireExceptionObject);
  end;
  Size := 0;
end;

function WriteOutput(Adapter: POutputAdapter; Buffer: Pointer; Size: NativeUInt): NativeUInt; cdecl;
var
  Count: LongInt;
begin
  Result := 0;
  try
    if Adapter^.Failure <> nil then
      Exit;
    while Size > 0 do begin
      if Size > NativeUInt(High(LongInt)) then
        Count := High(LongInt)
      else
        Count := LongInt(Size);
      Adapter^.Stream.WriteBuffer(Buffer^, Count);
      Inc(PByte(Buffer), Count);
      Inc(Result, Count);
      Dec(Size, Count);
    end;
  except
    Adapter^.Failure := TObject(AcquireExceptionObject);
  end;
end;

function ReportProgress(Adapter: PProgressAdapter; InputBytes, OutputBytes: UInt64): Integer; cdecl;
begin
  Result := 10; { SZ_ERROR_PROGRESS }
  if Adapter^.Failure <> nil then
    Exit;
  try
    Adapter^.Handler(InputBytes, OutputBytes);
    Result := 0;
  except
    Adapter^.Failure := TObject(AcquireExceptionObject);
  end;
end;

procedure EncodeNativeLZMA(const Input, Output: TStream; const UseLZMA2: Boolean;
  const Props: TLZMAEncoderProps; const Progress: TLZMANativeProgress);
var
  Handle: Pointer;
  Source: TInputAdapter;
  Destination: TOutputAdapter;
  ProgressAdapter: TProgressAdapter;
  ProgressPtr: PProgressAdapter;
  Code: Integer;
  Failure: TObject;

  procedure Check(const Status: Integer);
  begin
    if Status = 2 then
      OutOfMemoryError;
    if Status <> 0 then
      raise ECompressInternalError.CreateFmt('lzma: Native encoder error %d', [Status]);
  end;

begin
  Source.Read := ReadInput;
  Source.Stream := Input;
  Source.Failure := nil;
  Destination.Write := WriteOutput;
  Destination.Stream := Output;
  Destination.Failure := nil;
  ProgressAdapter.Report := ReportProgress;
  ProgressAdapter.Handler := Progress;
  ProgressAdapter.Failure := nil;
  ProgressPtr := nil;
  if Assigned(Progress) then
    ProgressPtr := @ProgressAdapter;
  Check(LZMA_Init(Ord(UseLZMA2), Handle));
  try
    Check(LZMA_SetProps(Handle, @Props, SizeOf(Props)));
    Code := LZMA_Encode(Handle, @Source, @Destination, ProgressPtr);
    if Source.Failure <> nil then begin
      Failure := Source.Failure;
      Source.Failure := nil;
      raise Failure;
    end;
    if Destination.Failure <> nil then begin
      Failure := Destination.Failure;
      Destination.Failure := nil;
      raise Failure;
    end;
    if ProgressAdapter.Failure <> nil then begin
      Failure := ProgressAdapter.Failure;
      ProgressAdapter.Failure := nil;
      raise Failure;
    end;
    Check(Code);
  finally
    LZMA_End(Handle);
    Source.Failure.Free;
    Destination.Failure.Free;
    ProgressAdapter.Failure.Free;
  end;
end;

type
  TSpoolStream = class(THandleStream)
    destructor Destroy; override;
  end;

  TEncoderOutput = class(TStream)
    Writer: TCompressorWriteProc;
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

{$IFNDEF MSWINDOWS}
function mkstemp(Template: PAnsiChar): Integer; cdecl; external 'c' name 'mkstemp';
{$ENDIF}

destructor TSpoolStream.Destroy;
begin
  {$IFDEF MSWINDOWS}CloseHandle(Handle);{$ELSE}fpClose(Handle);{$ENDIF}
  inherited;
end;

function TEncoderOutput.Write(const Buffer; Count: LongInt): LongInt;
begin
  Writer(Buffer, Cardinal(Count));
  Result := Count;
end;

constructor TLZMACompressor.Create(AWriteProc: TCompressorWriteProc;
  AProgressProc: TCompressorProgressProc; CompressionLevel: Integer;
  ACompressorProps: TCompressorProps);
begin
  inherited;
  FProps := ResolveLZMAEncoderProps(CompressionLevel, ACompressorProps);
end;

destructor TLZMACompressor.Destroy;
begin
  FInput.Free;
  inherited;
end;

function TLZMACompressor.UseLZMA2: Boolean;
begin
  Result := False;
end;

function TLZMA2Compressor.UseLZMA2: Boolean;
begin
  Result := True;
end;

procedure TLZMACompressor.OpenInput;
{$IFDEF MSWINDOWS}
const
  DeleteAccess = $00010000;
{$ENDIF}
var
  {$IFDEF MSWINDOWS}
  TempPath: array[0..MAX_PATH] of WideChar;
  TempPathLength: Cardinal;
  TempId: TGUID;
  Filename: String;
  FileHandle: THandle;
  {$ELSE}
  Template: UTF8String;
  FD: Integer;
  {$ENDIF}
begin
  if FInput <> nil then
    Exit;
  {$IFDEF MSWINDOWS}
  TempPathLength := GetTempPathW(Length(TempPath), @TempPath[0]);
  if TempPathLength = 0 then
    RaiseLastOSError;
  if TempPathLength >= Length(TempPath) then
    RaiseLastOSError(ERROR_INSUFFICIENT_BUFFER);
  if CreateGUID(TempId) <> 0 then
    raise EInOutError.Create('Cannot create an LZMA temporary file name');
  Filename := PathConvertNormalToSuper(String(PWideChar(@TempPath[0])) + 'inno-lzma-' + GUIDToString(TempId));
  FileHandle := CreateFileW(PWideChar(Filename), GENERIC_READ or GENERIC_WRITE or DeleteAccess,
    0, nil, CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY or FILE_FLAG_DELETE_ON_CLOSE, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    FInput := TSpoolStream.Create(FileHandle);
  except
    CloseHandle(FileHandle);
    raise;
  end;
  {$ELSE}
  Template := UTF8Encode(UTF8Decode(IncludeTrailingPathDelimiter(GetTempDir)) + 'inno-lzma-XXXXXX');
  FD := mkstemp(PAnsiChar(Template));
  if FD < 0 then
    RaiseLastOSError;
  try
    if fpUnlink(PAnsiChar(Template)) <> 0 then
      RaiseLastOSError;
    FInput := TSpoolStream.Create(FD);
  except
    fpClose(FD);
    raise;
  end;
  {$ENDIF}
end;

procedure TLZMACompressor.DoCompress(const Buffer; Count: Cardinal);
var
  Cursor: PByte;
  Chunk: LongInt;
begin
  OpenInput;
  Cursor := @Buffer;
  while Count <> 0 do begin
    if Count > Cardinal(High(LongInt)) then
      Chunk := High(LongInt)
    else
      Chunk := LongInt(Count);
    FInput.WriteBuffer(Cursor^, Chunk);
    Inc(Cursor, Chunk);
    Dec(Count, Cardinal(Chunk));
    if Assigned(ProgressProc) then
      ProgressProc(Cardinal(Chunk));
  end;
end;

procedure TLZMACompressor.DoFinish;
var
  Output: TEncoderOutput;
begin
  OpenInput;
  Output := TEncoderOutput.Create;
  try
    Output.Writer := WriteProc;
    FInput.Position := 0;
    EncodeNativeLZMA(FInput, Output, UseLZMA2, FProps);
  finally
    Output.Free;
    FreeAndNil(FInput);
  end;
end;

end.
