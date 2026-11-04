unit Shared.FPCStringUtils;

{
  Inno Setup
  Copyright (C) 2026 Inno Setup contributors
  For conditions of distribution and use, see LICENSE.TXT.

  Unicode RTL entry points for the compiler hosts
}

{$IFDEF FPC}{$MODE DELPHIUNICODE}{$ENDIF}

interface

uses SysUtils;

function InnoCompareText(const A, B: UnicodeString): Integer;
function InnoCompareStr(const A, B: UnicodeString): Integer;
function InnoSameText(const A, B: UnicodeString): Boolean;
function InnoSameStr(const A, B: UnicodeString): Boolean;
function InnoFormat(const Fmt: UnicodeString; const Args: array of const): UnicodeString; overload;
function InnoFormat(const Fmt: UnicodeString; const Args: array of const;
  const Settings: TFormatSettings): UnicodeString; overload;
function InnoIntToStr(Value: Int64): UnicodeString; overload;
function InnoIntToStr(Value: UInt64): UnicodeString; overload;
function InnoIntToHex(Value: Int64; Digits: Integer): UnicodeString; overload;
function InnoIntToHex(Value: UInt64; Digits: Integer): UnicodeString; overload;
function InnoStrToInt(const S: UnicodeString): Integer;
function InnoStrToInt64(const S: UnicodeString): Int64;
function InnoStrToIntDef(const S: UnicodeString; Default: Integer): Integer;
function InnoTryStrToInt(const S: UnicodeString; out Value: Integer): Boolean;
function ToNativeText(const S: UnicodeString): {$IFDEF FPC}UTF8String{$ELSE}UnicodeString{$ENDIF};
function FromNativeText(const S: {$IFDEF FPC}RawByteString{$ELSE}UnicodeString{$ENDIF}): UnicodeString;
function InnoTryStrToInt64(const S: UnicodeString; out Value: Int64): Boolean;
function InnoStringReplace(const S, OldText, NewText: UnicodeString; Flags: TReplaceFlags): UnicodeString;
function InnoFormatDateTime(const Fmt: UnicodeString; Value: TDateTime): UnicodeString;

implementation

function InnoCompareText(const A, B: UnicodeString): Integer;
begin
  Result := {$IFDEF FPC}UnicodeCompareText{$ELSE}SysUtils.CompareText{$ENDIF}(A, B);
end;

function InnoCompareStr(const A, B: UnicodeString): Integer;
begin
  Result := {$IFDEF FPC}UnicodeCompareStr{$ELSE}SysUtils.CompareStr{$ENDIF}(A, B);
end;

function InnoSameText(const A, B: UnicodeString): Boolean;
begin
  Result := {$IFDEF FPC}UnicodeSameText{$ELSE}SysUtils.SameText{$ENDIF}(A, B);
end;

function InnoSameStr(const A, B: UnicodeString): Boolean;
begin
  Result := {$IFDEF FPC}UnicodeSameStr{$ELSE}SysUtils.SameStr{$ENDIF}(A, B);
end;

function InnoFormat(const Fmt: UnicodeString; const Args: array of const): UnicodeString;
begin
  Result := {$IFDEF FPC}UnicodeFormat{$ELSE}SysUtils.Format{$ENDIF}(Fmt, Args);
end;

function InnoFormat(const Fmt: UnicodeString; const Args: array of const;
  const Settings: TFormatSettings): UnicodeString;
begin
  Result := {$IFDEF FPC}UnicodeFormat{$ELSE}SysUtils.Format{$ENDIF}(Fmt, Args, Settings);
end;

function InnoIntToStr(Value: Int64): UnicodeString;
begin
  Result := UnicodeString(SysUtils.IntToStr(Value));
end;

function InnoIntToStr(Value: UInt64): UnicodeString;
begin
  Result := UnicodeString(SysUtils.IntToStr(Value));
end;

function InnoIntToHex(Value: Int64; Digits: Integer): UnicodeString;
begin
  Result := UnicodeString(SysUtils.IntToHex(Value, Digits));
end;

function InnoIntToHex(Value: UInt64; Digits: Integer): UnicodeString;
begin
  Result := UnicodeString(SysUtils.IntToHex(Value, Digits));
end;
function InnoStrToInt(const S: UnicodeString): Integer;
begin
  Result := SysUtils.StrToInt(ToNativeText(S));
end;

function InnoStrToInt64(const S: UnicodeString): Int64;
begin
  Result := SysUtils.StrToInt64(ToNativeText(S));
end;

function InnoStrToIntDef(const S: UnicodeString; Default: Integer): Integer;
begin
  Result := SysUtils.StrToIntDef(ToNativeText(S), Default);
end;

function InnoTryStrToInt(const S: UnicodeString; out Value: Integer): Boolean;
begin
  Result := SysUtils.TryStrToInt(ToNativeText(S), Value);
end;

function ToNativeText(const S: UnicodeString): {$IFDEF FPC}UTF8String{$ELSE}UnicodeString{$ENDIF};
begin
  Result := {$IFDEF FPC}UTF8Encode(S){$ELSE}S{$ENDIF};
end;

function FromNativeText(const S: {$IFDEF FPC}RawByteString{$ELSE}UnicodeString{$ENDIF}): UnicodeString;
begin
  Result := {$IFDEF FPC}UTF8Decode(S){$ELSE}S{$ENDIF};
end;

function InnoTryStrToInt64(const S: UnicodeString; out Value: Int64): Boolean;
begin
  Result := SysUtils.TryStrToInt64(ToNativeText(S), Value);
end;

function InnoStringReplace(const S, OldText, NewText: UnicodeString; Flags: TReplaceFlags): UnicodeString;
begin
  Result := {$IFDEF FPC}UnicodeStringReplace{$ELSE}SysUtils.StringReplace{$ENDIF}(S, OldText, NewText, Flags);
end;

function InnoFormatDateTime(const Fmt: UnicodeString; Value: TDateTime): UnicodeString;
begin
  Result := FromNativeText(SysUtils.FormatDateTime(ToNativeText(Fmt), Value));
end;

end.
