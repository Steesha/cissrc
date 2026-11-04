unit SHA256;

{
  SHA256.pas: portable SHA-256 in the style of the old MD5.pas and SHA1.pas
  Author: Martijn Laan
  License for SHA256.pas: Public domain, no copyright claimed
}

interface

type
  TSHA256Context = record
    State: array[0..7] of Cardinal;
    Buffer: array[0..63] of Byte;
    BufferUsed: Cardinal;
    TotalBytes: UInt64;
  end;
  TSHA256Digest = array[0..31] of Byte;

procedure SHA256Init(var ctx: TSHA256Context);
procedure SHA256Update(var ctx: TSHA256Context; const buffer; len: Cardinal);
function SHA256Final(var ctx: TSHA256Context): TSHA256Digest;

function SHA256Buf(const Buffer; Len: Cardinal): TSHA256Digest;
function SHA256DigestsEqual(const A, B: TSHA256Digest): Boolean;
function SHA256DigestToString(const D: TSHA256Digest): String;
function SHA256DigestFromString(const S: String): TSHA256Digest;

implementation

uses
  SysUtils;

{$Q-} { SHA-256 uses arithmetic modulo 2^32 }

function RotateRight(const Value: Cardinal; const Bits: Byte): Cardinal; inline;
begin
  Result := (Value shr Bits) or (Value shl (32 - Bits));
end;

procedure SHA256Transform(var ctx: TSHA256Context);
const
  K: array[0..63] of Cardinal = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);
var
  W: array[0..63] of Cardinal;
  A, B, C, D, E, F, G, H, T1, T2, S0, S1: Cardinal;
  I, J: Integer;
begin
  for I := 0 to 15 do begin
    J := I * 4;
    W[I] := (Cardinal(ctx.Buffer[J]) shl 24) or (Cardinal(ctx.Buffer[J+1]) shl 16) or
      (Cardinal(ctx.Buffer[J+2]) shl 8) or Cardinal(ctx.Buffer[J+3]);
  end;
  for I := 16 to 63 do begin
    S0 := RotateRight(W[I-15], 7) xor RotateRight(W[I-15], 18) xor (W[I-15] shr 3);
    S1 := RotateRight(W[I-2], 17) xor RotateRight(W[I-2], 19) xor (W[I-2] shr 10);
    W[I] := Cardinal(W[I-16] + S0 + W[I-7] + S1);
  end;
  A := ctx.State[0]; B := ctx.State[1]; C := ctx.State[2]; D := ctx.State[3];
  E := ctx.State[4]; F := ctx.State[5]; G := ctx.State[6]; H := ctx.State[7];
  for I := 0 to 63 do begin
    S1 := RotateRight(E, 6) xor RotateRight(E, 11) xor RotateRight(E, 25);
    T1 := Cardinal(H + S1 + ((E and F) xor ((not E) and G)) + K[I] + W[I]);
    S0 := RotateRight(A, 2) xor RotateRight(A, 13) xor RotateRight(A, 22);
    T2 := Cardinal(S0 + ((A and B) xor (A and C) xor (B and C)));
    H := G; G := F; F := E; E := Cardinal(D + T1);
    D := C; C := B; B := A; A := Cardinal(T1 + T2);
  end;
  ctx.State[0] := Cardinal(ctx.State[0] + A); ctx.State[1] := Cardinal(ctx.State[1] + B); ctx.State[2] := Cardinal(ctx.State[2] + C); ctx.State[3] := Cardinal(ctx.State[3] + D);
  ctx.State[4] := Cardinal(ctx.State[4] + E); ctx.State[5] := Cardinal(ctx.State[5] + F); ctx.State[6] := Cardinal(ctx.State[6] + G); ctx.State[7] := Cardinal(ctx.State[7] + H);
  FillChar(W, SizeOf(W), 0);
end;

procedure SHA256Init(var ctx: TSHA256Context);
const
  Initial: array[0..7] of Cardinal = (
    $6a09e667, $bb67ae85, $3c6ef372, $a54ff53a, $510e527f, $9b05688c, $1f83d9ab, $5be0cd19);
begin
  FillChar(ctx, SizeOf(ctx), 0);
  Move(Initial, ctx.State, SizeOf(Initial));
end;

procedure SHA256Update(var ctx: TSHA256Context; const buffer; len: Cardinal);
var
  Source: PByte;
  Count: Cardinal;
begin
  Source := @buffer;
  Inc(ctx.TotalBytes, len);
  while len > 0 do begin
    Count := 64 - ctx.BufferUsed;
    if Count > len then
      Count := len;
    Move(Source^, ctx.Buffer[ctx.BufferUsed], Count);
    Inc(Source, Count);
    Inc(ctx.BufferUsed, Count);
    Dec(len, Count);
    if ctx.BufferUsed = 64 then begin
      SHA256Transform(ctx);
      ctx.BufferUsed := 0;
    end;
  end;
end;

function SHA256Final(var ctx: TSHA256Context): TSHA256Digest;
var
  Bits: UInt64;
  I: Integer;
begin
  Bits := ctx.TotalBytes shl 3;
  ctx.Buffer[ctx.BufferUsed] := $80;
  Inc(ctx.BufferUsed);
  if ctx.BufferUsed > 56 then begin
    if ctx.BufferUsed < 64 then
      FillChar(ctx.Buffer[ctx.BufferUsed], 64 - ctx.BufferUsed, 0);
    SHA256Transform(ctx);
    ctx.BufferUsed := 0;
  end;
  FillChar(ctx.Buffer[ctx.BufferUsed], 56 - ctx.BufferUsed, 0);
  for I := 0 to 7 do
    ctx.Buffer[56 + I] := Byte(Bits shr ((7 - I) * 8));
  SHA256Transform(ctx);
  for I := 0 to 31 do
    Result[I] := Byte(ctx.State[I div 4] shr ((3 - I mod 4) * 8));
  FillChar(ctx, SizeOf(ctx), 0);
end;

function SHA256Buf(const Buffer; Len: Cardinal): TSHA256Digest;
var
  Context: TSHA256Context;
begin
  SHA256Init(Context);
  SHA256Update(Context, Buffer, Len);
  Result := SHA256Final(Context);
end;

function SHA256DigestsEqual(const A, B: TSHA256Digest): Boolean;
var
  Diff: Byte;
  I: Integer;
begin
  { Security: constant-time comparison to prevent timing side channels }
  Diff := 0;
  for I := Low(TSHA256Digest) to High(TSHA256Digest) do
    Diff := Diff or (A[I] xor B[I]);
  Result := Diff = 0;
end;

function SHA256DigestToString(const D: TSHA256Digest): String;
const
  Digits: array[0..15] of Char = '0123456789abcdef';
var
  Buf: array[0..63] of Char;
  P: PChar;
  I: Integer;
begin
  P := @Buf[0];
  for I := 0 to 31 do begin
    P^ := Digits[D[I] shr 4];
    Inc(P);
    P^ := Digits[D[I] and 15];
    Inc(P);
  end;
  SetString(Result, Buf, 64);
end;

function SHA256DigestFromString(const S: String): TSHA256Digest;
var
  I, ResultIndex: Integer;
  B: Byte;
  C: Char;
begin
  if Length(S) <> 64 then
    raise EConvertError.Create('Invalid string length');

  for I := 0 to 63 do begin
    C := UpCase(S[I+1]);
    case C of
      '0'..'9': B := Byte(Ord(C) - Ord('0'));
      'A'..'F': B := Byte(Ord(C) - (Ord('A') - 10));
    else
      raise EConvertError.Create('Invalid digit character');
    end;
    ResultIndex := I shr 1;
    if not Odd(I) then
      Result[ResultIndex] := Byte(B shl 4)
    else
      Result[ResultIndex] := Result[ResultIndex] or B;
  end;
end;

end.
