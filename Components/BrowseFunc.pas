unit BrowseFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Functions for browsing for folders/files
}

interface

uses
  Windows, Classes, Forms;

function BrowseForFolder(const Prompt: String; var Directory: String;
  const ParentWnd: HWND): Boolean;
function NewGetOpenFileName(const Prompt: String; var FileName: String;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND): Boolean;
function NewGetOpenFileNameMulti(const Prompt: String; const FileNameList: TStrings;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND): Boolean;
function NewGetSaveFileName(const Prompt: String; var FileName: String;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND): Boolean;

implementation

uses
  CommDlg, ShlObj, ActiveX,
  SysUtils, {$IFDEF FPC}Controls,{$ELSE}Themes,{$ENDIF}
  PathFunc;

{$IFDEF FPC}
function SHCreateItemFromParsingName(const Path: PWideChar; const BindContext: IBindCtx;
  constref IID: TGUID; out Item): HRESULT; stdcall; external 'shell32.dll';

function BrowseOpenFileNameW(var OpenFile: TOpenFilenameW): BOOL; stdcall;
  external 'comdlg32.dll' name 'GetOpenFileNameW';
function BrowseSaveFileNameW(var OpenFile: TOpenFilenameW): BOOL; stdcall;
  external 'comdlg32.dll' name 'GetSaveFileNameW';
{$ENDIF}

function BrowseForFolder(const Prompt: String; var Directory: String;
  const ParentWnd: HWND): Boolean;

  function RemoveSinglePeriod(const S: String): String;
  var
    FirstPeriodPos, LastPeriodPos: Integer;
  begin
    Result := S;
    FirstPeriodPos := Pos('.', S);
    if FirstPeriodPos <> 0 then begin
      LastPeriodPos := LastDelimiter('.', S);
      if (FirstPeriodPos = LastPeriodPos) and (LastPeriodPos = Length(S)) then
        Delete(Result, LastPeriodPos, 1);
    end;
  end;

var
  InitialDir: String;
  Options: DWORD;
  ActiveWindow: HWND;
  WindowList: {$IFDEF FPC}TList{$ELSE}Pointer{$ENDIF};
  ResultPath: PWideChar;
  FileDialog: IFileDialog;
  ShellItem: IShellItem;
begin
  Result := False;
  InitialDir := RemoveBackslashUnlessRoot(Directory);  { Win95 doesn't allow trailing backslash }

  if Failed(CoInitialize(nil)) then
    Exit;
  ActiveWindow := GetActiveWindow;
  WindowList := {$IFDEF FPC}Screen.DisableForms(GetParentForm(FindControl(ParentWnd))){$ELSE}DisableTaskWindows(ParentWnd){$ENDIF};
  {$IFNDEF FPC}
  const SaveHooks = TStyleManager.SystemHooks;
  TStyleManager.SystemHooks := []; { See below }
  {$ENDIF}
  try
    if Failed(CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER, {$IFDEF FPC}IFileDialog{$ELSE}IID_IFileDialog{$ENDIF}, FileDialog)) or
       Failed(FileDialog.GetOptions({$IFDEF FPC}@{$ENDIF}Options)) then { On Windows 11 this returned FOS_NOCHANGEDIR or FOS_PATHMUSTEXIST or FOS_FILEMUSTEXIST }
      Exit;

    Options := Options or FOS_PICKFOLDERS or FOS_FORCEFILESYSTEM;
    if Failed(FileDialog.SetOptions(Options)) then
      Exit;

    if Prompt <> '' then
      FileDialog.SetTitle(PChar(RemoveSinglePeriod(Prompt)));

    if (InitialDir <> '') and Succeeded(SHCreateItemFromParsingName(PChar(InitialDir), nil, {$IFDEF FPC}IShellItem{$ELSE}IID_IShellItem{$ENDIF}, ShellItem)) then
      FileDialog.SetFolder(ShellItem);

    if Failed(FileDialog.Show(ParentWnd)) or
       Failed(FileDialog.GetResult({$IFDEF FPC}@{$ENDIF}ShellItem)) or
       Failed(ShellItem.GetDisplayName(SIGDN_FILESYSPATH, {$IFDEF FPC}PWideChar(@ResultPath){$ELSE}ResultPath{$ENDIF})) then
      Exit;

    try
      Directory := ResultPath;
    finally
      CoTaskMemFree(ResultPath);
    end;
  finally
    {$IFDEF FPC}
    Screen.EnableForms(WindowList);
    {$ELSE}
    TStyleManager.SystemHooks := SaveHooks;
    EnableTaskWindows(WindowList);
    {$ENDIF}
    SetActiveWindow(ActiveWindow);
    ShellItem := nil;
    FileDialog := nil;
    CoUninitialize;
  end;
  Result := True;
end;

type
  TGetOpenOrSaveFileNameFunc = function(var OpenFile: TOpenFilenameW): Bool; stdcall;

function NewGetOpenOrSaveFileName(const Prompt: String; var FileName: String;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND; const GetOpenOrSaveFileNameFunc: TGetOpenOrSaveFileNameFunc;
  const FunctionName: String; const Flags: DWORD): Boolean;

  function AllocFilterStr(const S: string): string;
  var
    P: PChar;
  begin
    Result := '';
    if S <> '' then
    begin
      Result := S + #0;  // double null terminators
      P := PathStrScan(PChar(Result), '|');
      while P <> nil do
      begin
        P^ := #0;
        Inc(P);
        P := PathStrScan(P, '|');
      end;
    end;
  end;

  function GetMultiSelectString(const P: PChar): String;
  var
    E: PChar;
  begin
    E := P;
    while E^ <> #0 do
      Inc(E, StrLen(E) + 1);
    SetString(Result, P, E - P);
  end;

  function ShowDialog(var ofn: TOpenFileNameW; out ExtendedError: DWORD): Boolean;
  begin
    Result := GetOpenOrSaveFileNameFunc(ofn);
    if Result then
      ExtendedError := 0
    else
      ExtendedError := CommDlgExtendedError; { 0 if the user cancelled }
  end;

var
  ofn: TOpenFileNameW;
  FileBuffer: array of WideChar;
  MultiSelect: Boolean;
  MaxFile, ExtendedError: DWORD;
  {$IFDEF CPUX86}FPUControlWord: Word;{$ENDIF}
  TempFilter: String;
  SaveCurDir: String;
  ActiveWindow: HWND;
  WindowList: {$IFDEF FPC}TList{$ELSE}Pointer{$ENDIF};
begin
  MultiSelect := Flags and OFN_ALLOWMULTISELECT <> 0;
  if MultiSelect then
    MaxFile := High(Word) - 16 { Same as TOpenDialog }
  else
    MaxFile := 8192;
  SetLength(FileBuffer, MaxFile); { Zero-filled, which GetMultiSelectString needs after a single selection }
  StrPLCopy(@FileBuffer[0], FileName, MaxFile - 1);

  FillChar(ofn, SizeOf(ofn), 0);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := ParentWnd;
  TempFilter := AllocFilterStr(Filter);
  ofn.lpstrFilter := PChar(TempFilter);
  ofn.lpstrFile := @FileBuffer[0];
  ofn.nMaxFile := MaxFile;
  ofn.lpstrInitialDir := PChar(InitialDirectory);
  ofn.lpstrTitle := PChar(Prompt);
  ofn.Flags := Flags or OFN_NOCHANGEDIR;
  ofn.lpstrDefExt := Pointer(DefaultExtension);

  ActiveWindow := GetActiveWindow;
  WindowList := {$IFDEF FPC}Screen.DisableForms(GetParentForm(FindControl(ParentWnd))){$ELSE}DisableTaskWindows(ParentWnd){$ENDIF};
  { Temporarily clear SystemHooks to make it support dark mode if Windows is in dark mode.
    Taken from Vcl.Dialogs' TCustomFileDialog.Execute. }
  {$IFNDEF FPC}
  const SaveHooks = TStyleManager.SystemHooks;
  TStyleManager.SystemHooks := [];
  {$ENDIF}
  try
    {$IFDEF CPUX86}
    asm
      // Avoid FPU control word change in NETRAP.dll, NETAPI32.dll, etc
      FNSTCW  FPUControlWord
    end;
    {$ENDIF}
    try
      SaveCurDir := GetCurrentDir;
      Result := ShowDialog(ofn, ExtendedError);
      if (ExtendedError = FNERR_INVALIDFILENAME) and (ofn.lpstrFile^ <> #0) then begin
        { Windows rejects an invalid initial file name without showing the dialog }
        FillChar(FileBuffer[0], MaxFile * SizeOf(Char), 0); { See above, full fill for GetMultiSelectString }
        Result := ShowDialog(ofn, ExtendedError);
      end;
      if Result then begin
        if MultiSelect then
          FileName := GetMultiSelectString(ofn.lpstrFile)
        else
          FileName := ofn.lpstrFile;
      end;
      { Restore current directory. The OFN_NOCHANGEDIR flag we pass is
        supposed to do that, but the MSDN docs claim: "This flag is
        ineffective for GetOpenFileName." I see no such problem on
        Windows 2000 or XP, but to be safe... }
      SetCurrentDir(SaveCurDir);
      if ExtendedError <> 0 then
        raise Exception.CreateFmt('%s failed with error code 0x%x',
          [FunctionName, ExtendedError]);
    finally
      {$IFDEF CPUX86}
      asm
        FNCLEX
        FLDCW FPUControlWord
      end;
      {$ENDIF}
    end;
  finally
    {$IFDEF FPC}
    Screen.EnableForms(WindowList);
    {$ELSE}
    TStyleManager.SystemHooks := SaveHooks;
    EnableTaskWindows(WindowList);
    {$ENDIF}
    SetActiveWindow(ActiveWindow);
  end;
end;

function NewGetOpenFileName(const Prompt: String; var FileName: String;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND): Boolean;
begin
  Result := NewGetOpenOrSaveFileName(Prompt, FileName, InitialDirectory, Filter, DefaultExtension,
    ParentWnd, {$IFDEF FPC}BrowseOpenFileNameW{$ELSE}GetOpenFileNameW{$ENDIF}, 'GetOpenFileName', OFN_HIDEREADONLY or OFN_PATHMUSTEXIST or OFN_FILEMUSTEXIST);
end;

function NewGetOpenFileNameMulti(const Prompt: String; const FileNameList: TStrings;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND): Boolean;

  function ExtractStr(var P: PChar): String;
  var
    L: Integer;
  begin
    L := Integer(StrLen(P));
    SetString(Result, P, L);
    if L > 0 then
      Inc(P, L + 1);
  end;

var
  Files, Dir, FileName: String;
  P: PChar;
begin
  Result := NewGetOpenOrSaveFileName(Prompt, Files, InitialDirectory, Filter, DefaultExtension,
    ParentWnd, {$IFDEF FPC}BrowseOpenFileNameW{$ELSE}GetOpenFileNameW{$ENDIF}, 'GetOpenFileName', OFN_HIDEREADONLY or OFN_PATHMUSTEXIST or OFN_FILEMUSTEXIST or
    OFN_ALLOWMULTISELECT or OFN_EXPLORER);
  if Result then begin
    FileNameList.Clear;
    P := PChar(Files);
    Dir := ExtractStr(P);
    FileName := ExtractStr(P);
    if FileName = '' then begin
      { When only one file is selected, the list contains just a file name }
      FileNameList.Add({$IFDEF FPC}UTF8Encode(Dir){$ELSE}Dir{$ENDIF});
    end
    else begin
      repeat
        { The filenames can include paths if the user typed them in manually }
        FileNameList.Add({$IFDEF FPC}UTF8Encode(PathCombine(Dir, FileName)){$ELSE}PathCombine(Dir, FileName){$ENDIF});
        FileName := ExtractStr(P);
      until FileName = '';
    end;
  end;
end;

function NewGetSaveFileName(const Prompt: String; var FileName: String;
  const InitialDirectory, Filter, DefaultExtension: String;
  const ParentWnd: HWND): Boolean;
begin
  Result := NewGetOpenOrSaveFileName(Prompt, FileName, InitialDirectory, Filter, DefaultExtension,
    ParentWnd, {$IFDEF FPC}BrowseSaveFileNameW{$ELSE}GetSaveFileNameW{$ENDIF}, 'GetSaveFileName', OFN_OVERWRITEPROMPT or OFN_HIDEREADONLY or OFN_PATHMUSTEXIST);
end;

end.
