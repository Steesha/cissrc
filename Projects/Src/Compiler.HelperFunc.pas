unit Compiler.HelperFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Additional compiler functions
}

{$IFDEF FPC}{$MODESWITCH NESTEDPROCVARS}{$ENDIF}

interface

uses
  Classes, SysUtils, {$IFNDEF FPC}UITypes, {$ENDIF}
  Shared.FileClass;

{$IFDEF FPC}
type
  TColor = type Integer;
  TCheckedTrustProc = procedure(CheckedTrust: Boolean) of object;

const
  { Windows target color values used by the installer and Pascal Script }
  clScrollBar = Integer($FF000000);
  clBackground = Integer($FF000001);
  clActiveCaption = Integer($FF000002);
  clInactiveCaption = Integer($FF000003);
  clMenu = Integer($FF000004);
  clWindow = Integer($FF000005);
  clWindowFrame = Integer($FF000006);
  clMenuText = Integer($FF000007);
  clWindowText = Integer($FF000008);
  clCaptionText = Integer($FF000009);
  clActiveBorder = Integer($FF00000A);
  clInactiveBorder = Integer($FF00000B);
  clAppWorkSpace = Integer($FF00000C);
  clHighlight = Integer($FF00000D);
  clHighlightText = Integer($FF00000E);
  clBtnFace = Integer($FF00000F);
  clBtnShadow = Integer($FF000010);
  clGrayText = Integer($FF000011);
  clBtnText = Integer($FF000012);
  clInactiveCaptionText = Integer($FF000013);
  clBtnHighlight = Integer($FF000014);
  cl3DDkShadow = Integer($FF000015);
  cl3DLight = Integer($FF000016);
  clInfoText = Integer($FF000017);
  clInfoBk = Integer($FF000018);
  clBlack = $000000;
  clMaroon = $000080;
  clGreen = $008000;
  clOlive = $008080;
  clNavy = $800000;
  clPurple = $800080;
  clTeal = $808000;
  clGray = $808080;
  clSilver = $C0C0C0;
  clRed = $0000FF;
  clLime = $00FF00;
  clYellow = $00FFFF;
  clBlue = $FF0000;
  clFuchsia = $FF00FF;
  clAqua = $FFFF00;
  clLtGray = $C0C0C0;
  clDkGray = $808080;
  clWhite = $FFFFFF;
  clNone = $1FFFFFFF;
{$ELSE}
type
  TCheckedTrustProc = TProc<Boolean>;

const
  clScrollBar = TColors.SysScrollBar;
  clBackground = TColors.SysBackground;
  clActiveCaption = TColors.SysActiveCaption;
  clInactiveCaption = TColors.SysInactiveCaption;
  clMenu = TColors.SysMenu;
  clWindow = TColors.SysWindow;
  clWindowFrame = TColors.SysWindowFrame;
  clMenuText = TColors.SysMenuText;
  clWindowText = TColors.SysWindowText;
  clCaptionText = TColors.SysCaptionText;
  clActiveBorder = TColors.SysActiveBorder;
  clInactiveBorder = TColors.SysInactiveBorder;
  clAppWorkSpace = TColors.SysAppWorkSpace;
  clHighlight = TColors.SysHighlight;
  clHighlightText = TColors.SysHighlightText;
  clBtnFace = TColors.SysBtnFace;
  clBtnShadow = TColors.SysBtnShadow;
  clGrayText = TColors.SysGrayText;
  clBtnText = TColors.SysBtnText;
  clInactiveCaptionText = TColors.SysInactiveCaptionText;
  clBtnHighlight = TColors.SysBtnHighlight;
  cl3DDkShadow = TColors.Sys3DDkShadow;
  cl3DLight = TColors.Sys3DLight;
  clInfoText = TColors.SysInfoText;
  clInfoBk = TColors.SysInfoBk;

  clBlack = TColors.Black;
  clMaroon = TColors.Maroon;
  clGreen = TColors.Green;
  clOlive = TColors.Olive;
  clNavy = TColors.Navy;
  clPurple = TColors.Purple;
  clTeal = TColors.Teal;
  clGray = TColors.Gray;
  clSilver = TColors.Silver;
  clRed = TColors.Red;
  clLime = TColors.Lime;
  clYellow = TColors.Yellow;
  clBlue = TColors.Blue;
  clFuchsia = TColors.Fuchsia;
  clAqua = TColors.Aqua;
  clLtGray = TColors.LtGray;
  clDkGray = TColors.DkGray;
  clWhite = TColors.White;
  clNone = TColors.SysNone;
{$ENDIF}

function StringToColor(const S: string): TColor;
function CreateMemoryStreamFromFile(const Filename: String; const CheckTrust: Boolean = False;
  const OnCheckedTrust: TCheckedTrustProc = nil): TMemoryStream;
function FileSizeAndCRCIs(const Filename: String; const Size: Cardinal;
  const CRC: Longint): Boolean;
function IsX86OrX64Executable(const F: TFile): Boolean;
function CountChars(const S: String; C: Char): Integer;
function IsValidIdentString(const S: String; AllowBackslash, AllowOperators: Boolean): Boolean;
procedure SkipWhitespace(var S: PChar);
function ExtractWords(var S: PChar; const Sep: Char): String;
function UnescapeBraces(const S: String): String;

function BuildLanguageMessageData(const Messages: array of String): AnsiString;

implementation

uses
  PathFunc, TrustFunc,
  Compression.Base, Compiler.Messages, Shared.CompilerSupport, Shared.Struct;

type
  TColorEntry = record
    Value: TColor;
    Name: string;
  end;

const
  Colors: array[0..43] of TColorEntry = (
    (Value: clBlack; Name: 'clBlack'),
    (Value: clMaroon; Name: 'clMaroon'),
    (Value: clGreen; Name: 'clGreen'),
    (Value: clOlive; Name: 'clOlive'),
    (Value: clNavy; Name: 'clNavy'),
    (Value: clPurple; Name: 'clPurple'),
    (Value: clTeal; Name: 'clTeal'),
    (Value: clGray; Name: 'clGray'),
    (Value: clSilver; Name: 'clSilver'),
    (Value: clRed; Name: 'clRed'),
    (Value: clLime; Name: 'clLime'),
    (Value: clYellow; Name: 'clYellow'),
    (Value: clBlue; Name: 'clBlue'),
    (Value: clFuchsia; Name: 'clFuchsia'),
    (Value: clAqua; Name: 'clAqua'),
    (Value: clLtGray; Name: 'clLtGray'),
    (Value: clDkGray; Name: 'clDkGray'),
    (Value: clWhite; Name: 'clWhite'),
    (Value: clScrollBar; Name: 'clScrollBar'),
    (Value: clBackground; Name: 'clBackground'),
    (Value: clActiveCaption; Name: 'clActiveCaption'),
    (Value: clInactiveCaption; Name: 'clInactiveCaption'),
    (Value: clMenu; Name: 'clMenu'),
    (Value: clWindow; Name: 'clWindow'),
    (Value: clWindowFrame; Name: 'clWindowFrame'),
    (Value: clMenuText; Name: 'clMenuText'),
    (Value: clWindowText; Name: 'clWindowText'),
    (Value: clCaptionText; Name: 'clCaptionText'),
    (Value: clActiveBorder; Name: 'clActiveBorder'),
    (Value: clInactiveBorder; Name: 'clInactiveBorder'),
    (Value: clAppWorkSpace; Name: 'clAppWorkSpace'),
    (Value: clHighlight; Name: 'clHighlight'),
    (Value: clHighlightText; Name: 'clHighlightText'),
    (Value: clBtnFace; Name: 'clBtnFace'),
    (Value: clBtnShadow; Name: 'clBtnShadow'),
    (Value: clGrayText; Name: 'clGrayText'),
    (Value: clBtnText; Name: 'clBtnText'),
    (Value: clInactiveCaptionText; Name: 'clInactiveCaptionText'),
    (Value: clBtnHighlight; Name: 'clBtnHighlight'),
    (Value: cl3DDkShadow; Name: 'cl3DDkShadow'),
    (Value: cl3DLight; Name: 'cl3DLight'),
    (Value: clInfoText; Name: 'clInfoText'),
    (Value: clInfoBk; Name: 'clInfoBk'),
    (Value: clNone; Name: 'clNone'));

function StringToColor(const S: string): TColor;

  function IdentToColor(Ident: string; var Color: Integer): Boolean;
  var
    I: Integer;
  begin
    if not PathStartsWith(Ident, 'cl') then
      Ident := 'cl' + Ident;
    for I := Low(Colors) to High(Colors) do
      if PathSame(Colors[I].Name, Ident) then begin
        Color := Integer(Colors[I].Value);
        Exit(True);
      end;
    Result := False;
  end;

var
  Hex: String;
begin
  if not IdentToColor(S, Integer(Result)) then begin
    Hex := S;
    if (Length(Hex) = 7) and (Hex[1] = '#') then
      Hex := '$' + Copy(Hex, 6, 2)  + Copy(Hex, 4, 2) + Copy(Hex, 2, 2);
    Result := TColor(StrToInt({$IFDEF FPC}UTF8Encode(Hex){$ELSE}Hex{$ENDIF}));
  end;
end;

function CreateMemoryStreamFromFile(const Filename: String; const CheckTrust: Boolean;
  const OnCheckedTrust: TCheckedTrustProc): TMemoryStream;
{ Creates a TMemoryStream and loads the contents of the specified file into it }
var
  F: TFile;
  SizeOfFile: Cardinal;
  FS: TFileStream;
begin
  Result := TMemoryStream.Create;
  try
    if CheckTrust then begin
      try
        FS := CheckFileTrust(Filename, [cftoKeepOpen]);
      except
        {$IFDEF FPC}
        raise Exception.Create(UTF8Encode(UnicodeFormat(
          SCompilerCheckPrecompiledFileTrustError, [GetExceptMessage])));
        {$ELSE}
        raise Exception.CreateFmt(SCompilerCheckPrecompiledFileTrustError, [GetExceptMessage]);
        {$ENDIF}
      end;
    end else
      FS := nil;
    try
      if Assigned(OnCheckedTrust) then
        OnCheckedTrust(CheckTrust);

      {$IFNDEF MSWINDOWS}
      { Read from the verified handle so a path replacement cannot redirect the read }
      if Assigned(FS) then begin
        FS.Position := 0;
        SizeOfFile := High(Int32);
        if FS.Size < SizeOfFile then
          SizeOfFile := Cardinal(FS.Size);
        Result.SetSize(SizeOfFile);
        if SizeOfFile <> 0 then
          FS.ReadBuffer(Result.Memory^, SizeOfFile);
        Exit;
      end;
      {$ENDIF}

      { Why not use TMemoryStream.LoadFromFile here?
        1. On Delphi 2 it opens files for exclusive access (not good).
        2. It doesn't give specific error messages. }
      F := TFile.Create(Filename, fdOpenExisting, faRead, fsRead);
      try
        SizeOfFile := F.CappedSize;
        Result.SetSize(SizeOfFile);
        F.ReadBuffer(Result.Memory^, SizeOfFile);
      finally
        F.Free;
      end;
    finally
      FS.Free;
    end;
  except
    Result.Free;
    {$IFDEF FPC}
    raise Exception.Create(UTF8Encode(UnicodeFormat(SCompilerReadError, [Filename, GetExceptMessage])));
    {$ELSE}
    raise Exception.CreateFmt(SCompilerReadError, [Filename, GetExceptMessage]);
    {$ENDIF}
  end;
end;

function FileSizeAndCRCIs(const Filename: String; const Size: Cardinal;
  const CRC: Longint): Boolean;
var
  F: TFile;
  Buf: AnsiString;
begin
  Result := False;
  try
    F := TFile.Create(Filename, fdOpenExisting, faRead, fsRead);
    try
      if F.Size = Size then begin
        SetLength(Buf, Size);
        F.ReadBuffer(Buf[1], Size);
        if GetCRC32(Buf[1], Size) = CRC then
          Result := True;
      end;
    finally
      F.Free;
    end;
  except
  end;
end;

const
  IMAGE_NT_SIGNATURE = $00004550;  { 'PE'#0#0 }

function IsX86OrX64Executable(const F: TFile): Boolean;
const
  IMAGE_FILE_MACHINE_I386 = $014C;
  IMAGE_FILE_MACHINE_AMD64 = $8664;
var
  DosHeader: array[0..63] of Byte;
  PEHeaderOffset: Longint;
  PESigAndHeader: packed record
    Sig: UInt32;
    Machine: Word;
  end;
begin
  Result := False;
  if F.Read(DosHeader, SizeOf(DosHeader)) = SizeOf(DosHeader) then begin
    if (DosHeader[0] = Ord('M')) and (DosHeader[1] = Ord('Z')) then begin
      PEHeaderOffset := PInteger(@DosHeader[60])^;
      if PEHeaderOffset > 0 then begin
        F.Seek(PEHeaderOffset);
        if F.Read(PESigAndHeader, SizeOf(PESigAndHeader)) = SizeOf(PESigAndHeader) then begin
          if (PESigAndHeader.Sig = IMAGE_NT_SIGNATURE) and
             ((PESigAndHeader.Machine = IMAGE_FILE_MACHINE_I386) or
              (PESigAndHeader.Machine = IMAGE_FILE_MACHINE_AMD64)) then
            Result := True;
        end;
      end;
    end;
  end;
  F.Seek(0);
end;

function CountChars(const S: String; C: Char): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] = C then
      Inc(Result);
end;

function IsValidIdentString(const S: String; AllowBackslash, AllowOperators: Boolean): Boolean;
var
  I, N: Integer;
begin
  if S = '' then
    Result := False
  else if not AllowOperators and (PathSame(S, 'not') or
     PathSame(S, 'and') or PathSame(S, 'or')) then
    Result := False
  else begin
    N := Length(S);
    for I := 1 to N do
      if not (CharInSet(S[I], ['A'..'Z', 'a'..'z', '_']) or
              ((I > 1) and CharInSet(S[I], ['0'..'9'])) or
              (AllowBackslash and (I > 1) and (I < N) and (S[I] = '\'))) then begin
        Result := False;
        Exit;
      end;
    Result := True;
  end;
end;

procedure SkipWhitespace(var S: PChar);
begin
  Shared.CompilerSupport.SkipWhitespace(S);
end;

function ExtractWords(var S: PChar; const Sep: Char): String;
{ Extracts characters from S until it reaches the character Sep or the end
  of S. The returned string has trailing whitespace characters trimmed off. }
var
  StartPos, EndPos: PChar;
begin
  StartPos := S;
  EndPos := S;
  while (S^ <> #0) and (S^ <> Sep) do begin
    if S^ > ' ' then
      EndPos := S + 1;
    Inc(S);
  end;
  SetString(Result, StartPos, EndPos - StartPos);
end;

function UnescapeBraces(const S: String): String;
{ Changes all '{{' to '{'. Assumes that S does not contain any constants; you
  should check before calling. }
var
  I: Integer;
begin
  Result := S;
  I := 1;
  while I < Length(Result) do begin
    if Result[I] = '{' then begin
      Inc(I);
      if Result[I] = '{' then
        Delete(Result, I, 1);
    end
    else
      Inc(I);
  end;
end;

function BuildLanguageMessageData(const Messages: array of String): AnsiString;
const
  Terminator: WideChar = #0;
var
  Stream: TMemoryStream;
  Header: TMessagesHeader;
  MessageText: String;
  PayloadOffset: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(MessagesHdrID, SizeOf(MessagesHdrID));
    FillChar(Header, SizeOf(Header), 0);
    Stream.WriteBuffer(Header, SizeOf(Header));
    PayloadOffset := SizeOf(MessagesHdrID) + SizeOf(Header);

    for MessageText in Messages do begin
      if MessageText <> '' then
        Stream.WriteBuffer(PWideChar(MessageText)^, Length(MessageText) * SizeOf(WideChar));
      Stream.WriteBuffer(Terminator, SizeOf(Terminator));
    end;

    if Stream.Size > High(Cardinal) then
      raise Exception.CreateFmt(SCompilerCompressInternalError, ['Unexpected message data size']);
    Header.NumMessages := Length(Messages);
    Header.TotalSize := Cardinal(Stream.Size);
    Header.NotTotalSize := not Header.TotalSize;
    Header.CRCMessages := GetCRC32((PByte(Stream.Memory) + PayloadOffset)^,
      Header.TotalSize - Cardinal(PayloadOffset));
    Stream.Position := SizeOf(MessagesHdrID);
    Stream.WriteBuffer(Header, SizeOf(Header));
    SetString(Result, PAnsiChar(Stream.Memory), Stream.Size);
  finally
    Stream.Free;
  end;
end;

end.
