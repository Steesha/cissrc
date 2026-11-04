unit PBKDF2;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  PBKDF2-HMAC-SHA256 password-based key derivation
}

interface

uses
  SysUtils;

function PBKDF2SHA256(const Password: TBytes; const Salt: TBytes; const Iterations, KeyLength: Integer): TBytes; overload;
function PBKDF2SHA256(const Password: String; const Salt: TBytes; const Iterations, KeyLength: Integer): TBytes; overload;

implementation

uses
  SHA256;

type
  THMACSHA256Context = record
    Inner, Outer: TSHA256Context;
  end;

procedure InitHMAC(var Context: THMACSHA256Context; const Password: TBytes);
var
  Pad: array[0..63] of Byte;
  Digest: TSHA256Digest;
  I: Integer;
begin
  FillChar(Pad, SizeOf(Pad), 0);
  FillChar(Digest, SizeOf(Digest), 0);
  try
    if Length(Password) > SizeOf(Pad) then begin
      Digest := SHA256Buf(Password[0], Length(Password));
      Move(Digest, Pad, SizeOf(Digest));
    end else if Length(Password) > 0 then
      Move(Password[0], Pad, Length(Password));
    for I := Low(Pad) to High(Pad) do
      Pad[I] := Pad[I] xor $36;
    SHA256Init(Context.Inner);
    SHA256Update(Context.Inner, Pad, SizeOf(Pad));
    for I := Low(Pad) to High(Pad) do
      Pad[I] := Pad[I] xor $36 xor $5c;
    SHA256Init(Context.Outer);
    SHA256Update(Context.Outer, Pad, SizeOf(Pad));
  finally
    FillChar(Pad, SizeOf(Pad), 0);
    FillChar(Digest, SizeOf(Digest), 0);
  end;
end;

function HMAC(const Context: THMACSHA256Context; const Buffer;
  const Count: Cardinal): TSHA256Digest;
var
  Inner, Outer: TSHA256Context;
  Digest: TSHA256Digest;
begin
  Inner := Context.Inner;
  Outer := Context.Outer;
  try
    SHA256Update(Inner, Buffer, Count);
    Digest := SHA256Final(Inner);
    SHA256Update(Outer, Digest, SizeOf(Digest));
    Result := SHA256Final(Outer);
  finally
    FillChar(Inner, SizeOf(Inner), 0);
    FillChar(Outer, SizeOf(Outer), 0);
    FillChar(Digest, SizeOf(Digest), 0);
  end;
end;

function PBKDF2SHA256(const Password: TBytes; const Salt: TBytes;
  const Iterations, KeyLength: Integer): TBytes;
var
  Context: THMACSHA256Context;
  SaltAndBlock: TBytes;
  U, F: TSHA256Digest;
  Block: Cardinal;
  BytesDone, BytesToCopy, I, J: Integer;
begin
  if (Iterations < 1) or (KeyLength < 0) then
    raise EArgumentException.Create('Invalid PBKDF2 iterations or key length');
  Result := nil;
  SetLength(Result, KeyLength);
  if KeyLength = 0 then
    Exit;
  InitHMAC(Context, Password);
  try
    SetLength(SaltAndBlock, Length(Salt) + 4);
    if Length(Salt) > 0 then
      Move(Salt[0], SaltAndBlock[0], Length(Salt));
    BytesDone := 0;
    Block := 1;
    while BytesDone < KeyLength do begin
      for I := 0 to 3 do
        SaltAndBlock[Length(Salt) + I] := Byte(Block shr ((3 - I) * 8));
      U := HMAC(Context, SaltAndBlock[0], Length(SaltAndBlock));
      F := U;
      for I := 2 to Iterations do begin
        U := HMAC(Context, U, SizeOf(U));
        for J := Low(F) to High(F) do
          F[J] := F[J] xor U[J];
      end;
      BytesToCopy := KeyLength - BytesDone;
      if BytesToCopy > SizeOf(F) then
        BytesToCopy := SizeOf(F);
      Move(F, Result[BytesDone], BytesToCopy);
      Inc(BytesDone, BytesToCopy);
      Inc(Block);
    end;
  finally
    FillChar(Context, SizeOf(Context), 0);
    FillChar(U, SizeOf(U), 0);
    FillChar(F, SizeOf(F), 0);
  end;
end;

function PBKDF2SHA256(const Password: String; const Salt: TBytes;
  const Iterations, KeyLength: Integer): TBytes;
var
  PasswordBytes: TBytes;
  I: Integer;
begin
  { The installer format uses UTF-16LE password bytes on every host }
  SetLength(PasswordBytes, Length(Password) * 2);
  for I := 1 to Length(Password) do begin
    PasswordBytes[(I-1)*2] := Byte(Ord(Password[I]));
    PasswordBytes[(I-1)*2+1] := Byte(Ord(Password[I]) shr 8);
  end;
  try
    Result := PBKDF2SHA256(PasswordBytes, Salt, Iterations, KeyLength);
  finally
    if Length(PasswordBytes) > 0 then
      FillChar(PasswordBytes[0], Length(PasswordBytes), 0);
  end;
end;

end.
