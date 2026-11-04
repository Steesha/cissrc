unit Shared.TaskDialogFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  TaskDialogMsgBox function integrating with Shared.CommonFunc.Vcl's MsgBox functions
}

interface

uses
  Windows, Shared.CommonFunc.Vcl;

function TaskDialogMsgBox(const Icon, Instruction, Text, Caption: String; const Typ: TMsgBoxType;
  const Buttons: Cardinal; const ButtonLabels: array of String; const ShieldButton: Integer;
  const VerificationText: String = ''; const pfVerificationFlagChecked: PBOOL = nil): Integer;

implementation

{$IF Defined(SETUPPROJ) and (Defined(VCLSTYLES) or Defined(INNO_LCL_DARK_RESOURCES))}
  {$DEFINE USETASKDIALOGFORM}
{$IFEND}

uses
  Math, Classes, Controls, Forms, SysUtils, Themes, CommCtrl
  {$IFDEF USETASKDIALOGFORM}, Setup.TaskDialogForm {$IFDEF FPC}, Setup.SetupForm{$ENDIF}{$ENDIF}
  {$IFDEF SETUPPROJ}, Setup.InstFunc {$ENDIF};

{$IFDEF FPC}
const
  TDF_SIZE_TO_CONTENT = $01000000;
type
  TTaskDialogButton = TTASKDIALOG_BUTTON;
{$ENDIF}

var
  TaskDialogIndirectFunc: function(const pTaskConfig: PTaskDialogConfig;
    pnButton: PInteger; pnRadioButton: PInteger;
    pfVerificationFlagChecked: PBOOL): HRESULT; stdcall;

function ShieldButtonCallback(hwnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM; lpRefData: LONG_PTR): HResult; stdcall;
begin
  if (msg = TDN_CREATED) and (lpRefData <> 0) then
    SendMessage(hwnd, TDM_SET_BUTTON_ELEVATION_REQUIRED_STATE, lpRefData, 1);
  Result := S_OK;
end;

function DoTaskDialog(const hWnd: HWND; const Instruction, Text, Caption, Icon: PWideChar;
  const CommonButtons: Cardinal; const ButtonLabels: array of String; const ButtonIDs: array of Integer;
  const ShieldButton: Integer; const RightToLeft: Boolean; const TriggerMessageBoxCallbackFuncFlags: Cardinal;
  var ModalResult: Integer; const VerificationText: PWideChar; const pfVerificationFlagChecked: PBOOL): Boolean;
var
  Config: TTaskDialogConfig;
  ButtonItems: array of TTaskDialogButton;
  ActiveWindow: Windows.HWND;
  WindowList: {$IFDEF FPC}TList{$ELSE}Pointer{$ENDIF};
  I, NButtonLabelsAvailable: Integer;
begin
  if Assigned(TaskDialogIndirectFunc) then begin
    ZeroMemory(@Config, Sizeof(Config));
    Config.cbSize := SizeOf(Config);
    if (StrPos(Text, ':\') <> nil) or (StrPos(Text, '\\') <> nil) then
      Config.dwFlags := Config.dwFlags or TDF_SIZE_TO_CONTENT;
    if RightToLeft then
      Config.dwFlags := Config.dwFlags or TDF_RTL_LAYOUT;
    Config.hInstance := HInstance;
    Config.hwndParent := hWnd;
    Config.dwCommonButtons := CommonButtons;
    Config.pszWindowTitle := Caption;
    Config.pszMainIcon := Icon;
    Config.pszMainInstruction := Instruction;
    Config.pszContent := Text;
    if (VerificationText <> nil) and (VerificationText^ <> #0) then
      Config.pszVerificationText := VerificationText;
    if ShieldButton <> 0 then begin
      Config.pfCallback := ShieldButtonCallback;
      Config.lpCallbackData := ShieldButton;
    end;
    NButtonLabelsAvailable := Length(ButtonLabels);
    if NButtonLabelsAvailable <> 0 then begin
      SetLength(ButtonItems, NButtonLabelsAvailable);
      Config.dwFlags := Config.dwFlags or TDF_USE_COMMAND_LINKS;
      for I := 0 to NButtonLabelsAvailable-1 do begin
        ButtonItems[I].pszButtonText := PWideChar(ButtonLabels[I]);
        ButtonItems[I].nButtonID := ButtonIDs[I];
      end;
      Config.pButtons := @ButtonItems[0];
      Config.cButtons := UINT(NButtonLabelsAvailable);
    end;
    TriggerMessageBoxCallbackFunc(TriggerMessageBoxCallbackFuncFlags, False);
    ActiveWindow := GetActiveWindow;
    {$IFDEF FPC}
    WindowList := Screen.DisableForms(GetParentForm(FindControl(Config.hwndParent)));
    {$ELSE}
    WindowList := DisableTaskWindows(Config.hwndParent);
    { Temporarily clear SystemHooks to stop it from breaking the title bar. Does not make it dark.
      Also see BrowseFunc's NewGetOpenOrSaveFileName. }
    const SaveHooks = TStyleManager.SystemHooks;
    TStyleManager.SystemHooks := [];
    {$ENDIF}
    try
      Result := TaskDialogIndirectFunc(@Config, @ModalResult, nil, pfVerificationFlagChecked) = S_OK;
    finally
      {$IFDEF FPC}
      Screen.EnableForms(WindowList);
      {$ELSE}
      TStyleManager.SystemHooks := SaveHooks;
      EnableTaskWindows(WindowList);
      {$ENDIF}
      SetActiveWindow(ActiveWindow);
      TriggerMessageBoxCallbackFunc(TriggerMessageBoxCallbackFuncFlags, True);
    end;
  end else
    Result := False;
end;

procedure DoInternalError(const Msg: String);
begin
  {$IFDEF SETUPPROJ}
    InternalError(Msg);
  {$ELSE}
    raise Exception.Create(Msg);
  {$ENDIF}
end;

function TaskDialogMsgBox(const Icon, Instruction, Text, Caption: String; const Typ: TMsgBoxType;
  const Buttons: Cardinal; const ButtonLabels: array of String; const ShieldButton: Integer;
  const VerificationText: String = ''; const pfVerificationFlagChecked: PBOOL = nil): Integer;
var
  IconP: PWideChar;
  NButtonLabelsAvailable: Integer;
  ButtonIDs: TArray<Integer>;
  TDCommonButtons, TriggerMessageBoxCallbackFuncFlags: Cardinal;
  MessageBoxCaption: String;
begin
  Application.Restore; { See comments in MsgBox }

  { Set icon }
  if Icon <> '' then
    IconP := PWideChar(Icon)
  else begin
    case Typ of
      mbInformation: IconP := TD_INFORMATION_ICON;
      mbError: IconP := TD_WARNING_ICON;
      mbCriticalError: IconP := TD_ERROR_ICON;
    else
      IconP := nil; { No other TD_ constant available, MS recommends to use no icon for questions now and the old icon should only be used for help entries }
    end;
  end;

  { Set ButtonIDs and TDCommonButtons }
  NButtonLabelsAvailable := Length(ButtonLabels);
  case Buttons of
    MB_OK, MB_OKCANCEL:
      begin
        if NButtonLabelsAvailable = 0 then
          TDCommonButtons := TDCBF_OK_BUTTON
        else begin
          TDCommonButtons := 0;
          ButtonIDs := [IDOK];
        end;
        if Buttons = MB_OKCANCEL then
          TDCommonButtons := TDCommonButtons or TDCBF_CANCEL_BUTTON;
      end;
    MB_YESNO, MB_YESNOCANCEL:
      begin
        if NButtonLabelsAvailable = 0 then
          TDCommonButtons := TDCBF_YES_BUTTON or TDCBF_NO_BUTTON
        else begin
          TDCommonButtons := 0;
          ButtonIDs := [IDYES, IDNO];
        end;
        if Buttons = MB_YESNOCANCEL then
          TDCommonButtons := TDCommonButtons or TDCBF_CANCEL_BUTTON;
      end;
    MB_RETRYCANCEL:
      begin
        if NButtonLabelsAvailable = 0 then
          TDCommonButtons := TDCBF_RETRY_BUTTON
        else begin
          TDCommonButtons := 0;
          ButtonIDs := [IDRETRY];
        end;
        TDCommonButtons := TDCommonButtons or TDCBF_CANCEL_BUTTON;
      end;
    MB_ABORTRETRYIGNORE:
      begin
        if NButtonLabelsAvailable = 0 then
          DoInternalError('TaskDialogMsgBox: Invalid ButtonLabels')
        else
          ButtonIDs := [IDRETRY, IDIGNORE, IDABORT]; { Notice the order, abort label must be last }
        TDCommonButtons := 0;
      end;
    else
      begin
        DoInternalError('TaskDialogMsgBox: Invalid Buttons');
        TDCommonButtons := 0; { Silence compiler }
      end;
  end;

  { Allow extra label to replace TDCBF_CANCEL_BUTTON by an IDCANCEL button id }
  if (TDCommonButtons and TDCBF_CANCEL_BUTTON <> 0) and
     (NButtonLabelsAvailable-1 = Length(ButtonIDs)) then begin
    TDCommonButtons := TDCommonButtons and not TDCBF_CANCEL_BUTTON;
    SetLength(ButtonIDs, NButtonLabelsAvailable);
    ButtonIDs[NButtonLabelsAvailable-1] := IDCANCEL;
  end;

  { Check }
  if Length(ButtonIDs) <> NButtonLabelsAvailable then
    DoInternalError('TaskDialogMsgBox: Invalid ButtonLabels');

  { Go }
  MessageBoxCaption := Caption;
  if MessageBoxCaption = '' then
    MessageBoxCaption := {$IFDEF FPC}UTF8Decode(Application.Title){$ELSE}Application.Title{$ENDIF};
  TriggerMessageBoxCallbackFuncFlags := Cardinal(IfThen(Typ in [mbError, mbCriticalError], MB_ICONSTOP, 0));

  {$IFDEF USETASKDIALOGFORM}
  {$IFDEF FPC}
  if HasActiveLclStyle then begin
  {$ELSE}
  const LStyle = TStyleManager.ActiveStyle;
  if not LStyle.IsSystemStyle then begin
  {$ENDIF}

    { Note: Shared.CommonFunc.Vcl also uses TaskDialogForm }
    Result := TaskDialogForm(Instruction, Text, MessageBoxCaption, IconP, TDCommonButtons, ButtonLabels, ButtonIDs, 0, ShieldButton,
      TriggerMessageBoxCallbackFuncFlags, VerificationText, pfVerificationFlagChecked, dkTaskDialog, True);
    Exit;
  end;
  {$ENDIF}

  if not DoTaskDialog(GetOwnerWndForMessageBox, PWideChar(Instruction), PWideChar(Text),
           PWideChar(MessageBoxCaption), IconP, TDCommonButtons, ButtonLabels, ButtonIDs, ShieldButton,
           GetMessageBoxRightToLeft, TriggerMessageBoxCallbackFuncFlags, Result, PWideChar(VerificationText), pfVerificationFlagChecked) then //note that MB_ICONEXCLAMATION (used by mbError) includes MB_ICONSTOP (used by mbCriticalError)
    Result := 0;
end;

initialization
  InitCommonControls;
  TaskDialogIndirectFunc := GetProcAddress(GetModuleHandle(comctl32), 'TaskDialogIndirect');

end.
