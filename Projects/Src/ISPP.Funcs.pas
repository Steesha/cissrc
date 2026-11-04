{
  Inno Setup Preprocessor
  Copyright (C) 2001-2002 Alex Yackimoff

  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.
}

unit ISPP.Funcs;

interface

uses
  {$IFDEF MSWINDOWS}Windows,{$ENDIF} Classes,
  ISPP.VarUtils, ISPP.Intf, ISPP.Preprocessor, Shared.FPCStringUtils;

procedure RegisterFunctions(Preproc: TPreprocessor);

implementation

uses
  SysUtils, IniFiles, {$IFDEF MSWINDOWS}Registry,{$ELSE}Process, Pipes, Contnrs, BaseUnix,{$ENDIF} Math,
  MD5, SHA1, SHA256, PathFunc, UnsignedFunc,
  Shared.FileClass, {$IFDEF MSWINDOWS}Shared.CommonFunc{$ELSE}Shared.CompilerSupport{$ENDIF},
  ISPP.Sessions, ISPP.Base, ISPP.IdentMan, Shared.VerInfoFunc;

{$IFNDEF MSWINDOWS}
const
  IsWin64 = False;
{$ELSE}
{$IFDEF WIN64}
const
  IsWin64 = True;
{$ELSE}
var
  IsWin64: Boolean;
{$ENDIF}
{$ENDIF}

function PrependPath(const Ext: NativeInt; const Filename: String): String;
var
  Preprocessor: TPreprocessor;
begin
  Preprocessor := TObject(Ext) as TPreprocessor;
  Result := Preprocessor.PrependDirName(Filename, Preprocessor.SourcePath);
  {$IFDEF MSWINDOWS}
  Result := PathExpand(Result);
  {$ELSE}
  Result := UTF8Decode(ExpandFileName(UTF8Encode(Result)));
  {$ENDIF}
end;

function CheckParams(const Params: IIsppFuncParams;
  Types: array of TIsppVarType; Minimum: Integer; var Error: TIsppFuncResult;
  AllowManyArgs: Boolean = False): Boolean;
var
  I: NativeInt;
begin
  FillChar(Error, SizeOf(TIsppFuncResult), 0);
  Result := False;
  if Params.GetCount < Minimum then begin
    Error.Error := ISPPFUNC_INSUFARGS;
    Exit;
  end else if not AllowManyArgs and (Params.GetCount > High(Types) + 1) then begin
    Error.Error := ISPPFUNC_MANYARGS;
    Exit;
  end else
    with IInternalFuncParams(Params) do
      for I := 0 to Min(Params.GetCount - 1, High(Types)) do
      begin
        if (Types[I] = evSpecial) or (Get(I)^.Typ = evNull) then
          Continue;
        if Types[I] <> Get(I)^.Typ then begin
          if Types[I] = evStr then
            Error.Error := ISPPFUNC_STRWANTED
          else
            Error.Error := ISPPFUNC_INTWANTED;
          Exit;
        end;
      end;
  Result := True;
end;

function Int(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evSpecial, evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      ResPtr^ := ToInt(Get(0)^);
  except
    on E: EConvertError do
      with IInternalFuncParams(Params) do
      begin
        if GetCount > 1 then
          ResPtr^ := Get(1)^
        else
          FuncResult.RaiseError(PChar(String(E.Message)));
      end;
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function Str(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evSpecial], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      ResPtr^ := ToStr(Get(0)^);
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{FileExists(<filename>)}
function FileExists(Ext: NativeInt; const Params: IIsppFuncParams; const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeBool(ResPtr^, {$IFDEF MSWINDOWS}NewFileExists(PrependPath(Ext, Get(0).AsStr)){$ELSE}SysUtils.FileExists(UTF8Encode(PrependPath(Ext, Get(0).AsStr))){$ENDIF});
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function DirExists(Ext: NativeInt; const Params: IIsppFuncParams; const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeBool(ResPtr^, {$IFDEF MSWINDOWS}Shared.CommonFunc.DirExists(PrependPath(Ext, Get(0).AsStr)){$ELSE}DirectoryExists(UTF8Encode(PrependPath(Ext, Get(0).AsStr))){$ENDIF});
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function ForceDirectoriesFunc(Ext: NativeInt; const Params: IIsppFuncParams; const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeBool(ResPtr^, ForceDirectories({$IFDEF FPC}UTF8Encode({$ENDIF}PrependPath(Ext, Get(0).AsStr){$IFDEF FPC}){$ENDIF}));
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{FileSize(<filename>)}
function FileSize(Ext: NativeInt; const Params: IIsppFuncParams; const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  SearchRec: TSearchRec;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      if FindFirst(ToNativeText(PrependPath(Ext, Get(0).AsStr)), faAnyFile, SearchRec) = 0 then begin
        try
          MakeInt(ResPtr^, SearchRec.Size);
        finally
          FindClose(SearchRec);
        end;
      end else
        MakeInt(ResPtr^, -1);
    end
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{ReadIni(<file:str>,<section:str>,<name:str>,[<default:str>])}
function ReadIni(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Default: string;
begin
  if CheckParams(Params, [evStr, evStr, evStr, evStr], 3, Result) then
  try
    with IInternalFuncParams(Params) do
      with TIniFile.Create(ToNativeText(PrependPath(Ext, Get(0).AsStr))) do
      try
        if GetCount < 4 then Default := '' else Default := Get(3).AsStr;
        MakeStr(ResPtr^, FromNativeText(ReadString(ToNativeText(Get(1).AsStr), ToNativeText(Get(2).AsStr), ToNativeText(Default))));
      finally
        Free
      end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function WriteIni(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr, evStr, evStr, evSpecial], 4, Result) then
  try
    with IInternalFuncParams(Params) do
      with TIniFile.Create(ToNativeText(PrependPath(Ext, Get(0).AsStr))) do
      try
        case Get(3).Typ of
          evInt: WriteInt64(ToNativeText(Get(1).AsStr), ToNativeText(Get(2).AsStr), Get(3).AsInt64);
          evStr: WriteString(ToNativeText(Get(1).AsStr), ToNativeText(Get(2).AsStr), ToNativeText(Get(3).AsStr));
        else
          WriteString(ToNativeText(Get(1).AsStr), ToNativeText(Get(2).AsStr), '');
        end;
        ResPtr^ := NULL;
      finally
        Free;
      end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{ReadReg(<root:int>,<key:str>,[<name:str>,<default:str>])}
function ReadReg(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
{$IFDEF MSWINDOWS}
const
  { These are based on CodeRootKey* from Shared.SetupTypes }
  ISPPRootKeyFlagMask  = $7F000000;
  ISPPRootKeyFlag32Bit = $01000000;
  ISPPRootKeyFlag64Bit = $02000000;
  ISPPRootKeyValidFlags = ISPPRootKeyFlag32Bit or ISPPRootKeyFlag64Bit;

  procedure CrackISPPRootKey(const ISPPRootKey: Int64; var RegView64, RegView32: Boolean;
    var RootKey: HKEY);
  begin
    { Allow only predefined key handles (8xxxxxxx). Can't accept handles to
      open keys because they might have our special flag bits set.
      Also reject unknown flags which may have a meaning in the future. }
    if (ISPPRootKey shr 31 <> 1) or
       ((ISPPRootKey and ISPPRootKeyFlagMask) and not ISPPRootKeyValidFlags <> 0) then
      raise Exception.Create('Invalid root key value');

    RegView64 := ISPPRootKey and ISPPRootKeyFlag64Bit <> 0;
    if RegView64 and not IsWin64 then
      raise Exception.Create('Cannot access 64-bit registry keys on this version of Windows');
    RegView32 := ISPPRootKey and ISPPRootKeyFlag32Bit <> 0;
    RootKey := HKEY(ISPPRootKey and not ISPPRootKeyFlagMask);
  end;

var
  Name: string;
  Default: TIsppVariant;
  RegView32, RegView64: Boolean;
  ARootKey: HKEY;
  AAccess: Cardinal;
begin
  if CheckParams(Params, [evInt, evStr, evStr, evSpecial], 2, Result) then
  try
    with IInternalFuncParams(Params) do begin
      CrackISPPRootKey(Get(0).AsInt64, RegView64, RegView32, ARootKey);
      AAccess := KEY_QUERY_VALUE;
      if RegView64 then
        AAccess := AAccess or KEY_WOW64_64KEY
      else if RegView32 then
        AAccess := AAccess or KEY_WOW64_32KEY;
      with TRegistry.Create(AAccess) do
      try
        RootKey := ARootKey;
        if GetCount < 3 then Name := '' else Name := Get(2).AsStr;
        if GetCount < 4 then Default := NULL else Default := Get(3)^;
        if OpenKey(Get(1).AsStr, False) and ((Name = '') or ValueExists(Name)) then
          case GetDataType(Name) of
            rdString, rdExpandString: MakeStr(ResPtr^, ReadString(Name));
            rdInteger: MakeInt(ResPtr^, ReadInteger(Name));
            {$IF Defined(FPC) or (Declared(RtlVersion) and (RtlVersion >= 36.0))}
            rdInt64: MakeInt(ResPtr^, ReadInt64(Name));
            {$ENDIF}
          else
            CopyExpVar(Default, ResPtr^);
          end
        else
          CopyExpVar(Default, ResPtr^);
      finally
        Free
      end;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
{$ELSE}
begin
  if CheckParams(Params, [evInt, evStr, evStr, evSpecial], 2, Result) then
    FuncResult.RaiseError('ReadReg requires a Windows host');
{$ENDIF}
end;

function GetEnvFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeStr(ResPtr^, {$IFDEF MSWINDOWS}GetEnv(Get(0).AsStr){$ELSE}UTF8Decode(GetEnvironmentVariable(UTF8Encode(Get(0).AsStr))){$ENDIF});
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

const
  SSetup = '[Setup]';

function SetupSetting(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;

  function Find(L: TStrings; const S: string): string;
  var
    InSetupSection: Boolean;
    I, J: Integer;
    N: String;
  begin
    InSetupSection := False;
    Result := '';
    with L do
      for I := 0 to Count - 1 do
      begin
        if Length(Trim(Strings[I])) = 0 then Continue;
        if InSetupSection then
        begin
          if (Trim(Strings[I])[1] = '[') then
          begin
            if not InnoSameText(FromNativeText(Trim(Strings[I])), SSetup) then
              InSetupSection := False;
            Continue;
          end;
          J := Pos('=', Strings[I]);
          if J = 0 then Continue;
          N := FromNativeText(Trim(Copy(Strings[I], 1, J - 1)));
          if InnoCompareText(N, S) = 0 then
          begin
            Result := FromNativeText(Trim(Copy(Strings[I], J + 1, MaxInt)));
            Break;
          end;
        end
        else
          if InnoSameText(FromNativeText(Trim(Strings[I])), SSetup) then
            InSetupSection := True;
      end;
  end;

begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeStr(ResPtr^, Find(TPreprocessor(Ext).StringList, Get(0).AsStr));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{SetSetupSetting(<SetupSectionParameterName>,<ParameterValue>)}
function SetSetupSetting(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;

  procedure DoSet(L: TStrings; const S, V: string);
  var
    InSetupSection: Boolean;
    FirstSetupSectionLine, I, J: Integer;
    N: String;
  begin
    FirstSetupSectionLine := -1;
    InSetupSection := False;
    with L do
    begin
      for I := 0 to Count - 1 do
      begin
        if Length(Trim(Strings[I])) = 0 then Continue;
        if InSetupSection then
        begin
          if (Trim(Strings[I])[1] = '[') then
          begin
            if not InnoSameText(FromNativeText(Trim(Strings[I])), SSetup) then
              InSetupSection := False;
            Continue;
          end;
          J := Pos('=', Strings[I]);
          if J = 0 then Continue;
          N := FromNativeText(Trim(Copy(Strings[I], 1, J - 1)));
          if InnoCompareText(N, S) = 0 then
          begin
            Strings[I] := ToNativeText(S + '=' + V);
            Exit;
          end;
        end
        else
          if InnoSameText(FromNativeText(Trim(Strings[I])), SSetup) then
          begin
            InSetupSection := True;
            if FirstSetupSectionLine < 0 then
              FirstSetupSectionLine := I;
          end;
      end;
      if FirstSetupSectionLine < 0 then
        FirstSetupSectionLine := L.Add(SSetup);
      L.Insert(FirstSetupSectionLine + 1, ToNativeText(S + '=' + V));
    end;
  end;

begin
  if CheckParams(Params, [evStr, evStr], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      ResPtr^.Typ := evNull;
      DoSet(TPreprocessor(Ext).StringList, Get(0).AsStr, Get(1).AsStr);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{EntryCount(<SectionName>)}
function EntryCountFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  I, J: Integer;
  DoCount: Boolean;
  N, S: string;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    J := 0;
    DoCount := False;
    with IInternalFuncParams(Params), TStringList(TPreprocessor(Ext).StringList) do
    begin
      S := Get(0).AsStr;
      for I := 0 to Count - 1 do
      begin
        N := FromNativeText(Trim(Strings[I]));
        if (N <> '') and (N[1] = '[') then
        begin
          DoCount := InnoCompareText(Copy(N, 2, Length(N) - 2), S) = 0;
          Continue;
        end;
        if DoCount and (N <> '') and (N[1] <> ';') then Inc(J);
      end;
      MakeInt(ResPtr^, J);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{SaveToFile(<Filename>)}
function SaveToFile(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      TPreprocessor(Ext).SaveToFile(PrependPath(Ext, Get(0).AsStr));
      ResPtr^ := NULL;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{Find(<what>[,<contains>[,<what>,<contains>[,<what>[,<contains>]]]])}
function FindLine(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;

  type
    TFindWhere = (fwMatch, fwBegin, fwEnd, fwContains);

  function Meets(const Str, Substr: string; Sensitive: Boolean; Where: TFindWhere): Boolean;
  begin
    case Where of
      fwMatch: Result := PathStrCompare(PChar(Str), Length(Str), PChar(Substr), Length(Substr), not Sensitive) = 0;
      fwBegin: Result := PathStartsWith(Str, Substr, not Sensitive);
      fwEnd: Result := PathEndsWith(Str, Substr, not Sensitive);
      fwContains: Result := (Substr = '') or ((Length(Str) >= Length(Substr)) and
        (PathStrFind(PChar(Str), Length(Str), PChar(Substr), Length(Substr), not Sensitive) <> -1));
    else
      raise Exception.Create('FindLine Meets: invalid Where');
    end;
  end;

const
  FIND_WHEREMASK  = $01 or $02;
  FIND_SENSITIVE  = $04;
  FIND_OR         = $08;
  FIND_NOT        = $10;
  FIND_TRIM       = $20;
var
  Strs: array[0..2] of string;
  StrCount, StartFromLine, I: Integer;
  Lines: TStrings;
  Line: String;
  Found, MoreFound: Boolean;
  Flags: array[0..2] of Integer;
begin
  if CheckParams(Params, [evInt, evStr, evInt, evStr, evInt, evStr, evInt], 2, Result) then
  try
    FillChar(Flags, SizeOf(Flags), 0);

    with IInternalFuncParams(Params) do
    begin
      StartFromLine := Get(0).AsInteger;
      if StartFromLine < 0 then
        StartFromLine := 0;

      Strs[0] := Get(1).AsStr;
      StrCount := 1;

      if GetCount > 2 then begin
        Flags[0] := Get(2).AsInteger;
        if GetCount > 3 then begin
          Strs[1] := Get(3).AsStr;
          Inc(StrCount);
          if GetCount > 4 then begin
            Flags[1] := Get(4).AsInteger;
            if GetCount > 5 then begin
              Strs[2] := Get(5).AsStr;
              Inc(StrCount);
              if GetCount > 6 then
                Flags[2] := Get(6).AsInteger;
            end
          end;
        end
      end;

      Lines := TPreprocessor(Ext).StringList;

      for I := StartFromLine to Lines.Count-1 do begin
        Line := FromNativeText(Lines[I]);
        if Flags[0] and FIND_TRIM <> 0 then { As documented, the FIND_TRIM flag must be used on Flags[0] }
          Line := Trim(Line);

        Found := Meets(Line, Strs[0], Flags[0] and FIND_SENSITIVE <> 0,
          TFindWhere(Flags[0] and FIND_WHEREMASK)) xor (Flags[0] and FIND_NOT <> 0);

        if (StrCount > 1) and
           (((Flags[1] and FIND_OR <> 0{OR}) and not Found) or
            ((Flags[1] and FIND_OR = 0{AND}) and Found)) then begin
          MoreFound := Meets(Line, Strs[1], Flags[1] and FIND_SENSITIVE <> 0,
            TFindWhere(Flags[1] and FIND_WHEREMASK)) xor (Flags[1] and FIND_NOT <> 0);
          if Flags[1] and FIND_OR <> 0 then
            Found := Found or MoreFound
          else
            Found := Found and MoreFound;
        end;

        if (StrCount > 2) and
           (((Flags[2] and FIND_OR <> 0{OR}) and not Found) or
            ((Flags[2] and FIND_OR = 0{AND}) and Found)) then begin
          MoreFound := Meets(Line, Strs[2], Flags[2] and FIND_SENSITIVE <> 0,
            TFindWhere(Flags[2] and FIND_WHEREMASK)) xor (Flags[2] and FIND_NOT <> 0);
          if Flags[2] and FIND_OR <> 0 then
            Found := Found or MoreFound
          else
            Found := Found and MoreFound;
        end;

        if Found then begin
          MakeInt(ResPtr^, I);
          Exit;
        end;
      end;

      MakeInt(ResPtr^, -2);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{$IFDEF MSWINDOWS}
function Exec(const Filename, Params: String; WorkingDir: String;
  const WaitUntilTerminated: Boolean; const ShowCmd: Word;
  const Preprocessor: TPreprocessor; const OutputReader: TCreateProcessOutputReader;
  var ResultCode: Integer): Boolean;
var
  CmdLine: String;
  WorkingDirP: PChar;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  InheritHandles: Boolean;
  CreationFlags: DWORD;
begin
  {This function is a combination of InstFuncs' InstExec and Compile's InternalSignCommand }

  if Filename = '>' then
    CmdLine := Params
  else begin
    if (Filename = '') or (Filename[1] <> '"') then
      CmdLine := '"' + Filename + '"'
    else
      CmdLine := Filename;
    if Params <> '' then
      CmdLine := CmdLine + ' ' + Params;
    if InnoSameText(PathExtractExt(Filename), '.bat') or
       InnoSameText(PathExtractExt(Filename), '.cmd') then begin
      { See InstExec for explanation }
      CmdLine := '"' + AddBackslash(GetSystemDir) + 'cmd.exe" /C "' + CmdLine + '"'
    end;
    if WorkingDir = '' then
      WorkingDir := PathExtractDir(Filename);
  end;

  FillChar (StartupInfo, SizeOf(StartupInfo), 0);
  StartupInfo.cb := SizeOf(StartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := ShowCmd;
  if WorkingDir <> '' then
    WorkingDirP := PChar(WorkingDir)
  else
    WorkingDirP := nil;

  InheritHandles := False;
  CreationFlags := CREATE_DEFAULT_ERROR_MODE;

  if (OutputReader <> nil) and WaitUntilTerminated then begin
    OutputReader.UpdateStartupInfo(StartupInfo);
    InheritHandles := True;
    CreationFlags := CreationFlags or CREATE_NO_WINDOW;
  end;

  UniqueString(CmdLine);
  Result := CreateProcessW(nil, PWideChar(CmdLine), nil, nil, InheritHandles,
    CreationFlags, nil, WorkingDirP, TStartupInfoW(StartupInfo), ProcessInfo);
  if not Result then begin
    DWORD(ResultCode) := GetLastError;
    Exit;
  end;

  { Don't need the thread handle, so close it now }
  CloseHandle(ProcessInfo.hThread);
  if OutputReader <> nil then
    OutputReader.NotifyCreateProcessDone;

  try
    if WaitUntilTerminated then begin
      while True do begin
        case WaitForSingleObject(ProcessInfo.hProcess, 50) of
          WAIT_OBJECT_0: Break;
          WAIT_TIMEOUT:
            begin
              if OutputReader <> nil then
                OutputReader.Read(False);
              Preprocessor.CallIdleProc; { Doesn't allow an Abort }
            end;
        else
          Preprocessor.RaiseError('Exec: WaitForSingleObject failed');
        end;
      end;
      if OutputReader <> nil then
        OutputReader.Read(True);
    end;
    { Get the exit code. Will be set to STILL_ACTIVE if not yet available }
    if not GetExitCodeProcess(ProcessInfo.hProcess, DWORD(ResultCode)) then
      ResultCode := -1;  { just in case }
  finally
    CloseHandle(ProcessInfo.hProcess);
  end;
end;

{$ELSE}
var
  AsyncProcesses: TObjectList;

function ExecNative(const Filename, Params, WorkingDir: String;
  const WaitUntilTerminated: Boolean; const Preprocessor: TPreprocessor;
  out ResultCode: Integer; out FirstLine: String): Boolean;
var
  Child: TProcess;
  OutputPending, ErrorPending: RawByteString;
  Executable: String;
  I: Integer;

  procedure Drain(const Pipe: TInputPipeStream; var Pending: RawByteString;
    const IsError, Flush: Boolean);
  var
    Buffer: array[0..4095] of AnsiChar;
    Count, Newline: Integer;
    Chunk: RawByteString;

    procedure Emit(const Bytes: RawByteString);
    var
      Line: String;
    begin
      Line := UTF8Decode(Bytes);
      if IsError then
        Preprocessor.WarningMsg('%s', [Line])
      else begin
        if (FirstLine = '') and (Trim(Line) <> '') then
          FirstLine := Line;
        Preprocessor.StatusMsg('Exec output: %s', [Line]);
      end;
    end;

  begin
    Count := Min(Pipe.NumBytesAvailable, SizeOf(Buffer));
    if Count > 0 then begin
      Count := Pipe.Read(Buffer, Count);
      if Count > 0 then begin
        SetString(Chunk, PAnsiChar(@Buffer[0]), Count);
        Pending := Pending + Chunk;
        repeat
          Newline := Pos(#10, Pending);
          if Newline = 0 then
            Break;
          Chunk := Copy(Pending, 1, Newline - 1);
          if (Length(Chunk) <> 0) and (Chunk[Length(Chunk)] = #13) then
            SetLength(Chunk, Length(Chunk) - 1);
          Emit(Chunk);
          Delete(Pending, 1, Newline);
        until False;
      end;
    end;
    if Flush and (Length(Pending) <> 0) then
      Emit(Pending);
  end;

begin
  if AsyncProcesses <> nil then
    for I := AsyncProcesses.Count - 1 downto 0 do
      if not TProcess(AsyncProcesses[I]).Running then
        AsyncProcesses.Delete(I);
  FirstLine := '';
  ResultCode := -1;
  Child := TProcess.Create(nil);
  try
    if Filename = '>' then begin
      CommandToList(UTF8Encode(Params), Child.Parameters);
      if Child.Parameters.Count > 0 then begin
        Child.Executable := Child.Parameters[0];
        Child.Parameters.Delete(0);
      end;
    end else begin
      Executable := Filename;
      if (Length(Executable) >= 2) and (Executable[1] = '"') and
         (Executable[Length(Executable)] = '"') then
        Executable := Copy(Executable, 2, Length(Executable) - 2);
      Child.Executable := UTF8Encode(Executable);
      CommandToList(UTF8Encode(Params), Child.Parameters);
      if WorkingDir = '' then
        Child.CurrentDirectory := ExtractFileDir(UTF8Encode(Executable));
    end;
    if WorkingDir <> '' then
      Child.CurrentDirectory := UTF8Encode(WorkingDir);
    if WaitUntilTerminated then
      Child.Options := [poUsePipes];
    try
      Child.Execute;
    except
      on E: EProcess do begin
        Preprocessor.WarningMsg('%s', [UTF8Decode(E.Message)]);
        Exit(False);
      end;
    end;
    if WaitUntilTerminated then begin
      Child.CloseInput;
      while Child.Running do begin
        Drain(Child.Output, OutputPending, False, False);
        Drain(Child.Stderr, ErrorPending, True, False);
        Preprocessor.CallIdleProc;
        if (Child.Output.NumBytesAvailable = 0) and (Child.Stderr.NumBytesAvailable = 0) then
          Sleep(10);
      end;
      while (Child.Output.NumBytesAvailable > 0) or (Child.Stderr.NumBytesAvailable > 0) do begin
        Drain(Child.Output, OutputPending, False, False);
        Drain(Child.Stderr, ErrorPending, True, False);
      end;
      Drain(Child.Output, OutputPending, False, True);
      Drain(Child.Stderr, ErrorPending, True, True);
      ResultCode := Child.ExitCode;
    end else begin
      if AsyncProcesses = nil then
        AsyncProcesses := TObjectList.Create;
      AsyncProcesses.Add(Child);
      Child := nil;
    end;
    Result := True;
  finally
    Child.Free;
  end;
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
procedure ExecLog(const S: String; const Error, FirstLine: Boolean; const Data: NativeInt);
var
  Preprocessor: TPreprocessor;
begin
  Preprocessor := TPreprocessor(Data);
  if Error then
    Preprocessor.WarningMsg(S)
  else
    Preprocessor.StatusMsg('Exec output: %s', [S]);
end;

{$ENDIF}

{
  int Exec(str FileName, str Params, str WorkingDir, int Wait, int ShowCmd)
}

function ExecFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  ParamsS, WorkingDir: String;
  ResultCode: Integer;
  Success, WaitUntilTerminated: Boolean;
  {$IFDEF MSWINDOWS}
  ShowCmd: Word;
  Preprocessor: TPreprocessor;
  OutputReader: TCreateProcessOutputReader;
  {$ELSE}
  FirstLine: String;
  {$ENDIF}
begin
  if CheckParams(Params, [evStr, evStr, evStr, evInt, evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      {$IFDEF MSWINDOWS}
      ParamsS := '';
      WorkingDir := '';
      WaitUntilTerminated := True;
      ShowCmd := SW_SHOWNORMAL;
      if GetCount > 1 then ParamsS := Get(1).AsStr;
      if GetCount > 2 then WorkingDir := PrependPath(Ext, Get(2).AsStr);
      if (GetCount > 3) and (Get(3).Typ <> evNull) then WaitUntilTerminated := Get(3).AsBoolean;
      if (GetCount > 4) and (Get(4).Typ <> evNull) then ShowCmd := Get(4).AsWord;
      Preprocessor := TPreprocessor(Ext);
      OutputReader := TCreateProcessOutputReader.Create(ExecLog, NativeInt(Preprocessor));
      try
        Success := Exec(Get(0).AsStr, ParamsS, WorkingDir, WaitUntilTerminated,
          ShowCmd, Preprocessor, OutputReader, ResultCode);
        if not WaitUntilTerminated then
          MakeBool(ResPtr^, Success)
        else
          MakeInt(ResPtr^, ResultCode);
      finally
        OutputReader.Free;
      end;
      {$ELSE}
      ParamsS := '';
      WorkingDir := '';
      if GetCount > 1 then ParamsS := Get(1).AsStr;
      if GetCount > 2 then WorkingDir := PrependPath(Ext, Get(2).AsStr);
      WaitUntilTerminated := (GetCount <= 3) or (Get(3).Typ = evNull) or Get(3).AsBoolean;
      Success := ExecNative(Get(0).AsStr, ParamsS, WorkingDir, WaitUntilTerminated,
        TPreprocessor(Ext), ResultCode, FirstLine);
      if WaitUntilTerminated then
        MakeInt(ResPtr^, ResultCode)
      else
        MakeBool(ResPtr^, Success);
      {$ENDIF}
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

type
  PExecAndGetFirstLineLogData = ^TExecAndGetFirstLineLogData;
  TExecAndGetFirstLineLogData = record
    Preprocessor: TPreprocessor;
    Line: String;
  end;

{$IFDEF MSWINDOWS}
procedure ExecAndGetFirstLineLog(const S: String; const Error, FirstLine: Boolean; const Data: NativeInt);
var
  Data2: PExecAndGetFirstLineLogData;
begin
  Data2 := PExecAndGetFirstLineLogData(Data);
  if not Error and (Data2.Line = '') and (Trim(S) <> '') then
    Data2.Line := S;
  ExecLog(S, Error, FirstLine, NativeInt(Data2.Preprocessor));
end;

{$ENDIF}

{
  str ExecAndGetFirstLine(str FileName, str Params, str WorkingDir,)
}

function ExecAndGetFirstLineFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  ParamsS, WorkingDir: String;
  ResultCode: Integer;
  Success: Boolean;
  {$IFDEF MSWINDOWS}
  Data: TExecAndGetFirstLineLogData;
  OutputReader: TCreateProcessOutputReader;
  {$ELSE}
  FirstLine: String;
  {$ENDIF}
begin
  if CheckParams(Params, [evStr, evStr, evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      {$IFDEF MSWINDOWS}
      ParamsS := '';
      WorkingDir := '';
      if GetCount > 1 then ParamsS := Get(1).AsStr;
      if GetCount > 2 then WorkingDir := PrependPath(Ext, Get(2).AsStr);
      Data.Preprocessor := TPreprocessor(Ext);
      Data.Line := '';
      OutputReader := TCreateProcessOutputReader.Create(ExecAndGetFirstLineLog, NativeInt(@Data));
      try
        Success := Exec(Get(0).AsStr, ParamsS, WorkingDir, True,
          SW_SHOWNORMAL, Data.Preprocessor, OutputReader, ResultCode);
        if Success then
          MakeStr(ResPtr^, Data.Line)
        else begin
          Data.Preprocessor.WarningMsg('CreateProcess failed (%d).', [ResultCode]);
          ResPtr^.Typ := evNull;
        end;
      finally
        OutputReader.Free;
      end;
      {$ELSE}
      ParamsS := '';
      WorkingDir := '';
      if GetCount > 1 then ParamsS := Get(1).AsStr;
      if GetCount > 2 then WorkingDir := PrependPath(Ext, Get(2).AsStr);
      Success := ExecNative(Get(0).AsStr, ParamsS, WorkingDir, True,
        TPreprocessor(Ext), ResultCode, FirstLine);
      if Success then
        MakeStr(ResPtr^, FirstLine)
      else
        ResPtr^.Typ := evNull;
      {$ENDIF}
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function LenFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeInt(ResPtr^, Length(Get(0).AsStr));
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function CopyFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: string;
  B, C: Int64;
begin
  if CheckParams(Params, [evStr, evInt, evInt], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := Get(0).AsStr;
      B := Get(1).AsInt64;
      if GetCount > 2 then C := Get(2).AsInt64 else C := MaxInt;

      { Constrain 64-bit arguments to 32 bits without truncating them }
      if B < 1 then
        B := 1;
      if C > MaxInt then
        C := MaxInt;
      if (B > MaxInt) or (C < 0) then begin
        { Result should be empty in these cases }
        B := 1;
        C := 0;
      end;

      MakeStr(ResPtr^, Copy(S, Integer(B), Integer(C)));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function PosFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr, evStr], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeInt(ResPtr^, Pos(Get(0).AsStr, Get(1).AsStr));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function LowerCaseFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeStr(ResPtr^, LowerCase(Get(0).AsStr));
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function UpperCaseFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeStr(ResPtr^, UpperCase(Get(0).AsStr));
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function RPosFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Haystack, Needle: String;
  I, NeedleLength: Integer;
begin
  if CheckParams(Params, [evStr, evStr], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      Haystack := Get(1).AsStr;
      Needle := Get(0).AsStr;
      NeedleLength := Length(Needle);
      I := Length(Haystack) - NeedleLength + 1;
      if NeedleLength = 0 then
        I := 0
      else
        while I > 0 do begin
          if CompareMem(@Haystack[I], PChar(Needle), NeedleLength * SizeOf(Char)) then
            Break;
          Dec(I);
        end;
      if I < 0 then
        I := 0;
      MakeInt(ResPtr^, I);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetVersionNumbersStringFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Version: TFileVersionNumbers;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      ResPtr^.Typ := evNull;
      if GetVersionNumbers(PrependPath(Ext, Get(0).AsStr), Version) then
        MakeStr(ResPtr^,
          InnoIntToStr(Version.MS shr 16) + '.' + InnoIntToStr(Version.MS and $FFFF) + '.' +
          InnoIntToStr(Version.LS shr 16) + '.' + InnoIntToStr(Version.LS and $FFFF));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function ComparePackedVersionFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evInt, evInt], 2, Result) then
  try
    with IInternalFuncParams(Params) do
      if UInt64(Get(0).AsInt64) < UInt64(Get(1).AsInt64) then
        MakeInt(ResPtr^, -1)
      else if UInt64(Get(0).AsInt64) > UInt64(Get(1).AsInt64) then
        MakeInt(ResPtr^, 1)
      else
        MakeInt(ResPtr^, 0);
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function SamePackedVersionFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evInt, evInt], 2, Result) then
  try
    with IInternalFuncParams(Params) do
      if Get(0).AsInt64 = Get(1).AsInt64 then
        MakeInt(ResPtr^, 1)
      else
        MakeInt(ResPtr^, 0)
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetStringFileInfoFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
{$IFDEF MSWINDOWS}
var
  Buf: Pointer;

  function GetStringFileInfo(Lang: UINT; const Name: string; var Value: string): Boolean;
  var
    InfoBuf: Pointer;
    InfoBufSize: Cardinal;
  begin
    Result := VerQueryValueW(Buf, PChar('\StringFileInfo\' + InnoIntToHex(LoWord(Lang), 4) +
      InnoIntToHex(HiWord(Lang), 4) +
      '\' + Name), InfoBuf, InfoBufSize) and (InfoBufSize > 0);
    if Result then SetString(Value, PChar(InfoBuf), InfoBufSize - 1)
  end;

type
  TUINTArray = array[0..$100] of UINT;
  PUINTArray = ^TUINTArray;
var
  Filename: string;
  VersionHandle, Size: Cardinal;
  I, LangCount: Integer;
  Langs: PUINTArray;
  Lang, LangsSize: UINT;
  Value: string;
  Success: Boolean;
begin
  if CheckParams(Params, [evStr, evStr, evInt], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      Success := False;
      ResPtr^.Typ := evNull;
      Filename := PrependPath(Ext, Get(0).AsStr);
      Size := GetFileVersionInfoSizeW(PChar(Filename), VersionHandle);
      if Size > 0 then
      begin
        GetMem(Buf, Size);
        try
          if GetFileVersionInfoW(PChar(Filename), VersionHandle, Size, Buf) then
          begin
            if GetCount > 2 then
            begin
              Lang := Get(2).AsCardinal;
              Success := GetStringFileInfo(Lang, Get(1).AsStr, Value);
            end
            else
            begin
              if VerQueryValueW(Buf, PChar('\VarFileInfo\Translation'), Pointer(Langs),
                LangsSize) then
              begin
                LangCount := LangsSize div SizeOf(UINT);
                for I := 0 to LangCount - 1 do
                begin
                  Success := GetStringFileInfo(Langs[I], Get(1).AsStr, Value);
                  if Success then Break;
                end;
              end;
            end;
            if Success then
              MakeStr(ResPtr^, Value);
          end;
        finally
          FreeMem(Buf)
        end;
      end;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
{$ELSE}
var
  InternalParams: IInternalFuncParams;
  Translation: Cardinal;
  Value: String;
begin
  if CheckParams(Params, [evStr, evStr, evInt], 2, Result) then
  try
    InternalParams := IInternalFuncParams(Params);
    InternalParams.ResPtr^.Typ := evNull;
    Translation := 0;
    if InternalParams.GetCount > 2 then
      Translation := InternalParams.Get(2).AsCardinal;
    if GetVersionString(PrependPath(Ext, InternalParams.Get(0).AsStr),
       InternalParams.Get(1).AsStr, InternalParams.GetCount > 2, Translation, Value) then
      MakeStr(InternalParams.ResPtr^, Value);
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
{$ENDIF}
end;

function DelFileFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      QueueFileForDeletion(PrependPath(Ext, Get(0).AsStr));
      ResPtr^.Typ := evNull;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function DelFileNowFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeBool(ResPtr^, DeleteFile(PChar(PrependPath(Ext, Get(0).AsStr))));
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{$IFNDEF MSWINDOWS}
function CopyNativeFile(const SourceName, DestName: String): Boolean;
var
  SourceHandle, DestHandle: Integer;
  SourceInfo, DestInfo: Stat;
  SourceStream, DestStream: THandleStream;
begin
  SourceHandle := fpOpen(UTF8Encode(SourceName), O_RDONLY);
  if SourceHandle < 0 then
    Exit(False);
  try
    if (fpFStat(SourceHandle, SourceInfo) <> 0) or not fpS_ISREG(SourceInfo.st_mode) then
      Exit(False);
    DestHandle := fpOpen(UTF8Encode(DestName), O_WRONLY or O_CREAT, SourceInfo.st_mode and &777);
    if DestHandle < 0 then
      Exit(False);
    try
      if (fpFStat(DestHandle, DestInfo) <> 0) or not fpS_ISREG(DestInfo.st_mode) or
         ((SourceInfo.st_dev = DestInfo.st_dev) and (SourceInfo.st_ino = DestInfo.st_ino)) or
         (fpFTruncate(DestHandle, 0) <> 0) then
        Exit(False);
      SourceStream := THandleStream.Create(SourceHandle);
      try
        DestStream := THandleStream.Create(DestHandle);
        try
          try
            DestStream.CopyFrom(SourceStream, 0);
            Result := True;
          except
            on E: EStreamError do
              Result := False;
          end;
        finally
          DestStream.Free;
        end;
      finally
        SourceStream.Free;
      end;
    finally
      if fpClose(DestHandle) <> 0 then
        Result := False;
    end;
  finally
    fpClose(SourceHandle);
  end;
end;
{$ENDIF}

function CopyFileFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr, evStr], 2, Result) then
  try
    with IInternalFuncParams(Params) do
      {$IFDEF MSWINDOWS}
      MakeBool(ResPtr^, CopyFileW(PChar(PrependPath(Ext, Get(0).AsStr)), PChar(PrependPath(Ext, Get(1).AsStr)), False));
      {$ELSE}
      MakeBool(ResPtr^, CopyNativeFile(PrependPath(Ext, Get(0).AsStr), PrependPath(Ext, Get(1).AsStr)));
      {$ENDIF}
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

type
  PSearchRec = ^TSearchRec;

procedure GarbageCloseFind(Item: Pointer);
begin
  FindClose(PSearchRec(Item)^);
  Dispose(PSearchRec(Item));
end;

function FindFirstFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Filename: string;
  SR: PSearchRec;
begin
  if CheckParams(Params, [evStr, evInt], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      Filename := PrependPath(Ext, Get(0).AsStr);
      New(SR);
      ResPtr^.Typ := evInt;
      if FindFirst(ToNativeText(Filename), Get(1).AsInteger, SR^) = 0 then
      begin
        ResPtr^.AsInt64 := NativeInt(SR);
        TPreprocessor(Ext).CollectGarbage(SR, Addr(GarbageCloseFind));
      end
      else
      begin
        ResPtr^.AsInt64 := 0;
        Dispose(SR);
      end;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FindGetHandle(const Params: IInternalFuncParams; const Index: Integer): PSearchRec;
begin
  Result := PSearchRec(Params.Get(Index).AsInt64);
  if Result = nil then
    raise Exception.Create('Invalid find handle');
end;

function FindNextFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      ResPtr.Typ := evInt;
      if FindNext(FindGetHandle(IInternalFuncParams(Params), 0)^) = 0 then
        ResPtr^.AsInt64 := 1
      else
        ResPtr^.AsInt64 := 0;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FindGetFileName(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeStr(ResPtr^, FromNativeText(FindGetHandle(IInternalFuncParams(Params), 0)^.Name));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FindCloseFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  SearchRec: PSearchRec;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      SearchRec := FindGetHandle(IInternalFuncParams(Params), 0);
      FindClose(SearchRec^);
      Dispose(SearchRec);
      TPreprocessor(Ext).UncollectGarbage(SearchRec);
      ResPtr^ := NULL;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

type
  PTextFile = ^TextFile;

procedure GarbageCloseFile(Item: Pointer);
var
  F: PTextFile;
begin
  F := Item;
  Close(F^);
  Dispose(F);
end;

function FileOpenFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  F: PTextFile;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    New(F);
    try
      with IInternalFuncParams(Params) do
      begin
        FileMode := fmOpenRead or fmShareDenyWrite;
        AssignFile(F^, PrependPath(Ext, Get(0).AsStr));
        {$I-}
        Reset(F^);
        {$I+}
        if IOResult <> 0 then
        begin
          Dispose(F);
          MakeInt(ResPtr^, 0)
        end
        else
        begin
          MakeInt(ResPtr^, NativeInt(F));
          TPreprocessor(Ext).CollectGarbage(F, Addr(GarbageCloseFile));
        end;
      end;
    except
      Dispose(F);
      raise
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FileGetHandle(const Params: IInternalFuncParams; const Index: Integer): PTextFile;
begin
  Result := PTextFile(Params.Get(Index).AsInt64);
  if Result = nil then
    raise Exception.Create('Invalid file handle');
end;

function FileReadFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: string;
  P: IInternalFuncParams;
  F: PTextFile;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    P := IInternalFuncParams(Params);
    F := FileGetHandle(P, 0);
    {$I-}
    Readln(F^, S);
    {$I+}
    if IOResult <> 0 then
      P.ResPtr^ := NULL
    else
      MakeStr(P.ResPtr^, S);
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FileResetFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  P: IInternalFuncParams;
  F: PTextFile;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    P := IInternalFuncParams(Params);
    F := FileGetHandle(P, 0);
    {$I-}
    Reset(F^);
    {$I+}
    if IOResult <> 0 then
      raise Exception.Create('Failed to reset a file')
    else
      P.ResPtr^ := NULL
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FileEofFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  IsEof: Boolean;
  P: IInternalFuncParams;
  F: PTextFile;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    P := IInternalFuncParams(Params);
    F := FileGetHandle(P, 0);
    {$I-}
    IsEof := Eof(F^);
    {$I+}
    if IOResult <> 0 then
      P.ResPtr^ := NULL
    else
      MakeBool(P.ResPtr^, IsEof);
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FileCloseFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  P: IInternalFuncParams;
  F: PTextFile;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    P := IInternalFuncParams(Params);
    F := FileGetHandle(P, 0);
    {$I-}
    Close(F^);
    {$I+}
    P.ResPtr^ := NULL;
    Dispose(F);
    TPreprocessor(Ext).UncollectGarbage(F);
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function SaveStringToFileFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Filename: String;
  F: TextFile;
  DoAppend: Boolean;
  CodePage: Word;
begin
  if CheckParams(Params, [evStr, evStr, evInt, evInt], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      Filename := PrependPath(Ext, Get(0).AsStr);
      if (GetCount < 3) or Get(2).AsBoolean then DoAppend := True else DoAppend := False;
      if (GetCount < 4) or Get(3).AsBoolean then CodePage := CP_UTF8 else CodePage := 0;
      DoAppend := DoAppend and {$IFDEF MSWINDOWS}NewFileExists(Filename){$ELSE}SysUtils.FileExists(UTF8Encode(Filename)){$ENDIF};
      AssignFile(F, FileName, CodePage);
      {$I-}
      if DoAppend then
        Append(F)
      else
        Rewrite(F);
      {$I+}
      if IOResult <> 0 then
        MakeInt(ResPtr^, 0)
      else begin
        try
          MakeInt(ResPtr^, 1);
          if not DoAppend and (CodePage = CP_UTF8) then
            Write(F, #$FEFF); //Strings are UTF-16 so this UTF-16 BOM will actually be saved as an UTF-8 BOM
          Write(F, Get(1).AsStr);
        finally
          CloseFile(F);
        end;
      end;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

type
  PDateTime = ^TDateTime;

procedure GarbageReleaseDateTime(Item: Pointer);
begin
  Dispose(PDateTime(Item));
end;

function FileGetDate(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  FileDate: PDateTime;
  Age: TDateTime;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      if FileAge(PrependPath(Ext, Get(0).AsStr), Age) then
      begin
        New(FileDate);
        FileDate^ := Age;
        TPreprocessor(Ext).CollectGarbage(FileDate, GarbageReleaseDateTime);
        MakeInt(ResPtr^, Int64(FileDate));
      end
      else
        MakeInt(ResPtr^, -1);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetNow(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  DateTime: PDateTime;
begin
  if CheckParams(Params, [], 0, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      New(DateTime);
      DateTime^ := Now;
      TPreprocessor(Ext).CollectGarbage(DateTime, GarbageReleaseDateTime);
      MakeInt(ResPtr^, Int64(DateTime));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetDateFromDT(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeInt(ResPtr^, DateTimeToTimeStamp(PDateTime(Get(0).AsInt64)^).Date);
    end;
  except
    on E: EAccessViolation do
      FuncResult.RaiseError('Invalid datetime value');
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetTimeFromDT(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evInt], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeInt(ResPtr^, DateTimeToTimeStamp(PDateTime(Get(0).AsInt64)^).Time);
    end;
  except
    on E: EAccessViolation do
      FuncResult.RaiseError('Invalid datetime value');
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetDateTimeString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  NewDateSeparatorString, NewTimeSeparatorString: String;
  OldDateSeparator, OldTimeSeparator: Char;
begin
  if CheckParams(Params, [evStr, evStr, evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      OldDateSeparator := FormatSettings.DateSeparator;
      OldTimeSeparator := FormatSettings.TimeSeparator;
      try
        if GetCount > 1 then
          NewDateSeparatorString := Get(1).AsStr;
        if GetCount > 2 then
          NewTimeSeparatorString := Get(2).AsStr;
        if NewDateSeparatorString <> '' then
          FormatSettings.DateSeparator := NewDateSeparatorString[1];
        if NewTimeSeparatorString <> '' then
          FormatSettings.TimeSeparator := NewTimeSeparatorString[1];
        MakeStr(ResPtr^, InnoFormatDateTime(Get(0).AsStr, Now()));
      finally
        FormatSettings.TimeSeparator := OldTimeSeparator;
        FormatSettings.DateSeparator := OldDateSeparator;
      end;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetFileDateTimeString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  NewDateSeparatorString, NewTimeSeparatorString: String;
  OldDateSeparator, OldTimeSeparator: Char;
  Age: TDateTime;
begin
  if CheckParams(Params, [evStr, evStr, evStr, evStr], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      OldDateSeparator := FormatSettings.DateSeparator;
      OldTimeSeparator := FormatSettings.TimeSeparator;
      try
        if GetCount > 2 then
          NewDateSeparatorString := Get(2).AsStr;
        if GetCount > 3 then
          NewTimeSeparatorString := Get(3).AsStr;
        if NewDateSeparatorString <> '' then
          FormatSettings.DateSeparator := NewDateSeparatorString[1];
        if NewTimeSeparatorString <> '' then
          FormatSettings.TimeSeparator := NewTimeSeparatorString[1];
        if not FileAge(PrependPath(Ext, Get(0).AsStr), Age) then
          FuncResult.RaiseError('Invalid file name')
        else
          MakeStr(ResPtr^, InnoFormatDateTime(Get(1).AsStr, Age));
      finally
        FormatSettings.TimeSeparator := OldTimeSeparator;
        FormatSettings.DateSeparator := OldDateSeparator;
      end;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetMD5OfFile(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Buf: array[0..65535] of Byte;
  Context: TMD5Context;
  F: TFile;
  NumRead: Cardinal;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MD5Init(Context);
      F := TFile.Create(PrependPath(Ext, Get(0).AsStr), fdOpenExisting, faRead, fsReadWrite);
      try
        while True do begin
          NumRead := F.Read(Buf, SizeOf(Buf));
          if NumRead = 0 then
            Break;
          MD5Update(Context, Buf, NumRead);
        end;
      finally
        F.Free;
      end;
      MakeStr(ResPtr^, MD5DigestToString(MD5Final(Context)));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetMD5OfString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: AnsiString;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := AnsiString(Get(0).AsStr);
      MakeStr(ResPtr^, MD5DigestToString(MD5Buf(Pointer(S)^, ULength(S)*SizeOf(S[1]))));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetMD5OfUnicodeString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: String;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := Get(0).AsStr;
      MakeStr(ResPtr^, MD5DigestToString(MD5Buf(Pointer(S)^, ULength(S)*SizeOf(S[1]))));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetSHA1OfFile(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Buf: array[0..65535] of Byte;
  Context: TSHA1Context;
  F: TFile;
  NumRead: Cardinal;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      SHA1Init(Context);
      F := TFile.Create(PrependPath(Ext, Get(0).AsStr), fdOpenExisting, faRead, fsReadWrite);
      try
        while True do begin
          NumRead := F.Read(Buf, SizeOf(Buf));
          if NumRead = 0 then
            Break;
          SHA1Update(Context, Buf, NumRead);
        end;
      finally
        F.Free;
      end;
      MakeStr(ResPtr^, SHA1DigestToString(SHA1Final(Context)));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetSHA1OfString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: AnsiString;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := AnsiString(Get(0).AsStr);
      MakeStr(ResPtr^, SHA1DigestToString(SHA1Buf(Pointer(S)^, ULength(S)*SizeOf(S[1]))));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetSHA1OfUnicodeString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: String;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := Get(0).AsStr;
      MakeStr(ResPtr^, SHA1DigestToString(SHA1Buf(Pointer(S)^, ULength(S)*SizeOf(S[1]))));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetSHA256OfFile(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Buf: array[0..65535] of Byte;
  Context: TSHA256Context;
  F: TFile;
  NumRead: Cardinal;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      SHA256Init(Context);
      F := TFile.Create(PrependPath(Ext, Get(0).AsStr), fdOpenExisting, faRead, fsReadWrite);
      try
        while True do begin
          NumRead := F.Read(Buf, SizeOf(Buf));
          if NumRead = 0 then
            Break;
          SHA256Update(Context, Buf, NumRead);
        end;
      finally
        F.Free;
      end;
      MakeStr(ResPtr^, SHA256DigestToString(SHA256Final(Context)));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetSHA256OfString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: AnsiString;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := AnsiString(Get(0).AsStr);
      MakeStr(ResPtr^, SHA256DigestToString(SHA256Buf(Pointer(S)^, ULength(S)*SizeOf(S[1]))));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function GetSHA256OfUnicodeString(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: String;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := Get(0).AsStr;
      MakeStr(ResPtr^, SHA256DigestToString(SHA256Buf(Pointer(S)^, ULength(S)*SizeOf(S[1]))));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function FormatFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  Args: array of TVarRec;
  IntArgs: array of Int64;
  StrArgs: array of string;
  ArgCount, I: Integer;
  Arg: PIsppVariant;
begin
  if CheckParams(Params, [evStr], 1, Result, True) then
  try
    with IInternalFuncParams(Params) do
    begin
      ArgCount := GetCount - 1;
      SetLength(Args, ArgCount);
      SetLength(IntArgs, ArgCount);
      SetLength(StrArgs, ArgCount);
      for I := 0 to ArgCount - 1 do
      begin
        Arg := Get(I + 1);
        case Arg.Typ of
          evInt:
            begin
              IntArgs[I] := Arg.AsInt64;
              Args[I].VType := vtInt64;
              Args[I].VInt64 := @IntArgs[I];
            end;
          evStr:
            begin
              StrArgs[I] := Arg.AsStr;
              Args[I].VType := vtUnicodeString;
              Args[I].VUnicodeString := Pointer(StrArgs[I]);
            end;
        else
          raise Exception.CreateFmt(
            'Format: argument %d must be an integer or string', [I + 1]);
        end;
      end;
      MakeStr(ResPtr^, InnoFormat(Get(0).AsStr, Args));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function TrimFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
      MakeStr(ResPtr^, Trim(Get(0).AsStr));
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function StringChangeFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  S: String;
begin
  if CheckParams(Params, [evStr, evStr, evStr], 3, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      S := Get(0).AsStr;
      {$IFDEF MSWINDOWS}
      StringChangeEx(S, Get(1).AsStr, Get(2).AsStr, True);
      {$ELSE}
      S := InnoStringReplace(S, Get(1).AsStr, Get(2).AsStr, [rfReplaceAll]);
      {$ENDIF}
      MakeStr(ResPtr^, S);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function IsWin64Func(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [], 0, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeBool(ResPtr^, IsWin64);
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function MessageFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do begin
      { Also see Pragma in IsppPreprocessor }
      TPreprocessor(Ext).StatusMsg(Get(0).AsStr);
      ResPtr^ := NULL;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function WarningFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do begin
      { Also see Pragma in IsppPreprocessor }
      TPreprocessor(Ext).WarningMsg(Get(0).AsStr);
      ResPtr^ := NULL;
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function ErrorFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
var
  CatchException: Boolean;
  ErrorMsg: String;
begin
  CatchException := True;
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do begin
      { Also see Pragma and pcErrorDir in IsppPreprocessor }
      ErrorMsg := Get(0).AsStr;
      if ErrorMsg = '' then ErrorMsg := 'Error';
      CatchException := False;
      TPreprocessor(Ext).RaiseError(ErrorMsg);
    end;
  except
    on E: Exception do
    begin
      if CatchException then
        FuncResult.RaiseError(PChar(String(E.Message)))
      else
        raise;
    end;
  end;
end;

function AddQuotesFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
{$IFNDEF MSWINDOWS}
var
  S: String;
{$ENDIF}
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      {$IFDEF MSWINDOWS}
      MakeStr(ResPtr^, AddQuotes(Get(0).AsStr));
      {$ELSE}
      S := Trim(Get(0).AsStr);
      if (Pos(' ', S) <> 0) and ((S[1] <> '"') or (S[Length(S)] <> '"')) then
        S := '"' + S + '"';
      MakeStr(ResPtr^, S);
      {$ENDIF}
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

function SameStrFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr, evStr], 2, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeBool(ResPtr^, InnoSameStr(Get(0).AsStr, Get(1).AsStr));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

{$IFNDEF MSWINDOWS}
function Is64BitPEImage(const Filename: String): Boolean;
var
  DosHeader: packed record
    Signature: Word;
    Reserved: array[0..57] of Byte;
    PEOffset: Cardinal;
  end;
  PEHeader: packed record
    Signature: Cardinal;
    COFFHeader: array[0..19] of Byte;
    OptionalMagic: Word;
  end;
  F: TFile;
begin
  F := TFile.Create(Filename, fdOpenExisting, faRead, fsRead);
  try
    if (F.Read(DosHeader, SizeOf(DosHeader)) <> SizeOf(DosHeader)) or
       (DosHeader.Signature <> $5A4D) or (DosHeader.PEOffset = 0) then
      Exit(False);
    F.Seek(DosHeader.PEOffset);
    Result := (F.Read(PEHeader, SizeOf(PEHeader)) = SizeOf(PEHeader)) and
      (PEHeader.Signature = $4550) and (PEHeader.OptionalMagic = $20B);
  finally
    F.Free;
  end;
end;
{$ENDIF}

function Is64BitPEImageFunc(Ext: NativeInt; const Params: IIsppFuncParams;
  const FuncResult: IIsppFuncResult): TIsppFuncResult; stdcall;
begin
  if CheckParams(Params, [evStr], 1, Result) then
  try
    with IInternalFuncParams(Params) do
    begin
      MakeBool(ResPtr^, Is64BitPEImage(PrependPath(Ext, Get(0).AsStr)));
    end;
  except
    on E: Exception do
      FuncResult.RaiseError(PChar(String(E.Message)));
  end;
end;

procedure RegisterFunctions(Preproc: TPreprocessor);
begin
  with Preproc do
  begin
    { -1 as Ext parameter means that function will be called with Ext set to
      preprocessor instance instead of -1. }
    RegisterFunction('Int', Int, -1);
    RegisterFunction('Str', Str, -1);
    RegisterFunction('FileExists', FileExists, -1);
    RegisterFunction('DirExists', DirExists, -1);
    RegisterFunction('ForceDirectories', ForceDirectoriesFunc, -1);
    RegisterFunction('FileSize', FileSize, -1);
    RegisterFunction('ReadIni', ReadIni, -1);
    RegisterFunction('WriteIni', WriteIni, -1);
    RegisterFunction('ReadReg', ReadReg, -1);
    RegisterFunction('Exec', ExecFunc, -1);
    RegisterFunction('ExecAndGetFirstLine', ExecAndGetFirstLineFunc, -1);
    RegisterFunction('Copy', CopyFunc, -1);
    RegisterFunction('Pos', PosFunc, -1);
    RegisterFunction('RPos', RPosFunc, -1);
    RegisterFunction('Len', LenFunc, -1);
    RegisterFunction('GetVersionNumbersString', GetVersionNumbersStringFunc, -1);
    RegisterFunction('ComparePackedVersion', ComparePackedVersionFunc, -1);
    RegisterFunction('SamePackedVersion', SamePackedVersionFunc, -1);
    RegisterFunction('GetStringFileInfo', GetStringFileInfoFunc, -1);
    RegisterFunction('SaveToFile', ISPP.Funcs.SaveToFile, -1);
    RegisterFunction('Find', FindLine, -1);
    RegisterFunction('SetupSetting', SetupSetting, -1);
    RegisterFunction('SetSetupSetting', SetSetupSetting, -1);
    RegisterFunction('LowerCase', LowerCaseFunc, -1);
    RegisterFunction('UpperCase', UpperCaseFunc, -1);
    RegisterFunction('EntryCount', EntryCountFunc, -1);
    RegisterFunction('GetEnv', GetEnvFunc, -1);
    RegisterFunction('DeleteFile', DelFileFunc, -1);
    RegisterFunction('DeleteFileNow', DelFileNowFunc, -1);
    RegisterFunction('CopyFile', CopyFileFunc, -1);
    RegisterFunction('ReadEnv', GetEnvFunc, -1);
    RegisterFunction('FindFirst', FindFirstFunc, -1);
    RegisterFunction('FindNext', FindNextFunc, -1);
    RegisterFunction('FindGetFileName', FindGetFileName, -1);
    RegisterFunction('FindClose', FindCloseFunc, -1);
    RegisterFunction('FileOpen', FileOpenFunc, -1);
    RegisterFunction('FileRead', FileReadFunc, -1);
    RegisterFunction('FileReset', FileResetFunc, -1);
    RegisterFunction('FileEof', FileEofFunc, -1);
    RegisterFunction('FileClose', FileCloseFunc, -1);
    RegisterFunction('SaveStringToFile', SaveStringToFileFunc, -1);
    RegisterFunction('GetDateTimeString', GetDateTimeString, -1);
    RegisterFunction('GetFileDateTimeString', GetFileDateTimeString, -1);
    RegisterFunction('GetMD5OfFile', GetMD5OfFile, -1);
    RegisterFunction('GetMD5OfString', GetMD5OfString, -1);
    RegisterFunction('GetMD5OfUnicodeString', GetMD5OfUnicodeString, -1);
    RegisterFunction('GetSHA1OfFile', GetSHA1OfFile, -1);
    RegisterFunction('GetSHA1OfString', GetSHA1OfString, -1);
    RegisterFunction('GetSHA1OfUnicodeString', GetSHA1OfUnicodeString, -1);
    RegisterFunction('GetSHA256OfFile', GetSHA256OfFile, -1);
    RegisterFunction('GetSHA256OfString', GetSHA256OfString, -1);
    RegisterFunction('GetSHA256OfUnicodeString', GetSHA256OfUnicodeString, -1);
    RegisterFunction('Format', FormatFunc, -1);
    RegisterFunction('Trim', TrimFunc, -1);
    RegisterFunction('StringChange', StringChangeFunc, -1);
    RegisterFunction('IsWin64', IsWin64Func, -1);
    RegisterFunction('Message', MessageFunc, -1);
    RegisterFunction('Warning', WarningFunc, -1);
    RegisterFunction('Error', ErrorFunc, -1);
    RegisterFunction('AddQuotes', AddQuotesFunc, -1);
    RegisterFunction('SameStr', SameStrFunc, -1);
    RegisterFunction('Is64BitPEImage', Is64BitPEImageFunc, -1);
    { The following functions are intentionally undocumented, as they do
      not integrate with the rest of the functions }
    RegisterFunction('FileGetDateTime', FileGetDate, -1);
    RegisterFunction('Now', GetNow, -1);
    RegisterFunction('DateTimeToDate', GetDateFromDT, -1);
    RegisterFunction('DateTimeToTime', GetTimeFromDT, -1);
  end;
end;

{$IF Defined(MSWINDOWS) and not Defined(WIN64)}

procedure InitIsWin64;
var
  IsWow64ProcessFunc: function(hProcess: THandle; var Wow64Process: BOOL): BOOL; stdcall;
  Wow64Process: BOOL;
begin
  IsWow64ProcessFunc := GetProcAddress(GetModuleHandle(kernel32), 'IsWow64Process');
  IsWin64 := Assigned(IsWow64ProcessFunc) and
             IsWow64ProcessFunc(GetCurrentProcess, Wow64Process) and
             Wow64Process;
end;

initialization
  InitIsWin64;

{$ENDIF}

{$IFNDEF MSWINDOWS}
finalization
  AsyncProcesses.Free;
{$ENDIF}

end.
