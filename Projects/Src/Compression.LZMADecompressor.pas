unit Compression.LZMADecompressor;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Interface to the LZMA/LZMA2 SDK decompression OBJs in
  Compression.LZMADecompressor\Lzma2Decode, used by Setup.
}

interface

uses
  {$IFDEF MSWINDOWS} Windows, {$ENDIF} SysUtils, Compression.Base;

type
  TLZMACustomDecompressor = class(TCustomDecompressor)
  private
    FReachedEnd: Boolean;
    FHeaderProcessed: Boolean;
    FNextIn: PByte;
    FAvailIn: Cardinal;
    FBuffer: array[0..65535] of Byte;
  protected
    function DecodeToBuf(var Dest; var DestLen: Cardinal; const Src;
      var SrcLen: Cardinal; var Status: Integer): Integer; virtual; abstract;
    procedure FreeDecoder; virtual; abstract;
    procedure ProcessHeader; virtual; abstract;
  public
    destructor Destroy; override;
    procedure DecompressInto(var Buffer; Count: Cardinal); override;
    procedure Reset; override;
  end;

type
  { Internally-used record }
  TLZMAInternalDecoderState = array[0..31] of UInt64;

  TLZMA1Decompressor = class(TLZMACustomDecompressor)
  private
    FDecoderState: TLZMAInternalDecoderState;
  protected
    function DecodeToBuf(var Dest; var DestLen: Cardinal; const Src;
      var SrcLen: Cardinal; var Status: Integer): Integer; override;
    procedure FreeDecoder; override;
    procedure ProcessHeader; override;
  end;

  TLZMA2Decompressor = class(TLZMACustomDecompressor)
  private
    FDecoderState: TLZMAInternalDecoderState;
  protected
    function DecodeToBuf(var Dest; var DestLen: Cardinal; const Src;
      var SrcLen: Cardinal; var Status: Integer): Integer; override;
    procedure FreeDecoder; override;
    procedure ProcessHeader; override;
  end;

implementation

uses
  UnsignedFunc;

type
  TLZMASRes = type Integer;

  PLZMAISzAlloc = ^TLZMAISzAlloc;
  TLZMAISzAlloc = record
    Alloc: function(p: PLZMAISzAlloc; size: NativeUInt): Pointer; cdecl;
    Free: procedure(p: PLZMAISzAlloc; address: Pointer); cdecl;
  end;

const
  { SRes (TLZMASRes) }
  SZ_OK = 0;
  SZ_ERROR_DATA = 1;
  SZ_ERROR_MEM = 2;

  { ELzmaFinishMode }
  LZMA_FINISH_ANY = 0;
  LZMA_FINISH_END = 1;

  { ELzmaStatus }
  LZMA_STATUS_NOT_SPECIFIED = 0;
  LZMA_STATUS_FINISHED_WITH_MARK = 1;
  LZMA_STATUS_NOT_FINISHED = 2;
  LZMA_STATUS_NEEDS_MORE_INPUT = 3;
  LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK = 4;

  SLZMADecompDataError = 'lzmadecomp: Compressed data is corrupted (%d)';

  { To ensure we don't allocate inordinate amounts of memory in the event a
    stream's header is corrupted, we limit the dictionary size to the maximum
    size the compiler currently allows, so same as ssLZMADictionarySize allows
    in Compiler.SetupCompiler.pas. }
  {$IF Defined(WIN64) or Defined(CPU64)}
  MaxDictionarySize = Cardinal(15) shl 28;
  { Lzma2Dec_GetOldProps in Lzma2Dec.c decodes LZMA2 property 40 as 4 GB - 1, and
    LzmaDec_Allocate in LzmaDec.c then allocates 4 GB }
  MaxAllocSize = NativeUInt(4096) shl 20;
  {$ELSE}
  MaxDictionarySize = 1024 shl 20;
  MaxAllocSize = MaxDictionarySize;
  {$ENDIF}

{$IFDEF FPC}
{$LINKLIB inno_decoders}
{$ELSE}
{ Compiled by Visual Studio 2022 using compile.bat }
{$IFNDEF WIN64}
{ To enable source debugging recompile using compile-bcc32c.bat
  Note that in a speed test the code produced by bcc32c was about 33% slower }
{$L Src\Compression.LZMADecompressor\Lzma2Decode\ISLzmaDec-x86.obj}
{$ELSE}
{$L Src\Compression.LZMADecompressor\Lzma2Decode\ISLzmaDec-x64.obj}
{$ENDIF}
{$ENDIF}

function IS_LzmaDec_Init(var state: TLZMAInternalDecoderState;
  stateSize: NativeUInt; const props; propsSize: Cardinal;
  {$IFDEF FPC}constref{$ELSE}const{$ENDIF} alloc: TLZMAISzAlloc): TLZMASRes; cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_IS_LzmaDec_Init' {$ELSE} 'IS_LzmaDec_Init'{$ENDIF};
function IS_LzmaDec_StateSize: NativeUInt; cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_IS_LzmaDec_StateSize' {$ELSE} 'IS_LzmaDec_StateSize'{$ENDIF};
function LzmaDec_DecodeToBuf(var state: TLZMAInternalDecoderState; var dest;
  var destLen: NativeUInt; const src; var srcLen: NativeUInt; finishMode: Integer;
  var status: Integer): TLZMASRes; cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_LzmaDec_DecodeToBuf' {$ELSE} 'LzmaDec_DecodeToBuf'{$ENDIF};
procedure LzmaDec_Free(var state: TLZMAInternalDecoderState;
  {$IFDEF FPC}constref{$ELSE}const{$ENDIF} alloc: TLZMAISzAlloc); cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_LzmaDec_Free' {$ELSE} 'LzmaDec_Free'{$ENDIF};

function IS_Lzma2Dec_Init(var state: TLZMAInternalDecoderState;
  stateSize: NativeUInt; prop: Byte; {$IFDEF FPC}constref{$ELSE}const{$ENDIF} alloc: TLZMAISzAlloc): TLZMASRes; cdecl;
  external name {$IF not Defined(WIN64) and not Defined(FPC)} '_IS_Lzma2Dec_Init' {$ELSE} 'IS_Lzma2Dec_Init'{$ENDIF};
function IS_Lzma2Dec_StateSize: NativeUInt; cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_IS_Lzma2Dec_StateSize' {$ELSE} 'IS_Lzma2Dec_StateSize'{$ENDIF};
function Lzma2Dec_DecodeToBuf(var state: TLZMAInternalDecoderState; var dest;
  var destLen: NativeUInt; const src; var srcLen: NativeUInt; finishMode: Integer;
  var status: Integer): TLZMASRes; cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_Lzma2Dec_DecodeToBuf' {$ELSE} 'Lzma2Dec_DecodeToBuf'{$ENDIF};
procedure IS_Lzma2Dec_Free(var state: TLZMAInternalDecoderState;
  {$IFDEF FPC}constref{$ELSE}const{$ENDIF} alloc: TLZMAISzAlloc); cdecl; external name {$IF not Defined(WIN64) and not Defined(FPC)} '_IS_Lzma2Dec_Free' {$ELSE} 'IS_Lzma2Dec_Free'{$ENDIF};


{$IF not Defined(FPC) or Defined(MSWINDOWS)}
function {$IFNDEF WIN64} _memcpy {$ELSE} memcpy {$ENDIF}(dest, src: Pointer; n: NativeUInt): Pointer; cdecl;
  {$IFDEF FPC} public name {$IF Defined(MSWINDOWS) and not Defined(WIN64)}'_memcpy'{$ELSE}'memcpy'{$IFEND}; {$ENDIF}
begin
  UMove(src^, dest^, n);
  Result := dest;
end;
{$ENDIF}

procedure LZMADecompInternalError(const Msg: String);
begin
  raise ECompressInternalError.CreateFmt('lzmadecomp: %s', [Msg]);
end;

procedure LZMADecompDataError(const Id: Integer);
begin
  raise ECompressDataError.CreateFmt(SLZMADecompDataError, [Id]);
end;

function LZMAAllocFunc(p: PLZMAISzAlloc; size: NativeUInt): Pointer; cdecl;
begin
  if (size <> 0) and (size <= MaxAllocSize) then
    {$IFDEF MSWINDOWS}
    Result := VirtualAlloc(nil, size, MEM_COMMIT, PAGE_READWRITE)
    {$ELSE}
    try
      GetMem(Result, size);
    except
      on EOutOfMemory do Result := nil;
    end
    {$ENDIF}
  else
    Result := nil;
end;

procedure LZMAFreeFunc(p: PLZMAISzAlloc; address: Pointer); cdecl;
begin
  if Assigned(address) then
    {$IFDEF MSWINDOWS}
    VirtualFree(address, 0, MEM_RELEASE);
    {$ELSE}
    FreeMem(address);
    {$ENDIF}
end;

const
  LZMAAlloc: TLZMAISzAlloc = (Alloc: LZMAAllocFunc; Free: LZMAFreeFunc);

{ TLZMACustomDecompressor }

destructor TLZMACustomDecompressor.Destroy;
begin
  FreeDecoder;
  inherited;
end;

procedure TLZMACustomDecompressor.DecompressInto(var Buffer; Count: Cardinal);
var
  NextOut: PByte;
  OutBytes, InBytes, AvailOut: Cardinal;
  Code: TLZMASRes;
  DecodeStatus: Integer;
begin
  if not FHeaderProcessed then begin
    { Reset these following a reset }
    FNextIn := PByte(@FBuffer);
    FAvailIn := 0;
    ProcessHeader;
    FHeaderProcessed := True;
  end;
  NextOut := @Buffer;
  AvailOut := Count;
  while AvailOut > 0 do begin
    if (FAvailIn = 0) and not FReachedEnd then begin
      FNextIn := PByte(@FBuffer);
      FAvailIn := ReadProc(FBuffer, SizeOf(FBuffer));
      if FAvailIn = 0 then
        FReachedEnd := True;  { not really necessary, but for consistency }
    end;
    OutBytes := AvailOut;
    InBytes := FAvailIn;
    Code := DecodeToBuf(NextOut^, OutBytes, FNextIn^, InBytes, DecodeStatus);
    case Code of
      SZ_OK: ;
      SZ_ERROR_DATA: LZMADecompDataError(3);
    else
      LZMADecompInternalError(Format('DecodeToBuf failed (%d)', [Code]));
    end;
    { No bytes in or out indicates corruption somewhere. Possibilities:
      - The caller is asking for too many bytes.
      - It needs more input but there isn't any left.
      - It encountered an "end mark" previously and is now refusing to
        process any further input. }
    if (InBytes = 0) and (OutBytes = 0) then
      LZMADecompDataError(4);
    Dec(AvailOut, OutBytes);
    Inc(NextOut, OutBytes);
    Dec(FAvailIn, InBytes);
    Inc(FNextIn, InBytes);
  end;
end;

procedure TLZMACustomDecompressor.Reset;
begin
  FHeaderProcessed := False;
  FReachedEnd := False;
end;

{ TLZMA1Decompressor }

procedure TLZMA1Decompressor.FreeDecoder;
begin
  LzmaDec_Free(FDecoderState, LZMAAlloc);
end;

procedure TLZMA1Decompressor.ProcessHeader;
var
  StateSize, DecoderStateSize: NativeUInt;
  Props: packed record  { size = LZMA_PROPS_SIZE (5) }
    Misc: Byte;
    DictionarySize: Cardinal;  { little endian, unaligned }
  end;
begin
  { Read header fields }
  if ReadProc(Props, SizeOf(Props)) <> SizeOf(Props) then
    LZMADecompDataError(1);

  if Props.DictionarySize > MaxDictionarySize then
    LZMADecompDataError(5);

  StateSize := IS_LzmaDec_StateSize;
  DecoderStateSize := SizeOf(FDecoderState);
  if StateSize > DecoderStateSize then
    LZMADecompDataError(-Integer(StateSize));

  { Note: IS_LzmaDec_Init will re-use already-allocated memory if it can.
    FDecoderState is assumed to be initialized to zero on the first call. }
  case IS_LzmaDec_Init(FDecoderState, DecoderStateSize, Props,
     SizeOf(Props), LZMAAlloc) of
    SZ_OK: ;
    SZ_ERROR_MEM: OutOfMemoryError;
  else
    { SZ_ERROR_UNSUPPORTED and anything else }
    LZMADecompDataError(2);
  end;
end;

function TLZMA1Decompressor.DecodeToBuf(var Dest; var DestLen: Cardinal;
  const Src; var SrcLen: Cardinal; var Status: Integer): Integer;
var
  NativeDestLen, NativeSrcLen: NativeUInt;
begin
  NativeDestLen := DestLen;
  NativeSrcLen := SrcLen;
  Result := LzmaDec_DecodeToBuf(FDecoderState, Dest, NativeDestLen, Src, NativeSrcLen,
    LZMA_FINISH_ANY, Status);
  DestLen := Cardinal(NativeDestLen);
  SrcLen := Cardinal(NativeSrcLen);
end;

{ TLZMA2Decompressor }

procedure TLZMA2Decompressor.FreeDecoder;
begin
  IS_Lzma2Dec_Free(FDecoderState, LZMAAlloc);
end;

procedure TLZMA2Decompressor.ProcessHeader;

  { Macro from Lzma2Dec.c: }
  function LZMA2_DIC_SIZE_FROM_PROP(p: Cardinal): Cardinal;
  begin
    Result := (2 or (p and 1)) shl (p div 2 + 11);
  end;

var
  Prop: Byte;
  StateSize, DecoderStateSize: NativeUInt;
begin
  { Read header fields }
  if ReadProc(Prop, SizeOf(Prop)) <> SizeOf(Prop) then
    LZMADecompDataError(1);

  if Prop > 40 then
    LZMADecompDataError(5)
  else if Prop = 40 then begin
    { Lzma2Enc_WriteProperties in Lzma2Enc.c writes 40 for any dictionary size above
      the size for 39, which is 3 GB. So only accept 40 if MaxDictionarySize is above 3 GB. }
    if LZMA2_DIC_SIZE_FROM_PROP(39) >= MaxDictionarySize then
      LZMADecompDataError(5);
  end else if LZMA2_DIC_SIZE_FROM_PROP(Prop) > MaxDictionarySize then
    LZMADecompDataError(5);

  StateSize := IS_Lzma2Dec_StateSize;
  DecoderStateSize := SizeOf(FDecoderState);
  if StateSize > DecoderStateSize then
    LZMADecompDataError(-Integer(StateSize));

  { Note: IS_Lzma2Dec_Init will re-use already-allocated memory if it can.
    FDecoderState is assumed to be initialized to zero on the first call. }
  case IS_Lzma2Dec_Init(FDecoderState, DecoderStateSize, Prop,
     LZMAAlloc) of
    SZ_OK: ;
    SZ_ERROR_MEM: OutOfMemoryError;
  else
    { SZ_ERROR_UNSUPPORTED and anything else }
    LZMADecompDataError(2);
  end;
end;

function TLZMA2Decompressor.DecodeToBuf(var Dest; var DestLen: Cardinal;
  const Src; var SrcLen: Cardinal; var Status: Integer): Integer;
var
  NativeDestLen, NativeSrcLen: NativeUInt;
begin
  NativeDestLen := DestLen;
  NativeSrcLen := SrcLen;
  Result := Lzma2Dec_DecodeToBuf(FDecoderState, Dest, NativeDestLen, Src, NativeSrcLen,
    LZMA_FINISH_ANY, Status);
  DestLen := Cardinal(NativeDestLen);
  SrcLen := Cardinal(NativeSrcLen);
end;

end.
