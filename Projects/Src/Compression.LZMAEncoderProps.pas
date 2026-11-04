unit Compression.LZMAEncoderProps;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Common LZMA encoder presets and islzma C record layout
}

interface

uses
  Compression.Base;

const
  clLZMAFast = 1;
  clLZMANormal = 2;
  clLZMAMax = 3;
  clLZMAUltra = 4;
  clLZMAUltra64 = 5;


type
  TLZMACompressorProps = class(TCompressorProps)
  public
    Algorithm: Integer;
    BlockSize: Integer;
    BTMode: Integer;
    DictionarySize: Cardinal;
    NumBlockThreads: Integer;
    NumFastBytes: Integer;
    NumThreads: Integer;
    NumThreadGroups: Integer;
    constructor Create;
  end;

  TLZMAEncoderProps = record
    Algorithm: Integer;
    BlockSize: Integer;
    BTMode: Integer;
    NumHashBytes: Integer;
    DictionarySize: Cardinal;
    NumBlockThreads: Integer;
    NumFastBytes: Integer;
    NumThreads: Integer;
    NumThreadGroups: Integer;
  end;

function DefaultLZMAEncoderProps(const CompressionLevel: Integer): TLZMAEncoderProps;
function ResolveLZMAEncoderProps(const Level: Integer; const Options: TCompressorProps): TLZMAEncoderProps;

function LZMAGetLevel(const Value: String; var Level: Integer): Boolean;

implementation

uses
  SysUtils, Shared.FPCStringUtils;

function DefaultLZMAEncoderProps(const CompressionLevel: Integer): TLZMAEncoderProps;
const
  algorithm: array [clLZMAFast..clLZMAUltra64] of Integer = (0, 1, 1, 1, 1);
  dicSize: array [clLZMAFast..clLZMAUltra64] of Cardinal = (32 shl 10, 2 shl 20, 8 shl 20, 32 shl 20, 64 shl 20);
  numFastBytes: array [clLZMAFast..clLZMAUltra64] of Integer = (32, 32, 64, 64, 64);
  btMode: array [clLZMAFast..clLZMAUltra64] of Integer = (0, 1, 1, 1, 1);
begin
  if (CompressionLevel < Low(algorithm)) or (CompressionLevel > High(algorithm)) then
    raise ECompressInternalError.Create(ToNativeText('lzma: Invalid compression level ' + InnoIntToStr(CompressionLevel)));

  FillChar(Result, SizeOf(Result), 0);
  Result.Algorithm := algorithm[CompressionLevel];
  Result.BTMode := btMode[CompressionLevel];
  Result.DictionarySize := dicSize[CompressionLevel];
  Result.NumBlockThreads := -1;
  Result.NumFastBytes := numFastBytes[CompressionLevel];
  Result.NumThreads := -1;

end;

constructor TLZMACompressorProps.Create;
begin
  inherited;
  Algorithm := -1;
  BTMode := -1;
end;

function ResolveLZMAEncoderProps(const Level: Integer; const Options: TCompressorProps): TLZMAEncoderProps;
var
  Props: TLZMACompressorProps;
begin
  Result := DefaultLZMAEncoderProps(Level);
  if Options is TLZMACompressorProps then begin
    Props := TLZMACompressorProps(Options);
    if Props.Algorithm <> -1 then
      Result.Algorithm := Props.Algorithm;
    Result.BlockSize := Props.BlockSize;
    if Props.BTMode <> -1 then
      Result.BTMode := Props.BTMode;
    if Props.DictionarySize <> 0 then
      Result.DictionarySize := Props.DictionarySize;
    if Props.NumBlockThreads <> 0 then
      Result.NumBlockThreads := Props.NumBlockThreads;
    if Props.NumFastBytes <> 0 then
      Result.NumFastBytes := Props.NumFastBytes;
    if Props.NumThreads <> 0 then
      Result.NumThreads := Props.NumThreads;
    Result.NumThreadGroups := Props.NumThreadGroups;
  end;
  if Result.BTMode = 1 then
    Result.NumHashBytes := 4
  else
    Result.NumHashBytes := 5;
end;

function LZMAGetLevel(const Value: String; var Level: Integer): Boolean;
begin
  Result := True;
  if InnoCompareText(Value, 'fast') = 0 then
    Level := clLZMAFast
  else if InnoCompareText(Value, 'normal') = 0 then
    Level := clLZMANormal
  else if InnoCompareText(Value, 'max') = 0 then
    Level := clLZMAMax
  else if InnoCompareText(Value, 'ultra') = 0 then
    Level := clLZMAUltra
  else if InnoCompareText(Value, 'ultra64') = 0 then
    Level := clLZMAUltra64
  else
    Result := False;
end;

end.
