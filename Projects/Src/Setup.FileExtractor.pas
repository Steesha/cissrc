unit Setup.FileExtractor;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  TFileExtractor class to extract (=decrypt, decompress, and/or verify) Setup files
}

interface

uses
  SysUtils, Shared.FileClass, Compression.Base,
  Shared.Struct, ChaCha20;

type
  TExtractorProgressProc = procedure(const Bytes: Cardinal);
  TExtractorSliceFilenameFunc = function(const Slice: Integer): String;
  TExtractorErrorProc = procedure(const Reason: String; const Corrupt: Boolean);

  TFileExtractor = class
  private
    FDecompressor: array[Boolean] of TCustomDecompressor;
    FSourceF: TFile;
    FSourceFilename: String;
    FDataOffset: Int64;
    FEncryptionBaseNonce: TSetupEncryptionNonce;
    FSliceFilename: TExtractorSliceFilenameFunc;
    FOnError: TExtractorErrorProc;
    FOpenedSlice, FChunkFirstSlice, FChunkLastSlice: Integer;
    FChunkStartOffset: Int64;
    FChunkBytesLeft, FChunkDecompressedBytesRead: Int64;
    FNeedReset: Boolean;
    FChunkCompressed, FChunkEncrypted: Boolean;
    FCryptContext: TChaCha20Context;
    FCryptKey: TSetupEncryptionKey;
    FCryptKeySet: Boolean;
    FEntered: Integer;
    procedure Fail(const Reason: String; const Corrupt: Boolean);
    procedure DecompressBytes(var Buffer; Count: Cardinal);
    procedure OpenSlice(const ASlice: Integer);
    function ReadProc(var Buf; Count: Cardinal): Cardinal;
    procedure SetCryptKey(const Value: TSetupEncryptionKey);
  public
    constructor Create(ADecompressorClass: TCustomDecompressorClass; const SourceFilename: String;
      const DataOffset: Int64; const EncryptionBaseNonce: TSetupEncryptionNonce;
      const SliceFilename: TExtractorSliceFilenameFunc; const OnError: TExtractorErrorProc);
    destructor Destroy; override;
    procedure DecompressFile(const FL: TSetupFileLocationEntry; const DestF: TFile;
      const ProgressProc: TExtractorProgressProc; const VerifyChecksum: Boolean);
    procedure SeekTo(const FL: TSetupFileLocationEntry;
      const ProgressProc: TExtractorProgressProc);
    property CryptKey: TSetupEncryptionKey write SetCryptKey;
  end;

implementation

uses
  SHA256, Shared.EncryptionFunc;

constructor TFileExtractor.Create(ADecompressorClass: TCustomDecompressorClass;
  const SourceFilename: String; const DataOffset: Int64; const EncryptionBaseNonce: TSetupEncryptionNonce;
  const SliceFilename: TExtractorSliceFilenameFunc; const OnError: TExtractorErrorProc);
begin
  inherited Create;
  if (DataOffset = 0) and not Assigned(SliceFilename) then
    raise Exception.Create('Disk-spanning extraction requires a slice filename callback');
  FSourceFilename := SourceFilename;
  FDataOffset := DataOffset;
  FEncryptionBaseNonce := EncryptionBaseNonce;
  FSliceFilename := SliceFilename;
  FOnError := OnError;
  FOpenedSlice := -1;
  FChunkFirstSlice := -1;
  { Create one 'decompressor' for use with uncompressed chunks, and another
    for use with compressed chunks }
  FDecompressor[False] := TStoredDecompressor.Create(ReadProc);
  FDecompressor[True] := ADecompressorClass.Create(ReadProc);
end;

destructor TFileExtractor.Destroy;
begin
  FSourceF.Free;
  FDecompressor[True].Free;
  FDecompressor[False].Free;
  inherited;
end;

procedure TFileExtractor.SetCryptKey(const Value: TSetupEncryptionKey);
begin
  FCryptKey := Value;
  FCryptKeySet := True;
end;

procedure TFileExtractor.Fail(const Reason: String; const Corrupt: Boolean);
begin
  if Assigned(FOnError) then
    FOnError(Reason, Corrupt);
  if Corrupt then
    raise ECompressDataError.Create({$IFDEF FPC}UTF8Encode(Reason){$ELSE}Reason{$ENDIF});
  raise Exception.Create({$IFDEF FPC}UTF8Encode(Reason){$ELSE}Reason{$ENDIF});
end;

procedure TFileExtractor.OpenSlice(const ASlice: Integer);
var
  Filename: String;
  TestDiskSliceID: TDiskSliceID;
  DiskSliceHeader: TDiskSliceHeader;
begin
  if FOpenedSlice = ASlice then
    Exit;

  FOpenedSlice := -1;
  FreeAndNil(FSourceF);

  if FDataOffset = 0 then
    Filename := FSliceFilename(ASlice)
  else
    Filename := FSourceFilename;
  FSourceF := TFile.Create(Filename, fdOpenExisting, faRead, fsRead);
  if FDataOffset = 0 then begin
    if FSourceF.Read(TestDiskSliceID, SizeOf(TestDiskSliceID)) <> SizeOf(TestDiskSliceID) then
      Fail('Invalid slice header (1)', True);
    if TestDiskSliceID <> DiskSliceID then
      Fail('Invalid slice header (2)', True);
    if FSourceF.Read(DiskSliceHeader, SizeOf(DiskSliceHeader)) <> SizeOf(DiskSliceHeader) then
      Fail('Invalid slice header (3)', True);
    if FSourceF.Size <> DiskSliceHeader.TotalSize then
      Fail('Invalid slice header (4)', True);
  end;
  FOpenedSlice := ASlice;
end;

procedure TFileExtractor.DecompressBytes(var Buffer; Count: Cardinal);
begin
  try
    FDecompressor[FChunkCompressed].DecompressInto(Buffer, Count);
  except
    { If DecompressInto raises an exception, force a decompressor reset &
      re-seek the next time SeekTo is called by setting FNeedReset to True.
      We don't want to get stuck in an endless loop with the decompressor
      in e.g. a data error state. Also, we have no way of knowing if
      DecompressInto successfully decompressed some of the requested bytes
      before the exception was raised. }
    FNeedReset := True;
    raise;
  end;
  Inc(FChunkDecompressedBytesRead, Count);
end;

procedure TFileExtractor.SeekTo(const FL: TSetupFileLocationEntry;
  const ProgressProc: TExtractorProgressProc);

  procedure Discard(Count: Int64);
  var
    Buf: array[0..65535] of Byte;
    BufSize: Cardinal;
  begin
    try
      while Count > 0 do begin
        BufSize := SizeOf(Buf);
        if Count < BufSize then
          BufSize := Cardinal(Count);
        DecompressBytes(Buf, BufSize);
        Dec(Count, BufSize);
        if Assigned(ProgressProc) then
          ProgressProc(0);
      end;
    except
      on E: ECompressDataError do
        Fail(E.Message, True);
    end;
  end;

var
  TestCompID: TCompID;
  Diff: Int64;
begin
  if FEntered <> 0 then
    Fail('Cannot call file extractor recursively', False);
  Inc(FEntered);
  try
    if (floChunkEncrypted in FL.Flags) and not FCryptKeySet then
      Fail('Cannot read an encrypted file before the key has been set', False);

    { Is the file in a different chunk than the current one?
      Or, is the file in a part of the current chunk that we've already passed?
      Or, did a previous decompression operation fail, necessitating a reset? }
    if (FChunkFirstSlice <> FL.FirstSlice) or
       (FChunkStartOffset <> FL.StartOffset) or
       (FL.ChunkSuboffset < FChunkDecompressedBytesRead) or
       FNeedReset then begin
      FChunkFirstSlice := -1;
      FDecompressor[floChunkCompressed in FL.Flags].Reset;
      FNeedReset := False;

      OpenSlice(FL.FirstSlice);

      FSourceF.Seek(FDataOffset + FL.StartOffset);
      if FSourceF.Read(TestCompID, SizeOf(TestCompID)) <> SizeOf(TestCompID) then
        Fail('Failed to read CompID', True);
      if TestCompID <> ZLIBID then
        Fail('Invalid CompID', True);

      FChunkFirstSlice := FL.FirstSlice;
      FChunkLastSlice := FL.LastSlice;
      FChunkStartOffset := FL.StartOffset;
      FChunkBytesLeft := FL.ChunkCompressedSize;
      FChunkDecompressedBytesRead := 0;
      FChunkCompressed := floChunkCompressed in FL.Flags;
      FChunkEncrypted := floChunkEncrypted in FL.Flags;

      if floChunkEncrypted in FL.Flags then
        InitCryptContext(FCryptKey, FEncryptionBaseNonce, FChunkStartOffset, FChunkFirstSlice, FCryptContext);
    end;

    { Need to seek forward in the chunk? }
    if FL.ChunkSuboffset > FChunkDecompressedBytesRead then begin
      Diff := FL.ChunkSuboffset;
      Dec(Diff, FChunkDecompressedBytesRead);
      Discard(Diff);
    end;
  finally
    Dec(FEntered);
  end;
end;

function TFileExtractor.ReadProc(var Buf; Count: Cardinal): Cardinal;
var
  Buffer: Pointer;
  Left, Res: Cardinal;
begin
  if FChunkBytesLeft < 0 then  { sanity checks }
    Fail('TFileExtractor.ReadProc: Negative FChunkBytesLeft', False);
  Buffer := @Buf;
  Left := Count;
  if FChunkBytesLeft < Left then
    Left := Cardinal(FChunkBytesLeft);
  Result := Left;
  while Left <> 0 do begin
    Res := FSourceF.Read(Buffer^, Left);
    Dec(FChunkBytesLeft, Res);

    { Decrypt the data after reading from the file }
    if FChunkEncrypted then
      XChaCha20Crypt(FCryptContext, Buffer^, Buffer^, Res);

    if Left = Res then
      Break
    else begin
      Dec(Left, Res);
      Inc(PByte(Buffer), Res);
      { Go to next disk }
      if FOpenedSlice >= FChunkLastSlice then
        { Already on the last slice, so the file must be corrupted... }
        Fail('Already on last slice', True);
      OpenSlice(FOpenedSlice + 1);
    end;
  end;
end;

procedure TFileExtractor.DecompressFile(const FL: TSetupFileLocationEntry;
  const DestF: TFile; const ProgressProc: TExtractorProgressProc;
  const VerifyChecksum: Boolean);
var
  Context: TSHA256Context;
  AddrOffset: UInt32;
  BytesLeft: Int64;
  BufSize: Cardinal;
  Buf: array[0..65535] of Byte;
  { ^ *must* be the same buffer size used by the compiler (TCompressionHandler),
    otherwise the TransformCallInstructions call will break }
begin
  if FEntered <> 0 then
    Fail('Cannot call file extractor recursively', False);
  Inc(FEntered);
  try
    BytesLeft := FL.OriginalSize;
    if BytesLeft < 0 then  { sanity check }
      Fail('TFileExtractor.DecompressFile: Negative size', False);

    { To avoid file system fragmentation, preallocate all of the bytes in the
      destination file }
    DestF.Seek(BytesLeft);
    DestF.Truncate;
    DestF.Seek(0);

    SHA256Init(Context);

    try
      AddrOffset := 0;
      while BytesLeft > 0 do begin
        BufSize := SizeOf(Buf);
        if BytesLeft < BufSize then
          BufSize := Cardinal(BytesLeft);

        DecompressBytes(Buf, BufSize);
        if floCallInstructionOptimized in FL.Flags then begin
          TransformCallInstructions(Buf, BufSize, False, AddrOffset);
          Inc(AddrOffset, BufSize);  { may wrap, but OK }
        end;
        Dec(BytesLeft, BufSize);
        SHA256Update(Context, Buf, BufSize);
        DestF.WriteBuffer(Buf, BufSize);

        if Assigned(ProgressProc) then
          ProgressProc(BufSize);
      end;
    except
      on E: ECompressDataError do
        Fail(E.Message, True);
    end;

    if VerifyChecksum and not SHA256DigestsEqual(SHA256Final(Context), FL.SHA256Sum) then
      Fail('SHA-256 hash mismatch', True);
  finally
    Dec(FEntered);
  end;
end;

end.
