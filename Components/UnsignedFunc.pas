unit UnsignedFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Provides unsigned alternatives to Delphi functions that use signed types for parameters or return
  values where unsigned types would have been more appropriate
}

interface

uses
  SysUtils;

function ULength(const S: String): Cardinal; overload; inline;
function ULength(const S: RawByteString): Cardinal; overload; inline;
function ULength(const S: WideString): Cardinal; overload; inline;
function ULength(const S: TBytes): Cardinal; overload; inline;
procedure UMove(const Source; var Dest; Count: NativeUInt);
procedure UFillChar(var Dest; Count: NativeUInt; const Value: Integer);
function UCompareMem(P1, P2: Pointer; Length: NativeUInt): Boolean;

implementation

function ULength(const S: String): Cardinal;
begin
  Result := Cardinal(Length(S));
end;

function ULength(const S: RawByteString): Cardinal;
begin
  Result := Cardinal(Length(S));
end;

function ULength(const S: WideString): Cardinal;
begin
  Result := Cardinal(Length(S));
end;

function ULength(const S: TBytes): Cardinal;
begin
  Result := Cardinal(Length(S));
end;

procedure UMove(const Source; var Dest; Count: NativeUInt);
var
  SourceBuf, DestBuf: PByte;
  Backward: Boolean;
  SignedCount: NativeInt;
begin
  SourceBuf := @Source;
  DestBuf := @Dest;
  Backward := NativeUInt(DestBuf) > NativeUInt(SourceBuf);
  if Backward then begin
    Inc(SourceBuf, Count);
    Inc(DestBuf, Count);
  end;
  while Count > 0 do begin
    SignedCount := High(NativeInt);
    if Count < NativeUInt(SignedCount) then
      SignedCount := NativeInt(Count);
    if Backward then begin
      Dec(SourceBuf, SignedCount);
      Dec(DestBuf, SignedCount);
    end;
    Move(SourceBuf^, DestBuf^, SignedCount);
    Dec(Count, SignedCount);
    if not Backward then begin
      Inc(SourceBuf, SignedCount);
      Inc(DestBuf, SignedCount);
    end;
  end;
end;

procedure UFillChar(var Dest; Count: NativeUInt; const Value: Integer);
var
  DestBuf: PByte;
  SignedCount: NativeInt;
begin
  DestBuf := @Dest;
  while Count > 0 do begin
    SignedCount := High(NativeInt);
    if Count < NativeUInt(SignedCount) then
      SignedCount := NativeInt(Count);
    FillChar(DestBuf^, SignedCount, Value);
    Dec(Count, SignedCount);
    Inc(DestBuf, SignedCount);
  end;
end;

function UCompareMem(P1, P2: Pointer; Length: NativeUInt): Boolean;
var
  SignedLength: NativeInt;
begin
  Result := True;
  if P1 <> P2 then begin
    while Length > 0 do begin
      SignedLength := High(Integer);
      if Length < Cardinal(SignedLength) then
        SignedLength := Integer(Length);
      if not CompareMem(P1, P2, SignedLength) then
        Exit(False);
      Dec(Length, SignedLength);
      Inc(PByte(P1), SignedLength);
      Inc(PByte(P2), SignedLength);
    end;
  end;
end;

end.
