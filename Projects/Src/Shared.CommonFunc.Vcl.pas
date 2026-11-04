unit Shared.CommonFunc.Vcl;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Common VCL functions
}

{$B-}

interface

uses
  Windows, Messages, SysUtils, {$IFDEF FPC}Classes, {$ENDIF} Forms, Graphics, Controls, StdCtrls;

type
  TWindowDisabler = class
  private
    FFallbackWnd, FOwnerWnd: HWND;
    FPreviousActiveWnd, FPreviousFocusWnd: HWND;
    FWindowList: {$IFDEF FPC}TList{$ELSE}Pointer{$ENDIF};
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { Note: This type is also present in Compiler.ScriptFunc.pas }
  TMsgBoxType = (mbInformation, mbConfirmation, mbError, mbCriticalError);

  TMsgBoxCallbackFunc = procedure(const Flags: Cardinal; const After: Boolean;
    const Param: NativeInt);

  TControlHelper = class helper for TControl
    {$IFDEF FPC}
    function GetCurrentPPI: Integer;
    property CurrentPPI: Integer read GetCurrentPPI;
    {$ENDIF}
    procedure SetCurrentPPI(const CurrentPPI: Integer);
  end;

  TListBoxItemIsBoldFunc = function(const Index: Integer): Boolean of object;

function AppCreateForm(const AClass: TCustomFormClass): TCustomForm;
procedure UpdateScrollWidth(const ListBox: TCustomListBox;
  const ItemIsBold: TListBoxItemIsBoldFunc = nil);
function MinimizePathName(const Filename: String; const Font: TFont;
  MaxLen: Integer): String;
function MsgBox(const Text, Caption: PChar; Flags: Cardinal): Integer; overload;
function MsgBox(const Text, Caption: String; const Typ: TMsgBoxType;
  const Buttons: Cardinal): Integer; overload;
procedure SetMessageBoxRightToLeft(const ARightToLeft: Boolean);
function GetMessageBoxRightToLeft: Boolean;
procedure SetMessageBoxCallbackFunc(const AFunc: TMsgBoxCallbackFunc; const AParam: NativeInt);
procedure GetMessageBoxCallbackFunc(out AFunc: TMsgBoxCallbackFunc; out AParam: NativeInt);
procedure TriggerMessageBoxCallbackFunc(const Flags: Cardinal; const After: Boolean);
function GetOwnerWndForMessageBox: HWND;
procedure SetDarkTitleBar(const Form: TForm; const Dark: Boolean);

implementation

{$IF Defined(SETUPPROJ) and (Defined(VCLSTYLES) or Defined(INNO_LCL_DARK_RESOURCES))}
  {$DEFINE USETASKDIALOGFORM}
{$IFEND}

uses
  DwmApi, PathFunc, {$IFNDEF FPC}Themes, {$ENDIF}
  {$IFDEF USETASKDIALOGFORM} CommCtrl, Setup.TaskDialogForm, Setup.InstFunc, {$IFDEF FPC}Setup.SetupForm,{$ENDIF} {$ENDIF}
  Shared.CommonFunc;

var
  MessageBoxRightToLeft: Boolean;
  MessageBoxCallbackFunc: TMsgBoxCallbackFunc;
  MessageBoxCallbackParam: NativeInt;
  MessageBoxCallbackActive: Boolean;

function AppCreateForm(const AClass: TCustomFormClass): TCustomForm;
{ Creates a form, making it the main form if there isn't one already.
  Usage: AppCreateForm(TMyForm) as TMyForm
  This is a wrapper around Application.CreateForm, but with these advantages:
  - Safety: Returns a typed value instead of writing to an untyped parameter.
  - Safety: When used in an assignment statement: MyForm := AppCreateForm(...)
    the variable isn't modified until the form is fully constructed and the
    function exits. Application.CreateForm writes to its parameter, making the
    value public, before the form's constructor is executed, which could allow
    code outside the form to access the form before it's fully constructed.
  - When the result is casted with "as", it works with type inference.
  - When used in the .dpr, the Delphi IDE will never touch it. }
begin
  Application.CreateForm(AClass, Result);
end;

type
  TListBoxAccess = class(TCustomListBox);

procedure UpdateScrollWidth(const ListBox: TCustomListBox;
  const ItemIsBold: TListBoxItemIsBoldFunc);
var
  Font, BoldFont: TFont;
  DC: HDC;
  TextMetrics: TTextMetricW;
  Size: TSize;
  ItemText: String;
  I, MaxScrollWidth, ScrollWidth: Integer;
begin
  Font := TListBoxAccess(ListBox).Font;
  BoldFont := nil;
  try
    MaxScrollWidth := 0;
    DC := GetDC(0);
    try
      SelectObject(DC, Font.Handle);

      //Q66370 says tmAveCharWidth should be added to scroll width
      FillChar(TextMetrics, SizeOf(TextMetrics), 0);
      GetTextMetricsW(DC, {$IFDEF FPC}@{$ENDIF}TextMetrics);

      for I := 0 to ListBox.Items.Count-1 do begin
        if Assigned(ItemIsBold) and ItemIsBold(I) then begin
          if BoldFont = nil then begin
            BoldFont := TFont.Create;
            BoldFont.Assign(Font);
            BoldFont.Style := [fsBold];
          end;
          SelectObject(DC, BoldFont.Handle);
        end else if BoldFont <> nil then
          SelectObject(DC, Font.Handle);
        ItemText := {$IFDEF FPC}UTF8Decode(ListBox.Items[I]){$ELSE}ListBox.Items[I]{$ENDIF};
        if GetTextExtentPoint32W(DC, PChar(ItemText), Length(ItemText), Size) then begin
          ScrollWidth := Size.cx + TextMetrics.tmAveCharWidth;
          if ScrollWidth > MaxScrollWidth then
            MaxScrollWidth := ScrollWidth;
        end;
      end;

    finally
      ReleaseDC(0, DC);
    end;

    { Don't check the existing scroll width, it might be outdated }
    ListBox.ScrollWidth := MaxScrollWidth;
  finally
    BoldFont.Free;
  end;
end;

function MinimizePathName(const Filename: String; const Font: TFont;
  MaxLen: Integer): String;

  procedure CutFirstDirectory(var S: String);
  var
    P: Integer;
  begin
    if Copy(S, 1, 4) = '...\' then
      Delete(S, 1, 4);
    P := PathPos('\', S);
    if P <> 0 then
    begin
      Delete(S, 1, P);
      S := '...\' + S;
    end
    else
      S := '';
  end;

var
  DC: HDC;
  Drive, Dir, Name: String;
  DriveLen: Integer;
begin
  DC := GetDC(0);
  try
    SelectObject(DC, Font.Handle);

    Result := FileName;
    Dir := PathExtractPath(Result);
    Name := PathExtractName(Result);

    DriveLen := PathDrivePartLength(Dir);
    { Include any slash following drive part, or a leading slash if DriveLen=0 }
    if (DriveLen < Length(Dir)) and PathCharIsSlash(Dir[DriveLen+1]) then
      Inc(DriveLen);
    Drive := Copy(Dir, 1, DriveLen);
    Delete(Dir, 1, DriveLen);

    while ((Dir <> '') or (Drive <> '')) and (GetTextWidth(DC, Result, False) > MaxLen) do
    begin
      if Dir <> '' then
        CutFirstDirectory(Dir);
      { If there's no directory left, minimize the drive part.
        'C:\...\filename' -> '...\filename' }
      if (Dir = '') and (Drive <> '') then
      begin
        Drive := '';
        Dir := '...\';
      end;
      Result := Drive + Dir + Name;
    end;
  finally
    ReleaseDC(0, DC);
  end;
end;

procedure SetMessageBoxRightToLeft(const ARightToLeft: Boolean);
begin
  MessageBoxRightToLeft := ARightToLeft;
end;

function GetMessageBoxRightToLeft: Boolean;
begin
  Result := MessageBoxRightToLeft;
end;

procedure SetMessageBoxCallbackFunc(const AFunc: TMsgBoxCallbackFunc; const AParam: NativeInt);
begin
  MessageBoxCallbackFunc := AFunc;
  MessageBoxCallbackParam := AParam;
end;

procedure GetMessageBoxCallbackFunc(out AFunc: TMsgBoxCallbackFunc; out AParam: NativeInt);
begin
  AFunc := MessageBoxCallbackFunc;
  AParam := MessageBoxCallbackParam;
end;

procedure TriggerMessageBoxCallbackFunc(const Flags: Cardinal; const After: Boolean);
begin
  if Assigned(MessageBoxCallbackFunc) and not MessageBoxCallbackActive then begin
    MessageBoxCallbackActive := True;
    try
      MessageBoxCallbackFunc(Flags, After, MessageBoxCallbackParam);
    finally
      MessageBoxCallbackActive := False;
    end;
  end;
end;

function GetOwnerWndForMessageBox: HWND;
{ Returns window handle that Application.MessageBox, if called immediately
  after this function, would use as the owner window for the message box.
  Exception: If the window that would be returned is not shown on the taskbar,
  or is a minimized Application.Handle window, then 0 is returned instead.
  See comments in MsgBox. }
begin
  { This is what Application.MessageBox does (Delphi 11.3) }
  Result := Application.ActiveFormHandle;
  if Result = 0 then  { shouldn't be possible, but they have this check }
    Result := Application.Handle;

  { Now our overrides }
  if (Result = Application.Handle) and IsIconic(Result) then
    Exit(0);

  if not IsWindowOnTaskbar(Result) then
    Result := 0;
end;

procedure SetDarkTitleBar(const Form: TForm; const Dark: Boolean);
const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
var
  Value: BOOL;
  {$IFDEF FPC}
  Loaded: Boolean;
  {$ENDIF}
begin
  { Based on https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/apply-windows-themes
    Unlike this article we check for Windows 10 Version 2004 because that's the first version
    that introduced DWMWA_USE_IMMERSIVE_DARK_MODE as 20 (the now documented value) instead of 19 }
  if CurrentWindowsVersionAtLeast(10, 0, 19041) then begin
    {$IFDEF FPC}
    Loaded := InitDwmLibrary;
    try
      if Loaded and Assigned(DwmSetWindowAttribute) then begin
        Value := Dark;
        DwmSetWindowAttribute(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Value, SizeOf(Value));
      end;
    finally
      FreeDwmLibrary;
    end;
    {$ELSE}
    if TStyleManager.FormBorderStyle = fbsCurrentStyle then
      Form.StyleElements := Form.StyleElements - [seBorder];
    Value := Dark;
    DwmSetWindowAttribute(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Value, SizeOf(Value));
    {$ENDIF}
  end;
end;

{$IFDEF USETASKDIALOGFORM}
var
  MsgBoxTaskDialogFormActive: Boolean;
{$ENDIF}

function MsgBox(const Text, Caption: PChar; Flags: Cardinal): Integer;

{$IFDEF USETASKDIALOGFORM}
  procedure MsgBoxFlagsDecode(const Flags: Cardinal; out Icon: PChar;
    out TDCommonButtons: Cardinal; out DefCommonButton: Integer; out SetForeground: Boolean);
  begin
    case Flags and MB_ICONMASK of
      MB_ICONEXCLAMATION {equals MB_ICONWARNING}: Icon := TD_WARNING_ICON;
      MB_ICONINFORMATION {equals MB_ICONASTERISK}: Icon := TD_INFORMATION_ICON;
      MB_ICONQUESTION: Icon := TD_TASKFORM_HELP_ICON;
      MB_ICONSTOP {equals MB_ICONERROR and MB_ICONHAND}:  Icon := TD_ERROR_ICON;
    else
      Icon := nil;
    end;

    case Flags and MB_TYPEMASK of
      MB_OK: TDCommonButtons := TDCBF_OK_BUTTON;
      MB_OKCANCEL: TDCommonButtons := TDCBF_OK_BUTTON or TDCBF_CANCEL_BUTTON;
      MB_YESNOCANCEL: TDCommonButtons := TDCBF_YES_BUTTON or TDCBF_NO_BUTTON or TDCBF_CANCEL_BUTTON;
      MB_YESNO: TDCommonButtons := TDCBF_YES_BUTTON or TDCBF_NO_BUTTON;
      MB_RETRYCANCEL: TDCommonButtons := TDCBF_RETRY_BUTTON or TDCBF_CANCEL_BUTTON;
    else
      InternalError('MsgBoxFlagsDecode: Invalid Flags');
    end;

    case Flags and MB_DEFMASK of
      MB_DEFBUTTON2: DefCommonButton := 2;
      MB_DEFBUTTON3: DefCommonButton := 3;
    else
      DefCommonButton := 0;
    end;

    SetForeground := Flags and MB_SETFOREGROUND <> 0;
  end;
{$ENDIF}

{$IFDEF USETASKDIALOGFORM}
const
  MB_CANCELTRYCONTINUE = $00000006;
{$ENDIF}
var
  {$IFDEF USETASKDIALOGFORM}
  Icon: PChar;
  TDCommonButtons, Typ: Cardinal;
  DefCommonButton: Integer;
  SetForeground: Boolean;
  {$ENDIF}
  ActiveWindow: HWND;
  WindowList: {$IFDEF FPC}TList{$ELSE}Pointer{$ENDIF};
begin
  { Always restore the app first if it's minimized. This makes sense from a
    usability perspective (e.g., it may be unclear which app generated the
    message box if it's shown by itself), but it's also a VCL bug mitigation
    (seen on Delphi 11.3):
    Without this, when Application.MainFormOnTaskBar=True, showing a window
    like a message box causes a WM_ACTIVATEAPP message to be sent to
    Application.Handle, and the VCL strangely responds by setting FAppIconic
    to False -- even though the main form is still iconic (minimized). If we
    later try to call Application.Restore, nothing happens because it sees
    FAppIconic=False. }
  Application.Restore;

  { Always try to bring the message box to the foreground. Task dialogs appear
    to do that by default.
    Due to Windows' protections against apps stealing the foreground, the
    message box won't actually come to the foreground in most cases. Instead,
    the taskbar button will flash. That's really all we need; the user just
    needs to be made aware that a message box is awaiting their response.
    (Note: Don't run under the debugger when testing because Windows allows
    debugged processes to steal the foreground with no restrictions.) }
  Flags := Flags or MB_SETFOREGROUND;

  if MessageBoxRightToLeft then
    Flags := Flags or (MB_RTLREADING or MB_RIGHT);

  TriggerMessageBoxCallbackFunc(Flags, False);
  try
    {$IFDEF USETASKDIALOGFORM}
    if not MsgBoxTaskDialogFormActive then begin { Protect against TaskDialogForm calling MsgBox }
      MsgBoxTaskDialogFormActive := True;
      try
        { We don't use MB_ABORTRETRYIGNORE or MB_CANCELTRYCONTINUE, but end users
          are liable to in [Code]. TaskDialogForm doesn't support them because
          currently we lack the strings needed for the required common buttons. }
        Typ := Flags and MB_TYPEMASK;
        if (Typ <> Cardinal(MB_ABORTRETRYIGNORE)) and (Typ <> Cardinal(MB_CANCELTRYCONTINUE)) then begin
          if {$IFDEF FPC}HasActiveLclStyle{$ELSE}not TStyleManager.ActiveStyle.IsSystemStyle{$ENDIF} then begin
            { Ignores MB_DEFBUTTON4 (there are never 4 buttons) and MB_RTLREADING+MB_RIGHT
              (TaskDialogForm has its own RTL detection) }
            MsgBoxFlagsDecode(Flags, Icon, TDCommonButtons, DefCommonButton, SetForeground);
            { Note: Shared.TaskDialogFunc also uses TaskDialogForm }
            Result := TaskDialogForm('', Text, Caption, Icon, TDCommonButtons, [], [], DefCommonButton, 0,
              Flags, '', nil, dkMessageBox, SetForeground);
            Exit;
          end;
        end;
      finally
        MsgBoxTaskDialogFormActive := False;
      end;
    end;
    {$ENDIF}

    { Application.MessageBox uses Application.ActiveFormHandle for the message
      box's owner window. If that window is Application.Handle AND it isn't
      currently shown on the taskbar [1], the result will be a message box
      with no taskbar button -- which can easily get lost behind other
      windows. Avoid that by calling MessageBox directly with no owner window.
      [1] That is the case when we're called while no forms are visible.
          But it can also be the case when Application.MainFormOnTaskBar=True
          and we're called while the application isn't in the foreground
          (i.e., GetActiveWindow=0). That seems like erroneous behavior on the
          VCL's part (it should return the same handle as when the app is in
          the foreground), and it causes modal TForms to get the 'wrong' owner
          as well. However, it can be worked around using a custom
          Application.OnGetActiveFormHandle handler (see IDE.MainForm).

      We also use the same MessageBox call when IsIconic(Application.Handle)
      is True to work around a separate issue:
        1. Start with Application.MainFormOnTaskBar=False
        2. Minimize the app
        3. While the app is still minimized, call Application.MessageBox
        4. Click the app's taskbar button (don't touch the message box)
      At this point, the form that was previously hidden when the app was
      minimized is shown again. But it's not disabled! You can interact with
      the form despite the message box not being dismissed (which can lead to
      reentrancy issues and undefined behavior). And the form is allowed to
      rise above the message box in z-order.
      The reason the form isn't disabled is that the VCL's DisableTaskWindows
      function, which is called by Application.MessageBox, ignores non-visible
      windows. Which seems wrong.
      When we call MessageBox here with no owner window, we pass the
      MB_TASKMODAL flag, which goes further than DisableTaskWindows and
      disables non-visible windows too. That prevents the user from
      interacting with the form. However, the form can still rise above the
      message box. But with separate taskbar buttons for the two windows,
      it's easier to get the message box back on top.
      (This problem doesn't occur when Application.MainFormOnTaskBar=True
      because the main form retains its WS_VISIBLE style while minimized.)

      UPDATE: Had to restrict the use of MB_TASKMODAL to only when
      MainFormOnTaskBar=False is set to work around *another* VCL issue.
      The above problem doesn't affect MainFormOnTaskBar=True so that should
      be fine.
      Details: When MainFormOnTaskBar=True and MessageBox is called with the
      MB_TASKMODAL flag after the main form is created but before the main
      form is shown, the message box appears on the screen but you can't
      interact with it using the keyboard; keys like Enter and Escape have no
      effect. The problem? The CM_ACTIVATE handler in TApplication.WndProc is
      calling SetFocus with a NULL window handle. This erroneous SetFocus call
      is only reached when the main form window is found to be disabled, which
      only happens when MB_TASKMODAL is used. As noted above, non-visible
      windows aren't disabled when only DisableTaskWindows is used.
    }
    if GetOwnerWndForMessageBox = 0 then begin
      ActiveWindow := GetActiveWindow;
      WindowList := {$IFDEF FPC}Screen.DisableForms(nil){$ELSE}DisableTaskWindows(0){$ENDIF};
      try
        { Note: DisableTaskWindows doesn't disable invisible windows.
          MB_TASKMODAL will ensure that Application.Handle gets disabled too. }
        if not Application.MainFormOnTaskBar then
          Flags := Flags or MB_TASKMODAL;
        Result := MessageBoxW(0, Text, Caption, UINT(Flags));
      finally
        {$IFDEF FPC}Screen.EnableForms(WindowList){$ELSE}EnableTaskWindows(WindowList){$ENDIF};
        SetActiveWindow(ActiveWindow);
      end;
      Exit;
    end;

    {$IFDEF FPC}
    Result := Application.MessageBox(PAnsiChar(UTF8Encode(String(Text))),
      PAnsiChar(UTF8Encode(String(Caption))), Integer(Flags));
    {$ELSE}
    Result := Application.MessageBox(Text, Caption, Integer(Flags));
    {$ENDIF}
  finally
    TriggerMessageBoxCallbackFunc(Flags, True);
  end;
end;

function MsgBox(const Text, Caption: String; const Typ: TMsgBoxType;
  const Buttons: Cardinal): Integer;
const
  IconFlags: array[TMsgBoxType] of Cardinal =
    (MB_ICONINFORMATION, MB_ICONQUESTION, MB_ICONEXCLAMATION, MB_ICONSTOP);
var
  NewCaption: String;
begin
  NewCaption := Caption;
  if NewCaption = '' then
    NewCaption := {$IFDEF FPC}UTF8Decode(Application.Title){$ELSE}Application.Title{$ENDIF};
  Result := MsgBox(PChar(Text), PChar(NewCaption), Buttons or IconFlags[Typ]);
end;

{ TWindowDisabler }

const
  WindowDisablerWndClassName = 'TWindowDisabler-Window';
var
  WindowDisablerWndClassAtom: ATOM;

function WindowDisablerWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
begin
  if Msg = WM_CLOSE then
    { If the fallback window becomes focused (e.g. by Alt+Tabbing onto it) and
      Alt+F4 is pressed, we must not pass the message to DefWindowProc because
      it would destroy the window }
    Result := 0
  else
    Result := DefWindowProcW(Wnd, Msg, WParam, LParam);
end;

constructor TWindowDisabler.Create;
const
  WndClass: TWndClassW = (
    style: 0;
    lpfnWndProc: @WindowDisablerWndProc;
    cbClsExtra: 0;
    cbWndExtra: 0;
    hInstance: 0;
    hIcon: 0;
    hCursor: 0;
    hbrBackground: COLOR_WINDOW + 1;
    lpszMenuName: nil;
    lpszClassName: WindowDisablerWndClassName);
begin
  inherited Create;
  FPreviousActiveWnd := GetActiveWindow;
  FPreviousFocusWnd := GetFocus;
  FWindowList := {$IFDEF FPC}Screen.DisableForms(nil){$ELSE}DisableTaskWindows(0){$ENDIF};

  { Create the "fallback" window.
    When a child process hides its last window, Windows will try to activate
    the top-most enabled window on the desktop. If all of our windows were
    disabled, it would end up bringing some other application to the
    foreground. This gives Windows an enabled window to re-activate, which
    is invisible to the user. }
  if WindowDisablerWndClassAtom = 0 then
    WindowDisablerWndClassAtom := Windows.RegisterClassW(WndClass);
  if WindowDisablerWndClassAtom <> 0 then begin
    { Create an invisible owner window for the fallback window so that it
      doesn't display a taskbar button. (We can't just give it the
      WS_EX_TOOLWINDOW style because Windows skips tool windows when searching
      for a new window to activate.) }
    FOwnerWnd := CreateWindowExW(0, WindowDisablerWndClassName, '',
      WS_POPUP or WS_DISABLED, 0, 0, 0, 0, HWND_DESKTOP, 0, HInstance, nil);
    if FOwnerWnd <> 0 then begin
      FFallbackWnd := CreateWindowExW(0, WindowDisablerWndClassName,
        PChar({$IFDEF FPC}UTF8Decode(Application.Title){$ELSE}Application.Title{$ENDIF}), WS_POPUP, 0, 0, 0, 0, FOwnerWnd, 0,
        HInstance, nil);
      if FFallbackWnd <> 0 then
        ShowWindow(FFallbackWnd, SW_SHOWNA);
    end;
  end;

  { Take the focus away from whatever has it. While you can't click controls
    inside a disabled window, keystrokes will still reach the focused control
    (e.g. you can press Space to re-click a focused button). }
  SetFocus(0);
end;

destructor TWindowDisabler.Destroy;
begin
  {$IFDEF FPC}Screen.EnableForms(FWindowList){$ELSE}EnableTaskWindows(FWindowList){$ENDIF};
  { Re-activate the previous window. But don't do this if GetActiveWindow
    returns zero, because that means another application is in the foreground
    (possibly a child process spawned by us that is still running). }
  if GetActiveWindow <> 0 then begin
    if FPreviousActiveWnd <> 0 then
      SetActiveWindow(FPreviousActiveWnd);
    { If the active window never changed, then the above SetActiveWindow call
      won't have an effect. Explicitly restore the focus. }
    if FPreviousFocusWnd <> 0 then
      SetFocus(FPreviousFocusWnd);
  end;
  if FOwnerWnd <> 0 then
    DestroyWindow(FOwnerWnd);  { will destroy FFallbackWnd too }
  inherited;
end;

{ TControlHelper }

{$IFDEF FPC}
function TControlHelper.GetCurrentPPI: Integer;
begin
  Result := Font.PixelsPerInch;
end;
{$ENDIF}

procedure TControlHelper.SetCurrentPPI(const CurrentPPI: Integer);
{$IFDEF FPC}
var
  PreviousHeight: Integer;
{$ENDIF}
begin
  {$IFDEF FPC}
  if Font.PixelsPerInch <> CurrentPPI then begin
    PreviousHeight := Font.Height;
    Font.BeginUpdate;
    try
      Font.PixelsPerInch := CurrentPPI;
      Font.Height := PreviousHeight;
    finally
      Font.EndUpdate;
    end;
  end;
  {$ELSE}
  FCurrentPPI := CurrentPPI;
  {$ENDIF}
end;

end.
