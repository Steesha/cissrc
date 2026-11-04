unit Setup.TaskDialogForm;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Task Dialog form which can be styled

  Supports up to three command links
}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics,
  Controls, Forms, Dialogs, {$IFNDEF FPC}WinXPanels,{$ENDIF} ExtCtrls, StdCtrls,
  NewCtrls, BitmapImage, NewStaticText,
  Setup.SetupForm;

const
  TD_TASKFORM_HELP_ICON = MAKEINTRESOURCEW(Word(-100));
  {$IFDEF FPC}
  SIID_HELP = 23;
  SIID_WARNING = 78;
  SIID_INFO = 79;
  SIID_ERROR = 80;
  SIID_INVALID = -1;
  {$ENDIF}

type
  TDialogKind = (dkTaskDialog, dkMessageBox);

  TTaskDialogForm = class(TSetupForm)
    BottomPanel: TPanel;
    MainPanel: TPanel;
    LeftPanel: TPanel;
    BitmapImage: TBitmapImage;
    MainStackPanel: {$IFDEF FPC}TPanel{$ELSE}TStackPanel{$ENDIF};
    InstructionText: TNewStaticText;
    TextText: TNewStaticText;
    MainButton1: TNewButton;
    MainButton2: TNewButton;
    MainButton3: TNewButton;
    BottomStackPanel: {$IFDEF FPC}TPanel{$ELSE}TStackPanel{$ENDIF};
    OkButton: TNewButton;
    YesButton: TNewButton;
    NoButton: TNewButton;
    RetryButton: TNewButton;
    CancelButton: TNewButton;
    BottomPanel2: TPanel;
    VerificationCheck: TNewCheckBox;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FCommonButtons: array of TNewButton;
    FCommonButtonFlags: array of Cardinal;
    FMainButtons: array of TNewButton;
    FDialogKind: TDialogKind;
    procedure Finish(const DefCommonButton: Integer);
    procedure UpdateCommonButtons(const CommonButtons: Cardinal; const ShieldButton: Integer);
    procedure UpdateIcon(const Icon: PChar);
    procedure UpdateInstructionAndText(const Instruction, Text: String);
    procedure UpdateHeight;
    procedure UpdateMainButtonsAndBorderIcons(const CommonButtons: Cardinal;
      const ButtonLabels: array of String; const ButtonIDs: array of Integer; const ShieldButton: Integer);
    procedure UpdateVerificationText(const VerificationText: String);
    {$IFDEF FPC}
    procedure LayoutContent;
    {$ELSE}
    procedure WMClose(var Message: TWMClose); message WM_CLOSE;
    {$ENDIF}
  public
    constructor Create(AOwner: TComponent; const ADialogKind: TDialogKind; const ASetForeground: Boolean); reintroduce;
  end;

function TaskDialogForm(const Instruction, Text, Caption: String; const Icon: PChar;
  const CommonButtons: Cardinal; const ButtonLabels: array of String; const ButtonIDs: array of Integer;
  const DefCommonButton, ShieldButton: Integer; const TriggerMessageBoxCallbackFuncFlags: Cardinal;
  const VerificationText: String; const pfVerificationFlagChecked: PBOOL; const DialogKind: TDialogKind;
  const SetForeground: Boolean): Integer;

implementation

uses
  CommCtrl, Clipbrd, {$IFNDEF FPC}Themes,{$ENDIF} ShellAPI,
  Shared.SetupMessageIDs, Shared.CommonFunc, Shared.CommonFunc.Vcl,
  SetupLdrAndSetup.Messages, Setup.MainFunc;

{$IFDEF FPC}{$R *.lfm}{$ELSE}{$R *.dfm}{$ENDIF}

function TaskDialogForm(const Instruction, Text, Caption: String; const Icon: PChar;
  const CommonButtons: Cardinal; const ButtonLabels: array of String; const ButtonIDs: array of Integer;
  const DefCommonButton, ShieldButton: Integer; const TriggerMessageBoxCallbackFuncFlags: Cardinal;
  const VerificationText: String; const pfVerificationFlagChecked: PBOOL; const DialogKind: TDialogKind;
  const SetForeground: Boolean): Integer;
var
  Form: TTaskDialogForm;
begin
  Form := TTaskDialogForm.Create(nil, DialogKind, SetForeground);
  try
    Form.Caption := {$IFDEF FPC}UTF8Encode(Caption){$ELSE}Caption{$ENDIF};
    Form.UpdateInstructionAndText(Instruction, Text);
    Form.UpdateIcon(Icon);
    Form.UpdateCommonButtons(CommonButtons, ShieldButton);
    Form.UpdateVerificationText(VerificationText);

    if (Pos(':\', Text) <> 0) or (Pos('\\', Text) <> 0) then
      Form.Width := MulDiv(Form.Width, 125, 100);
    {$IFDEF FPC}Form.LayoutContent;{$ENDIF}
    if Form.InstructionText.Visible then
      Form.InstructionText.AdjustHeight;
    if Form.TextText.Visible then
      Form.TextText.AdjustHeight;
    Form.UpdateMainButtonsAndBorderIcons(CommonButtons, ButtonLabels, ButtonIDs, ShieldButton);
    Form.UpdateHeight;

    Form.Finish(DefCommonButton);

    TriggerMessageBoxCallbackFunc(TriggerMessageBoxCallbackFuncFlags, False);
    try
      Result := Form.ShowModal;
      {$IFDEF FPC}
      { LCL returns Cancel for the window close button. An OK-only message box
        treats that action as OK, matching the Windows message box. }
      if (Result = IDCANCEL) and (DialogKind = dkMessageBox) and (CommonButtons = TDCBF_OK_BUTTON) then
        Result := IDOK;
      {$ENDIF}
      if pfVerificationFlagChecked <> nil then
        pfVerificationFlagChecked^ := Form.VerificationCheck.Checked;
    finally
      TriggerMessageBoxCallbackFunc(TriggerMessageBoxCallbackFuncFlags, True);
    end;
  finally
    Form.Free;
  end;
end;

{ TTaskDialogForm }

constructor TTaskDialogForm.Create(AOwner: TComponent; const ADialogKind: TDialogKind; const ASetForeground: Boolean);
const
  Pad = 10;
var
  PadX, PadY: Integer;
begin
  inherited Create(AOwner);

  FCommonButtons := [OkButton, YesButton, NoButton, RetryButton, CancelButton];
  FCommonButtonFlags := [TDCBF_OK_BUTTON, TDCBF_YES_BUTTON, TDCBF_NO_BUTTON, TDCBF_RETRY_BUTTON, TDCBF_CANCEL_BUTTON];
  FMainButtons := [MainButton1, MainButton2, MainButton3];
  FDialogKind := ADialogKind;
  SetForeground := ASetForeground;

  if not CustomWizardBackground or (SetupHeader.WizardBackColor = clWindow) then begin
    {$IFDEF FPC}
    MainPanel.ParentColor := True;
    {$ELSE}
    var LStyle := StyleServices(Self);
    if not LStyle.Enabled or LStyle.IsSystemStyle then
      LStyle := nil;
    if LStyle <> nil then begin
      { Make MainPanel look the same as WizardForm's main area }
      MainPanel.StyleElements := [];
      MainPanel.Color := LStyle.GetStyleColor(scWindow);
    end;
    {$ENDIF}
  end else
    MainPanel.ParentBackground := True;

  { KeepSizeX: Already bit wider than regular task dialogs
    KeepSizeY: UpdateHeight will set height }
  InitializeFont(True, True);

  PadX := ScalePixelsX(Pad);
  PadY := ScalePixelsY(Pad);

  {$IFNDEF FPC}
  MainPanel.Padding.Left := PadX;
  MainPanel.Padding.Top := PadY;
  MainPanel.Padding.Right := PadX;
  MainPanel.Padding.Bottom := PadY;
  MainStackPanel.Padding.Left := PadX; { Also see Finish }
  MainStackPanel.Spacing := PadY;
  BottomStackPanel.Spacing := PadX;
  BottomStackPanel.Padding.Right := PadX; { Also see Finish }
  {$ENDIF}
  VerificationCheck.Left := PadX;

  OkButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonOK]{$IFDEF FPC}){$ENDIF};
  YesButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonYes]{$IFDEF FPC}){$ENDIF};
  NoButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonNo]{$IFDEF FPC}){$ENDIF};
  RetryButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgAbortRetryIgnoreRetry]{$IFDEF FPC}){$ENDIF};
  CancelButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonCancel]{$IFDEF FPC}){$ENDIF};
end;

procedure TTaskDialogForm.Finish(const DefCommonButton: Integer);
var
  I: Integer;
  CommonButton: TNewButton;
begin
  {$IFNDEF FPC}
  if RightToLeft then begin
    { FlipAndCenterIfNeeded does not update Align or Padding }
    if LeftPanel.Visible then
      LeftPanel.Align := alRight;
    MainStackPanel.Padding.Right := MainStackPanel.Padding.Left;
    MainStackPanel.Padding.Left := 0;
    if BottomPanel.Visible then begin
      BottomStackPanel.Align := alLeft;
      BottomStackPanel.Padding.Left := BottomStackPanel.Padding.Right;
      BottomStackPanel.Padding.Right := 0;
    end;
  end;

  {$ENDIF}
  if DefCommonButton > 0 then begin
    I := DefCommonButton;
    for CommonButton in FCommonButtons do begin
      if CommonButton.Visible then begin
        Dec(I);
        if I = 0 then begin
          ActiveControl := CommonButton;
          Exit;
        end;
      end;
    end;
  end;
end;

procedure TTaskDialogForm.UpdateCommonButtons(const CommonButtons: Cardinal; const ShieldButton: Integer);
var
  VisibleCaptions: array of String;
  VisibleExtraWidths: array of Integer;
  NVisibleCaptions, I, W: Integer;
  CommonButton: TNewButton;
  CommonButtonFlag: Cardinal;
begin
  NVisibleCaptions := 0;
  for I := 0 to Length(FCommonButtons)-1 do begin
    CommonButton := FCommonButtons[I];
    CommonButtonFlag := FCommonButtonFlags[I];
    CommonButton.Visible := CommonButtons and CommonButtonFlag <> 0;
    if CommonButton.Visible then begin
      CommonButton.ElevationRequired := CommonButton.ModalResult = ShieldButton;
      Inc(NVisibleCaptions);
      SetLength(VisibleCaptions, NVisibleCaptions);
      SetLength(VisibleExtraWidths, NVisibleCaptions);
      VisibleCaptions[NVisibleCaptions-1] := {$IFDEF FPC}UTF8Decode(CommonButton.Caption){$ELSE}CommonButton.Caption{$ENDIF};
      { Room for the shield, assumed to be 16 pixels wide at 96 DPI, and for the unscaled
        2 pixel gap after it, as in TButtonStyleHook.DrawButton }
      if CommonButton.ElevationRequired then
        VisibleExtraWidths[NVisibleCaptions-1] := MulDiv(16, {$IFDEF FPC}PixelsPerInch, 96{$ELSE}CurrentPPI, Screen.DefaultPixelsPerInch{$ENDIF}) + 2
      else
        VisibleExtraWidths[NVisibleCaptions-1] := 0;
    end;
  end;

  BottomPanel.Visible := NVisibleCaptions > 0;
  if BottomPanel.Visible then begin
    W := CalculateButtonWidthWithExtraWidths(VisibleCaptions, VisibleExtraWidths);
    for CommonButton in FCommonButtons do
      if CommonButton.Visible then
        CommonButton.Width := W;
  end;
end;

{$IFDEF FPC}
procedure TTaskDialogForm.LayoutContent;
var
  Control: TControl;
  Button: TNewButton;
  I, Left, Top, Width, PadX, PadY: Integer;
begin
  PadX := ScalePixelsX(10);
  PadY := ScalePixelsY(10);
  Left := PadX;
  if LeftPanel.Visible then begin
    LeftPanel.SetBounds(PadX, PadY, LeftPanel.Width, LeftPanel.Height);
    Inc(Left, LeftPanel.Width + PadX);
  end;
  Width := ClientWidth - Left - PadX;
  MainStackPanel.SetBounds(Left, PadY, Width, MainStackPanel.Height);
  Top := 0;
  for I := 0 to MainStackPanel.ControlCount-1 do begin
    Control := MainStackPanel.Controls[I];
    if Control.Visible then begin
      Control.SetBounds(0, Top, Width, Control.Height);
      Inc(Top, Control.Height + PadY);
    end;
  end;

  Left := ClientWidth - PadX;
  BottomStackPanel.SetBounds(0, 0, ClientWidth, BottomPanel.Height);
  for I := High(FCommonButtons) downto 0 do begin
    Button := FCommonButtons[I];
    if Button.Visible then begin
      Dec(Left, Button.Width);
      Button.Left := Left;
      Dec(Left, PadX);
    end;
  end;
end;
{$ENDIF}

procedure TTaskDialogForm.UpdateHeight;
var
  BottomControl: TControl;
  NewClientHeight, MinimumClientHeight: Integer;
begin
  {$IFDEF FPC}LayoutContent;{$ENDIF}
  BottomControl := nil;

  if MainButton3.Visible then
    BottomControl := MainButton3
  else if MainButton2.Visible then
    BottomControl := MainButton2
  else if MainButton1.Visible then
    BottomControl := MainButton1
  else if TextText.Visible then
    BottomControl := TextText
  else if InstructionText.Visible then
    BottomControl := InstructionText;

  { Note that MainStackPanel.Top already includes MainPanel.Padding.Top }
  NewClientHeight := MainStackPanel.Top + {$IFDEF FPC}ScalePixelsY(10){$ELSE}MainPanel.Padding.Bottom{$ENDIF};
  if BottomControl <> nil then
    NewClientHeight := NewClientHeight + BottomControl.Top + BottomControl.Height;

  if LeftPanel.Visible then begin
    { Make sure the height is enough to fit the icon. Note that LeftPanel.Top
      already includes MainPanel.Padding.Top. }
    MinimumClientHeight := LeftPanel.Top + {$IFDEF FPC}ScalePixelsY(10){$ELSE}MainPanel.Padding.Bottom{$ENDIF} + BitmapImage.Top + BitmapImage.Height;
    if MinimumClientHeight > NewClientHeight then
      NewClientHeight := MinimumClientHeight;
  end;

  if BottomPanel.Visible then
    NewClientHeight := NewClientHeight + BottomPanel.Height;
  if BottomPanel2.Visible then
    NewClientHeight := NewClientHeight + BottomPanel2.Height;

  ClientHeight := NewClientHeight;
end;

procedure TTaskDialogForm.UpdateIcon(const Icon: PChar);
var
  Siid: SHSTOCKICONID;
begin
  if Icon = TD_ERROR_ICON then
    Siid := SIID_ERROR
  else if Icon = TD_TASKFORM_HELP_ICON then
    Siid := SIID_HELP
  else if Icon = TD_INFORMATION_ICON then
    Siid := SIID_INFO
  else if Icon = TD_WARNING_ICON then
    Siid := SIID_WARNING
  else
    Siid := SIID_INVALID;

  if Siid <> SIID_INVALID then
    BitmapImage.InitializeFromStockIcon(Siid, clNone, [32, 48, 64])
  else if Icon <> nil then
    BitmapImage.InitializeFromIcon(HInstance, Icon, clNone, [32, 48, 64])
  else
    LeftPanel.Visible := False;
end;

procedure TTaskDialogForm.UpdateInstructionAndText(const Instruction, Text: String);
begin
  InstructionText.Visible := Instruction <> '';
  if InstructionText.Visible then begin
    InstructionText.Caption := {$IFDEF FPC}UTF8Encode(Instruction){$ELSE}Instruction{$ENDIF};
    InstructionText.Font.Height := MulDiv(InstructionText.Font.Height, 12, 9);
  end;
  TextText.Visible := Text <> '';
  if TextText.Visible then
    TextText.Caption := {$IFDEF FPC}UTF8Encode(Text){$ELSE}Text{$ENDIF};
end;

procedure TTaskDialogForm.UpdateMainButtonsAndBorderIcons(const CommonButtons: Cardinal;
  const ButtonLabels: array of String; const ButtonIDs: array of Integer; const ShieldButton: Integer);
var
  HaveCancel: Boolean;
  I, P: Integer;
  MainButton: TNewButton;
  Caption, Hint: String;
  SystemMenu: HMENU;
begin
  HaveCancel := False;
  for I := 0 to Length(FMainButtons)-1 do begin
    MainButton := FMainButtons[I];
    MainButton.Visible := I < Length(ButtonLabels);
    if MainButton.Visible then begin
      Caption := ButtonLabels[I];
      P := Pos(#10, Caption);
      if P <> 0 then begin
        Hint := Copy(Caption, P+1, MaxInt);
        Delete(Caption, P, MaxInt);
      end else
        Hint := '';
      MainButton.Caption := {$IFDEF FPC}UTF8Encode(Caption){$ELSE}Caption{$ENDIF};
      MainButton.Font.Height := MulDiv(MainButton.Font.Height, 12, 9);
      MainButton.CommandLinkHint := Hint;
      MainButton.ModalResult := ButtonIDs[I];
      if MainButton.ModalResult = IDCANCEL then begin
        MainButton.Cancel := True;
        HaveCancel := True;
      end;
      MainButton.ElevationRequired := MainButton.ModalResult = ShieldButton;
      MainButton.AdjustHeightIfCommandLink;
    end;
  end;

  if (FDialogKind = dkMessageBox) and (CommonButtons = TDCBF_OK_BUTTON) then begin
    { Same as MessageBox: Escape and the close button choose OK if it is the only button.
      Also see WMClose. Note that TaskDialog ignores Escape in this situation, because we
      don't use TDF_ALLOW_DIALOG_CANCELLATION. }
    OkButton.Cancel := True;
    HaveCancel := True;
  end;

  if not HaveCancel and (CommonButtons and TDCBF_CANCEL_BUTTON = 0) then begin
    SystemMenu := GetSystemMenu(Handle, False);
    if SystemMenu <> 0 then
      EnableMenuItem(SystemMenu, SC_CLOSE, MF_BYCOMMAND or MF_GRAYED);
  end;
end;

procedure TTaskDialogForm.UpdateVerificationText(const VerificationText: String);
begin
  if VerificationText <> '' then
    VerificationCheck.Caption := {$IFDEF FPC}UTF8Encode(VerificationText){$ELSE}VerificationText{$ENDIF}
  else
    BottomPanel2.Visible := False;
end;

{$IFNDEF FPC}
procedure TTaskDialogForm.WMClose(var Message: TWMClose);
begin
  { Close would return mrCancel }
  if OkButton.Cancel then
    ModalResult := OkButton.ModalResult
  else
    inherited;
end;
{$ENDIF}

procedure TTaskDialogForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

const
  SLine = '---------------------------';
  SLineAndNewLine = SLine + SNewLine;
var
  SB: TStringBuilder;
  MessageBoxFormat: Boolean;
  MainButton, CommonButton: TNewButton;

  procedure AddButtonCaption(const SB: TStringBuilder; const MessageBoxFormat: Boolean;
    const Button: TButton);
  var
    Caption: String;
  begin
    Caption := RemoveAccelChar({$IFDEF FPC}UTF8Decode(Button.Caption){$ELSE}Button.Caption{$ENDIF});
    if MessageBoxFormat then
      SB.Append(Format('%s   ', [Caption]))
    else
      SB.Append(Format('[%s] ', [Caption]));
  end;

begin
  if (Shift = [ssCtrl]) and (Key = Ord('C')) then begin
    Key := 0;
    SB := TStringBuilder.Create;
    try
      { Do not localize }
      MessageBoxFormat := FDialogKind = dkMessageBox;

      if MessageBoxFormat then
        SB.Append(SLine)
      else
        SB.Append('[Window Title]');
      SB.Append(SNewLine);
      SB.Append({$IFDEF FPC}UTF8Decode(Caption){$ELSE}Caption{$ENDIF});
      SB.Append(SNewLine);
      if MessageBoxFormat then
        SB.Append(SLineAndNewLine)
      else
        SB.Append(SNewLine);

      if InstructionText.Visible then begin
        if not MessageBoxFormat then begin
          SB.Append('[Main Instruction]');
          SB.Append(SNewLine);
        end;
        SB.Append({$IFDEF FPC}UTF8Decode(InstructionText.Caption){$ELSE}InstructionText.Caption{$ENDIF});
        SB.Append(SNewLine);
        if not MessageBoxFormat or TextText.Visible then
          SB.Append(SNewLine);
      end;

      if TextText.Visible then begin
        if not MessageBoxFormat then begin
          SB.Append('[Content]');
          SB.Append(SNewLine);
        end;
        SB.Append({$IFDEF FPC}UTF8Decode(TextText.Caption){$ELSE}TextText.Caption{$ENDIF});
        SB.Append(SNewLine);
        if not MessageBoxFormat then
          SB.Append(SNewLine);
      end;

      if MessageBoxFormat then
        SB.Append(SLineAndNewLine);

      for MainButton in FMainButtons do
        if MainButton.Visible then
          AddButtonCaption(SB, MessageBoxFormat, MainButton);

      for CommonButton in FCommonButtons do
        if CommonButton.Visible then
          AddButtonCaption(SB, MessageBoxFormat, CommonButton);

      if MessageBoxFormat then begin
        SB.Append(SNewLine);
        SB.Append(SLine); { Causes the spaces after the last button caption not to be trimmed, but this is same as with native MessageBox }
      end;

      Clipboard.AsText := {$IFDEF FPC}UTF8Encode(Trim(SB.ToString)){$ELSE}SB.ToString.Trim{$ENDIF};
    finally
      SB.Free;
    end;
  end;
end;

end.
