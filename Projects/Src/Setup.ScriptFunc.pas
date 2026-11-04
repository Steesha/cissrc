unit Setup.ScriptFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Script support functions (run time - used by Setup)
}

interface

uses
  uPSRuntime;

procedure ScriptFuncLibraryRegister_R(ScriptInterpreter: TPSExec);

implementation

uses
  Windows,
  Forms, {$IFDEF FPC}Controls,{$ENDIF} SysUtils, Classes, Graphics, ActiveX, Generics.Collections, Math,
  uPSUtils, PathFunc, ISSigFunc, BrowseFunc, MD5, SHA1, SHA256, BitmapButton, BitmapImage,
  PSStackHelper, UnsignedFunc,
  Shared.Struct, Setup.WizardForm.CustomPages, Setup.MainFunc, Shared.CommonFunc.Vcl,
  Shared.CommonFunc, Shared.FileClass, SetupLdrAndSetup.InstFunc,
  Setup.DownloadFileFunc, Setup.ExtractFileFunc, Setup.ISSigVerifyFunc, Setup.InstFunc, Setup.InstFunc.Ole,
  SetupLdrAndSetup.Messages, Shared.SetupMessageIDs, Setup.NewDiskForm,
  Setup.WizardForm, Shared.VerInfoFunc, Shared.SetupTypes,
  Setup.LoggingFunc, Setup.SetupForm, Setup.RegDLL,
  Setup.SpawnClient, Setup.DotNetFunc,
  Shared.DotNetVersion, Setup.MsiFunc, Compression.SevenZipDecoder, Compression.SevenZipDLLDecoder,
  Setup.DebugClient, Shared.ScriptFunc, Setup.ScriptFunc.HelperFunc, Setup.PathRedir;

type
  TScriptFunc = procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);

  TScriptFuncTyp = (sfNormal, sfNoUninstall, sfOnlyUninstall);

  TScriptFuncEx = record
    OrgName: AnsiString;
    ScriptFunc: TScriptFunc;
    Typ: TScriptFuncTyp;
    constructor Create(const AOrgName: AnsiString; const AScriptFunc: TScriptFunc; const ATyp: TScriptFuncTyp);
    procedure Run(const Caller: TPSExec; const Stack: TPSStack);
  end;

  TScriptFuncs = TDictionary<AnsiString, TScriptFuncEx>;

  { Internal, used only by Script.Test.iss }
  TTestPSStackHelperProc = function(Value: Integer): Integer of object;
  TTestHandlerExtendedProc = function(E1, E2, E3: Extended; Tail: Integer): Extended of object;
  TTestHandlerCurrencyProc = function(C1, C2, C3: Currency; Tail: Integer): Currency of object;
  TTestHandlerMixedProc = procedure(A: Integer; E: Extended; C: Currency; Tail: Integer) of object;
  TTestHandlerRecProc = function(R1: TTestHandlerRec4; R2: TTestHandlerRec6; R3: TTestHandlerRec8; Tail: Integer): Integer of object;
  TTestHandlerRecProc2 = function(R1: TTestHandlerRec3; R2: TTestHandlerRec10; Tail: Integer): Integer of object;
  TTestHandlerSetProc = function(S1: TTestHandlerSet4; S2: TTestHandlerSet6; S3: TTestHandlerSet8; Tail: Integer): Integer of object;
  TTestHandlerSetProc2 = function(S1: TTestHandlerSet3; S2: TTestHandlerSet10; Tail: Integer): Integer of object;
  TTestHandlerArrProc = function(A1: TTestHandlerArr4; A2: TTestHandlerArr6; A3: TTestHandlerArr8; Tail: Integer): Integer of object;
  TTestHandlerArrProc2 = function(A1: TTestHandlerArr3; A2: TTestHandlerArr10; Tail: Integer): Integer of object;
  TTestHandlerRecRet1Proc = function(A, B: Integer): TTestHandlerRec1 of object;
  TTestHandlerRecRet3Proc = function(A, B: Integer): TTestHandlerRec3 of object;
  TTestHandlerRecRet4Proc = function(A, B: Integer): TTestHandlerRec4 of object;
  TTestHandlerRecRet8Proc = function(A, B: Integer): TTestHandlerRec8 of object;
  TTestHandlerRecRetStringProc = function(A, B: Integer): TTestHandlerRecString of object;
  TTestHandlerArrRet3Proc = function(A, B: Integer): TTestHandlerArr3 of object;
  TTestHandlerArrRet4Proc = function(A, B: Integer): TTestHandlerArr4 of object;
  TTestHandlerArrRet8Proc = function(A, B: Integer): TTestHandlerArr8 of object;
  TTestHandlerArrRetStringProc = function(A, B: Integer): TTestHandlerArrString of object;

var
  ScriptFuncs: TScriptFuncs;

constructor TScriptFuncEx.Create(const AOrgName: AnsiString; const AScriptFunc: TScriptFunc; const ATyp: TScriptFuncTyp);
begin
  OrgName := AOrgName;
  ScriptFunc := AScriptFunc;
  Typ := ATyp;
end;

procedure TScriptFuncEx.Run(const Caller: TPSExec; const Stack: TPSStack);
begin
  if (Typ = sfNoUninstall) and IsUninstaller then
    NoUninstallFuncError(OrgName)
  else if (Typ = sfOnlyUninstall) and not IsUninstaller then
    OnlyUninstallFuncError(OrgName)
  else
    ScriptFunc(Caller, OrgName, Stack, Integer(Stack.Count-1));
end;

{ Called by ROPS }
function ScriptFuncPSProc(Caller: TPSExec; Proc: TPSExternalProcRec; Global, Stack: TPSStack): Boolean;
var
  ScriptFuncEx: TScriptFuncEx;
begin
  Result := ScriptFuncs.TryGetValue(Proc.Name, ScriptFuncEx);
  if Result then
    ScriptFuncEx.Run(Caller, Stack);
end;

procedure ScriptPageFromID(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetClass(PStart, GetWizardForm.PageFromID(Stack.GetInt(PStart-1)));
end;

procedure ScriptPageIndexFromID(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeInt(PStart, GetWizardForm.PageIndexFromID(Stack.GetInt(PStart-1)));
end;

procedure ScriptCreateCustomPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewPage: TWizardPage;
begin
  NewPage := TWizardPage.Create(GetWizardForm);
  try
    NewPage.Caption := Stack.GetString(PStart-2);
    NewPage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewPage, Stack.GetInt(PStart-1));
  except
    NewPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewPage);
end;

procedure ScriptCreateInputQueryPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewInputQueryPage: TInputQueryWizardPage;
begin
  NewInputQueryPage := TInputQueryWizardPage.Create(GetWizardForm);
  try
    NewInputQueryPage.Caption := Stack.GetString(PStart-2);
    NewInputQueryPage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewInputQueryPage, Stack.GetInt(PStart-1));
    NewInputQueryPage.Initialize(Stack.GetString(PStart-4));
  except
    NewInputQueryPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewInputQueryPage);
end;

procedure ScriptCreateInputOptionPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewInputOptionPage: TInputOptionWizardPage;
begin
  NewInputOptionPage := TInputOptionWizardPage.Create(GetWizardForm);
  try
    NewInputOptionPage.Caption := Stack.GetString(PStart-2);
    NewInputOptionPage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewInputOptionPage, Stack.GetInt(PStart-1));
    NewInputOptionPage.Initialize(Stack.GetString(PStart-4),
      Stack.GetBool(PStart-5), Stack.GetBool(PStart-6));
  except
    NewInputOptionPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewInputOptionPage);
end;

procedure ScriptCreateInputDirPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewInputDirPage: TInputDirWizardPage;
begin
  NewInputDirPage := TInputDirWizardPage.Create(GetWizardForm);
  try
    NewInputDirPage.Caption := Stack.GetString(PStart-2);
    NewInputDirPage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewInputDirPage, Stack.GetInt(PStart-1));
    NewInputDirPage.Initialize(Stack.GetString(PStart-4), Stack.GetBool(PStart-5),
       Stack.GetString(PStart-6));
  except
    NewInputDirPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewInputDirPage);
end;

procedure ScriptCreateInputFilePage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewInputFilePage: TInputFileWizardPage;
begin
  NewInputFilePage := TInputFileWizardPage.Create(GetWizardForm);
  try
    NewInputFilePage.Caption := Stack.GetString(PStart-2);
    NewInputFilePage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewInputFilePage, Stack.GetInt(PStart-1));
    NewInputFilePage.Initialize(Stack.GetString(PStart-4));
  except
    NewInputFilePage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewInputFilePage);
end;

procedure ScriptCreateOutputMsgPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewOutputMsgPage: TOutputMsgWizardPage;
begin
  NewOutputMsgPage := TOutputMsgWizardPage.Create(GetWizardForm);
  try
    NewOutputMsgPage.Caption := Stack.GetString(PStart-2);
    NewOutputMsgPage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewOutputMsgPage, Stack.GetInt(PStart-1));
    NewOutputMsgPage.Initialize(Stack.GetString(PStart-4));
  except
    NewOutputMsgPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewOutputMsgPage);
end;

procedure ScriptCreateOutputMsgMemoPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewOutputMsgMemoPage: TOutputMsgMemoWizardPage;
begin
  NewOutputMsgMemoPage := TOutputMsgMemoWizardPage.Create(GetWizardForm);
  try
    NewOutputMsgMemoPage.Caption := Stack.GetString(PStart-2);
    NewOutputMsgMemoPage.Description := Stack.GetString(PStart-3);
    GetWizardForm.AddPage(NewOutputMsgMemoPage, Stack.GetInt(PStart-1));
    NewOutputMsgMemoPage.Initialize(Stack.GetString(PStart-4),
       Stack.GetAnsiString(PStart-5));
  except
    NewOutputMsgMemoPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewOutputMsgMemoPage);
end;

procedure ScriptCreateOutputProgressPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewOutputProgressPage: TOutputProgressWizardPage;
begin
  NewOutputProgressPage := TOutputProgressWizardPage.Create(GetWizardForm);
  try
    NewOutputProgressPage.Caption := Stack.GetString(PStart-1);
    NewOutputProgressPage.Description := Stack.GetString(PStart-2);
    GetWizardForm.AddPage(NewOutputProgressPage, -1);
    NewOutputProgressPage.Initialize;
  except
    NewOutputProgressPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewOutputProgressPage);
end;

procedure ScriptCreateOutputMarqueeProgressPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewOutputMarqueeProgressPage: TOutputMarqueeProgressWizardPage;
begin
  NewOutputMarqueeProgressPage := TOutputMarqueeProgressWizardPage.Create(GetWizardForm);
  try
    NewOutputMarqueeProgressPage.Caption := Stack.GetString(PStart-1);
    NewOutputMarqueeProgressPage.Description := Stack.GetString(PStart-2);
    GetWizardForm.AddPage(NewOutputMarqueeProgressPage, -1);
    NewOutputMarqueeProgressPage.Initialize;
  except
    NewOutputMarqueeProgressPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewOutputMarqueeProgressPage);
end;

procedure ScriptCreateDownloadPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewDownloadPage: TDownloadWizardPage;
begin
  NewDownloadPage := TDownloadWizardPage.Create(GetWizardForm);
  try
    NewDownloadPage.Caption := Stack.GetString(PStart-1);
    NewDownloadPage.Description := Stack.GetString(PStart-2);
    GetWizardForm.AddPage(NewDownloadPage, -1);
    NewDownloadPage.Initialize;
    NewDownloadPage.OnDownloadProgress := TOnDownloadProgress(Stack.GetProc(PStart-3, Caller));
  except
    NewDownloadPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewDownloadPage);
end;

procedure ScriptCreateExtractionPage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewExtractionPage: TExtractionWizardPage;
begin
  NewExtractionPage := TExtractionWizardPage.Create(GetWizardForm);
  try
    NewExtractionPage.Caption := Stack.GetString(PStart-1);
    NewExtractionPage.Description := Stack.GetString(PStart-2);
    GetWizardForm.AddPage(NewExtractionPage, -1);
    NewExtractionPage.Initialize;
    NewExtractionPage.OnExtractionProgress := TOnExtractionProgress(Stack.GetProc(PStart-3, Caller));
  except
    NewExtractionPage.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewExtractionPage);
end;

procedure ScriptSCALEX(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  InitializeScaleBaseUnits;
  Stack.SetInt(PStart, TSetupForm.ScalePixelsX(OrigScaleBaseUnitX, ScaleBaseUnitX, Stack.GetInt(PStart-1)));
end;

procedure ScriptSCALEY(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  InitializeScaleBaseUnits;
  Stack.SetInt(PStart, TSetupForm.ScalePixelsY(OrigScaleBaseUnitY, ScaleBaseUnitY, Stack.GetInt(PStart-1)));
end;

procedure ScriptCREATECUSTOMFORM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  NewSetupForm: TSetupForm;
begin
  NewSetupForm := TSetupForm.CreateNew(nil);
  try
    NewSetupForm.PopupMode := pmAuto;
    NewSetupForm.AutoScroll := False;
    NewSetupForm.BorderStyle := {$IFDEF FPC}Controls.{$ENDIF}bsDialog;
    NewSetupForm.ClientWidth := Stack.GetInt(PStart-1);
    NewSetupForm.ClientHeight := Stack.GetInt(PStart-2);
    NewSetupForm.InitializeFont(Stack.GetBool(PStart-3), Stack.GetBool(PStart-4));
  except
    NewSetupForm.Free;
    raise;
  end;
  Stack.SetClass(PStart, NewSetupForm);
end;

procedure ScriptSELECTDISK(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-3);
  Stack.SetBool(PStart, SelectDisk(Stack.GetInt(PStart-1), Stack.GetString(PStart-2), S));
  Stack.SetString(PStart-3, S);
end;

procedure ScriptBROWSEFORFOLDER(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-2);
  Stack.SetBool(PStart, BrowseForFolder(Stack.GetString(PStart-1), S, GetOwnerWndForMessageBox));
  Stack.SetString(PStart-2, S);
end;

procedure ScriptGETOPENFILENAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-2);
  Stack.SetBool(PStart, NewGetOpenFileName(Stack.GetString(PStart-1), S, Stack.GetString(PStart-3), Stack.GetString(PStart-4), Stack.GetString(PStart-5), GetOwnerWndForMessageBox));
  Stack.SetString(PStart-2, S);
end;

procedure ScriptGETOPENFILENAMEMULTI(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, NewGetOpenFileNameMulti(Stack.GetString(PStart-1), TStrings(Stack.GetClass(PStart-2)), Stack.GetString(PStart-3), Stack.GetString(PStart-4), Stack.GetString(PStart-5), GetOwnerWndForMessageBox));
end;

procedure ScriptGETSAVEFILENAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-2);
  Stack.SetBool(PStart, NewGetSaveFileName(Stack.GetString(PStart-1), S, Stack.GetString(PStart-3), Stack.GetString(PStart-4), Stack.GetString(PStart-5), GetOwnerWndForMessageBox));
  Stack.SetString(PStart-2, S);
end;

procedure ScriptMINIMIZEPATHNAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, MinimizePathName(Stack.GetString(PStart-1), TFont(Stack.GetClass(PStart-2)), Stack.GetInt(PStart-3)));
end;

procedure ScriptFILEEXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, NewFileExists(Stack.GetString(PStart-1)));
end;

procedure ScriptDIREXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, DirExists(Stack.GetString(PStart-1)));
end;

procedure ScriptFILEORDIREXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, FileOrDirExists(Stack.GetString(PStart-1)));
end;

procedure ScriptGETINISTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetIniString(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetString(PStart-3), Stack.GetString(PStart-4)));
end;

procedure ScriptGETINIINT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, GetIniInt(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetInt(PStart-3), Stack.GetInt(PStart-4), Stack.GetInt(PStart-5), Stack.GetString(PStart-6)));
end;

procedure ScriptGETINIBOOL(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, GetIniBool(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetBool(PStart-3), Stack.GetString(PStart-4)));
end;

procedure ScriptINIKEYEXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IniKeyExists(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetString(PStart-3)));
end;

procedure ScriptISINISECTIONEMPTY(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsIniSectionEmpty(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptSETINISTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SetIniString(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetString(PStart-3), Stack.GetString(PStart-4)));
end;

procedure ScriptSETINIINT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SetIniInt(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetInt(PStart-3), Stack.GetString(PStart-4)));
end;

procedure ScriptSETINIBOOL(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SetIniBool(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetBool(PStart-3), Stack.GetString(PStart-4)));
end;

procedure ScriptDELETEINIENTRY(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  DeleteIniEntry(Stack.GetString(PStart), Stack.GetString(PStart-1), Stack.GetString(PStart-2));
end;

procedure ScriptDELETEINISECTION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  DeleteIniSection(Stack.GetString(PStart), Stack.GetString(PStart-1));
end;

procedure ScriptGETENV(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetEnv(Stack.GetString(PStart-1)));
end;

procedure ScriptGETCMDTAIL(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetCmdTail);
end;

procedure ScriptPARAMCOUNT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  if NewParamsForCode.Count = 0 then
    InternalError('NewParamsForCode not set');
  Stack.SetInt(PStart, NewParamsForCode.Count-1);
end;

procedure ScriptPARAMSTR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  I: Integer;
begin
  I := Stack.GetInt(PStart-1);
  if (I >= 0) and (I < NewParamsForCode.Count) then
    Stack.SetString(PStart, NewParamsForCode[I])
  else
    Stack.SetString(PStart, '');
end;

procedure ScriptADDQUOTES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, AddQuotes(Stack.GetString(PStart-1)));
end;

procedure ScriptREMOVEQUOTES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, RemoveQuotes(Stack.GetString(PStart-1)));
end;

procedure ScriptGETSHORTNAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetShortName(Stack.GetString(PStart-1)));
end;

procedure ScriptGETWINDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetWinDir);
end;

procedure ScriptGETSYSTEMDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetSystemDir);
end;

procedure ScriptGETSYSWOW64DIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetSysWow64Dir);
end;

procedure ScriptGETSYSNATIVEDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetSysNativeDir(IsWin64));
end;

procedure ScriptGETTEMPDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetTempDir);
end;

procedure ScriptSTRINGCHANGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-1);
  Stack.SetInt(PStart, StringChange(S, Stack.GetString(PStart-2), Stack.GetString(PStart-3)));
  Stack.SetString(PStart-1, S);
end;

procedure ScriptSTRINGCHANGEEX(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-1);
  Stack.SetInt(PStart, StringChangeEx(S, Stack.GetString(PStart-2), Stack.GetString(PStart-3), Stack.GetBool(PStart-4)));
  Stack.SetString(PStart-1, S);
end;

procedure ScriptUSINGWINNT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, True);
end;

procedure ScriptCOPYFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  ExistingFilename: String;
begin
  ExistingFilename := Stack.GetString(PStart-1);
  if not IsProtectedSrcExe(ExistingFilename) then
    Stack.SetBool(PStart, CopyFileW(PChar(ExistingFilename), PChar(Stack.GetString(PStart-2)), Stack.GetBool(PStart-3)))
  else
    Stack.SetBool(PStart, False);
end;

procedure ScriptCONVERTPERCENTSTR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
begin
  S := Stack.GetString(PStart-1);
  Stack.SetBool(PStart, ConvertPercentStr(S));
  Stack.SetString(PStart-1, S);
end;

procedure ScriptREGKEYEXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_QUERY_VALUE, K) = ERROR_SUCCESS then begin
    Stack.SetBool(PStart, True);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGVALUEEXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_QUERY_VALUE, K) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Stack.SetBool(PStart, RegValueExists(K, PChar(ValueName)));
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGDELETEKEYINCLUDINGSUBKEYS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  SubKey: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKey := Stack.GetString(PStart-2);
  Stack.SetBool(PStart, RegDeleteKeyIncludingSubkeys(RegView, RootKey, PChar(SubKey)) = ERROR_SUCCESS);
end;

procedure ScriptREGDELETEKEYIFEMPTY(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  SubKeyName: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  Stack.SetBool(PStart, RegDeleteKeyIfEmpty(RegView, RootKey, PChar(SubKeyName)) = ERROR_SUCCESS);
end;

procedure ScriptREGDELETEVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_SET_VALUE, K) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Stack.SetBool(PStart, RegDeleteValueW(K, PChar(ValueName)) = ERROR_SUCCESS);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGGETSUBKEYNAMES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  Stack.SetBool(PStart, GetSubkeyOrValueNames(RegView, RootKey,
    Stack.GetString(PStart-2), Stack, PStart-3, True));
end;

procedure ScriptREGGETVALUENAMES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  Stack.SetBool(PStart, GetSubkeyOrValueNames(RegView, RootKey,
    Stack.GetString(PStart-2), Stack, PStart-3, False));
end;

procedure ScriptREGQUERYSTRINGVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
  S: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_QUERY_VALUE, K) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    S := Stack.GetString(PStart-4);
    Stack.SetBool(PStart, RegQueryStringValue(K, PChar(ValueName), S));
    Stack.SetString(PStart-4, S);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGQUERYMULTISTRINGVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
  S: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_QUERY_VALUE, K) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    S := Stack.GetString(PStart-4);
    Stack.SetBool(PStart, RegQueryMultiStringValue(K, PChar(ValueName), S));
    Stack.SetString(PStart-4, S);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGQUERYDWORDVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  Typ: DWORD;
  Data: DWORD;
  Size: DWORD;
  SubKeyName: String;
  ValueName: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_QUERY_VALUE, K) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Size := SizeOf(Data);
    if (RegQueryValueExW(K, PChar(ValueName), nil, @Typ, PByte(@Data), @Size) = ERROR_SUCCESS) and (Typ = REG_DWORD) then begin
      Stack.SetInt(PStart-4, Integer(Data));
      Stack.SetBool(PStart, True);
    end else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGQUERYBINARYVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  Typ: DWORD;
  Size: DWORD;
  Data: AnsiString;
  SubKeyName: String;
  ValueName: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegOpenKeyExView(RegView, RootKey, PChar(SubKeyName), 0, KEY_QUERY_VALUE, K) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    if RegQueryValueExW(K, PChar(ValueName), nil, @Typ, nil, @Size) = ERROR_SUCCESS then begin
      SetLength(Data, Size);
      if RegQueryValueExW(K, PChar(ValueName), nil, @Typ, PByte(@Data[1]), @Size) = ERROR_SUCCESS then begin
        Stack.SetAnsiString(PStart-4, Data);
        Stack.SetBool(PStart, True);
      end else
        Stack.SetBool(PStart, False);
    end else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGWRITESTRINGVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  Typ: DWORD;
  ExistingTyp: DWORD;
  SubKeyName: String;
  ValueName: String;
  Data: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegCreateKeyExView(RegView, RootKey, PChar(SubKeyName), 0, nil, REG_OPTION_NON_VOLATILE, KEY_QUERY_VALUE or KEY_SET_VALUE, nil, K, nil) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Data := Stack.GetString(PStart-4);
    if (RegQueryValueExW(K, PChar(ValueName), nil, @ExistingTyp, nil, nil) = ERROR_SUCCESS) and (ExistingTyp = REG_EXPAND_SZ) then
      Typ := REG_EXPAND_SZ
    else
      Typ := REG_SZ;
    if RegSetValueExW(K, PChar(ValueName), 0, Typ, PChar(Data), (ULength(Data)+1)*SizeOf(Data[1])) = ERROR_SUCCESS then
      Stack.SetBool(PStart, True)
    else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGWRITEEXPANDSTRINGVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
  Data: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegCreateKeyExView(RegView, RootKey, PChar(SubKeyName), 0, nil, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nil, K, nil) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Data := Stack.GetString(PStart-4);
    if RegSetValueExW(K, PChar(ValueName), 0, REG_EXPAND_SZ, PByte(PWideChar(Data)), (ULength(Data)+1)*SizeOf(Data[1])) = ERROR_SUCCESS then
      Stack.SetBool(PStart, True)
    else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGWRITEMULTISTRINGVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
  Data: String;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegCreateKeyExView(RegView, RootKey, PChar(SubKeyName), 0, nil, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nil, K, nil) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Data := Stack.GetString(PStart-4);
    { Multi-string data requires two null terminators: one after the last
      string, and one to mark the end.
      Delphi's String type is implicitly null-terminated, so only one null
      needs to be added to the end. }
    if (Data <> '') and (Data[Length(Data)] <> #0) then
      Data := Data + #0;
    if RegSetValueExW(K, PChar(ValueName), 0, REG_MULTI_SZ, PByte(PWideChar(Data)), (ULength(Data)+1)*SizeOf(Data[1])) = ERROR_SUCCESS then
      Stack.SetBool(PStart, True)
    else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGWRITEDWORDVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
  Data: Cardinal;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegCreateKeyExView(RegView, RootKey, PChar(SubKeyName), 0, nil, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nil, K, nil) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Data := Stack.GetUInt(PStart-4);
    if RegSetValueExW(K, PChar(ValueName), 0, REG_DWORD, @Data, SizeOf(Data)) = ERROR_SUCCESS then
      Stack.SetBool(PStart, True)
    else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptREGWRITEBINARYVALUE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  RegView: TRegView;
  RootKey: HKEY;
  K: HKEY;
  SubKeyName: String;
  ValueName: String;
  Data: AnsiString;
begin
  CrackCodeRootKey(UInt32(Stack.GetNativeUInt(PStart-1)), RegView, RootKey);
  SubKeyName := Stack.GetString(PStart-2);
  if RegCreateKeyExView(RegView, RootKey, PChar(SubKeyName), 0, nil, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nil, K, nil) = ERROR_SUCCESS then begin
    ValueName := Stack.GetString(PStart-3);
    Data := Stack.GetAnsiString(PStart-4);
    if RegSetValueExW(K, PChar(ValueName), 0, REG_BINARY, @Data[1], ULength(Data)) = ERROR_SUCCESS then
      Stack.SetBool(PStart, True)
    else
      Stack.SetBool(PStart, False);
    RegCloseKey(K);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptISADMIN(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsAdmin);
end;

procedure ScriptISPOWERUSERLOGGEDON(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsPowerUserLoggedOn);
end;

procedure ScriptISADMININSTALLMODE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsAdminInstallMode);
end;

procedure ScriptFONTEXISTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, FontExists(Stack.GetString(PStart-1)));
end;

procedure ScriptGETUILANGUAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, GetUILanguage);
end;

procedure ScriptADDPERIOD(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, AddPeriod(Stack.GetString(PStart-1)));
end;

procedure ScriptSETNTFSCOMPRESSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SetNTFSCompression(Stack.GetString(PStart-1), Stack.GetBool(PStart-2)));
end;

procedure ScriptISWILDCARD(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsWildcard(Stack.GetString(PStart-1)));
end;

procedure ScriptWILDCARDMATCH(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: String;
  N: String;
begin
  S := Stack.GetString(PStart-1);
  N := Stack.GetString(PStart-2);
  Stack.SetBool(PStart, WildcardMatch(PChar(S), PChar(N)));
end;

procedure ScriptHighContrastActive(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, HighContrastActive);
end;

procedure ScriptAddBackslash(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, AddBackslash(Stack.GetString(PStart-1)));
end;

procedure ScriptRemoveBackslash(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, RemoveBackslash(Stack.GetString(PStart-1)));
end;

procedure ScriptRemoveBackslashUnlessRoot(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, RemoveBackslashUnlessRoot(Stack.GetString(PStart-1)));
end;

procedure ScriptPathCombine(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathCombine(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptPathHasInvalidCharacters(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PathHasInvalidCharacters(Stack.GetString(PStart-1), Stack.GetBool(PStart-2)));
end;

procedure ScriptPathIsRooted(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PathIsRooted(Stack.GetString(PStart-1)));
end;

procedure ScriptPathNormalizeSlashes(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathNormalizeSlashes(Stack.GetString(PStart-1)));
end;

procedure ScriptPathSame(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PathSame(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptPathStartsWith(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PathStartsWith(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetBool(PStart-3)));
end;

procedure ScriptPathEndsWith(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PathEndsWith(Stack.GetString(PStart-1), Stack.GetString(PStart-2), Stack.GetBool(PStart-3)));
end;

procedure ScriptPathConvertNormalToSuper(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathConvertNormalToSuper(Stack.GetString(PStart-1)));
end;

procedure ScriptPathConvertSuperToNormal(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathConvertSuperToNormal(Stack.GetString(PStart-1)));
end;

procedure ScriptCHARLENGTH(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, 1);
end;

procedure ScriptEXPANDFILENAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathExpand(Stack.GetString(PStart-1)));
end;

procedure ScriptEXTRACTFILEDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathExtractDir(Stack.GetString(PStart-1)));
end;

procedure ScriptEXTRACTFILEDRIVE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathExtractDrive(Stack.GetString(PStart-1)));
end;

procedure ScriptEXTRACTFILEEXT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathExtractExt(Stack.GetString(PStart-1)));
end;

procedure ScriptEXTRACTFILENAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathExtractName(Stack.GetString(PStart-1)));
end;

procedure ScriptEXTRACTFILEPATH(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathExtractPath(Stack.GetString(PStart-1)));
end;

procedure ScriptCHANGEFILEEXT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, PathChangeExt(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptExtractTemporaryFile(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  ExtractTemporaryFile(Stack.GetString(PStart));
end;

procedure ScriptExtractTemporaryFiles(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, ExtractTemporaryFiles(Stack.GetString(PStart-1)));
end;

procedure ScriptDownloadTemporaryFile(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Url: String;
  ISSigUrl: String;
  BaseName: String;
  RequiredSHA256OfFile: String;
  ISSigAllowedKeys: AnsiString;
  OnDownloadProgress: TOnDownloadProgress;
  ISSigVerify: Boolean;
  Verification: TSetupFileVerification;
  Throttler: TProgressThrottler;
begin
  ISSigVerify := OrgName = 'DownloadTemporaryFileWithISSigVerify';

  if ISSigVerify then begin
    Url := Stack.GetString(PStart-1);
    ISSigUrl := Stack.GetString(PStart-2);
    BaseName := Stack.GetString(PStart-3);
    ISSigAllowedKeys := ConvertAllowedKeysRuntimeIDsToISSigAllowedKeys(TStringList(Stack.GetClass(PStart-4)));
    OnDownloadProgress := TOnDownloadProgress(Stack.GetProc(PStart-5, Caller));
  end else begin
    Url := Stack.GetString(PStart-1);
    BaseName := Stack.GetString(PStart-2);
    RequiredSHA256OfFile := Stack.GetString(PStart-3);
    OnDownloadProgress := TOnDownloadProgress(Stack.GetProc(PStart-4, Caller));
  end;

  Verification := NoVerification;
  if RequiredSHA256OfFile <> '' then begin
    Verification.Typ := fvHash;
    Verification.Hash := SHA256DigestFromString(RequiredSHA256OfFile)
  end else if ISSigVerify then begin
    Verification.Typ := fvISSig;
    Verification.ISSigAllowedKeys := ISSigAllowedKeys
  end;

  Throttler := TProgressThrottler.Create(OnDownloadProgress);
  try
    { Also see Setup.WizardForm.CustomPages TDownloadWizardPage.AddExWithISSigVerify }
    if ISSigVerify then
      DownloadTemporaryFile(GetISSigUrl(Url, ISSigUrl), BaseName + ISSigExt, NoVerification, Throttler.OnDownloadProgress, nil);
    Throttler.Reset;
    Stack.SetInt64(PStart, DownloadTemporaryFile(Url, BaseName, Verification, Throttler.OnDownloadProgress, nil));
  finally
    Throttler.Free;
  end;
end;

procedure ScriptDownloadTemporaryFileSize(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt64(PStart, DownloadTemporaryFileSize(Stack.GetString(PStart-1)));
end;

procedure ScriptDownloadTemporaryFileDate(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, DownloadTemporaryFileDate(Stack.GetString(PStart-1)));
end;

procedure ScriptSetDownloadCredentials(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  SetDownloadTemporaryFileCredentials(Stack.GetString(PStart),Stack.GetString(PStart-1));
end;

procedure ScriptCHECKFORMUTEXES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, CheckForMutexes(Stack.GetString(PStart-1)));
end;

procedure ScriptDECREMENTSHAREDCOUNT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, DecrementSharedCount(Stack.GetBool(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptDELAYDELETEFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  DelayDeleteFile(Stack.GetString(PStart), Stack.GetInt(PStart-1), 250, 250);
end;

procedure ScriptDELTREE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, DelTree(Stack.GetString(PStart-1), Stack.GetBool(PStart-2), True, Stack.GetBool(PStart-3), Stack.GetBool(PStart-4), False, nil, nil, nil));
end;

procedure ScriptGENERATEUNIQUENAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GenerateUniqueName(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptGETCOMPUTERNAMESTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetComputerNameString);
end;

procedure ScriptGETMD5OFFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, MD5DigestToString(GetMD5OfFile(Stack.GetString(PStart-1))));
end;

procedure ScriptGETMD5OFSTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, MD5DigestToString(GetMD5OfAnsiString(Stack.GetAnsiString(PStart-1))));
end;

procedure ScriptGETMD5OFUNICODESTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, MD5DigestToString(GetMD5OfUnicodeString(Stack.GetString(PStart-1))));
end;

procedure ScriptGETSHA1OFFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA1DigestToString(GetSHA1OfFile(Stack.GetString(PStart-1))));
end;

procedure ScriptGETSHA1OFSTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA1DigestToString(GetSHA1OfAnsiString(Stack.GetAnsiString(PStart-1))));
end;

procedure ScriptGETSHA1OFUNICODESTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA1DigestToString(GetSHA1OfUnicodeString(Stack.GetString(PStart-1))));
end;

procedure ScriptGETSHA256OFFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA256DigestToString(GetSHA256OfFile(Stack.GetString(PStart-1))));
end;

procedure ScriptGETSHA256OFSTREAM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA256DigestToString(ISSigCalcStreamHash(TStream(Stack.GetClass(PStart-1)))));
end;

procedure ScriptGETSHA256OFSTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA256DigestToString(GetSHA256OfAnsiString(Stack.GetAnsiString(PStart-1))));
end;

procedure ScriptGETSHA256OFUNICODESTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA256DigestToString(GetSHA256OfUnicodeString(Stack.GetString(PStart-1))));
end;

procedure ScriptGETSPACEONDISK(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  FreeBytes: Int64;
  TotalBytes: Int64;
  MaxBytes: Integer;
begin
  if GetSpaceOnDisk(Stack.GetString(PStart-1), FreeBytes, TotalBytes) then begin
    if Stack.GetBool(PStart-2) then begin
      FreeBytes := FreeBytes div (1024*1024);
      TotalBytes := TotalBytes div (1024*1024);
    end;
    { Cap at 2 GB, as GetSpaceOnDisk doesn't use 64-bit integers }
    MaxBytes := High(Int32);
    if FreeBytes > MaxBytes then
      FreeBytes := MaxBytes;
    if TotalBytes > MaxBytes then
      TotalBytes := MaxBytes;
    Stack.SetUInt(PStart-3, Cardinal(FreeBytes));
    Stack.SetUInt(PStart-4, Cardinal(TotalBytes));
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptGETSPACEONDISK64(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  FreeBytes: Int64;
  TotalBytes: Int64;
begin
  if GetSpaceOnDisk(Stack.GetString(PStart-1), FreeBytes, TotalBytes) then begin
    Stack.SetInt64(PStart-2, FreeBytes);
    Stack.SetInt64(PStart-3, TotalBytes);
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptGETUSERNAMESTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetUserNameString);
end;

procedure ScriptINCREMENTSHAREDCOUNT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  IncrementSharedCount(Stack.GetBool(PStart), Stack.GetString(PStart-1),
    Stack.GetBool(PStart-2));
end;

procedure ScriptExec(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Method: TMethod;
  OutputReader: TCreateProcessOutputReader;
  ResultCode: DWORD;
  RunAsOriginalUser: Boolean;
  S: String;
  LogOutput: Boolean;
  CaptureOutput: Boolean;
  LogOrCaptureOutput: Boolean;
  WithNativeSysDir: Boolean;
  ExecWait: TExecWait;
  Filename: String;
  WindowDisabler: TWindowDisabler;
begin
  RunAsOriginalUser := OrgName = 'ExecAsOriginalUser';
  if IsUninstaller and RunAsOriginalUser then
    NoUninstallFuncError(OrgName);

  S := String(OrgName);
  LogOutput := Pos('LogOutput', S) <> 0;
  CaptureOutput := Pos('CaptureOutput', S) <> 0;
  LogOrCaptureOutput := LogOutput or CaptureOutput;
  WithNativeSysDir := Pos('WithNativeSysDir', S) <> 0;

 { Must stay alive until OutputReader is freed }
  OutputReader := nil;
  try
    if LogOutput then begin
      Method := Stack.GetProc(PStart-7, Caller);
      if Method.Code <> nil then
        OutputReader := TCreateProcessOutputReader.Create(ExecAndLogOutputLogCustom, NativeInt(@Method))
      else if GetLogActive then
        OutputReader := TCreateProcessOutputReader.Create(ExecAndLogOutputLog, 0);
    end else if CaptureOutput then
      OutputReader := TCreateProcessOutputReader.Create(ExecAndLogOutputLog, 0, omCapture);
    ExecWait := TExecWait(Stack.GetInt(PStart-5));
    if LogOrCaptureOutput and (ExecWait <> ewWaitUntilTerminated) then
      InternalError(Format('Must call "%s" function with Wait = ewWaitUntilTerminated', [OrgName]));

    Filename := Stack.GetString(PStart-1);
    if not IsProtectedSrcExe(Filename) then begin
      { Disable windows so the user can't utilize our UI during the InstExec
        call }
      WindowDisabler := TWindowDisabler.Create;
      try
        Stack.SetBool(PStart, InstExecEx(RunAsOriginalUser,
          IsWin64 and WithNativeSysDir, Filename, Stack.GetString(PStart-2),
          Stack.GetString(PStart-3), ExecWait,
          Stack.GetInt(PStart-4), LogOrCaptureOutput, ProcessMessagesProc, OutputReader, ResultCode));
      finally
        WindowDisabler.Free;
      end;
      Stack.SetInt(PStart-6, Integer(ResultCode));
      if CaptureOutput then begin
        { Set the three TExecOutput fields }
        Stack.SetArray(PStart-7, OutputReader.CaptureOutList, 0);
        Stack.SetArray(PStart-7, OutputReader.CaptureErrList, 1);
        Stack.SetInt(PStart-7, OutputReader.CaptureError.ToInteger, 2);
      end;
    end else begin
      Stack.SetBool(PStart, False);
      Stack.SetInt(PStart-6, ERROR_ACCESS_DENIED);
    end;
  finally
    OutputReader.Free;
  end;
end;

procedure ScriptShellExec(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  ErrorCode: DWORD;
  RunAsOriginalUser: Boolean;
  Filename: String;
  WindowDisabler: TWindowDisabler;
begin
  RunAsOriginalUser := OrgName = 'ShellExecAsOriginalUser';
  if IsUninstaller and RunAsOriginalUser then
    NoUninstallFuncError(OrgName);
  Filename := Stack.GetString(PStart-2);
  if not IsProtectedSrcExe(Filename) then begin
    { Disable windows so the user can't utilize our UI during the
      InstShellExec call }
    WindowDisabler := TWindowDisabler.Create;
    try
      Stack.SetBool(PStart, InstShellExecEx(RunAsOriginalUser,
        Stack.GetString(PStart-1), Filename, Stack.GetString(PStart-3),
        Stack.GetString(PStart-4), TExecWait(Stack.GetInt(PStart-6)),
        Stack.GetInt(PStart-5), ProcessMessagesProc, ErrorCode));
    finally
      WindowDisabler.Free;
    end;
    Stack.SetInt(PStart-7, Integer(ErrorCode));
  end else begin
    Stack.SetBool(PStart, False);
    Stack.SetInt(PStart-7, ERROR_ACCESS_DENIED);
  end;
end;

procedure ScriptISPROTECTEDSYSTEMFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsProtectedSystemFile(Stack.GetString(PStart-1)));
end;

procedure ScriptMAKEPENDINGFILERENAMEOPERATIONSCHECKSUM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SHA256DigestToString(MakePendingFileRenameOperationsChecksum));
end;

procedure ScriptMODIFYPIFFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, ModifyPifFile(Stack.GetString(PStart-1), Stack.GetBool(PStart-2)));
end;

procedure ScriptREGISTERSERVER(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  RegisterServer(False, Stack.GetBool(PStart), Stack.GetString(PStart-1));
end;

procedure ScriptUNREGISTERSERVER(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  try
    RegisterServer(True, Stack.GetBool(PStart-1), Stack.GetString(PStart-2));
    Stack.SetBool(PStart, True);
  except
    Stack.SetBool(PStart, False);
  end;
end;

procedure ScriptUNREGISTERFONT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  UnregisterFont(Stack.GetString(PStart), Stack.GetString(PStart-1), Stack.GetBool(PStart-2));
end;

procedure ScriptRESTARTREPLACE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  RestartReplace(Stack.GetString(PStart), Stack.GetString(PStart-1));
end;

procedure ScriptFORCEDIRECTORIES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, NewForceDirectories(Stack.GetString(PStart-1)));
end;

procedure ScriptCREATESHELLLINK(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, CreateShellLink(Stack.GetString(PStart-1),
    Stack.GetString(PStart-2), Stack.GetString(PStart-3),
    Stack.GetString(PStart-4), Stack.GetString(PStart-5),
    Stack.GetString(PStart-6), Stack.GetInt(PStart-7),
    Stack.GetInt(PStart-8), 0, '', nil, False, False));
end;

procedure ScriptREGISTERTYPELIBRARY(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Is64Bit: Boolean;
begin
  Is64Bit := Stack.GetBool(PStart);
  {$IFDEF WIN64}
  if not Is64Bit then
    InternalError('Cannot register 32-bit type libraries on this version of Setup');
  {$ELSE}
  if Is64Bit then
    InternalError('Cannot register 64-bit type libraries on this version of Setup');
  {$ENDIF}
  RegisterTypeLibrary(Stack.GetString(PStart-1));
end;

procedure ScriptUNREGISTERTYPELIBRARY(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Is64Bit: Boolean;
begin
  Is64Bit := Stack.GetBool(PStart-1);
  {$IFDEF WIN64}
  if not Is64Bit then
    InternalError('Cannot unregister 32-bit type libraries on this version of Setup');
  {$ELSE}
  if Is64Bit then
    InternalError('Cannot unregister 64-bit type libraries on this version of Setup');
  {$ENDIF}
  try
    UnregisterTypeLibrary(Stack.GetString(PStart-2));
    Stack.SetBool(PStart, True);
  except
    Stack.SetBool(PStart, False);
  end;
end;

procedure ScriptUNPINSHELLLINK(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, UnpinShellLink(Stack.GetString(PStart-1)));
end;

procedure ScriptACTIVELANGUAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, ExpandConst('{language}'));
end;

procedure ScriptEXPANDCONSTANT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, ExpandConst(Stack.GetString(PStart-1)));
end;

procedure ScriptEXPANDCONSTANTEX(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, ExpandConstEx(Stack.GetString(PStart-1), [Stack.GetString(PStart-2), Stack.GetString(PStart-3)]));
end;

procedure ScriptEXITSETUPMSGBOX(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, ExitSetupMsgBox);
end;

procedure ScriptGETSHELLFOLDERBYCSIDL(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetShellFolderByCSIDL(Stack.GetInt(PStart-1), Stack.GetBool(PStart-2)));
end;

procedure ScriptINSTALLONTHISVERSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  MinVersion: TSetupVersionData;
  OnlyBelowVersion: TSetupVersionData;
begin
  if not StrToSetupVersionData(Stack.GetString(PStart-1), MinVersion) then
    InternalError(Format('%s: Invalid MinVersion string', [OrgName]))
  else if not StrToSetupVersionData(Stack.GetString(PStart-2), OnlyBelowVersion) then
    InternalError(Format('%s: Invalid OnlyBelowVersion string', [OrgName]))
  else
    Stack.SetBool(PStart, (InstallOnThisVersion(MinVersion, OnlyBelowVersion) = irInstall));
end;

procedure ScriptGETWINDOWSVERSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetUInt(PStart, WindowsVersion);
end;

procedure ScriptGETWINDOWSVERSIONSTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, Format('%u.%.2u.%u', [WindowsVersion shr 24,
    (WindowsVersion shr 16) and $FF, WindowsVersion and $FFFF]));
end;

procedure ScriptMsgBox(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Suppressible: Boolean;
  Default: Integer;
begin
  if OrgName = 'MsgBox' then begin
    Suppressible := False;
    Default := 0;
  end else begin
    Suppressible := True;
    Default := Stack.GetInt(PStart-4);
  end;
  Stack.SetInt(PStart, LoggedMsgBox(Stack.GetString(PStart-1), '', TMsgBoxType(Stack.GetInt(PStart-2)), Cardinal(Stack.GetInt(PStart-3)), Suppressible, Default));
end;

procedure ScriptTaskDialogMsgBox(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Suppressible: Boolean;
  Default: Integer;
  ButtonLabels: TPSStackHelper.TArrayOfString;
begin
  if OrgName = 'TaskDialogMsgBox' then begin
    Suppressible := False;
    Default := 0;
  end else begin
    Suppressible := True;
    Default := Stack.GetInt(PStart-7);
  end;
  ButtonLabels := Stack.GetStringArray(PStart-5);
  Stack.SetInt(PStart, LoggedTaskDialogMsgBox('', Stack.GetString(PStart-1), Stack.GetString(PStart-2), '', TMsgBoxType(Stack.GetInt(PStart-3)), Cardinal(Stack.GetInt(PStart-4)), ButtonLabels, Stack.GetInt(PStart-6), Suppressible, Default));
end;

procedure ScriptISWIN64(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsWin64);
end;

procedure ScriptIS64BITINSTALLMODE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, Is64BitInstallMode);
end;

procedure ScriptIsWinDark(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsWinDark);
end;

procedure ScriptIsDarkInstallMode(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsDarkInstallMode);
end;

procedure ScriptPROCESSORARCHITECTURE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, Integer(ProcessorArchitecture));
end;

procedure ScriptIsArm32Compatible(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  ArchitectureIdentifier: String;
begin
  ArchitectureIdentifier := LowerCase(Copy(String(OrgName), 3, MaxInt));
  Stack.SetBool(PStart, EvalArchitectureIdentifier(ArchitectureIdentifier));
end;

procedure ScriptIsCurrentProcess64Bit(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsCurrentProcess64Bit);
end;

procedure ScriptCUSTOMMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, CustomMessage(Stack.GetString(PStart-1)));
end;

procedure ScriptRMSESSIONSTARTED(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, RmSessionStarted);
end;

procedure ScriptREGISTEREXTRACLOSEAPPLICATIONSRESOURCE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, CodeRegisterExtraCloseApplicationsResource(Stack.GetString(PStart-1)));
end;

procedure ScriptGETWIZARDFORM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetClass(PStart, GetWizardForm);
end;

procedure ScriptWizardIsComponentSelected(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  StringList: TStringList;
  Components: Boolean;
  S: String;
begin
  StringList := TStringList.Create;
  try
    Components := (OrgName = 'WizardIsComponentSelected') or (OrgName = 'IsComponentSelected');
    if Components then
      GetWizardForm.GetSelectedComponents(StringList, False, False)
    else
      GetWizardForm.GetSelectedTasks(StringList, False, False, False);
    S := Stack.GetString(PStart-1);
    StringChange(S, '/', '\');
    if Components then
      Stack.SetBool(PStart, ShouldProcessEntry(StringList, nil, S, '', '', ''))
    else
      Stack.SetBool(PStart, ShouldProcessEntry(nil, StringList, '', S, '', ''));
  finally
    StringList.Free;
  end;
end;

procedure ScriptSETUPMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, SetupMessages[TSetupMessageID(Stack.GetInt(PStart-1))]);
end;

procedure ScriptRANDOM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, Integer(TStrongRandom.GenerateUInt32Range(UInt32(Stack.GetInt(PStart-1)))));
end;

procedure ScriptFILESIZE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  F: TFile;
begin
  try
    F := TFile.Create(Stack.GetString(PStart-1), fdOpenExisting, faRead, fsReadWrite);
    try
      Stack.SetInt(PStart-2, Integer(F.CappedSize)); { Even though CappedSize returns Cardinal, it's capped at High(Int32) }
      Stack.SetBool(PStart, True);
    finally
      F.Free;
    end;
  except
    Stack.SetBool(PStart, False);
  end;
end;

procedure ScriptFILESIZE64(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  F: TFile;
begin
  try
    F := TFile.Create(Stack.GetString(PStart-1), fdOpenExisting, faRead, fsReadWrite);
    try
      Stack.SetInt64(PStart-2, F.Size);
      Stack.SetBool(PStart, True);
    finally
      F.Free;
    end;
  except
    Stack.SetBool(PStart, False);
  end;
end;

procedure ScriptSET8087CW(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Set8087CW(Word(Stack.GetInt(PStart)));
end;

procedure ScriptGET8087CW(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, Get8087CW);
end;

procedure ScriptUTF8ENCODE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetAnsiString(PStart, Utf8Encode(Stack.GetString(PStart-1)));
end;

procedure ScriptUTF8DECODE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, UTF8ToString(Stack.GetAnsiString(PStart-1)));
end;

procedure ScriptBEEP(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Beep;
end;

procedure ScriptTRIMLEFT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, TrimLeft(Stack.GetString(PStart-1)));
end;

procedure ScriptTRIMRIGHT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, TrimRight(Stack.GetString(PStart-1)));
end;

procedure ScriptGETCURRENTDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetCurrentDir);
end;

procedure ScriptSETCURRENTDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SetCurrentDir(Stack.GetString(PStart-1)));
end;

procedure ScriptEXPANDUNCFILENAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, ExpandUNCFileName(Stack.GetString(PStart-1)));
end;

procedure ScriptEXTRACTRELATIVEPATH(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, NewExtractRelativePath(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptFILESEARCH(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, NewFileSearch(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptRENAMEFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  OldName: String;
begin
  OldName := Stack.GetString(PStart-1);
  if not IsProtectedSrcExe(OldName) then
    Stack.SetBool(PStart, MoveFileW(PChar(OldName), PChar(Stack.GetString(PStart-2))))
  else
    Stack.SetBool(PStart, False);
end;

procedure ScriptDELETEFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, Windows.DeleteFileW(PChar(Stack.GetString(PStart-1))));
end;

procedure ScriptCREATEDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, CreateDirectoryW(PChar(Stack.GetString(PStart-1)), nil));
end;

procedure ScriptREMOVEDIR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, RemoveDirectoryW(PChar(Stack.GetString(PStart-1))));
end;

procedure ScriptCOMPARESTR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, CompareStr(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptCOMPARETEXT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, CompareText(Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptSAMESTR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, CompareStr(Stack.GetString(PStart-1), Stack.GetString(PStart-2)) = 0);
end;

procedure ScriptSAMETEXT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, CompareText(Stack.GetString(PStart-1), Stack.GetString(PStart-2)) = 0);
end;

procedure ScriptGETDATETIMESTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  OldDateSeparator: Char;
  OldTimeSeparator: Char;
  NewDateSeparator: Char;
  NewTimeSeparator: Char;
begin
  OldDateSeparator := FormatSettings.DateSeparator;
  OldTimeSeparator := FormatSettings.TimeSeparator;
  try
    NewDateSeparator := Stack.GetChar(PStart-2);
    NewTimeSeparator := Stack.GetChar(PStart-3);
    if NewDateSeparator <> #0 then
      FormatSettings.DateSeparator := NewDateSeparator;
    if NewTimeSeparator <> #0 then
      FormatSettings.TimeSeparator := NewTimeSeparator;
    Stack.SetString(PStart, FormatDateTime(Stack.GetString(PStart-1), Now));
  finally
    FormatSettings.TimeSeparator := OldTimeSeparator;
    FormatSettings.DateSeparator := OldDateSeparator;
  end;
end;

procedure ScriptSYSERRORMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, Win32ErrorString(Stack.GetUInt(PStart-1)));
end;

procedure ScriptGETVERSIONNUMBERS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  if GetVersionNumbers(Stack.GetString(PStart-1), VersionNumbers) then begin
    Stack.SetUInt(PStart-2, VersionNumbers.MS);
    Stack.SetUInt(PStart-3, VersionNumbers.LS);
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptGETVERSIONCOMPONENTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  if GetVersionNumbers(Stack.GetString(PStart-1), VersionNumbers) then begin
    Stack.SetUInt(PStart-2, VersionNumbers.MS shr 16);
    Stack.SetUInt(PStart-3, VersionNumbers.MS and $FFFF);
    Stack.SetUInt(PStart-4, VersionNumbers.LS shr 16);
    Stack.SetUInt(PStart-5, VersionNumbers.LS and $FFFF);
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptGETVERSIONNUMBERSSTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  if GetVersionNumbers(Stack.GetString(PStart-1), VersionNumbers) then begin
    Stack.SetString(PStart-2, Format('%u.%u.%u.%u', [VersionNumbers.MS shr 16,
      VersionNumbers.MS and $FFFF, VersionNumbers.LS shr 16, VersionNumbers.LS and $FFFF]));
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptGETPACKEDVERSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  if GetVersionNumbers(Stack.GetString(PStart-1), VersionNumbers) then begin
    Stack.SetInt64(PStart-2, VersionNumbersToInt64(VersionNumbers));
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptPACKVERSIONNUMBERS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionMS: Cardinal;
  VersionLS: Cardinal;
begin
  VersionMS := Stack.GetUInt(PStart-1);
  VersionLS := Stack.GetUInt(PStart-2);
  Stack.SetInt64(PStart, HighLowToInt64(VersionMS, VersionLS));
end;

procedure ScriptPACKVERSIONCOMPONENTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  VersionNumbers.MS := (Stack.GetUInt(PStart-1) shl 16) or (Stack.GetUInt(PStart-2) and $FFFF);
  VersionNumbers.LS := (Stack.GetUInt(PStart-3) shl 16) or (Stack.GetUInt(PStart-4) and $FFFF);
  Stack.SetInt64(PStart, VersionNumbersToInt64(VersionNumbers));
end;

procedure ScriptCOMPAREPACKEDVERSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, CompareUInt64(UInt64(Stack.GetInt64(PStart-1)), UInt64(Stack.GetInt64(PStart-2))));
end;

procedure ScriptSAMEPACKEDVERSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, Stack.GetInt64(PStart-1) = Stack.GetInt64(PStart-2));
end;

procedure ScriptUNPACKVERSIONNUMBERS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  VersionNumbers.MS := UInt32(UInt64(Stack.GetInt64(PStart)) shr 32);
  VersionNumbers.LS := UInt32(UInt64(Stack.GetInt64(PStart)) and $FFFFFFFF);
  Stack.SetUInt(PStart-1, VersionNumbers.MS);
  Stack.SetUInt(PStart-2, VersionNumbers.LS);
end;

procedure ScriptUNPACKVERSIONCOMPONENTS(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  VersionNumbers.MS := UInt32(UInt64(Stack.GetInt64(PStart)) shr 32);
  VersionNumbers.LS := UInt32(UInt64(Stack.GetInt64(PStart)) and $FFFFFFFF);
  Stack.SetUInt(PStart-1, VersionNumbers.MS shr 16);
  Stack.SetUInt(PStart-2, VersionNumbers.MS and $FFFF);
  Stack.SetUInt(PStart-3, VersionNumbers.LS shr 16);
  Stack.SetUInt(PStart-4, VersionNumbers.LS and $FFFF);
end;

procedure ScriptVERSIONTOSTR(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  VersionNumbers.MS := UInt32(UInt64(Stack.GetInt64(PStart-1)) shr 32);
  VersionNumbers.LS := UInt32(UInt64(Stack.GetInt64(PStart-1)) and $FFFFFFFF);
  Stack.SetString(PStart, Format('%u.%u.%u.%u', [VersionNumbers.MS shr 16,
    VersionNumbers.MS and $FFFF, VersionNumbers.LS shr 16, VersionNumbers.LS and $FFFF]));
end;

procedure ScriptSTRTOVERSION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  VersionNumbers: TFileVersionNumbers;
begin
  if StrToVersionNumbers(Stack.GetString(PStart-1), VersionNumbers) then begin
    Stack.SetInt64(PStart-2, VersionNumbersToInt64(VersionNumbers));
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptSLEEP(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Sleep(Stack.GetUInt(PStart));
end;

procedure ScriptFINDWINDOWBYCLASSNAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeUInt(PStart, FindWindowW(PChar(Stack.GetString(PStart-1)), nil));
end;

procedure ScriptFINDWINDOWBYWINDOWNAME(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeUInt(PStart, FindWindowW(nil, PChar(Stack.GetString(PStart-1))));
end;

procedure ScriptSENDMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeInt(PStart, SendMessage(Stack.GetNativeUInt(PStart-1), Stack.GetUInt(PStart-2), Stack.GetNativeUInt(PStart-3), Stack.GetNativeInt(PStart-4)));
end;

procedure ScriptPOSTMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PostMessage(Stack.GetNativeUInt(PStart-1), Stack.GetUInt(PStart-2), Stack.GetNativeUInt(PStart-3), Stack.GetNativeInt(PStart-4)));
end;

procedure ScriptSENDNOTIFYMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SendNotifyMessage(Stack.GetNativeUInt(PStart-1), Stack.GetUInt(PStart-2), Stack.GetNativeUInt(PStart-3), Stack.GetNativeInt(PStart-4)));
end;

procedure ScriptREGISTERWINDOWMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetUInt(PStart, RegisterWindowMessageW(PChar(Stack.GetString(PStart-1))));
end;

procedure ScriptSENDBROADCASTMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeInt(PStart, SendMessage(HWND_BROADCAST, Stack.GetUInt(PStart-1), Stack.GetNativeUInt(PStart-2), Stack.GetNativeInt(PStart-3)));
end;

procedure ScriptPOSTBROADCASTMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, PostMessage(HWND_BROADCAST, Stack.GetUInt(PStart-1), Stack.GetNativeUInt(PStart-2), Stack.GetNativeInt(PStart-3)));
end;

procedure ScriptSENDBROADCASTNOTIFYMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SendNotifyMessage(HWND_BROADCAST, Stack.GetUInt(PStart-1), Stack.GetNativeUInt(PStart-2), Stack.GetNativeInt(PStart-3)));
end;

procedure ScriptLOADDLL(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  DllHandle: HMODULE;
begin
  DllHandle := SafeLoadLibrary(Stack.GetString(PStart-1), SEM_NOOPENFILEERRORBOX);
  if DllHandle <> 0 then
    Stack.SetInt(PStart-2, 0)
  else
    Stack.SetInt(PStart-2, Integer(GetLastError));
  Stack.SetNativeUInt(PStart, DllHandle);
end;

procedure ScriptCALLDLLPROC(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
type
  TDllProc = function(const Param1, Param2: NativeInt): NativeInt; stdcall;
var
  DllProc: TDllProc;
begin
  DllProc := TDllProc(GetProcAddress(Stack.GetNativeUInt(PStart-1), PAnsiChar(Stack.GetAnsiString(PStart-2))));
  if Assigned(DllProc) then begin
    Stack.SetNativeInt(PStart-5, DllProc(Stack.GetNativeInt(PStart-3), Stack.GetNativeInt(PStart-4)));
    Stack.SetBool(PStart, True);
  end else
    Stack.SetBool(PStart, False);
end;

procedure ScriptFREEDLL(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, FreeLibrary(Stack.GetNativeUInt(PStart-1)));
end;

procedure ScriptCREATEMUTEX(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Windows.CreateMutexW(nil, False, PWideChar(Stack.GetString(PStart)));
end;

procedure ScriptOEMTOCHARBUFF(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: AnsiString;
begin
  S := Stack.GetAnsiString(PStart);
  UniqueString(S);
  OemToCharBuffA(PAnsiChar(S), PAnsiChar(S), ULength(S));
  Stack.SetAnsiString(PStart, S);
end;

procedure ScriptCHARTOOEMBUFF(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: AnsiString;
begin
  S := Stack.GetAnsiString(PStart);
  UniqueString(S);
  CharToOemBuffA(PAnsiChar(S), PAnsiChar(S), ULength(S));
  Stack.SetAnsiString(PStart, S);
end;

procedure ScriptCOFREEUNUSEDLIBRARIES(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  CoFreeUnusedLibraries;
end;

procedure ScriptLOG(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Log(Stack.GetString(PStart));
end;

procedure ScriptBRINGTOFRONTANDRESTORE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  { Must be in this order to work around VCL bug }
  Application.Restore;
  Application.BringToFront;
end;

procedure ScriptWizardDirValue(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, RemoveBackslashUnlessRoot(GetWizardForm.DirEdit.Text));
end;

procedure ScriptWizardGroupValue(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, RemoveBackslashUnlessRoot(GetWizardForm.GroupEdit.Text));
end;

procedure ScriptWizardNoIcons(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, GetWizardForm.NoIconsCheck.Checked);
end;

procedure ScriptWizardSetupType(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  TypeEntry: PSetupTypeEntry;
begin
  TypeEntry := GetWizardForm.GetSetupType;
  if TypeEntry <> nil then begin
    if Stack.GetBool(PStart-1) then
      Stack.SetString(PStart, ExpandConst(TypeEntry.Description))
    else
      Stack.SetString(PStart, TypeEntry.Name);
  end
  else
    Stack.SetString(PStart, '');
end;

procedure ScriptWizardSelectedComponents(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  StringList: TStringList;
begin
  StringList := TStringList.Create;
  try
    if OrgName = 'WizardSelectedComponents' then
      GetWizardForm.GetSelectedComponents(StringList, Stack.GetBool(PStart-1), False)
    else
      GetWizardForm.GetSelectedTasks(StringList, Stack.GetBool(PStart-1), False, False);
    Stack.SetString(PStart, StringsToCommaString(StringList));
  finally
    StringList.Free;
  end;
end;

procedure ScriptWizardSelectComponents(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  StringList: TStringList;
  S: String;
begin
  StringList := TStringList.Create;
  try
    S := Stack.GetString(PStart);
    StringChange(S, '/', '\');
    SetStringsFromCommaString(StringList, S);
    if OrgName = 'WizardSelectComponents' then
      GetWizardForm.SelectComponents(StringList)
    else
      GetWizardForm.SelectTasks(StringList);
  finally
    StringList.Free;
  end;
end;

procedure ScriptWizardSetBackImage(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Form: TSetupForm;
  WizardImages: TWizardImages;
  BackImages: TPSStackHelper.TArrayOfObject;
  BackImage: TObject;
begin
  WizardImages := TWizardImages.Create(False);
  try
    BackImages := Stack.GetClassArray(PStart);
    for BackImage in BackImages do
      WizardImages.Add(TGraphic(BackImage));
    if IsUninstaller then
      Form := GetUninstallProgressForm
    else
      Form := GetWizardForm;
    Form.SetBackImage(WizardImages, Stack.GetBool(PStart-1) , Stack.GetBool(PStart-2), Byte(Stack.GetInt(PStart-3)), True);
  finally
    WizardImages.Free;
  end;
end;

procedure ScriptWizardSilent(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, InstallMode <> imNormal);
end;

procedure ScriptISUNINSTALLER(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsUninstaller);
end;

procedure ScriptUninstallSilent(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, UninstallSilent);
end;

procedure ScriptCurrentFilename(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  if CheckOrInstallCurrentFilename <> '' then
    Stack.SetString(PStart, CheckOrInstallCurrentFilename)
  else
    InternalError(Format('An attempt was made to call the "%s" function from outside a "Check", "BeforeInstall" or "AfterInstall" event function belonging to a "[Files]" entry', [OrgName]));
end;

procedure ScriptCurrentSourceFilename(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  if CheckOrInstallCurrentSourceFilename <> '' then
    Stack.SetString(PStart, CheckOrInstallCurrentSourceFilename)
  else
    InternalError(Format('An attempt was made to call the "%s" function from outside a "Check", "BeforeInstall" or "AfterInstall" event function belonging to a "[Files]" entry with flag "external"', [OrgName]));
end;

procedure ScriptCASTSTRINGTOINTEGER(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeInt(PStart, NativeInt(PChar(Stack.GetString(PStart-1))));
end;

procedure ScriptCASTINTEGERTOSTRING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, String(PChar(Stack.GetNativeInt(PStart-1))));
end;

procedure ScriptABORT(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Abort;
end;

procedure ScriptGETEXCEPTIONMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetString(PStart, GetExceptionMessage(Caller));
end;

procedure ScriptRAISEEXCEPTION(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  raise Exception.Create(Stack.GetString(PStart));
end;

procedure ScriptSHOWEXCEPTIONMESSAGE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  ShowExceptionMsgText(AddPeriod(GetExceptionMessage(Caller)));
end;

procedure ScriptTERMINATED(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, Application.Terminated);
end;

procedure ScriptGETPREVIOUSDATA(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  if IsUninstaller then
    Stack.SetString(PStart, GetCodePreviousData(UninstallExpandedAppId, Stack.GetString(PStart-1), Stack.GetString(PStart-2)))
  else
    Stack.SetString(PStart, GetCodePreviousData(ExpandConst(SetupHeader.AppId), Stack.GetString(PStart-1), Stack.GetString(PStart-2)));
end;

procedure ScriptSETPREVIOUSDATA(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SetCodePreviousData(HKEY(UInt32(Stack.GetInt(PStart-1))), Stack.GetString(PStart-2), Stack.GetString(PStart-3)));
end;

procedure ScriptLOADSTRINGFROMFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: AnsiString;
begin
  S := Stack.GetAnsiString(PStart-2);
  Stack.SetBool(PStart, LoadStringFromFile(Stack.GetString(PStart-1), S, fsRead));
  Stack.SetAnsiString(PStart-2, S);
end;

procedure ScriptLOADSTRINGFROMLOCKEDFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  S: AnsiString;
begin
  S := Stack.GetAnsiString(PStart-2);
  Stack.SetBool(PStart, LoadStringFromFile(Stack.GetString(PStart-1), S, fsReadWrite));
  Stack.SetAnsiString(PStart-2, S);
end;

procedure ScriptLOADSTRINGSFROMFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, LoadStringsFromFile(Stack.GetString(PStart-1), Stack, PStart-2, fsRead));
end;

procedure ScriptLOADSTRINGSFROMLOCKEDFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, LoadStringsFromFile(Stack.GetString(PStart-1), Stack, PStart-2, fsReadWrite));
end;

procedure ScriptSAVESTRINGTOFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SaveStringToFile(Stack.GetString(PStart-1), Stack.GetAnsiString(PStart-2), Stack.GetBool(PStart-3)));
end;

procedure ScriptSAVESTRINGSTOFILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SaveStringsToFile(Stack.GetString(PStart-1), Stack, PStart-2, Stack.GetBool(PStart-3), False, False));
end;

procedure ScriptSAVESTRINGSTOUTF8FILE(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SaveStringsToFile(Stack.GetString(PStart-1), Stack, PStart-2, Stack.GetBool(PStart-3), True, False));
end;

procedure ScriptSAVESTRINGSTOUTF8FILEWITHOUTBOM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, SaveStringsToFile(Stack.GetString(PStart-1), Stack, PStart-2, Stack.GetBool(PStart-3), True, True));
end;

procedure ScriptGETUNINSTALLPROGRESSFORM(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetClass(PStart, GetUninstallProgressForm);
end;

procedure ScriptCREATECALLBACK(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetNativeInt(PStart, CreateCallback(Caller, PPSVariantProcPtr(Stack.Items[PStart-1])));
end;

procedure ScriptISDOTNETINSTALLED(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, IsDotNetInstalled(InstallDefaultRegView, TDotNetVersion(Stack.GetInt(PStart-1)), Stack.GetUInt(PStart-2)));
end;

procedure ScriptISMSIPRODUCTINSTALLED(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  ErrorCode: Cardinal;
begin
  Stack.SetBool(PStart, IsMsiProductInstalled(Stack.GetString(PStart-1), Stack.GetInt64(PStart-2), ErrorCode));
  if ErrorCode <> 0 then
    raise Exception.Create(Win32ErrorString(ErrorCode));
end;

procedure ScriptINITIALIZEBITMAPBUTTONFROMICON(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  AscendingTrySizes: TPSStackHelper.TArrayOfInteger;
begin
  AscendingTrySizes := Stack.GetIntArray(PStart-4);
  Stack.SetBool(PStart, TBitmapButton(Stack.GetClass(PStart-1)).InitializeFromIcon(0, PChar(Stack.GetString(PStart-2)), Stack.GetInt(PStart-3), AscendingTrySizes));
end;

procedure ScriptINITIALIZEBITMAPIMAGEFROMICON(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  AscendingTrySizes: TPSStackHelper.TArrayOfInteger;
begin
  AscendingTrySizes := Stack.GetIntArray(PStart-4);
  Stack.SetBool(PStart, TBitmapImage(Stack.GetClass(PStart-1)).InitializeFromIcon(0, PChar(Stack.GetString(PStart-2)), Stack.GetInt(PStart-3), AscendingTrySizes));
end;

procedure ScriptInitializeBitmapButtonFromStockIcon(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  AscendingTrySizes: TPSStackHelper.TArrayOfInteger;
begin
  AscendingTrySizes := Stack.GetIntArray(PStart-4);
  Stack.SetBool(PStart, TBitmapButton(Stack.GetClass(PStart-1)).InitializeFromStockIcon(Stack.GetInt(PStart-2), Stack.GetInt(PStart-3), AscendingTrySizes));
end;

procedure ScriptInitializeBitmapImageFromStockIcon(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  AscendingTrySizes: TPSStackHelper.TArrayOfInteger;
begin
  AscendingTrySizes := Stack.GetIntArray(PStart-4);
  Stack.SetBool(PStart, TBitmapImage(Stack.GetClass(PStart-1)).InitializeFromStockIcon(Stack.GetInt(PStart-2), Stack.GetInt(PStart-3), AscendingTrySizes));
end;

procedure ScriptExtract7ZipArchive(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Password: String;
  FullDirsItemNo: Longint;
  Throttler: TProgressThrottler;
begin
  if OrgName = 'Extract7ZipArchive' then begin
    Password := '';
    FullDirsItemNo := PStart-2;
  end else begin
    Password := Stack.GetString(PStart-2);
    FullDirsItemNo := PStart-3;
  end;

  Throttler := TProgressThrottler.Create(TOnExtractionProgress(Stack.GetProc(FullDirsItemNo-1, Caller)));
  try
    try
      if SetupHeader.SevenZipLibraryName <> '' then
        ExtractArchive(Stack.GetString(PStart), Stack.GetString(PStart-1),
          Password, Stack.GetBool(FullDirsItemNo), Throttler.OnExtractionProgress)
      else
        Extract7ZipArchive(Stack.GetString(PStart), Stack.GetString(PStart-1),
          Password, Stack.GetBool(FullDirsItemNo), Throttler.OnExtractionProgress);
    except
      on E: EAbort do
        raise Exception.Create(SetupMessages[msgErrorExtractionAborted])
      else
        raise Exception.Create(FmtSetupMessage1(msgErrorExtractionFailed, GetExceptMessage));
    end;
  finally
    Throttler.Free;
  end;
end;

procedure ScriptMapArchiveExtensions(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  if SetupHeader.SevenZipLibraryName <> '' then
    MapArchiveExtensions(Stack.GetString(PStart), Stack.GetString(PStart-1));
end;

procedure ScriptDEBUGGING(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetBool(PStart, Debugging);
end;

procedure ScriptStringJoin(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Values: TPSStackHelper.TArrayOfString;
  Separator, Joined: String;
  I: Integer;
begin
  Values := Stack.GetStringArray(PStart-2);
  Separator := Stack.GetString(PStart-1);
  Joined := '';
  for I := 0 to High(Values) do begin
    if I > 0 then
      Joined := Joined + Separator;
    Joined := Joined + Values[I];
  end;
  Stack.SetString(PStart, Joined);
end;

{$IFDEF FPC}
function SplitScriptString(const S: String; const Separators: array of String;
  const Quote: Char; const Options: TStringSplitOptions): TArray<String>;
var
  Start, Position, Count, SeparatorLength: Integer;
  Separator: String;
  Quoted: Boolean;

  procedure AddPart(const Last: Boolean);
  var
    Part: String;
  begin
    Part := Copy(S, Start, Position - Start);
    if (Part = '') and ((Options = TStringSplitOptions.ExcludeEmpty) or
       (Last and (Options = TStringSplitOptions.ExcludeLastEmpty))) then
      Exit;
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 8);
    Result[Count] := Part;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  Start := 1;
  Position := 1;
  Quoted := False;
  while Position <= Length(S) do begin
    SeparatorLength := 0;
    if (Quote <> #0) and (S[Position] = Quote) then
      Quoted := not Quoted
    else if not Quoted then begin
      for Separator in Separators do
        if (Separator <> '') and (Copy(S, Position, Length(Separator)) = Separator) then begin
          SeparatorLength := Length(Separator);
          Break;
        end;
    end;
    if SeparatorLength > 0 then begin
      AddPart(False);
      Inc(Position, SeparatorLength);
      Start := Position;
    end else
      Inc(Position);
  end;
  AddPart(True);
  SetLength(Result, Count);
end;
{$ENDIF}

procedure ScriptStringSplit(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Parts: TArray<String>;
  Separators: TPSStackHelper.TArrayOfString;
  Quote: Char;
begin
  Separators := Stack.GetStringArray(PStart-2);
  if OrgName = 'StringSplitEx' then begin
    Quote := Stack.GetChar(PStart-3);
    {$IFDEF FPC}
    Parts := SplitScriptString(Stack.GetString(PStart-1), Separators, Quote, TStringSplitOptions(Stack.GetInt(PStart-4)))
    {$ELSE}
    Parts := Stack.GetString(PStart-1).Split(Separators, Quote, Quote, TStringSplitOptions(Stack.GetInt(PStart-4)))
    {$ENDIF}
  end else
    {$IFDEF FPC}
    Parts := SplitScriptString(Stack.GetString(PStart-1), Separators, #0, TStringSplitOptions(Stack.GetInt(PStart-3)));
    {$ELSE}
    Parts := Stack.GetString(PStart-1).Split(Separators, TStringSplitOptions(Stack.GetInt(PStart-3)));
    {$ENDIF}
  Stack.SetArray(PStart, Parts);
end;

procedure ScriptISSigVerify(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  ExpectedFileHash: TSHA256Digest;
  ISSigAllowedKeys: AnsiString;
  Filename: String;
  VerifyFilename: Boolean;
  KeepOpen: Boolean;
  F: TFileStream;
  ActualFileHash: TSHA256Digest;
begin
  ISSigAllowedKeys := ConvertAllowedKeysRuntimeIDsToISSigAllowedKeys(TStringList(Stack.GetClass(PStart-1)));
  Filename := Stack.GetString(PStart-2);
  VerifyFilename := Stack.GetBool(PStart-3);
  KeepOpen := Stack.GetBool(PStart-4);

  { Verify signature & file, keeping open afterwards if requested
    Also see TrustFunc's CheckFileTrust which can also keep open afterwards }
  F := TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite);
  try
    DoISSigVerify(nil, F, Filename, VerifyFilename, ISSigAllowedKeys, ExpectedFileHash);
     { Couldn't get the SHA-256 while downloading so need to get and check it now }
    ActualFileHash := ISSigCalcStreamHash(F);
    if not SHA256DigestsEqual(ActualFileHash, ExpectedFileHash) then
      VerificationError(veFileHashIncorrect);
  except
    FreeAndNil(F);
    raise;
  end;
  if not KeepOpen then
    FreeAndNil(F);

  Stack.SetClass(PStart, F);
end;

procedure ScriptRound(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  SaveRoundMode: TFPURoundingMode;
begin
  SaveRoundMode := GetRoundMode;
  try
    SetRoundMode(rmNearest);
    Stack.SetInt64(PStart, Round(Stack.GetReal(PStart-1)));
  finally
    SetRoundMode(SaveRoundMode);
  end;
end;

procedure ScriptTrunc(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt64(PStart, Trunc(Stack.GetReal(PStart-1)));
end;

procedure ScriptMulDiv(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, MulDiv(Stack.GetInt(PStart-1), Stack.GetInt(PStart-2), Stack.GetInt(PStart-3)));
end;

procedure ScriptStrToColor(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  Hex: String;
begin
  Hex := Stack.GetString(PStart-1);
  if (Length(Hex) = 7) and (Hex[1] = '#') then
    Hex := '$' + Copy(Hex, 6, 2)  + Copy(Hex, 4, 2) + Copy(Hex, 2, 2);
  Stack.SetInt(PStart, SysUtils.StrToInt(Hex));
end;

procedure ScriptRPos(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
begin
  Stack.SetInt(PStart, Stack.GetString(PStart-2).LastIndexOf(Stack.GetString(PStart-1)) + 1);
end;

procedure ScriptApplyPathRedirRules(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer);
var
  TargetProcess: TPathRedirTargetProcess;
  Path: String;
begin
  if OrgName = 'ApplyPathRedirRulesForCurrentProcess' then
    TargetProcess := tpCurrent
  else
    TargetProcess := TPathRedirTargetProcess(Stack.GetInt(PStart-3));
  Path := Stack.GetString(PStart-2);
  if Path = '' then
    InternalError(Format('%s: Path must not be empty', [OrgName]));
  Stack.SetString(PStart, ApplyPathRedirRules(Stack.GetBool(PStart-1),
    Path, TargetProcess));
end;

procedure ScriptFuncLibraryRegister_R(ScriptInterpreter: TPSExec);
{$IFDEF DEBUG}
var
  Count: Integer;
{$ENDIF}

  procedure RegisterScriptFunc(const Name: AnsiString; const ScriptFuncTyp: TScriptFuncTyp; const ScriptFunc: TScriptFunc); overload;
  begin
    ScriptFuncs.Add(FastUpperCase(Name), TScriptFuncEx.Create(Name, ScriptFunc, ScriptFuncTyp));
    ScriptInterpreter.RegisterFunctionName(Name, ScriptFuncPSProc, nil, nil);
    {$IFDEF DEBUG}
    Inc(Count);
    {$ENDIF}
  end;

  procedure RegisterScriptFunc(const Names: array of AnsiString; const ScriptFuncTyp: TScriptFuncTyp; const ScriptFunc: TScriptFunc); overload;
  var
    Name: AnsiString;
  begin
    for Name in Names do
      RegisterScriptFunc(Name, ScriptFuncTyp, ScriptFunc);
  end;

  procedure RegisterScriptFunc(const Name: AnsiString; const ScriptFunc: TScriptFunc); overload;
  begin
    RegisterScriptFunc(Name, sfNormal, ScriptFunc);
  end;

  procedure RegisterScriptFunc(const Names: array of AnsiString; const ScriptFunc: TScriptFunc); overload;
  var
    Name: AnsiString;
  begin
    for Name in Names do
      RegisterScriptFunc(Name, ScriptFunc);
  end;

  procedure RegisterScriptDlgScriptFuncs;
  begin
    RegisterScriptFunc('PageFromID', sfNoUninstall, ScriptPageFromID);
    RegisterScriptFunc('PageIndexFromID', sfNoUninstall, ScriptPageIndexFromID);
    RegisterScriptFunc('CreateCustomPage', sfNoUninstall, ScriptCreateCustomPage);
    RegisterScriptFunc('CreateInputQueryPage', sfNoUninstall, ScriptCreateInputQueryPage);
    RegisterScriptFunc('CreateInputOptionPage', sfNoUninstall, ScriptCreateInputOptionPage);
    RegisterScriptFunc('CreateInputDirPage', sfNoUninstall, ScriptCreateInputDirPage);
    RegisterScriptFunc('CreateInputFilePage', sfNoUninstall, ScriptCreateInputFilePage);
    RegisterScriptFunc('CreateOutputMsgPage', sfNoUninstall, ScriptCreateOutputMsgPage);
    RegisterScriptFunc('CreateOutputMsgMemoPage', sfNoUninstall, ScriptCreateOutputMsgMemoPage);
    RegisterScriptFunc('CreateOutputProgressPage', sfNoUninstall, ScriptCreateOutputProgressPage);
    RegisterScriptFunc('CreateOutputMarqueeProgressPage', sfNoUninstall, ScriptCreateOutputMarqueeProgressPage);
    RegisterScriptFunc('CreateDownloadPage', sfNoUninstall, ScriptCreateDownloadPage);
    RegisterScriptFunc('CreateExtractionPage', sfNoUninstall, ScriptCreateExtractionPage);
    RegisterScriptFunc('SCALEX', ScriptSCALEX);
    RegisterScriptFunc('SCALEY', ScriptSCALEY);
    RegisterScriptFunc('CREATECUSTOMFORM', ScriptCREATECUSTOMFORM);
  end;

  procedure RegisterNewDiskFormScriptFuncs;
  begin
    RegisterScriptFunc('SELECTDISK', ScriptSELECTDISK);
  end;

  procedure RegisterBrowseFuncScriptFuncs;
  begin
    RegisterScriptFunc('BROWSEFORFOLDER', ScriptBROWSEFORFOLDER);
    RegisterScriptFunc('GETOPENFILENAME', ScriptGETOPENFILENAME);
    RegisterScriptFunc('GETOPENFILENAMEMULTI', ScriptGETOPENFILENAMEMULTI);
    RegisterScriptFunc('GETSAVEFILENAME', ScriptGETSAVEFILENAME);
  end;

  procedure RegisterCommonFuncVclScriptFuncs;
  begin
    RegisterScriptFunc('MINIMIZEPATHNAME', ScriptMINIMIZEPATHNAME);
  end;

  procedure RegisterCommonFuncScriptFuncs;
  begin
    RegisterScriptFunc('FILEEXISTS', ScriptFILEEXISTS);
    RegisterScriptFunc('DIREXISTS', ScriptDIREXISTS);
    RegisterScriptFunc('FILEORDIREXISTS', ScriptFILEORDIREXISTS);
    RegisterScriptFunc('GETINISTRING', ScriptGETINISTRING);
    RegisterScriptFunc('GETINIINT', ScriptGETINIINT);
    RegisterScriptFunc('GETINIBOOL', ScriptGETINIBOOL);
    RegisterScriptFunc('INIKEYEXISTS', ScriptINIKEYEXISTS);
    RegisterScriptFunc('ISINISECTIONEMPTY', ScriptISINISECTIONEMPTY);
    RegisterScriptFunc('SETINISTRING', ScriptSETINISTRING);
    RegisterScriptFunc('SETINIINT', ScriptSETINIINT);
    RegisterScriptFunc('SETINIBOOL', ScriptSETINIBOOL);
    RegisterScriptFunc('DELETEINIENTRY', ScriptDELETEINIENTRY);
    RegisterScriptFunc('DELETEINISECTION', ScriptDELETEINISECTION);
    RegisterScriptFunc('GETENV', ScriptGETENV);
    RegisterScriptFunc('GETCMDTAIL', ScriptGETCMDTAIL);
    RegisterScriptFunc('PARAMCOUNT', ScriptPARAMCOUNT);
    RegisterScriptFunc('PARAMSTR', ScriptPARAMSTR);
    RegisterScriptFunc('ADDQUOTES', ScriptADDQUOTES);
    RegisterScriptFunc('REMOVEQUOTES', ScriptREMOVEQUOTES);
    RegisterScriptFunc('GETSHORTNAME', ScriptGETSHORTNAME);
    RegisterScriptFunc('GETWINDIR', ScriptGETWINDIR);
    RegisterScriptFunc('GETSYSTEMDIR', ScriptGETSYSTEMDIR);
    RegisterScriptFunc('GETSYSWOW64DIR', ScriptGETSYSWOW64DIR);
    RegisterScriptFunc('GETSYSNATIVEDIR', ScriptGETSYSNATIVEDIR);
    RegisterScriptFunc('GETTEMPDIR', ScriptGETTEMPDIR);
    RegisterScriptFunc('STRINGCHANGE', ScriptSTRINGCHANGE);
    RegisterScriptFunc('STRINGCHANGEEX', ScriptSTRINGCHANGEEX);
    RegisterScriptFunc('USINGWINNT', ScriptUSINGWINNT);
    RegisterScriptFunc(['COPYFILE', 'FILECOPY'], ScriptCOPYFILE);
    RegisterScriptFunc('CONVERTPERCENTSTR', ScriptCONVERTPERCENTSTR);
    RegisterScriptFunc('REGKEYEXISTS', ScriptREGKEYEXISTS);
    RegisterScriptFunc('REGVALUEEXISTS', ScriptREGVALUEEXISTS);
    RegisterScriptFunc('REGDELETEKEYINCLUDINGSUBKEYS', ScriptREGDELETEKEYINCLUDINGSUBKEYS);
    RegisterScriptFunc('REGDELETEKEYIFEMPTY', ScriptREGDELETEKEYIFEMPTY);
    RegisterScriptFunc('REGDELETEVALUE', ScriptREGDELETEVALUE);
    RegisterScriptFunc('REGGETSUBKEYNAMES', ScriptREGGETSUBKEYNAMES);
    RegisterScriptFunc('REGGETVALUENAMES', ScriptREGGETVALUENAMES);
    RegisterScriptFunc('REGQUERYSTRINGVALUE', ScriptREGQUERYSTRINGVALUE);
    RegisterScriptFunc('REGQUERYMULTISTRINGVALUE', ScriptREGQUERYMULTISTRINGVALUE);
    RegisterScriptFunc('REGQUERYDWORDVALUE', ScriptREGQUERYDWORDVALUE);
    RegisterScriptFunc('REGQUERYBINARYVALUE', ScriptREGQUERYBINARYVALUE);
    RegisterScriptFunc('REGWRITESTRINGVALUE', ScriptREGWRITESTRINGVALUE);
    RegisterScriptFunc('REGWRITEEXPANDSTRINGVALUE', ScriptREGWRITEEXPANDSTRINGVALUE);
    RegisterScriptFunc('REGWRITEMULTISTRINGVALUE', ScriptREGWRITEMULTISTRINGVALUE);
    RegisterScriptFunc('REGWRITEDWORDVALUE', ScriptREGWRITEDWORDVALUE);
    RegisterScriptFunc('REGWRITEBINARYVALUE', ScriptREGWRITEBINARYVALUE);
    RegisterScriptFunc(['ISADMIN', 'ISADMINLOGGEDON'], ScriptISADMIN);
    RegisterScriptFunc('ISPOWERUSERLOGGEDON', ScriptISPOWERUSERLOGGEDON);
    RegisterScriptFunc('ISADMININSTALLMODE', ScriptISADMININSTALLMODE);
    RegisterScriptFunc('FONTEXISTS', ScriptFONTEXISTS);
    RegisterScriptFunc('GETUILANGUAGE', ScriptGETUILANGUAGE);
    RegisterScriptFunc('ADDPERIOD', ScriptADDPERIOD);
    RegisterScriptFunc('SETNTFSCOMPRESSION', ScriptSETNTFSCOMPRESSION);
    RegisterScriptFunc('ISWILDCARD', ScriptISWILDCARD);
    RegisterScriptFunc('WILDCARDMATCH', ScriptWILDCARDMATCH);
    RegisterScriptFunc('HighContrastActive', ScriptHighContrastActive);
  end;

  procedure RegisterPathFuncScriptFuncs;
  begin
    RegisterScriptFunc('AddBackslash', ScriptAddBackslash);
    RegisterScriptFunc('RemoveBackslash', ScriptRemoveBackslash);
    RegisterScriptFunc('RemoveBackslashUnlessRoot', ScriptRemoveBackslashUnlessRoot);
    RegisterScriptFunc('PathCombine', ScriptPathCombine);
    RegisterScriptFunc('PathHasInvalidCharacters', ScriptPathHasInvalidCharacters);
    RegisterScriptFunc('PathIsRooted', ScriptPathIsRooted);
    RegisterScriptFunc('PathNormalizeSlashes', ScriptPathNormalizeSlashes);
    RegisterScriptFunc('PathSame', ScriptPathSame);
    RegisterScriptFunc('PathStartsWith', ScriptPathStartsWith);
    RegisterScriptFunc('PathEndsWith', ScriptPathEndsWith);
    RegisterScriptFunc('PathConvertNormalToSuper', ScriptPathConvertNormalToSuper);
    RegisterScriptFunc('PathConvertSuperToNormal', ScriptPathConvertSuperToNormal);
    RegisterScriptFunc('CHARLENGTH', ScriptCHARLENGTH);
    RegisterScriptFunc('EXPANDFILENAME', ScriptEXPANDFILENAME);
    RegisterScriptFunc('EXTRACTFILEDIR', ScriptEXTRACTFILEDIR);
    RegisterScriptFunc('EXTRACTFILEDRIVE', ScriptEXTRACTFILEDRIVE);
    RegisterScriptFunc('EXTRACTFILEEXT', ScriptEXTRACTFILEEXT);
    RegisterScriptFunc('EXTRACTFILENAME', ScriptEXTRACTFILENAME);
    RegisterScriptFunc('EXTRACTFILEPATH', ScriptEXTRACTFILEPATH);
    RegisterScriptFunc('CHANGEFILEEXT', ScriptCHANGEFILEEXT);
  end;

  procedure RegisterInstallScriptFuncs;
  begin
    RegisterScriptFunc('ExtractTemporaryFile', sfNoUninstall, ScriptExtractTemporaryFile);
    RegisterScriptFunc('ExtractTemporaryFiles', sfNoUninstall, ScriptExtractTemporaryFiles);
    RegisterScriptFunc(['DownloadTemporaryFile', 'DownloadTemporaryFileWithISSigVerify'], sfNoUninstall, ScriptDownloadTemporaryFile);
    RegisterScriptFunc('DownloadTemporaryFileSize', sfNoUninstall, ScriptDownloadTemporaryFileSize);
    RegisterScriptFunc('DownloadTemporaryFileDate', sfNoUninstall, ScriptDownloadTemporaryFileDate);
    RegisterScriptFunc('SetDownloadCredentials', sfNoUninstall, ScriptSetDownloadCredentials);
  end;

  procedure RegisterInstFuncScriptFuncs;
  begin
    RegisterScriptFunc('CHECKFORMUTEXES', ScriptCHECKFORMUTEXES);
    RegisterScriptFunc('DECREMENTSHAREDCOUNT', ScriptDECREMENTSHAREDCOUNT);
    RegisterScriptFunc('DELAYDELETEFILE', ScriptDELAYDELETEFILE);
    RegisterScriptFunc('DELTREE', ScriptDELTREE);
    RegisterScriptFunc('GENERATEUNIQUENAME', ScriptGENERATEUNIQUENAME);
    RegisterScriptFunc('GETCOMPUTERNAMESTRING', ScriptGETCOMPUTERNAMESTRING);
    RegisterScriptFunc('GETMD5OFFILE', ScriptGETMD5OFFILE);
    RegisterScriptFunc('GETMD5OFSTRING', ScriptGETMD5OFSTRING);
    RegisterScriptFunc('GETMD5OFUNICODESTRING', ScriptGETMD5OFUNICODESTRING);
    RegisterScriptFunc('GETSHA1OFFILE', ScriptGETSHA1OFFILE);
    RegisterScriptFunc('GETSHA1OFSTRING', ScriptGETSHA1OFSTRING);
    RegisterScriptFunc('GETSHA1OFUNICODESTRING', ScriptGETSHA1OFUNICODESTRING);
    RegisterScriptFunc('GETSHA256OFFILE', ScriptGETSHA256OFFILE);
    RegisterScriptFunc('GETSHA256OFSTREAM', ScriptGETSHA256OFSTREAM);
    RegisterScriptFunc('GETSHA256OFSTRING', ScriptGETSHA256OFSTRING);
    RegisterScriptFunc('GETSHA256OFUNICODESTRING', ScriptGETSHA256OFUNICODESTRING);
    RegisterScriptFunc('GETSPACEONDISK', ScriptGETSPACEONDISK);
    RegisterScriptFunc('GETSPACEONDISK64', ScriptGETSPACEONDISK64);
    RegisterScriptFunc('GETUSERNAMESTRING', ScriptGETUSERNAMESTRING);
    RegisterScriptFunc('INCREMENTSHAREDCOUNT', ScriptINCREMENTSHAREDCOUNT);
    RegisterScriptFunc(['Exec', 'ExecAndLogOutput', 'ExecAndCaptureOutput',
      'ExecWithNativeSysDir', 'ExecAndLogOutputWithNativeSysDir', 'ExecAndCaptureOutputWithNativeSysDir',
      'ExecAsOriginalUser'], ScriptExec);
    RegisterScriptFunc(['ShellExec', 'ShellExecAsOriginalUser'], ScriptShellExec);
    RegisterScriptFunc('ISPROTECTEDSYSTEMFILE', ScriptISPROTECTEDSYSTEMFILE);
    RegisterScriptFunc('MAKEPENDINGFILERENAMEOPERATIONSCHECKSUM', ScriptMAKEPENDINGFILERENAMEOPERATIONSCHECKSUM);
    RegisterScriptFunc('MODIFYPIFFILE', ScriptMODIFYPIFFILE);
    RegisterScriptFunc('REGISTERSERVER', ScriptREGISTERSERVER);
    RegisterScriptFunc('UNREGISTERSERVER', ScriptUNREGISTERSERVER);
    RegisterScriptFunc('UNREGISTERFONT', ScriptUNREGISTERFONT);
    RegisterScriptFunc('RESTARTREPLACE', ScriptRESTARTREPLACE);
    RegisterScriptFunc('FORCEDIRECTORIES', ScriptFORCEDIRECTORIES);
  end;

  procedure RegisterInstFuncOleScriptFuncs;
  begin
    RegisterScriptFunc('CREATESHELLLINK', ScriptCREATESHELLLINK);
    RegisterScriptFunc('REGISTERTYPELIBRARY', ScriptREGISTERTYPELIBRARY);
    RegisterScriptFunc('UNREGISTERTYPELIBRARY', ScriptUNREGISTERTYPELIBRARY);
    RegisterScriptFunc('UNPINSHELLLINK', ScriptUNPINSHELLLINK);
  end;

  procedure RegisterMainFuncScriptFuncs;
  begin
    RegisterScriptFunc('ACTIVELANGUAGE', ScriptACTIVELANGUAGE);
    RegisterScriptFunc('EXPANDCONSTANT', ScriptEXPANDCONSTANT);
    RegisterScriptFunc('EXPANDCONSTANTEX', ScriptEXPANDCONSTANTEX);
    RegisterScriptFunc('EXITSETUPMSGBOX', ScriptEXITSETUPMSGBOX);
    RegisterScriptFunc('GETSHELLFOLDERBYCSIDL', ScriptGETSHELLFOLDERBYCSIDL);
    RegisterScriptFunc('INSTALLONTHISVERSION', ScriptINSTALLONTHISVERSION);
    RegisterScriptFunc('GETWINDOWSVERSION', ScriptGETWINDOWSVERSION);
    RegisterScriptFunc('GETWINDOWSVERSIONSTRING', ScriptGETWINDOWSVERSIONSTRING);
    RegisterScriptFunc(['MsgBox', 'SuppressibleMsgBox'], ScriptMsgBox);
    RegisterScriptFunc(['TaskDialogMsgBox', 'SuppressibleTaskDialogMsgBox'], ScriptTaskDialogMsgBox);
    RegisterScriptFunc('ISWIN64', ScriptISWIN64);
    RegisterScriptFunc('IS64BITINSTALLMODE', ScriptIS64BITINSTALLMODE);
    RegisterScriptFunc('IsWinDark', ScriptIsWinDark);
    RegisterScriptFunc('IsDarkInstallMode', ScriptIsDarkInstallMode);
    RegisterScriptFunc('PROCESSORARCHITECTURE', ScriptPROCESSORARCHITECTURE);
    RegisterScriptFunc(['IsArm32Compatible', 'IsArm64', 'IsX64', 'IsX64OS', 'IsX64Compatible', 'IsX86', 'IsX86OS', 'IsX86Compatible'], ScriptIsArm32Compatible);
    RegisterScriptFunc(['IsCurrentProcess64Bit'], ScriptIsCurrentProcess64Bit);
    RegisterScriptFunc('CUSTOMMESSAGE', ScriptCUSTOMMESSAGE);
    RegisterScriptFunc('RMSESSIONSTARTED', ScriptRMSESSIONSTARTED);
    RegisterScriptFunc('REGISTEREXTRACLOSEAPPLICATIONSRESOURCE', ScriptREGISTEREXTRACLOSEAPPLICATIONSRESOURCE);
    RegisterScriptFunc('GETWIZARDFORM', ScriptGETWIZARDFORM);
    RegisterScriptFunc(['WizardIsComponentSelected', 'IsComponentSelected', 'WizardIsTaskSelected', 'IsTaskSelected'], sfNoUninstall, ScriptWizardIsComponentSelected);
  end;

  procedure RegisterMessagesScriptFuncs;
  begin
    RegisterScriptFunc('SETUPMESSAGE', ScriptSETUPMESSAGE);
  end;

  procedure RegisterSystemScriptFuncs;
  begin
    RegisterScriptFunc('RANDOM', ScriptRANDOM);
    RegisterScriptFunc('FILESIZE', ScriptFILESIZE);
    RegisterScriptFunc('FILESIZE64', ScriptFILESIZE64);
    RegisterScriptFunc('SET8087CW', ScriptSET8087CW);
    RegisterScriptFunc('GET8087CW', ScriptGET8087CW);
    RegisterScriptFunc('UTF8ENCODE', ScriptUTF8ENCODE);
    RegisterScriptFunc('UTF8DECODE', ScriptUTF8DECODE);
  end;

  procedure RegisterSysUtilsScriptFuncs;
  begin
    RegisterScriptFunc('BEEP', ScriptBEEP);
    RegisterScriptFunc('TRIMLEFT', ScriptTRIMLEFT);
    RegisterScriptFunc('TRIMRIGHT', ScriptTRIMRIGHT);
    RegisterScriptFunc('GETCURRENTDIR', ScriptGETCURRENTDIR);
    RegisterScriptFunc('SETCURRENTDIR', ScriptSETCURRENTDIR);
    RegisterScriptFunc('EXPANDUNCFILENAME', ScriptEXPANDUNCFILENAME);
    RegisterScriptFunc('EXTRACTRELATIVEPATH', ScriptEXTRACTRELATIVEPATH);
    RegisterScriptFunc('FILESEARCH', ScriptFILESEARCH);
    RegisterScriptFunc('RENAMEFILE', ScriptRENAMEFILE);
    RegisterScriptFunc('DELETEFILE', ScriptDELETEFILE);
    RegisterScriptFunc('CREATEDIR', ScriptCREATEDIR);
    RegisterScriptFunc('REMOVEDIR', ScriptREMOVEDIR);
    RegisterScriptFunc('COMPARESTR', ScriptCOMPARESTR);
    RegisterScriptFunc('COMPARETEXT', ScriptCOMPARETEXT);
    RegisterScriptFunc('SAMESTR', ScriptSAMESTR);
    RegisterScriptFunc('SAMETEXT', ScriptSAMETEXT);
    RegisterScriptFunc('GETDATETIMESTRING', ScriptGETDATETIMESTRING);
    RegisterScriptFunc('SYSERRORMESSAGE', ScriptSYSERRORMESSAGE);
  end;

  procedure RegisterVerInfoFuncScriptFuncs;
  begin
    RegisterScriptFunc('GETVERSIONNUMBERS', ScriptGETVERSIONNUMBERS);
    RegisterScriptFunc('GETVERSIONCOMPONENTS', ScriptGETVERSIONCOMPONENTS);
    RegisterScriptFunc('GETVERSIONNUMBERSSTRING', ScriptGETVERSIONNUMBERSSTRING);
    RegisterScriptFunc('GETPACKEDVERSION', ScriptGETPACKEDVERSION);
    RegisterScriptFunc('PACKVERSIONNUMBERS', ScriptPACKVERSIONNUMBERS);
    RegisterScriptFunc('PACKVERSIONCOMPONENTS', ScriptPACKVERSIONCOMPONENTS);
    RegisterScriptFunc('COMPAREPACKEDVERSION', ScriptCOMPAREPACKEDVERSION);
    RegisterScriptFunc('SAMEPACKEDVERSION', ScriptSAMEPACKEDVERSION);
    RegisterScriptFunc('UNPACKVERSIONNUMBERS', ScriptUNPACKVERSIONNUMBERS);
    RegisterScriptFunc('UNPACKVERSIONCOMPONENTS', ScriptUNPACKVERSIONCOMPONENTS);
    RegisterScriptFunc('VERSIONTOSTR', ScriptVERSIONTOSTR);
    RegisterScriptFunc('STRTOVERSION', ScriptSTRTOVERSION);
  end;


  procedure RegisterWindowsScriptFuncs;
  begin
    RegisterScriptFunc('SLEEP', ScriptSLEEP);
    RegisterScriptFunc('FINDWINDOWBYCLASSNAME', ScriptFINDWINDOWBYCLASSNAME);
    RegisterScriptFunc('FINDWINDOWBYWINDOWNAME', ScriptFINDWINDOWBYWINDOWNAME);
    RegisterScriptFunc('SENDMESSAGE', ScriptSENDMESSAGE);
    RegisterScriptFunc('POSTMESSAGE', ScriptPOSTMESSAGE);
    RegisterScriptFunc('SENDNOTIFYMESSAGE', ScriptSENDNOTIFYMESSAGE);
    RegisterScriptFunc('REGISTERWINDOWMESSAGE', ScriptREGISTERWINDOWMESSAGE);
    RegisterScriptFunc('SENDBROADCASTMESSAGE', ScriptSENDBROADCASTMESSAGE);
    RegisterScriptFunc('POSTBROADCASTMESSAGE', ScriptPOSTBROADCASTMESSAGE);
    RegisterScriptFunc('SENDBROADCASTNOTIFYMESSAGE', ScriptSENDBROADCASTNOTIFYMESSAGE);
    RegisterScriptFunc('LOADDLL', ScriptLOADDLL);
    RegisterScriptFunc('CALLDLLPROC', ScriptCALLDLLPROC);
    RegisterScriptFunc('FREEDLL', ScriptFREEDLL);
    RegisterScriptFunc('CREATEMUTEX', ScriptCREATEMUTEX);
    RegisterScriptFunc('OEMTOCHARBUFF', ScriptOEMTOCHARBUFF);
    RegisterScriptFunc('CHARTOOEMBUFF', ScriptCHARTOOEMBUFF);
  end;

  procedure RegisterActiveXScriptFuncs;
  begin
    RegisterScriptFunc('COFREEUNUSEDLIBRARIES', ScriptCOFREEUNUSEDLIBRARIES);
  end;

  procedure RegisterLoggingFuncScriptFuncs;
  begin
    RegisterScriptFunc('LOG', ScriptLOG);
  end;

  procedure RegisterOtherScriptFuncs;
  begin
    RegisterScriptFunc('BRINGTOFRONTANDRESTORE', ScriptBRINGTOFRONTANDRESTORE);
    RegisterScriptFunc('WizardDirValue', sfNoUninstall, ScriptWizardDirValue);
    RegisterScriptFunc('WizardGroupValue', sfNoUninstall, ScriptWizardGroupValue);
    RegisterScriptFunc('WizardNoIcons', sfNoUninstall, ScriptWizardNoIcons);
    RegisterScriptFunc('WizardSetupType', sfNoUninstall, ScriptWizardSetupType);
    RegisterScriptFunc(['WizardSelectedComponents', 'WizardSelectedTasks'], sfNoUninstall, ScriptWizardSelectedComponents);
    RegisterScriptFunc(['WizardSelectComponents', 'WizardSelectTasks'], sfNoUninstall, ScriptWizardSelectComponents);
    RegisterScriptFunc('WizardSetBackImage', ScriptWizardSetBackImage);
    RegisterScriptFunc('WizardSilent', sfNoUninstall, ScriptWizardSilent);
    RegisterScriptFunc('ISUNINSTALLER', ScriptISUNINSTALLER);
    RegisterScriptFunc('UninstallSilent', sfOnlyUninstall, ScriptUninstallSilent);
    RegisterScriptFunc('CurrentFilename', sfNoUninstall, ScriptCurrentFilename);
    RegisterScriptFunc('CurrentSourceFilename', sfNoUninstall, ScriptCurrentSourceFilename);
    RegisterScriptFunc('CASTSTRINGTOINTEGER', ScriptCASTSTRINGTOINTEGER);
    RegisterScriptFunc('CASTINTEGERTOSTRING', ScriptCASTINTEGERTOSTRING);
    RegisterScriptFunc('ABORT', ScriptABORT);
    RegisterScriptFunc('GETEXCEPTIONMESSAGE', ScriptGETEXCEPTIONMESSAGE);
    RegisterScriptFunc('RAISEEXCEPTION', ScriptRAISEEXCEPTION);
    RegisterScriptFunc('SHOWEXCEPTIONMESSAGE', ScriptSHOWEXCEPTIONMESSAGE);
    RegisterScriptFunc('TERMINATED', ScriptTERMINATED);
    RegisterScriptFunc('GETPREVIOUSDATA', ScriptGETPREVIOUSDATA);
    RegisterScriptFunc('SETPREVIOUSDATA', ScriptSETPREVIOUSDATA);
    RegisterScriptFunc('LOADSTRINGFROMFILE', ScriptLOADSTRINGFROMFILE);
    RegisterScriptFunc('LOADSTRINGFROMLOCKEDFILE', ScriptLOADSTRINGFROMLOCKEDFILE);
    RegisterScriptFunc('LOADSTRINGSFROMFILE', ScriptLOADSTRINGSFROMFILE);
    RegisterScriptFunc('LOADSTRINGSFROMLOCKEDFILE', ScriptLOADSTRINGSFROMLOCKEDFILE);
    RegisterScriptFunc('SAVESTRINGTOFILE', ScriptSAVESTRINGTOFILE);
    RegisterScriptFunc('SAVESTRINGSTOFILE', ScriptSAVESTRINGSTOFILE);
    RegisterScriptFunc('SAVESTRINGSTOUTF8FILE', ScriptSAVESTRINGSTOUTF8FILE);
    RegisterScriptFunc('SAVESTRINGSTOUTF8FILEWITHOUTBOM', ScriptSAVESTRINGSTOUTF8FILEWITHOUTBOM);
    RegisterScriptFunc('GETUNINSTALLPROGRESSFORM', ScriptGETUNINSTALLPROGRESSFORM);
    RegisterScriptFunc('CREATECALLBACK', ScriptCREATECALLBACK);
    RegisterScriptFunc('ISDOTNETINSTALLED', ScriptISDOTNETINSTALLED);
    RegisterScriptFunc('ISMSIPRODUCTINSTALLED', ScriptISMSIPRODUCTINSTALLED);
    RegisterScriptFunc('INITIALIZEBITMAPBUTTONFROMICON', ScriptINITIALIZEBITMAPBUTTONFROMICON);
    RegisterScriptFunc('INITIALIZEBITMAPIMAGEFROMICON', ScriptINITIALIZEBITMAPIMAGEFROMICON);
    RegisterScriptFunc('InitializeBitmapButtonFromStockIcon', ScriptInitializeBitmapButtonFromStockIcon);
    RegisterScriptFunc('InitializeBitmapImageFromStockIcon', ScriptInitializeBitmapImageFromStockIcon);
    RegisterScriptFunc(['Extract7ZipArchive', 'ExtractArchive'], ScriptExtract7ZipArchive);
    RegisterScriptFunc('MapArchiveExtensions', ScriptMapArchiveExtensions);
    RegisterScriptFunc('DEBUGGING', ScriptDEBUGGING);
    RegisterScriptFunc('StringJoin', ScriptStringJoin);
    RegisterScriptFunc(['StringSplit', 'StringSplitEx'], ScriptStringSplit);
    RegisterScriptFunc('ISSigVerify', ScriptISSigVerify);
    RegisterScriptFunc('Round', ScriptRound);
    RegisterScriptFunc('Trunc', ScriptTrunc);
    RegisterScriptFunc('MulDiv', ScriptMulDiv);
    RegisterScriptFunc('StrToColor', ScriptStrToColor);
    RegisterScriptFunc('RPos', ScriptRPos);
    RegisterScriptFunc(['ApplyPathRedirRules', 'ApplyPathRedirRulesForCurrentProcess'], ScriptApplyPathRedirRules);
  end;

  procedure RegisterDelphiFunction(ProcPtr: Pointer; const Name: AnsiString;
    const CC: TPSCallingConvention = cdRegister);
  begin
    ScriptInterpreter.RegisterDelphiFunction(ProcPtr, Name, CC);
    {$IFDEF DEBUG}
    Inc(Count);
    {$ENDIF}
  end;

begin
  if ScriptFuncs <> nil then
    ScriptFuncs.Free;
  ScriptFuncs := TScriptFuncs.Create;

  { The following should register all tables in ScriptFuncTables }
  {$IFDEF DEBUG}
  Count := 0;
  {$ENDIF}
  RegisterScriptDlgScriptFuncs;
  RegisterNewDiskFormScriptFuncs;
  RegisterBrowseFuncScriptFuncs;
  RegisterCommonFuncVclScriptFuncs;
  RegisterCommonFuncScriptFuncs;
  RegisterPathFuncScriptFuncs;
  RegisterInstallScriptFuncs;
  RegisterInstFuncScriptFuncs;
  RegisterInstFuncOleScriptFuncs;
  RegisterMainFuncScriptFuncs;
  RegisterMessagesScriptFuncs;
  RegisterSystemScriptFuncs;
  RegisterSysUtilsScriptFuncs;
  RegisterVerInfoFuncScriptFuncs;
  RegisterWindowsScriptFuncs;
  RegisterActiveXScriptFuncs;
  RegisterLoggingFuncScriptFuncs;
  RegisterOtherScriptFuncs;
  {$IFDEF DEBUG}
  for var ScriptFuncTable in ScriptFuncTables do
    for var ScriptFunc in ScriptFuncTable do
      Dec(Count);
  if Count <> 0 then
    raise Exception.Create('Count <> 0');
  {$ENDIF}

  { The following should register all functions in DelphiScriptFuncTable }
  {$IFDEF DEBUG}
  Count := 0;
  {$ENDIF}
  RegisterDelphiFunction(@Format, 'Format');
  RegisterDelphiFunction(@LogFmtHelper, 'LogFmt');
  RegisterDelphiFunction(@FmtMessageHelper, 'FmtMessage');
  RegisterDelphiFunction(@FindFirstHelper, 'FindFirst');
  RegisterDelphiFunction(@FindNextHelper, 'FindNext');
  RegisterDelphiFunction(@FindCloseHelper, 'FindClose');
  RegisterDelphiFunction(@GetWindowsVersionExHelper, 'GetWindowsVersionEx');
  {$IFDEF DEBUG}
  if Count <> Length(DelphiScriptFuncTable) then
    raise Exception.Create('Count <> Length(DelphiScriptFuncTable)');
  {$ENDIF}

  {$IFNDEF FPC}
  { The following should register all functions in TestInnerfuseScriptFuncTable
    Internal, used only by Script.Test.iss }
  {$IFDEF DEBUG}
  Count := 0;
  {$ENDIF}
  RegisterDelphiFunction(@TestInnerfuse_EchoSingle, 'TestInnerfuse_EchoSingle');
  RegisterDelphiFunction(@TestInnerfuse_EchoDouble, 'TestInnerfuse_EchoDouble');
  RegisterDelphiFunction(@TestInnerfuse_EchoExtended, 'TestInnerfuse_EchoExtended');
  RegisterDelphiFunction(@TestInnerfuse_EchoCurrency, 'TestInnerfuse_EchoCurrency');
  RegisterDelphiFunction(@TestInnerfuse_EchoInt64, 'TestInnerfuse_EchoInt64');
  RegisterDelphiFunction(@TestInnerfuse_EchoSmallRec, 'TestInnerfuse_EchoSmallRec');
  RegisterDelphiFunction(@TestInnerfuse_SumRec3, 'TestInnerfuse_SumRec3');
  RegisterDelphiFunction(@TestInnerfuse_SumRec6StdCall, 'TestInnerfuse_SumRec6StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_SumRec8, 'TestInnerfuse_SumRec8');
  RegisterDelphiFunction(@TestInnerfuse_SumRec8StdCall, 'TestInnerfuse_SumRec8StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_SumSet3, 'TestInnerfuse_SumSet3');
  RegisterDelphiFunction(@TestInnerfuse_SumSet8, 'TestInnerfuse_SumSet8');
  RegisterDelphiFunction(@TestInnerfuse_SumSet8StdCall, 'TestInnerfuse_SumSet8StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_SumArray3, 'TestInnerfuse_SumArray3');
  RegisterDelphiFunction(@TestInnerfuse_SumArray4, 'TestInnerfuse_SumArray4');
  RegisterDelphiFunction(@TestInnerfuse_SumArray8, 'TestInnerfuse_SumArray8');
  RegisterDelphiFunction(@TestInnerfuse_SumArray8StdCall, 'TestInnerfuse_SumArray8StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoLargeRec, 'TestInnerfuse_EchoLargeRec');
  RegisterDelphiFunction(@TestInnerfuse_EchoPAnsiChar, 'TestInnerfuse_EchoPAnsiChar');
  RegisterDelphiFunction(@TestInnerfuse_EchoSingleStdCall, 'TestInnerfuse_EchoSingleStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoDoubleStdCall, 'TestInnerfuse_EchoDoubleStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoExtendedStdCall, 'TestInnerfuse_EchoExtendedStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoCurrencyStdCall, 'TestInnerfuse_EchoCurrencyStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoInt64StdCall, 'TestInnerfuse_EchoInt64StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoSmallRecStdCall, 'TestInnerfuse_EchoSmallRecStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_EchoLargeRecStdCall, 'TestInnerfuse_EchoLargeRecStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_MixedFloats, 'TestInnerfuse_MixedFloats');
  RegisterDelphiFunction(@TestInnerfuse_SixParams, 'TestInnerfuse_SixParams');
  RegisterDelphiFunction(@TestInnerfuse_SixParamsStdCall, 'TestInnerfuse_SixParamsStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_OpenArray, 'TestInnerfuse_OpenArray');
  RegisterDelphiFunction(@TestInnerfuse_EchoIntegerSafeCall, 'TestInnerfuse_EchoIntegerSafeCall', cdSafeCall);
  RegisterDelphiFunction(@TestInnerfuse_RaiseExceptionSafeCall, 'TestInnerfuse_RaiseExceptionSafeCall', cdSafeCall);
  RegisterDelphiFunction(@TestInnerfuse_RaiseException, 'TestInnerfuse_RaiseException');
  RegisterDelphiFunction(@TestCreateCallback_Invoke0, 'TestCreateCallback_Invoke0');
  RegisterDelphiFunction(@TestCreateCallback_Invoke5, 'TestCreateCallback_Invoke5');
  RegisterDelphiFunction(@TestCreateCallback_InvokeFloat4, 'TestCreateCallback_InvokeFloat4');
  RegisterDelphiFunction(@TestCreateCallback_InvokeExtended4, 'TestCreateCallback_InvokeExtended4');
  RegisterDelphiFunction(@TestCreateCallback_InvokeReturnInteger, 'TestCreateCallback_InvokeReturnInteger');
  RegisterDelphiFunction(@TestCreateCallback_InvokeReturnDouble, 'TestCreateCallback_InvokeReturnDouble');
  RegisterDelphiFunction(@TestCreateCallback_InvokeReturnInt64, 'TestCreateCallback_InvokeReturnInt64');
  RegisterDelphiFunction(@TestCreateCallback_InvokeRec8, 'TestCreateCallback_InvokeRec8');
  RegisterDelphiFunction(@TestCreateCallback_InvokeSet8, 'TestCreateCallback_InvokeSet8');
  RegisterDelphiFunction(@TestCreateCallback_InvokeArray8, 'TestCreateCallback_InvokeArray8');
  RegisterDelphiFunction(@TestCreateCallback_InvokeRecRet3, 'TestCreateCallback_InvokeRecRet3');
  RegisterDelphiFunction(@TestCreateCallback_InvokeRecRet5, 'TestCreateCallback_InvokeRecRet5');
  RegisterDelphiFunction(@TestCreateCallback_InvokeRecRetFloat3, 'TestCreateCallback_InvokeRecRetFloat3');
  RegisterDelphiFunction(@TestCreateCallback_InvokeRec8RecRet, 'TestCreateCallback_InvokeRec8RecRet');
{$IFDEF CPUX64}
  RegisterDelphiFunction(@TestCreateCallback_InvokeRecRet3RAX, 'TestCreateCallback_InvokeRecRet3RAX');
{$ENDIF}
  RegisterDelphiFunction(@TestInnerfuse_RecStringLength, 'TestInnerfuse_RecStringLength');
  RegisterDelphiFunction(@TestInnerfuse_RecStringLengthStdCall, 'TestInnerfuse_RecStringLengthStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_ArrStringLength, 'TestInnerfuse_ArrStringLength');
  RegisterDelphiFunction(@TestInnerfuse_ArrStringLengthStdCall, 'TestInnerfuse_ArrStringLengthStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_ReturnRec3, 'TestInnerfuse_ReturnRec3');
  RegisterDelphiFunction(@TestInnerfuse_ReturnRec4, 'TestInnerfuse_ReturnRec4');
  RegisterDelphiFunction(@TestInnerfuse_ReturnRec8, 'TestInnerfuse_ReturnRec8');
  RegisterDelphiFunction(@TestInnerfuse_ReturnRecString, 'TestInnerfuse_ReturnRecString');
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet3, 'TestInnerfuse_ReturnSet3');
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet4, 'TestInnerfuse_ReturnSet4');
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet6, 'TestInnerfuse_ReturnSet6');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr1, 'TestInnerfuse_ReturnArr1');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr2, 'TestInnerfuse_ReturnArr2');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr3, 'TestInnerfuse_ReturnArr3');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr4, 'TestInnerfuse_ReturnArr4');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr8, 'TestInnerfuse_ReturnArr8');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArrString, 'TestInnerfuse_ReturnArrString');
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr4Pascal, 'TestInnerfuse_ReturnArr4Pascal', cdPascal);
  RegisterDelphiFunction(@TestInnerfuse_ReturnArrStringPascal, 'TestInnerfuse_ReturnArrStringPascal', cdPascal);
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet3Pascal, 'TestInnerfuse_ReturnSet3Pascal', cdPascal);
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet6Pascal, 'TestInnerfuse_ReturnSet6Pascal', cdPascal);
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr4Cdecl, 'TestInnerfuse_ReturnArr4Cdecl', cdCdecl);
  RegisterDelphiFunction(@TestInnerfuse_ReturnArrStringCdecl, 'TestInnerfuse_ReturnArrStringCdecl', cdCdecl);
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet3Cdecl, 'TestInnerfuse_ReturnSet3Cdecl', cdCdecl);
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet6Cdecl, 'TestInnerfuse_ReturnSet6Cdecl', cdCdecl);
  RegisterDelphiFunction(@TestInnerfuse_ReturnArr4StdCall, 'TestInnerfuse_ReturnArr4StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_ReturnArrStringStdCall, 'TestInnerfuse_ReturnArrStringStdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet3StdCall, 'TestInnerfuse_ReturnSet3StdCall', cdStdCall);
  RegisterDelphiFunction(@TestInnerfuse_ReturnSet6StdCall, 'TestInnerfuse_ReturnSet6StdCall', cdStdCall);
  {$IFDEF DEBUG}
  if Count <> Length(TestInnerfuseScriptFuncTable) then
    raise Exception.Create('Count <> Length(TestInnerfuseScriptFuncTable)');
  {$ENDIF}

  { Following are all internal, used only by Script.Test.iss }

  RegisterScriptFunc('TestPSStackHelper_InvokeCallback', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then
      Stack.SetInt(PStart, TTestPSStackHelperProc(Method)(Stack.GetInt(PStart-2)))
    else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeExtended', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then
      Stack.SetReal(PStart, TTestHandlerExtendedProc(Method)(1.5, 2.5, 3.5, 4))
    else
      Stack.SetReal(PStart, 0);
  end);

  RegisterScriptFunc('TestHandler_InvokeCurrency', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then
      Stack.SetCurrency(PStart, TTestHandlerCurrencyProc(Method)(-1.5, -2.5, -3.5, -4))
    else
      Stack.SetCurrency(PStart, 0);
  end);

  RegisterScriptFunc('TestHandler_InvokeMixed', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart, Caller);
    if Method.Code <> nil then
      TTestHandlerMixedProc(Method)(10, 11.5, 12.5, 13);
  end);

  RegisterScriptFunc('TestHandler_InvokeRec', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      var R1: TTestHandlerRec4;
      R1.A := 10;
      R1.B := 11;
      var R2: TTestHandlerRec6;
      R2.A := 20;
      R2.B := 21;
      R2.C := 22;
      var R3: TTestHandlerRec8;
      R3.A := 30;
      R3.B := 31;
      R3.C := 32;
      R3.D := 33;
      Stack.SetInt(PStart, TTestHandlerRecProc(Method)(R1, R2, R3, 99));
    end else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeRec2', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      var R1: TTestHandlerRec3;
      R1.A := 10;
      R1.B := 11;
      R1.C := 12;
      var R2: TTestHandlerRec10;
      R2.A := 100;
      R2.B := 101;
      R2.C := 102;
      R2.D := 103;
      R2.E := 104;
      Stack.SetInt(PStart, TTestHandlerRecProc2(Method)(R1, R2, 99));
    end else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeSet', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      var S1: TTestHandlerSet4; S1 := [1, 30];
      var S2: TTestHandlerSet6; S2 := [2, 45];
      var S3: TTestHandlerSet8; S3 := [3, 60];
      Stack.SetInt(PStart, TTestHandlerSetProc(Method)(S1, S2, S3, 99));
    end else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeSet2', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      var S1: TTestHandlerSet3; S1 := [1, 20];
      var S2: TTestHandlerSet10; S2 := [4, 70];
      Stack.SetInt(PStart, TTestHandlerSetProc2(Method)(S1, S2, 99));
    end else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeArray', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      var A1: TTestHandlerArr4;
      for var I := 0 to High(A1) do
        A1[I] := Byte(10 + I);
      var A2: TTestHandlerArr6;
      for var I := 0 to High(A2) do
        A2[I] := Byte(20 + I);
      var A3: TTestHandlerArr8;
      for var I := 0 to High(A3) do
        A3[I] := Byte(30 + I);
      Stack.SetInt(PStart, TTestHandlerArrProc(Method)(A1, A2, A3, 99));
    end else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeArray2', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      var A1: TTestHandlerArr3;
      for var I := 0 to High(A1) do
        A1[I] := Byte(10 + I);
      var A2: TTestHandlerArr10;
      for var I := 0 to High(A2) do
        A2[I] := Byte(100 + I);
      Stack.SetInt(PStart, TTestHandlerArrProc2(Method)(A1, A2, 99));
    end else
      Stack.SetInt(PStart, -1);
  end);

  RegisterScriptFunc('TestHandler_InvokeRecRet1', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const R = TTestHandlerRecRet1Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(R.A));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeRecRet3', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const R = TTestHandlerRecRet3Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(R.A) + ',' + SysUtils.IntToStr(R.B) + ',' + SysUtils.IntToStr(R.C));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeRecRet4', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const R = TTestHandlerRecRet4Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(R.A) + ',' + SysUtils.IntToStr(R.B));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeRecRet8', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const R = TTestHandlerRecRet8Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(R.A) + ',' + SysUtils.IntToStr(R.B) + ',' + SysUtils.IntToStr(R.C) + ',' + SysUtils.IntToStr(R.D));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeRecRetString', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const R = TTestHandlerRecRetStringProc(Method)(10, 20);
      Stack.SetString(PStart, R.S);
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeArrRet3', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const A = TTestHandlerArrRet3Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(A[0]) + ',' + SysUtils.IntToStr(A[1]) + ',' + SysUtils.IntToStr(A[2]));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeArrRet4', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const A = TTestHandlerArrRet4Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(A[0]) + ',' + SysUtils.IntToStr(A[1]) + ',' + SysUtils.IntToStr(A[2]) + ',' + SysUtils.IntToStr(A[3]));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeArrRet8', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const A = TTestHandlerArrRet8Proc(Method)(10, 20);
      Stack.SetString(PStart, SysUtils.IntToStr(A[0]) + ',' + SysUtils.IntToStr(A[7]));
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestHandler_InvokeArrRetString', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const Method = Stack.GetProc(PStart-1, Caller);
    if Method.Code <> nil then begin
      const A = TTestHandlerArrRetStringProc(Method)(10, 20);
      Stack.SetString(PStart, A[0]);
    end else
      Stack.SetString(PStart, '');
  end);

  RegisterScriptFunc('TestRefCount_StringRefCount', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    { The -1 hides the reference GetString itself adds }
    Stack.SetInt(PStart, TestStringRefCount(Stack.GetString(PStart-1)) - 1);
  end);

  RegisterScriptFunc('TestTypes_NativeSizeOf', procedure(const Caller: TPSExec; const OrgName: AnsiString; const Stack: TPSStack; const PStart: Integer)
  begin
    const TypeName = Stack.GetString(PStart-1);
    var Size := -1;
    if TypeName = 'TTestInnerfuseSmallRec' then Size := SizeOf(TTestInnerfuseSmallRec)
    else if TypeName = 'TTestInnerfuseLargeRec' then Size := SizeOf(TTestInnerfuseLargeRec)
    else if TypeName = 'TTestHandlerRec1' then Size := SizeOf(TTestHandlerRec1)
    else if TypeName = 'TTestHandlerRec3' then Size := SizeOf(TTestHandlerRec3)
    else if TypeName = 'TTestHandlerRec4' then Size := SizeOf(TTestHandlerRec4)
    else if TypeName = 'TTestHandlerRec6' then Size := SizeOf(TTestHandlerRec6)
    else if TypeName = 'TTestHandlerRec8' then Size := SizeOf(TTestHandlerRec8)
    else if TypeName = 'TTestHandlerRec10' then Size := SizeOf(TTestHandlerRec10)
    else if TypeName = 'TTestHandlerRecString' then Size := SizeOf(TTestHandlerRecString)
    else if TypeName = 'TTestHandlerSet3' then Size := SizeOf(TTestHandlerSet3)
    else if TypeName = 'TTestHandlerSet4' then Size := SizeOf(TTestHandlerSet4)
    else if TypeName = 'TTestHandlerSet6' then Size := SizeOf(TTestHandlerSet6)
    else if TypeName = 'TTestHandlerSet8' then Size := SizeOf(TTestHandlerSet8)
    else if TypeName = 'TTestHandlerSet10' then Size := SizeOf(TTestHandlerSet10)
    else if TypeName = 'TTestHandlerArr1' then Size := SizeOf(TTestHandlerArr1)
    else if TypeName = 'TTestHandlerArr2' then Size := SizeOf(TTestHandlerArr2)
    else if TypeName = 'TTestHandlerArr3' then Size := SizeOf(TTestHandlerArr3)
    else if TypeName = 'TTestHandlerArr4' then Size := SizeOf(TTestHandlerArr4)
    else if TypeName = 'TTestHandlerArr6' then Size := SizeOf(TTestHandlerArr6)
    else if TypeName = 'TTestHandlerArr8' then Size := SizeOf(TTestHandlerArr8)
    else if TypeName = 'TTestHandlerArr10' then Size := SizeOf(TTestHandlerArr10)
    else if TypeName = 'TTestHandlerArrString' then Size := SizeOf(TTestHandlerArrString);
    Stack.SetInt(PStart, Size);
  end);
  {$ENDIF}
end;

initialization
finalization
  ScriptFuncs.Free;
end.
