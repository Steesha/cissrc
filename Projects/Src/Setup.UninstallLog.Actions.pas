unit Setup.UninstallLog.Actions;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Executes the operations recorded in an uninstall log
}

interface

uses
  Setup.UninstallLog;

type
  TDeleteUninstallDataFilesProc = procedure;

  TUninstallActionLog = class(TUninstallLog)
  protected
    procedure HandleException; virtual; abstract;
    function ShouldRemoveSharedFile(const Filename: String): Boolean; virtual;
    procedure StatusUpdate(StartingCount, CurCount: Integer); virtual;
  public
    function CheckMutexes: Boolean;
    function PerformUninstall(const CallFromUninstaller: Boolean;
      const DeleteUninstallDataFilesProc: TDeleteUninstallDataFilesProc): Boolean;
  end;

implementation

uses
  Windows, SysUtils, ShlObj,
  UnsignedFunc, PathFunc,
  Shared.CommonFunc, Shared.Struct, Shared.SetupTypes, Shared.SetupMessageIDs, SetupLdrAndSetup.Messages,
  Setup.InstFunc, Setup.InstFunc.Ole, Compression.Base,
  Setup.LoggingFunc, Setup.RegDLL, Setup.DotNetFunc, Setup.PathRedir;

{ Misc. uninstallation functions }

function ListContainsPathOrSubdir(const List: TSimpleStringList;
  const Path: String): Boolean;
{ Returns True if List contains Path or a subdirectory of Path }
var
  SlashPath: String;
  SlashPathLen, I: Integer;
begin
  SlashPath := AddBackslash(Path);
  SlashPathLen := Length(SlashPath);
  if SlashPathLen > 0 then begin   { ...sanity check }
    for I := 0 to List.Count-1 do begin
      if PathSame(List[I], Path) then begin
        Result := True;
        Exit;
      end;
      if (Length(List[I]) > SlashPathLen) and
         PathStartsWith(List[I], SlashPath) then begin
        Result := True;
        Exit;
      end;
    end;
  end;
  Result := False;
end;

procedure LoggedRestartDeleteDir(const Dir: String);
var
  ErrorCode: DWORD;
begin
  if not TryRestartReplace(Dir, '', ErrorCode) then
    LogWithErrorCode('MoveFileEx failed.', ErrorCode);
end;

function LoggedDeleteDir(const DirName: String;
  const DirsNotRemoved, RestartDeleteDirList: TSimpleStringList): Boolean;
const
  FILE_ATTRIBUTE_REPARSE_POINT = $00000400;
var
  Attribs, LastError: DWORD;
begin
  Attribs := GetFileAttributesW(PWideChar(DirName));
  { Does the directory exist? }
  if (Attribs <> INVALID_FILE_ATTRIBUTES) and
     (Attribs and FILE_ATTRIBUTE_DIRECTORY <> 0) then begin
    LogFmt('Deleting directory: %s', [DirName]);
    { If the directory has the read-only attribute, strip it first }
    if Attribs and FILE_ATTRIBUTE_READONLY <> 0 then begin
      if (Attribs and FILE_ATTRIBUTE_REPARSE_POINT <> 0) or
         IsDirEmpty(DirName) then begin
        if SetFileAttributesW(PWideChar(DirName), Attribs and not FILE_ATTRIBUTE_READONLY) then
          Log('Stripped read-only attribute.')
        else
          Log('Failed to strip read-only attribute.');
      end
      else
        Log('Not stripping read-only attribute because the directory ' +
          'does not appear to be empty.');
    end;
    Result := RemoveDirectoryW(PWideChar(DirName));
    if not Result then begin
      LastError := GetLastError;
      if Assigned(DirsNotRemoved) then begin
        LogFmt('Failed to delete directory (%d). Will retry later.', [LastError]);
        DirsNotRemoved.AddIfDoesntExist(DirName);
      end
      else if Assigned(RestartDeleteDirList) and
         ListContainsPathOrSubdir(RestartDeleteDirList, DirName) then begin
        LogFmt('Failed to delete directory (%d). Will delete on restart (if empty).',
          [LastError]);
        LoggedRestartDeleteDir(DirName);
      end
      else
        LogFmt('Failed to delete directory (%d).', [LastError]);
    end;
  end
  else
    Result := True;
end;

procedure CrackRegExtraData(const ExtraData: TUninstallRecExtraData;
  var RegView: TRegView; var RootKey: HKEY);
begin
  if ExtraData and utReg_64BitKey <> 0 then
    RegView := rv64Bit
  else
    RegView := rv32Bit;
  RootKey := ExtraData and utReg_KeyHandleMask;
end;

type
  PDeleteDirData = ^TDeleteDirData;
  TDeleteDirData = record
    DirsNotRemoved: TSimpleStringList;
  end;

function LoggedDeleteDirProc(const DirName: String; const Param: Pointer): Boolean;
begin
  Result := LoggedDeleteDir(DirName, PDeleteDirData(Param)^.DirsNotRemoved, nil);
end;

function LoggedDeleteFileProc(const FileName: String; const Param: Pointer): Boolean;
begin
  LogFmt('Deleting file: %s', [FileName]);
  Result := Windows.DeleteFileW(PWideChar(FileName));
  if not Result then
    LogFmt('Failed to delete the file; it may be in use (%d).', [GetLastError]);
end;

procedure ProcessMessagesProc; far;
var
  Msg: TMsg;
begin
  while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
end;

function TUninstallActionLog.CheckMutexes: Boolean;
var
  CurRec: PUninstallRec;
  Data: String;
begin
  Result := False;
  CurRec := LastList;
  while CurRec <> nil do begin
    if CurRec^.Typ = utMutexCheck then begin
      ExtractRecData(CurRec, Data);
      if CheckForMutexes(Data) then begin
        Result := True;
        Exit;
      end;
    end;
    CurRec := CurRec^.Prev;
  end;
end;

procedure RunExecLog(const S: String; const Error, FirstLine: Boolean; const Data: NativeInt);
begin
  if not Error and FirstLine then
    Log('Running Exec output:');
  Log(S);
end;

function TUninstallActionLog.PerformUninstall(const CallFromUninstaller: Boolean;
  const DeleteUninstallDataFilesProc: TDeleteUninstallDataFilesProc): Boolean;
{ Undoes all the changes in the uninstall list, in reverse order they were
  added. Deletes entries that were successfully undone.
  Returns True if all elements were successfully removed; False if some
  could not be removed. }

var
  RefreshFileAssoc: Boolean;
  ChangeNotifyList, RunOnceList: TSimpleStringList;
  UnregisteredServersList, RestartDeleteDirList: TSimpleStringList;
  DeleteDirData: TDeleteDirData;

  function LoggedFileDelete(const Filename: String; const NotifyChange,
    RestartDelete, RemoveReadOnly: Boolean): Boolean;
  var
    ExistingAttr, LastError: DWORD;
  begin
    Result := True;

    { Automatically delete generated indexes associated with help files }
    if SameText(PathExtractExt(Filename), '.hlp') then begin
      LoggedFileDelete(PathChangeExt(Filename, '.gid'), False, False, False);
      LoggedFileDelete(PathChangeExt(Filename, '.fts'), False, False, False);
    end
    else if SameText(PathExtractExt(Filename), '.chm') then
      LoggedFileDelete(PathChangeExt(Filename, '.chw'), False, False, False);

    { Automatically unpin shortcuts }
    if SameText(PathExtractExt(Filename), '.lnk') then
      UnpinShellLink(Filename);

    if NewFileExists(Filename) then begin
      LogFmt('Deleting file: %s', [FileName]);
      if RemoveReadOnly then begin
        ExistingAttr := GetFileAttributesW(PWideChar(Filename));
        if (ExistingAttr <> INVALID_FILE_ATTRIBUTES) and
           (ExistingAttr and FILE_ATTRIBUTE_READONLY <> 0) then
          if SetFileAttributesW(PWideChar(Filename),
             ExistingAttr and not FILE_ATTRIBUTE_READONLY) then
            Log('Stripped read-only attribute.')
          else
            Log('Failed to strip read-only attribute.');
      end;
      if not Windows.DeleteFileW(PWideChar(Filename)) then begin
        LastError := GetLastError;
        if RestartDelete and CallFromUninstaller and
           ((LastError = ERROR_ACCESS_DENIED) or (LastError = ERROR_SHARING_VIOLATION)) and
           (GetFileAttributesW(PWideChar(Filename)) and FILE_ATTRIBUTE_READONLY = 0) then begin
          LogFmt('The file appears to be in use (%d). Will delete on restart.',
            [LastError]);
          try
            RestartReplace(Filename, '');
            NeedRestart := True;
            { Add the file's directory to the list of directories that should
              be restart-deleted later }
            RestartDeleteDirList.AddIfDoesntExist(PathExtractDir(Filename));
          except
            Log('Exception message:' + SNewLine + GetExceptMessage);
            Result := False;
          end;
        end
        else begin
          LogFmt('Failed to delete the file; it may be in use (%d).', [LastError]);
          Result := False;
        end;
      end
      else begin
        if NotifyChange then
          ShellChangeNotifyPath(SHCNE_DELETE, Filename, False, ChangeNotifyList);
      end;
    end;
  end;

  procedure LoggedUnregisterServer(const Is64Bit: Boolean; const Filename: String);
  begin
    { Just as an optimization, make sure we aren't unregistering
      the same file again }
    if UnregisteredServersList.IndexOf(Filename) = -1 then begin
      if Is64Bit then
        LogFmt('Unregistering 64-bit DLL/OCX: %s', [Filename])
      else
        LogFmt('Unregistering 32-bit DLL/OCX: %s', [Filename]);
      try
        RegisterServer(True, Is64Bit, Filename);
        UnregisteredServersList.Add(Filename);
        Log('Unregistration successful.');
      except
        Log('Unregistration failed:' + SNewLine + GetExceptMessage);
      end;
    end
    else
      LogFmt('Not unregistering DLL/OCX again: %s', [Filename]);
  end;

  procedure LoggedUnregisterTypeLibrary(const Is64Bit: Boolean;
    const Filename: String);
  begin
    if Is64Bit then
      LogFmt('Unregistering 64-bit type library: %s', [Filename])
    else
      LogFmt('Unregistering 32-bit type library: %s', [Filename]);
    try
      {$IFDEF WIN64}
      if Is64Bit then
        UnregisterTypeLibrary(Filename)
      else
        raise Exception.Create('Cannot unregister 32-bit type libraries on this version of Uninstall');
      {$ELSE}
      if Is64Bit then
        raise Exception.Create('Cannot unregister 64-bit type libraries on this version of Uninstall')
      else
        UnregisterTypeLibrary(Filename);
      {$ENDIF}
      Log('Unregistration successful.');
    except
      Log('Unregistration failed:' + SNewLine + GetExceptMessage);
    end;
  end;

  procedure LoggedUninstallAssembly(const StrongAssemblyName: String);
  begin
    LogFmt('Uninstalling from GAC: %s', [StrongAssemblyName]);
    try
      with TAssemblyCacheInfo.Create(rvDefault) do try
        UninstallAssembly(StrongAssemblyName);
      finally
        Free;
      end;
    except
      Log('Uninstallation failed:' + SNewLine + GetExceptMessage);
    end;
  end;

  procedure LoggedProcessDirsNotRemoved;
  var
    I: Integer;
  begin
    for I := 0 to DeleteDirData.DirsNotRemoved.Count-1 do
      LoggedDeleteDir(DeleteDirData.DirsNotRemoved[I], nil, RestartDeleteDirList);
  end;

  function GetLogIniFilename(const Filename: String): String;
  begin
    if Filename <> '' then
      Result := Filename
    else
      Result := 'win.ini';
  end;

const
  NullChar: Char = #0;
var
  StartCount: Integer;
  CurRec: PUninstallRec;
  CurRecDataPChar: array[0..9] of PChar;
  CurRecData: array[0..9] of String;
  ShouldDeleteRec, IsSharedFile, SharedCountDidReachZero: Boolean;
  Section, Key: String;
  Subkey, ValueName: PChar;
  P: Integer;
  RegView: TRegView;
  RootKey, K: HKEY;
  Wait: TExecWait;
  ShowCmd: Integer;
  RunType, ExpandedFilename, ExpandedParameters, ExpandedWorkingDir: String;
  ExpandedFilenameBeforeRedir: String;
  RunEntry64Bit, LogOutputFlag: Boolean;
  RunErrorCode: DWORD;
  OutputReader: TCreateProcessOutputReader;
  IsTempFile, Is64Bit, RegisteredWithOppositeBitness: Boolean;
  Filename, FontFilename, Path: String;
  RegistryErrorCode: LongInt;

  procedure SplitData(const Rec: PUninstallRec);
  var
    C, I: Integer;
  begin
    C := ExtractRecData(Rec, CurRecData);
    for I := 0 to 9 do begin
      if I < C then
        CurRecDataPChar[I] := PChar(CurRecData[I])
      else
        CurRecDataPChar[I] := nil;
    end;
  end;

begin
  Log('Starting the uninstallation process.');
  SetCurrentDir(GetSystemDir);
  Result := True;
  NeedRestart := False;

  RefreshFileAssoc := False;
  RunOnceList := nil;
  UnregisteredServersList := nil;
  RestartDeleteDirList := nil;
  DeleteDirData.DirsNotRemoved := nil;
  ChangeNotifyList := TSimpleStringList.Create;
  try
    RunOnceList := TSimpleStringList.Create;
    UnregisteredServersList := TSimpleStringList.Create;
    RestartDeleteDirList := TSimpleStringList.Create;
    if Assigned(DeleteUninstallDataFilesProc) then
      DeleteDirData.DirsNotRemoved := TSimpleStringList.Create;

    StartCount := FCount;
    StatusUpdate(StartCount, FCount);

    { Step 1 - Process all utRun entries }
    if CallFromUninstaller then begin
      CurRec := LastList;
      while CurRec <> nil do begin
        if CurRec^.Typ = utRun then begin
          try
            SplitData(CurRec);
            { Verify that a utRun entry with the same RunOnceId has not
              already been executed }
            if (CurRecData[3] = '') or (RunOnceList.IndexOf(CurRecData[3]) = -1) then begin
              Wait := ewWaitUntilTerminated;
              if CurRec^.ExtraData and utRun_NoWait <> 0 then
                Wait := ewNoWait
              else if CurRec^.ExtraData and utRun_WaitUntilIdle <> 0 then
                Wait := ewWaitUntilIdle;
              ShowCmd := SW_SHOWNORMAL;
              if CurRec^.ExtraData and utRun_RunMinimized <> 0 then
                ShowCmd := SW_SHOWMINNOACTIVE
              else if CurRec^.ExtraData and utRun_RunMaximized <> 0 then
                ShowCmd := SW_SHOWMAXIMIZED
              else if CurRec^.ExtraData and utRun_RunHidden <> 0 then
                ShowCmd := SW_HIDE;

              { Note: The following code is similar to code in the ProcessRunEntry
                function of Setup.MainFunc.pas }

              if CurRec^.ExtraData and utRun_ShellExec = 0 then
                RunType := 'Exec'
              else
                RunType := 'ShellExec';

              RunEntry64Bit := CurRec^.ExtraData and utRun_Is64Bit <> 0;
              ExpandedFilename := CurRecData[0];
              ExpandedParameters := CurRecData[1];
              ExpandedWorkingDir := CurRecData[2];

              ExpandedFilenameBeforeRedir := ExpandedFilename;
              if CurRec^.ExtraData and utRun_ShellExec = 0 then
                ApplyRedirToRunEntryPaths(RunEntry64Bit, ExpandedFilename, ExpandedWorkingDir);

              LogFmt('Running %s filename: %s', [RunType, ExpandedFilename]);
              if (CurRec^.ExtraData and utRun_DontLogParameters = 0) and (ExpandedParameters <> '') then
                LogFmt('Running %s parameters: %s', [RunType, ExpandedParameters]);
              try
                if CurRec^.ExtraData and utRun_ShellExec = 0 then begin
                  if (CurRec^.ExtraData and utRun_SkipIfDoesntExist = 0) or
                     ((ExpandedFilenameBeforeRedir <> '') and
                      NewFileExists(ApplyPathRedirRules(RunEntry64Bit, ExpandedFilenameBeforeRedir, tpCurrent))) then begin
                    LogOutputFlag := CurRec^.ExtraData and utRun_LogOutput <> 0;
                    OutputReader := nil;
                    try
                      if GetLogActive and LogOutputFlag then
                        OutputReader := TCreateProcessOutputReader.Create(RunExecLog, 0);

                      if not InstExec(RunEntry64Bit and not IsCurrentProcess64Bit,
                         ExpandedFilename, ExpandedParameters, ExpandedWorkingDir,
                         Wait, ShowCmd, LogOutputFlag, ProcessMessagesProc, OutputReader, RunErrorCode) then begin
                        LogFmt('CreateProcess failed (%d).', [RunErrorCode]);
                        Result := False;
                      end
                      else begin
                        if Wait = ewWaitUntilTerminated then
                          LogFmt('Process exit code: %u', [RunErrorCode]);
                      end;
                    finally
                      OutputReader.Free;
                    end;
                  end else
                    Log('File doesn''t exist. Skipping.');
                end
                else begin
                  if (CurRec^.ExtraData and utRun_SkipIfDoesntExist = 0) or
                     FileOrDirExists(ExpandedFilename) then begin
                    if CurRec^.ExtraData and utRun_ShellExecRespectWaitFlags = 0 then
                      Wait := ewNoWait;

                    if not InstShellExec(CurRecData[4],
                       ExpandedFilename, ExpandedParameters, ExpandedWorkingDir,
                       Wait, ShowCmd, ProcessMessagesProc, RunErrorCode) then begin
                      LogFmt('ShellExecuteEx failed (%d).', [RunErrorCode]);
                      Result := False;
                    end
                    else begin
                      if Wait = ewWaitUntilTerminated then
                        LogFmt('Process exit code: %u', [RunErrorCode]);
                    end;
                  end else
                    Log('File/directory doesn''t exist. Skipping.');
                end;
              finally
                if CurRecData[3] <> '' then
                  RunOnceList.Add(CurRecData[3]);
              end;
            end else
              LogFmt('Skipping RunOnceId "%s" filename: %s', [CurRecData[3], CurRecData[0]]);
          except
            Result := False;
            if not(ExceptObject is EAbort) then
              HandleException;
          end;
          CurRec := Delete(CurRec);
          StatusUpdate(StartCount, FCount);
        end
        else
          CurRec := CurRec^.Prev;
      end;
    end;

    { Step 2 - Decrement shared file counts, unregister DLLs/TLBs/fonts, and uninstall from GAC }
    CurRec := LastList;
    while CurRec <> nil do begin
      ShouldDeleteRec := False;
      if CurRec^.Typ = utDeleteFile then begin
        { Default to deleting the record in case an exception is raised by
          DecrementSharedCount, the reference count doesn't reach zero, or the
          user opts not to delete the shared file. }
        ShouldDeleteRec := True;
        try
          SplitData(CurRec);
          { Note: Some of this code is duplicated in Step 3 }
          if CallFromUninstaller or (CurRec^.ExtraData and utDeleteFile_ExistedBeforeInstall = 0) then begin
            IsTempFile := not CallFromUninstaller and (CurRecData[1] <> '');

            Is64Bit := CurRec^.ExtraData and utDeleteFile_Is64Bit <> 0;
            Filename := ApplyPathRedirRules(Is64Bit, CurRecData[0], tpCurrent);

            { Decrement shared file count if necessary }
            IsSharedFile := CurRec^.ExtraData and utDeleteFile_SharedFile <> 0;
            if IsSharedFile then
              SharedCountDidReachZero := DecrementSharedCount(
                CurRec^.ExtraData and utDeleteFile_SharedFileIn64BitKey <> 0,
                Filename)
            else
              SharedCountDidReachZero := False; //silence compiler

            if not IsSharedFile or
               (SharedCountDidReachZero and
                (IsTempFile or not NewFileExists(Filename) or
                 (CurRec^.ExtraData and utDeleteFile_NoSharedFilePrompt <> 0) or
                 ShouldRemoveSharedFile(Filename))) then begin
              { The reference count reached zero and the user did not object
                to the file being deleted, so don't delete the record; allow
                the file to be deleted in the next step. }
              ShouldDeleteRec := False;
              { Unregister if necessary }
              if not IsTempFile then begin
                if CurRec^.ExtraData and utDeleteFile_RegisteredServer <> 0 then begin
                  RegisteredWithOppositeBitness :=
                    CurRec^.ExtraData and utDeleteFile_RegisteredWithOppositeBitness <> 0;
                  LoggedUnregisterServer(Is64Bit xor RegisteredWithOppositeBitness, Filename);
                end;
                if CurRec^.ExtraData and utDeleteFile_RegisteredTypeLib <> 0 then
                  LoggedUnregisterTypeLibrary(Is64Bit, Filename);
              end;
              if CurRec^.ExtraData and utDeleteFile_IsFont <> 0 then begin
                LogFmt('Unregistering font: %s', [CurRecData[2]]);
                FontFilename := CurRecData[3];
                if PathIsRooted(FontFilename) then { Filename may have been shorted by ShortenFontFilename }
                  FontFilename := ApplyPathRedirRules(Is64Bit, FontFilename, tpCurrent);
                UnregisterFont(CurRecData[2], FontFilename, CurRec^.ExtraData and utDeleteFile_PerUserFont <> 0);
              end;
              if CurRec^.ExtraData and utDeleteFile_GacInstalled <> 0 then
                LoggedUninstallAssembly(CurRecData[4]);
            end;
          end
          else begin
            { This case is handled entirely in Step 3 }
            ShouldDeleteRec := False;
          end;
        except
          Result := False;
          if not(ExceptObject is EAbort) then
            HandleException;
        end;
      end;
      if ShouldDeleteRec then begin
        CurRec := Delete(CurRec);
        StatusUpdate(StartCount, FCount);
      end
      else
        CurRec := CurRec^.Prev;
    end;

    { Step 3 - Remaining entries }
    CurRec := LastList;
    while CurRec <> nil do begin
      SplitData(CurRec);
      try
        case CurRec^.Typ of
          utUserDefined: begin
              {if CurRecData[0] = 'MyRecordType' then begin
                 ... your code here ...
              end
              else}
                raise Exception.Create(FmtSetupMessage1(msgUninstallUnknownEntry,
                  'utUserDefined:' + CurRecData[0]));
            end;
          utStartInstall,
          utEndInstall,
          utCompiledCode: { do nothing on these };
          utRun: begin
              { Will get here if CallFromUninstaller=False; in that case utRun
                entries will still be in the list, unprocessed. Just ignore
                them. }
            end;
          utDeleteDirOrFiles:
            if (CallFromUninstaller or (CurRec^.ExtraData and utDeleteDirOrFiles_Extra = 0)) then begin
              Is64Bit := CurRec^.ExtraData and utDeleteDirOrFiles_Is64Bit <> 0;
              Path := ApplyPathRedirRules(Is64Bit, CurRecData[0], tpCurrent);
              if DelTree(Path, CurRec^.ExtraData and utDeleteDirOrFiles_IsDir <> 0,
                 True,
                 CurRec^.ExtraData and utDeleteDirOrFiles_DeleteFiles <> 0,
                 CurRec^.ExtraData and utDeleteDirOrFiles_DeleteSubdirsAlso <> 0,
                 False, LoggedDeleteDirProc, LoggedDeleteFileProc, @DeleteDirData) then begin
                if (CurRec^.ExtraData and utDeleteDirOrFiles_IsDir <> 0) and
                   (CurRec^.ExtraData and utDeleteDirOrFiles_CallChangeNotify <> 0) then begin
                  ShellChangeNotifyPath(SHCNE_RMDIR, Path, False, ChangeNotifyList);
                end;
              end;
            end;
          utDeleteFile: begin
              { Note: Some of this code is duplicated in Step 2 }
              Is64Bit := CurRec^.ExtraData and utDeleteFile_Is64Bit <> 0;
              IsTempFile := not CallFromUninstaller and (CurRecData[1] <> '');
              if IsTempFile then
                Filename := CurRecData[1]
              else
                Filename := CurRecData[0];
              Filename := ApplyPathRedirRules(Is64Bit, Filename, tpCurrent);
              if CallFromUninstaller or (CurRec^.ExtraData and utDeleteFile_ExistedBeforeInstall = 0) then begin
                { Note: We handled utDeleteFile_SharedFile already }
                if CallFromUninstaller or (CurRec^.ExtraData and utDeleteFile_Extra = 0) then
                  if not LoggedFileDelete(Filename,
                     CurRec^.ExtraData and utDeleteFile_CallChangeNotify <> 0,
                     CurRec^.ExtraData and utDeleteFile_RestartDelete <> 0,
                     CurRec^.ExtraData and utDeleteFile_RemoveReadOnly <> 0) then
                    Result := False;
              end
              else begin
                { We're running from Setup, and the file existed before
                  installation... }
                if CurRec^.ExtraData and utDeleteFile_SharedFile <> 0 then
                  DecrementSharedCount(
                    CurRec^.ExtraData and utDeleteFile_SharedFileIn64BitKey <> 0,
                    ApplyPathRedirRules(Is64Bit, CurRecData[0], tpCurrent));
                { Delete file only if it's a temp file }
                if IsTempFile then
                  if not LoggedFileDelete(Filename,
                     CurRec^.ExtraData and utDeleteFile_CallChangeNotify <> 0,
                     CurRec^.ExtraData and utDeleteFile_RestartDelete <> 0,
                     CurRec^.ExtraData and utDeleteFile_RemoveReadOnly <> 0) then
                    Result := False;
              end;
            end;
          utDeleteGroupOrItem: ;   { dummy - no longer supported }
          utIniDeleteEntry: begin
              Section := CurRecData[1];
              Key := CurRecData[2];
              Filename := CurRecData[0];
              LogFmt('Deleting INI entry: %s in section %s in %s', [Key, Section, GetLogIniFilename(Filename)]);
              DeleteIniEntry(Section, Key, Filename);
            end;
          utIniDeleteSection: begin
              Section := CurRecData[1];
              Filename := CurRecData[0];
              if (CurRec^.ExtraData and utIniDeleteSection_OnlyIfEmpty = 0) or
                 IsIniSectionEmpty(Section, Filename) then begin
                LogFmt('Deleting INI section: %s in %s', [Section, GetLogIniFilename(Filename)]);
                DeleteIniSection(Section, Filename);
              end;
            end;
          utRegDeleteEntireKey: begin
              CrackRegExtraData(CurRec^.ExtraData, RegView, RootKey);
              Subkey := CurRecDataPChar[0];
              LogFmt('Deleting registry key: %s\%s', [GetRegRootKeyName(RootKey), Subkey]);
              RegistryErrorCode := RegDeleteKeyIncludingSubkeys(RegView, RootKey, Subkey);
              if not (RegistryErrorCode in [ERROR_SUCCESS, ERROR_FILE_NOT_FOUND]) then begin
                LogFmt('Deletion failed (%d).', [RegistryErrorCode]);
                Result := False;
              end;
            end;
          utRegClearValue: begin
              CrackRegExtraData(CurRec^.ExtraData, RegView, RootKey);
              Subkey := CurRecDataPChar[0];
              ValueName := CurRecDataPChar[1];
              LogFmt('Clearing registry value: %s\%s\%s', [GetRegRootKeyName(RootKey), Subkey, ValueName]);
              if RegOpenKeyExView(RegView, RootKey, Subkey, 0, KEY_SET_VALUE, K) = ERROR_SUCCESS then begin
                RegistryErrorCode := RegSetValueExW(K, ValueName, 0, REG_SZ, PByte(@NullChar), SizeOf(NullChar));
                if RegistryErrorCode <> ERROR_SUCCESS then begin
                  LogFmt('RegSetValueEx failed (%d).', [RegistryErrorCode]);
                  Result := False;
                end;
                RegCloseKey(K);
              end;
            end;
          utRegDeleteKeyIfEmpty: begin
              CrackRegExtraData(CurRec^.ExtraData, RegView, RootKey);
              Subkey := CurRecDataPChar[0];
              LogFmt('Deleting empty registry key: %s\%s', [GetRegRootKeyName(RootKey), Subkey]);
              RegistryErrorCode := RegDeleteKeyIfEmpty(RegView, RootKey, Subkey);
              if RegistryErrorCode = ERROR_DIR_NOT_EMPTY then
                Log('Deletion skipped (not empty).')
              else if not (RegistryErrorCode in [ERROR_SUCCESS, ERROR_FILE_NOT_FOUND]) then begin
                LogFmt('Deletion failed (%d).', [RegistryErrorCode]);
                Result := False;
              end;
            end;
          utRegDeleteValue: begin
              CrackRegExtraData(CurRec^.ExtraData, RegView, RootKey);
              Subkey := CurRecDataPChar[0];
              ValueName := CurRecDataPChar[1];
              LogFmt('Deleting registry value: %s\%s\%s', [GetRegRootKeyName(RootKey), Subkey, ValueName]);
              if RegOpenKeyExView(RegView, RootKey, Subkey, 0, KEY_QUERY_VALUE or KEY_SET_VALUE, K) = ERROR_SUCCESS then begin
                if RegValueExists(K, ValueName) then begin
                  RegistryErrorCode := RegDeleteValueW(K, ValueName);
                  if RegistryErrorCode <> ERROR_SUCCESS then begin
                    LogFmt('RegDeleteValue failed (%d).', [RegistryErrorCode]);
                    Result := False;
                  end;
                end;
                RegCloseKey(K);
              end;
            end;
          utDecrementSharedCount: begin
              { utDeleteFile and utDecrementSharedCount are different: utDeleteFile's
                CurRecData[0] is current-process-bit compared to utDeleteFile_Is64Bit,
                but utDecrementSharedCount's is not, because there was and is no
                utDecrementSharedCount_Is64Bit. Instead, ApplyRedirForRegistrationOperation
                was used when utDecrementSharedCount was added, see Setup.Install.
                This means CurRecData[0] is a 64-bit path if utDecrementSharedCount_64BitKey
                is set, and 32-bit otherwise. We use this to convert it into back
                a current-process-bit path. }
              Is64Bit := CurRec^.ExtraData and utDecrementSharedCount_64BitKey <> 0;
              Filename := ApplyPathRedirRules(Is64Bit, CurRecData[0], tpCurrent);
              DecrementSharedCount(Is64Bit, Filename);
            end;
          utRefreshFileAssoc:
            RefreshFileAssoc := True;
          utMutexCheck: ;    { do nothing; utMutexChecks aren't processed here }
        else
          raise Exception.Create(FmtSetupMessage1(msgUninstallUnknownEntry,
            Format('$%x', [CurRec^.Typ])));
        end;
      except
        Result := False;
        if not(ExceptObject is EAbort) then
          HandleException;
      end;
      CurRec := Delete(CurRec);
      StatusUpdate(StartCount, FCount);
    end;

    if RefreshFileAssoc then
      SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
    if ufChangesEnvironment in Flags then
      RefreshEnvironment;
    if Assigned(DeleteUninstallDataFilesProc) then begin
      DeleteUninstallDataFilesProc;
      { Now that uninstall data is deleted, try removing the directories it
        was in that couldn't be deleted before. }
      LoggedProcessDirsNotRemoved;
    end;
  finally
    DeleteDirData.DirsNotRemoved.Free;
    RestartDeleteDirList.Free;
    for P := 0 to ChangeNotifyList.Count-1 do
      if DirExists(ChangeNotifyList[P]) then
        ShellChangeNotifyPath(SHCNE_UPDATEDIR, ChangeNotifyList[P], True);
    UnregisteredServersList.Free;
    RunOnceList.Free;
    ChangeNotifyList.Free;
  end;
  Log('Uninstallation process succeeded.');
end;

function TUninstallActionLog.ShouldRemoveSharedFile(const Filename: String): Boolean;
begin
  Result := True;
end;

procedure TUninstallActionLog.StatusUpdate(StartingCount, CurCount: Integer);
begin
end;

end.
