unit Shared.CompilerSupport;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Host-independent helpers used by the compiler entry point
}

interface

type
  TSimpleLock = record
  strict private
    {$IFNDEF FPC}[volatile]{$ENDIF} FLockValue: Integer;
  public
    class function Create: TSimpleLock; static;
    procedure Release;
    function TryAcquire: Boolean;
  end;

function AddPeriod(const S: String): String;
function GetExceptMessage: String;
function TryStrToBoolean(const S: String; var BoolResult: Boolean): Boolean;
function RemoveQuotes(const S: String): String;
procedure SkipWhitespace(var S: PChar);

function WildcardMatch(const Text, Pattern: PChar): Boolean;

function SkipPastConst(const S: String; const Start: Integer): Integer;
function ConvertConstPercentStr(var S: String): Boolean;
function ConstPos(const Ch: Char; const S: String): Integer;

{$IFNDEF MSWINDOWS}
function TryStrToDWord(const S: String; out Value: Cardinal): Boolean;
function TryStrToQWord(const S: String; out Value: UInt64): Boolean;
{$ENDIF}

implementation

uses
  SysUtils, Shared.FPCStringUtils;

{ TSimpleLock }

class function TSimpleLock.Create: TSimpleLock;
begin
  Result.FLockValue := 0;
end;

procedure TSimpleLock.Release;
begin
  {$IFDEF FPC}
  System.InterlockedExchange(FLockValue, 0);
  {$ELSE}
  AtomicExchange(FLockValue, 0);
  {$ENDIF}
end;

function TSimpleLock.TryAcquire: Boolean;
begin
  {$IFDEF FPC}
  Result := System.InterlockedCompareExchange(FLockValue, 1, 0) = 0;
  {$ELSE}
  AtomicCmpExchange(FLockValue, 1, 0, Result);
  {$ENDIF}
end;

function AddPeriod(const S: String): String;
{ Returns the specified string with a full stop character (U+002E) appended,
  unless the string is empty, already ends with a sentence-terminating
  character, ends with a control character (such as CR or LF), or ends with
  a Thai or Lao character (these do not end sentences with a full stop),
  in which case the string is returned unchanged. }
begin
  if S <> '' then begin
    { This list is not intended to be exhaustive; it includes characters that
      are known/expected to be used in Inno Setup .isl translations.
      Keep the isxfunc.xml AddPeriod topic's table in sync. }
    case S[High(S)] of
      #0..#$001F, { Control characters (don't want '.' after trailing CR/LF) }
      '!',     { Exclamation Mark }
      '.',     { Full Stop }
      '?',     { Question Mark }
      #$0589,  { Armenian Full Stop }
      #$061F,  { Arabic Question Mark }
      #$06D4,  { Arabic Full Stop (used in Urdu, not Arabic) }
      #$0964..#$0965, { Devanagari Danda and Double Danda (used across Indic scripts) }
      #$0E00..#$0EFF, { Thai and Lao blocks (sentences do not end in a full stop) }
      #$104A..#$104B, { Myanmar sentence terminators }
      #$1362,  { Ethiopic Full Stop }
      #$1367,  { Ethiopic Question Mark }
      #$17D4..#$17D5, { Khmer sentence terminators }
      #$17DA,         { Khmer end-of-text mark }
      #$3002,  { Ideographic Full Stop (used in Japanese and Chinese) }
      #$FF01,  { Fullwidth Exclamation Mark }
      #$FF0E,  { Fullwidth Full Stop }
      #$FF1F:  { Fullwidth Question Mark }
        ;
    else
      Exit(S + '.');
    end;
  end;
  Result := S;
end;

function GetExceptMessage: String;
var
  E: TObject;
begin
  E := ExceptObject;
  if E = nil then
    Result := '[ExceptObject=nil]'   { should never get here }
  else if E is Exception then
    Result := AddPeriod(FromNativeText(Exception(E).Message))   { usual case }
  else
    Result := UnicodeString(E.ClassName);   { shouldn't get here under normal circumstances }
end;

function TryStrToBoolean(const S: String; var BoolResult: Boolean): Boolean;
begin
  if (S = '0') or (InnoCompareText(S, 'no') = 0) or (InnoCompareText(S, 'false') = 0) then begin
    BoolResult := False;
    Result := True;
  end
  else if (S = '1') or (InnoCompareText(S, 'yes') = 0) or (InnoCompareText(S, 'true') = 0) then begin
    BoolResult := True;
    Result := True;
  end
  else
    Result := False;
end;

function RemoveQuotes(const S: String): String;
{ Opposite of AddQuotes; removes any quotes around the string. }
begin
  Result := S;
  while (Result <> '') and (Result[1] = '"') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '"') do
    SetLength(Result, Length(Result)-1);
end;

procedure SkipWhitespace(var S: PChar);
begin
  while CharInSet(S^, [#1..' ']) do
    Inc(S);
end;

function WildcardMatch(const Text, Pattern: PChar): Boolean;
{ General-purpose wildcard matching function based on the widely used wildcat()
  code by Rich $alz. In this implementation, however, the only supported
  pattern matching characters are ? and *.
  Note that this function uses Unix shell semantics -- e.g. a dot always
  matches a dot (so a pattern of '*.*' won't match 'file'), and ? always
  matches exactly 1 character (so '?????' won't match 'file').
  Also note: The InternalWildcardMatch function can recursively call itself
  for each non-consecutive * character in the pattern. With enough *
  characters, the stack could overflow. So ideally the caller should impose a
  limit on either the length of the pattern string or the number of *
  characters in it. }
type
  TWildcardMatchResult = (wmFalse, wmTrue, wmAbort);

  function InternalWildcardMatch(T, P: PChar): TWildcardMatchResult;
  begin
    while P^ <> #0 do begin
      if (T^ = #0) and (P^ <> '*') then begin
        Result := wmAbort;
        Exit;
      end;
      case P^ of
        '?': ;  { Match any character }
        '*': begin
               Inc(P);
               while P^ = '*' do begin
                 { Consecutive stars act just like one }
                 Inc(P);
               end;
               if P^ = #0 then begin
                 { Trailing star matches everything }
                 Result := wmTrue;
                 Exit;
               end;
               while T^ <> #0 do begin
                 Result := InternalWildcardMatch(T, P);
                 if Result <> wmFalse then
                   Exit;
                 Inc(T);
               end;
               Result := wmAbort;
               Exit;
             end;
      else
        if T^ <> P^ then begin
          Result := wmFalse;
          Exit;
        end;
      end;
      Inc(T);
      Inc(P);
    end;
    if T^ = #0 then
      Result := wmTrue
    else
      Result := wmFalse;
  end;

begin
  Result := (InternalWildcardMatch(Text, Pattern) = wmTrue);
end;

function SkipPastConst(const S: String; const Start: Integer): Integer;
{ Returns the character index following the Inno Setup constant embedded
  into the string S at index Start.
  If the constant is not closed (missing a closing brace), it returns zero. }
var
  L, BraceLevel, LastOpenBrace: Integer;
begin
  Result := Start;
  L := Length(S);
  if Result < L then begin
    Inc(Result);
    if S[Result] = '{' then begin
      Inc(Result);
      Exit;
    end
    else begin
      BraceLevel := 1;
      LastOpenBrace := -1;
      while Result <= L do begin
        case S[Result] of
          '{': begin
                   if LastOpenBrace <> Result-1 then begin
                     Inc(BraceLevel);
                     LastOpenBrace := Result;
                   end
                   else
                     { Skip over '{{' when in an embedded constant }
                     Dec(BraceLevel);
                 end;
          '}': begin
                 Dec(BraceLevel);
                 if BraceLevel = 0 then begin
                   Inc(Result);
                   Exit;
                 end;
               end;
        end;
        Inc(Result);
      end;
    end;
  end;
  Result := 0;
end;

function ConvertConstPercentStr(var S: String): Boolean;
{ Same as ConvertPercentStr, but is designed to ignore embedded Inno Setup
  constants. Any '%' characters between braces are not translated. Two
  consecutive braces are ignored. }
var
  I, C, E: Integer;
  N: String;
begin
  Result := True;
  I := 1;
  while I <= Length(S) do begin
    case S[I] of
      '{': begin
             I := SkipPastConst(S, I);
             if I = 0 then begin
               Result := False;
               Break;
             end;
             Dec(I);  { ...since there's an Inc below }
           end;
      '%': begin
             N := Copy(S, I, 3);
             if Length(N) <> 3 then begin
               Result := False;
               Break;
             end;
             N[1] := '$';
             Val(N, C, E);
             if E <> 0 then begin
               Result := False;
               Break;
             end;
             { delete the two numbers following '%', and replace '%' with the character }
             Delete(S, I+1, 2);
             S[I] := Chr(C);
           end;
    end;
    Inc(I);
  end;
end;

function ConstPos(const Ch: Char; const S: String): Integer;
{ Like the standard Pos function, but skips over any Inno Setup constants
  embedded in S }
var
  I, L: Integer;
begin
  Result := 0;
  I := 1;
  L := Length(S);
  while I <= L do begin
    if S[I] = Ch then begin
      Result := I;
      Break;
    end
    else if S[I] = '{' then begin
      I := SkipPastConst(S, I);
      if I = 0 then
        Break;
    end
    else
      Inc(I);
  end;
end;

{$IFNDEF MSWINDOWS}
function TryParseRegistryInteger(const S: String; const MaxUnsigned, MaxNegativeDecimal: UInt64;
  out Value: UInt64): Boolean;
var
  Digits: String;
  Negative, Hex: Boolean;
  FirstDigit, I, ErrorIndex: Integer;
  Magnitude: UInt64;
begin
  Digits := Trim(S);
  if Digits = '' then
    Exit(False);
  Negative := Digits[1] = '-';
  if Negative or (Digits[1] = '+') then
    Delete(Digits, 1, 1);
  if Digits = '' then
    Exit(False);

  FirstDigit := 1;
  if Digits[1] = '$' then
    FirstDigit := 2
  else if (Length(Digits) >= 2) and (Digits[1] = '0') and (UpCase(Digits[2]) = 'X') then
    FirstDigit := 3;
  Hex := FirstDigit <> 1;
  if FirstDigit > Length(Digits) then
    Exit(False);
  for I := FirstDigit to Length(Digits) do
    if not CharInSet(UpCase(Digits[I]), ['0'..'9']) and
       not (Hex and CharInSet(UpCase(Digits[I]), ['A'..'F'])) then
      Exit(False);

  Val(Digits, Magnitude, ErrorIndex);
  if (ErrorIndex <> 0) or (Magnitude > MaxUnsigned) or
     (Negative and not Hex and (Magnitude > MaxNegativeDecimal)) then
    Exit(False);
  if Negative and (Magnitude <> 0) then
    Value := MaxUnsigned - Magnitude + 1
  else
    Value := Magnitude;
  Result := True;
end;

function TryStrToDWord(const S: String; out Value: Cardinal): Boolean;
var
  Parsed: UInt64;
begin
  Result := TryParseRegistryInteger(S, High(Cardinal), UInt64(High(Integer)) + 1, Parsed);
  if Result then
    Value := Cardinal(Parsed);
end;

function TryStrToQWord(const S: String; out Value: UInt64): Boolean;
begin
  Result := TryParseRegistryInteger(S, High(UInt64), UInt64(High(Int64)) + 1, Value);
end;
{$ENDIF}

end.
