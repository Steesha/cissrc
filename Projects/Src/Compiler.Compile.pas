unit Compiler.Compile;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Compiler DLL interface functions which wrap TSetupCompiler
}

interface

uses
  Shared.CompilerInt.Struct, Shared.FPCStringUtils;

function ISCompileScript(const Params: TCompileScriptParamsEx;
  const PropagateExceptions: Boolean; const MainScriptFilename: String = ''): Integer;
function ISGetVersion: PCompilerVersionInfo;

implementation

uses
  {$IFDEF MSWINDOWS} Windows, PathFunc, {$ELSE} Shared.PlatformTypes, {$ENDIF}
  SysUtils, Classes, Shared.Struct, Shared.CompilerSupport, Compiler.SetupCompiler;

var
  CompileScriptLock: TSimpleLock;

function GetSelfFilename: String;
{ Returns Filename of the calling DLL or application. (ParamStr(0) can only
  return the filename of the calling application.) }
{$IFDEF MSWINDOWS}
var
  Buf: array[0..MAX_PATH-1] of Char;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  SetString(Result, Buf, GetModuleFileNameW(HInstance, Buf, Length(Buf)));
  {$ELSE}
  Result := ExpandFileName(ParamStr(0));
  {$ENDIF}
end;

function ISCompileScript(const Params: TCompileScriptParamsEx;
  const PropagateExceptions: Boolean; const MainScriptFilename: String): Integer;
var
  SetupCompiler: TSetupCompiler;
  P: PChar;
  P2: Integer;
  Output, NoCompression, NoSigning, NoSignCheck, PreprocessOnly: Boolean;

  function CheckParams(const Params: TCompileScriptParamsEx): Boolean;
  begin
    Result := ((Params.Size = SizeOf(Params)) or
               (Params.Size = SizeOf(TCompileScriptParams))) and
              Assigned(Params.CallbackProc);
  end;

  procedure InitializeSetupCompiler(const SetupCompiler: TSetupCompiler;
    const Params: TCompileScriptParamsEx);
  begin
    SetupCompiler.AppData := Params.AppData;
    SetupCompiler.CallbackProc := Params.CallbackProc;
    if Assigned(Params.CompilerPath) then
      SetupCompiler.CompilerDir := Params.CompilerPath
    else
      {$IFDEF MSWINDOWS}
      SetupCompiler.CompilerDir := PathExtractPath(GetSelfFilename);
      {$ELSE}
      SetupCompiler.CompilerDir := UTF8Decode(ExtractFilePath(UTF8Encode(GetSelfFilename)));
      {$ENDIF}
    SetupCompiler.SourceDir := Params.SourcePath;
    SetupCompiler.MainScriptFilename := MainScriptFilename;
  end;

  function EncodeIncludedFilenames(const IncludedFilenames: TStringList): String;
  var
    S: String;
    I: Integer;
  begin
    S := '';
    for I := 0 to IncludedFilenames.Count-1 do
     S := S + {$IFDEF FPC}UTF8Decode(IncludedFilenames[I]){$ELSE}IncludedFilenames[I]{$ENDIF} + #0;
    Result := S;
  end;

  procedure NotifyPreproc(const SetupCompiler: TSetupCompiler);
  var
    Data: TCompilerCallbackData;
    S: String;
    {$IFDEF FPC}
    WriteTimes: TArray<TFileTime>;
    {$ENDIF}
  begin
    Data.PreprocessedScript := PChar(SetupCompiler.GetPreprocOutput);
    S := EncodeIncludedFilenames(SetupCompiler.GetPreprocIncludedFilenames);
    Data.IncludedFilenames := PChar(S);
    {$IFDEF FPC}
    WriteTimes := SetupCompiler.GetPreprocIncludedFilesLastWriteTimes.ToArray;
    Data.IncludedFilesLastWriteTimes := Pointer(WriteTimes);
    {$ELSE}
    Data.IncludedFilesLastWriteTimes := Pointer(SetupCompiler.GetPreprocIncludedFilesLastWriteTimes.List);
    {$ENDIF}
    Params.CallbackProc(iscbNotifyPreproc, Data, Params.AppData);
  end;

  procedure NotifySuccess(const SetupCompiler: TSetupCompiler);
  var
    Data: TCompilerCallbackData;
    DebugInfo: TMemoryStream;
  begin
    Data.OutputExeFilename := PChar(SetupCompiler.GetExeFilename);
    DebugInfo := SetupCompiler.GetDebugInfo;
    Data.DebugInfo := DebugInfo.Memory;
    if DebugInfo.Size > High(Cardinal) then
      raise Exception.Create('Unexpected DebugInfo.Size value');
    Data.DebugInfoSize := Cardinal(DebugInfo.Size);
    Params.CallbackProc(iscbNotifySuccess, Data, Params.AppData);
  end;

  procedure NotifyError(const SetupCompiler: TSetupCompiler);
  var
    Data: TCompilerCallbackData;
    S: String;
  begin
    Data.ErrorMsg := nil;
    Data.ErrorFilename := nil;
    Data.ErrorLine := 0;
    if not(ExceptObject is EAbort) then begin
      S := GetExceptMessage;
      Data.ErrorMsg := PChar(S);
      { use a Pointer cast instead of PChar so that we'll get a null
        pointer if the string is empty }
      Data.ErrorFilename := Pointer(SetupCompiler.GetLineFilename);
      Data.ErrorLine := SetupCompiler.GetLineNumber;
    end;
    Params.CallbackProc(iscbNotifyError, Data, Params.AppData);
  end;

begin
  if not CheckParams(Params) then
    Exit(isceInvalidParam);

  SetupCompiler := nil;
  if not CompileScriptLock.TryAcquire then
    Exit(isceConcurrentCall);
  try
    SetupCompiler := TSetupCompiler.Create(nil);
    InitializeSetupCompiler(SetupCompiler, Params);

    { Parse Options (only present in TCompileScriptParamsEx) }
    if (Params.Size <> SizeOf(TCompileScriptParams)) and Assigned(Params.Options) then begin
      P := Params.Options;
      while P^ <> #0 do begin
        if StrLIComp(P, 'Output=', Length('Output=')) = 0 then begin
          Inc(P, Length('Output='));
          if TryStrToBoolean(P, Output) then
            SetupCompiler.SetOutput(Output)
          else begin
            { Bad option }
            Result := isceInvalidParam;
            Exit;
          end;
        end else if StrLIComp(P, 'OutputDir=', Length('OutputDir=')) = 0 then begin
          Inc(P, Length('OutputDir='));
          SetupCompiler.SetOutputDir(P);
        end else if StrLIComp(P, 'OutputBaseFilename=', Length('OutputBaseFilename=')) = 0 then begin
          Inc(P, Length('OutputBaseFilename='));
          SetupCompiler.SetOutputBaseFilename(P);
        end else if StrLIComp(P, 'SignTool-', Length('SignTool-')) = 0 then begin
          Inc(P, Length('SignTool-'));
          P2 := Pos('=', String(P));
          if (P2 <> 0) then
            SetupCompiler.AddSignTool(Copy(P, 1, P2-1), Copy(P, P2+1, MaxInt))
          else begin
            { Bad option }
            Result := isceInvalidParam;
            Exit;
          end;
        end else if StrLIComp(P, 'NoCompression=', Length('NoCompression=')) = 0 then begin
          Inc(P, Length('NoCompression='));
          if TryStrToBoolean(P, NoCompression) then
            SetupCompiler.SetNoCompression(NoCompression)
          else begin
            Result := isceInvalidParam;
            Exit;
          end;
        end else if StrLIComp(P, 'NoSigning=', Length('NoSigning=')) = 0 then begin
          Inc(P, Length('NoSigning='));
          if TryStrToBoolean(P, NoSigning) then
            SetupCompiler.SetNoSigning(NoSigning)
          else begin
            Result := isceInvalidParam;
            Exit;
          end;
        end else if StrLIComp(P, 'NoSignCheck=', Length('NoSignCheck=')) = 0 then begin
          Inc(P, Length('NoSignCheck='));
          if TryStrToBoolean(P, NoSignCheck) then
            SetupCompiler.SetNoSignCheck(NoSignCheck)
          else begin
            Result := isceInvalidParam;
            Exit;
          end;
        end else if StrLIComp(P, 'PreprocessOnly=', Length('PreprocessOnly=')) = 0 then begin
          Inc(P, Length('PreprocessOnly='));
          if TryStrToBoolean(P, PreprocessOnly) then
            SetupCompiler.SetPreprocessOnly(PreprocessOnly)
          else begin
            Result := isceInvalidParam;
            Exit;
          end;
        end else if StrLIComp(P, 'ISPP:', Length('ISPP:')) = 0 then
          SetupCompiler.AddPreprocOption(P)
        else begin
          { Unknown option }
          Result := isceInvalidParam;
          Exit;
        end;
        Inc(P, StrLen(P) + 1);
      end;
    end;

    try
      try
        SetupCompiler.Compile;
      finally
        NotifyPreproc(SetupCompiler);
      end;
      Result := isceNoError;
      NotifySuccess(SetupCompiler);
    except
      Result := isceCompileFailure;
      NotifyError(SetupCompiler);
      if PropagateExceptions then
        raise;
    end;
  finally
    SetupCompiler.Free;
    CompileScriptLock.Release;
  end;
end;

function ISGetVersion: PCompilerVersionInfo;
const
  Ver: TCompilerVersionInfo =
   (Title: SetupTitle; Version: SetupVersion; BinVersion: SetupBinVersion);
begin
  Result := @Ver;
end;

end.
