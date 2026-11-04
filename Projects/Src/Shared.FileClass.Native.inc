{ POSIX implementation of TFile. Paths use host UTF-8 encoding. }

{$IF NOT DECLARED(FD_CLOEXEC)}
const
  FD_CLOEXEC = 1; { Linux UAPI; absent from FPC 3.2.2 Linux headers }
{$IFEND}

procedure SetFileCloseOnExec(const Handle: THandle);
var
  ErrorCode: Integer;
begin
  if fpFcntl(Handle, F_SETFD, FD_CLOEXEC) < 0 then begin
    ErrorCode := fpGetErrNo;
    fpClose(Handle);
    fpSetErrNo(ErrorCode);
    TCustomFile.RaiseLastError;
  end;
end;

constructor TFile.Create(const AFilename: String;
  ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
  ASharing: TFileSharing);
begin
  inherited Create;
  FHandle := CreateHandle(AFilename, ACreateDisposition, AAccess, ASharing);
  if FHandle < 0 then
    RaiseLastError;
  SetFileCloseOnExec(FHandle);
  FHandleCreated := True;
end;

constructor TFile.CreateDuplicate(const ASourceFile: TFile);
begin
  inherited Create;
  FHandle := fpDup(ASourceFile.Handle);
  if FHandle < 0 then
    RaiseLastError;
  SetFileCloseOnExec(FHandle);
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
    fpClose(FHandle);
  inherited;
end;

function TFile.CreateHandle(const AFilename: String;
  ACreateDisposition: TFileCreateDisposition; AAccess: TFileAccess;
  ASharing: TFileSharing): THandle;
const
  AccessFlags: array[TFileAccess] of Integer = (O_RDONLY, O_WRONLY, O_RDWR);
  Dispositions: array[TFileCreateDisposition] of Integer =
    (O_CREAT or O_TRUNC, O_CREAT or O_EXCL, 0, O_CREAT, O_TRUNC);
begin
  { POSIX sharing follows host semantics; Windows share-denial flags are not emulated }
  Result := fpOpen(PAnsiChar(UTF8Encode(AFilename)),
    AccessFlags[AAccess] or Dispositions[ACreateDisposition], &666);
end;

function TFile.GetPosition: Int64;
begin
  Result := fpLseek(FHandle, 0, SEEK_CUR);
  if Result < 0 then
    RaiseLastError;
end;

function TFile.GetCanSeek: Boolean;
var
  Info: Stat;
begin
  if fpFstat(FHandle, Info) <> 0 then
    RaiseLastError;
  Result := fpS_ISREG(Info.st_mode);
end;

function TFile.GetSize: Int64;
var
  Info: Stat;
begin
  if fpFstat(FHandle, Info) <> 0 then
    RaiseLastError;
  Result := Info.st_size;
end;

function TFile.Read(var Buffer; Count: Cardinal): Cardinal;
var
  BytesRead: Int64;
begin
  repeat
    BytesRead := fpRead(FHandle, Buffer, Count);
  until (BytesRead >= 0) or (fpGetErrNo <> ESysEINTR);
  if BytesRead < 0 then
    RaiseLastError;
  Result := BytesRead;
end;

procedure TFile.Seek(Offset: Int64);
begin
  if Offset < 0 then
    RaiseError(ERROR_NEGATIVE_SEEK);
  if fpLseek(FHandle, Offset, SEEK_SET) < 0 then
    RaiseLastError;
end;

procedure TFile.SeekToEnd;
begin
  if fpLseek(FHandle, 0, SEEK_END) < 0 then
    RaiseLastError;
end;

procedure TFile.Truncate;
begin
  if fpFtruncate(FHandle, GetPosition) <> 0 then
    RaiseLastError;
end;

procedure TFile.WriteBuffer(const Buffer; Count: Cardinal);
var
  Source: PByte;
  Written: Int64;
begin
  Source := @Buffer;
  while Count > 0 do begin
    repeat
      Written := fpWrite(FHandle, Source^, Count);
    until (Written >= 0) or (fpGetErrNo <> ESysEINTR);
    if Written < 0 then
      RaiseLastError;
    if Written = 0 then
      RaiseError(ERROR_WRITE_FAULT);
    Inc(Source, Written);
    Dec(Count, Written);
  end;
end;
