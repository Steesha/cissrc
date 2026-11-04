unit NewCtrls;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Previously this unit had RTL-capable versions of standard controls
  
  But now standard controls are RTL-capable already, and there's not much code left here

  Define VCLSTYLES to include an improved version TButtonStyleHook.DrawButton for command
  link buttons
}

interface

uses
  Windows, SysUtils, Messages, Classes, Graphics, Controls, Forms, Dialogs,
  {$IFDEF FPC}LCLType, LMessages,{$ELSE}{$IFDEF VCLSTYLES}Vcl.Themes,{$ELSE}Themes,{$ENDIF}{$ENDIF}
  StdCtrls, ExtCtrls;

type
  TNewEdit = class(TEdit)
    {$IFDEF FPC}
  protected
    procedure InitializeWnd; override;
    {$ENDIF}
  end;

  TNewPathEdit = class(TNewEdit)
  private
    FAutoCompleteFiles: Boolean;
    procedure SetAutoCompleteFiles(const Value: Boolean);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property AutoCompleteFiles: Boolean read FAutoCompleteFiles write SetAutoCompleteFiles;
  end;

  TNewMemo = class(TMemo)
    {$IFDEF FPC}
  protected
    procedure InitializeWnd; override;
    {$ENDIF}
  end;

  TNewComboBox = class(TComboBox)
    {$IFDEF FPC}
  protected
    procedure InitializeWnd; override;
    {$ENDIF}
  end;

  TNewListBox = class(TListBox)
    {$IFDEF FPC}
  protected
    procedure InitializeWnd; override;
    {$ENDIF}
  end;

  {$IFDEF FPC}
  TButtonStyle = (bsPushButton, bsCommandLink, bsSplitButton);
  {$ENDIF}

  TNewButton = class(TButton)
  private
    {$IFDEF FPC}
    FStyle: TButtonStyle;
    FCommandLinkHint: String;
    FElevationRequired: Boolean;
    procedure SetStyle(const Value: TButtonStyle);
    procedure SetCommandLinkHint(const Value: String);
    procedure SetElevationRequired(const Value: Boolean);
    {$ELSE}
    class constructor Create;
    class destructor Destroy;
    {$ENDIF}
  protected
    {$IFDEF FPC}
    class procedure WSRegisterClass; override;
    procedure CreateWnd; override;
    procedure CNNotify(var Message: TLMNotify); message CN_NOTIFY;
    {$ENDIF}
    procedure CreateParams(var Params: TCreateParams); override;
  public
    function AdjustHeightIfCommandLink: Integer;
  {$IFDEF FPC}
  published
    property Style: TButtonStyle read FStyle write SetStyle default bsPushButton;
    property CommandLinkHint: String read FCommandLinkHint write SetCommandLinkHint;
    property ElevationRequired: Boolean read FElevationRequired write SetElevationRequired default False;
  {$ENDIF}
  end;

  {$IFNDEF FPC}
  TNewButtonStyleHook = class(TButtonStyleHook)
{$IFDEF VCLSTYLES}
  private
    class function DrawOrMeasureCommandLink(const Draw: Boolean;
      const Control: TNewButton; const LStyle: TCustomStyleServices; const FPressed: Boolean;
      const ACanvas: TCanvas; const AMouseInControl: Boolean): Integer; static;
    class function GetIdealHeightIfCommandLink(const Control: TNewButton; const Style: TCustomStyleServices): Integer; static;
  protected
    procedure DrawButton(ACanvas: TCanvas; AMouseInControl: Boolean); override;
{$ENDIF}
  end;

  {$ENDIF}

  TNewCheckBox = class(TCheckBox)
    {$IFDEF FPC}
  protected
    procedure CNNotify(var Message: TLMNotify); message CN_NOTIFY;
    {$ENDIF}
  end;

  TNewRadioButton = class(TRadioButton)
    {$IFDEF FPC}
  protected
    procedure CNNotify(var Message: TLMNotify); message CN_NOTIFY;
    {$ENDIF}
  end;

  {$IFDEF FPC}
  TSysLinkType = (sltURL, sltID);
  TSysLinkEvent = procedure(Sender: TObject; const Link: String; LinkType: TSysLinkType) of object;

  TCustomLinkLabel = class(TWinControl)
  private
    FAlignment: TAlignment;
    FUseVisualStyle: Boolean;
    FOnLinkClick: TSysLinkEvent;
    procedure SetAlignment(const Value: TAlignment);
    procedure SetUseVisualStyle(const Value: Boolean);
  protected
    class procedure WSRegisterClass; override;
    procedure CreateParams(var Params: TCreateParams); override;
  public
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property AutoSize;
    property UseVisualStyle: Boolean read FUseVisualStyle write SetUseVisualStyle default False;
    property OnLinkClick: TSysLinkEvent read FOnLinkClick write FOnLinkClick;
  end;

  TLinkLabel = class(TCustomLinkLabel)
  published
    property Alignment;
    property Anchors;
    property AutoSize;
    property Caption;
    property Color;
    property Font;
    property ParentColor;
    property ParentFont;
    property OnLinkClick;
    property UseVisualStyle;
  end;
  {$ENDIF}

  TNewLinkLabel = class(TLinkLabel)
  public
    function AdjustHeight: Integer;
  end;

{$IFDEF FPC}
var
  ResolveEditStyleBrush: function(const Background, Foreground: TColor;
    out TextColor, BackColor: TColor): HBRUSH;
procedure InstallEditStyleHandler(const Control: TWinControl);
var
  DrawNewButtonStyle: function(const Button: TNewButton; const DC: HDC;
    const Bounds: TRect; const ItemState: Cardinal): Boolean;
  DrawNewCheckStyle: function(const Control: TCustomCheckBox; const DC: HDC;
    const Bounds: TRect; const ItemState: Cardinal): Boolean;
{$ENDIF}

procedure Register;
  
implementation

uses
  CommCtrl, ShLwApi,
  Types,
  {$IFDEF FPC}WSLCLClasses, Win32WSControls, Win32WSStdCtrls, Win32Proc,{$ENDIF}
  BidiUtils;

{$IFDEF FPC}
function ApplyInputStyleColors(const Control: TWinControl; const DC: HDC): HBRUSH;
var
  TextColor, BackColor: TColor;
begin
  Result := 0;
  if not Assigned(ResolveEditStyleBrush) or (Control = nil) or not Control.Enabled or
     ((Control is TCustomEdit) and (TCustomEdit(Control).EmulatedTextHintStatus = thsShowing)) then
    Exit;
  Result := ResolveEditStyleBrush(Control.Brush.Color, Control.Font.Color, TextColor, BackColor);
  if Result <> 0 then begin
    SetTextColor(DC, ColorToRGB(TextColor));
    SetBkColor(DC, ColorToRGB(BackColor));
  end;
end;

function EditStyleParentMessage(const Parent: TWinControl; Window: HWND; Msg: UInt;
  WParam: Windows.WParam; LParam: Windows.LParam; var MsgResult: Windows.LResult;
  var WinProcess: Boolean): Boolean;
var
  Brush: HBRUSH;
begin
  Result := False;
  if not Assigned(ResolveEditStyleBrush) or
     ((Msg <> WM_CTLCOLOREDIT) and (Msg <> WM_CTLCOLORSTATIC) and (Msg <> WM_CTLCOLORLISTBOX)) then
    Exit;
  Brush := ApplyInputStyleColors(GetWin32WindowInfo(HWND(LParam))^.WinControl, HDC(WParam));
  if Brush = 0 then
    Exit;
  MsgResult := LResult(Brush);
  WinProcess := False;
  Result := True;
end;

procedure InstallEditStyleHandler(const Control: TWinControl);
var
  Info: PWin32WindowInfo;
begin
  if not Assigned(ResolveEditStyleBrush) or not Control.HandleAllocated then
    Exit;
  Info := GetWin32WindowInfo(Control.Handle);
  if not Assigned(Info^.ParentMsgHandler) then
    Info^.ParentMsgHandler := @EditStyleParentMessage;
end;

procedure TNewEdit.InitializeWnd;
begin
  inherited;
  InstallEditStyleHandler(Self);
end;

procedure TNewMemo.InitializeWnd;
begin
  inherited;
  InstallEditStyleHandler(Self);
end;

function ComboBoxStyleSubclass(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM;
  SubclassID: UINT_PTR; RefData: DWORD_PTR): LRESULT; stdcall;
var
  Brush: HBRUSH;
begin
  case Msg of
    WM_CTLCOLOREDIT, WM_CTLCOLORSTATIC, WM_CTLCOLORLISTBOX:
      begin
        Brush := ApplyInputStyleColors(TNewComboBox(Pointer(RefData)), HDC(WParam));
        if Brush <> 0 then
          Exit(LRESULT(Brush));
      end;
    WM_NCDESTROY:
      RemoveWindowSubclass(Wnd, @ComboBoxStyleSubclass, SubclassID);
  end;
  Result := DefSubclassProc(Wnd, Msg, WParam, LParam);
end;

procedure TNewComboBox.InitializeWnd;
begin
  inherited;
  if Assigned(ResolveEditStyleBrush) then begin
    InstallEditStyleHandler(Self);
    SetWindowSubclass(Handle, @ComboBoxStyleSubclass, 0, DWORD_PTR(Self));
  end;
end;

procedure TNewListBox.InitializeWnd;
begin
  inherited;
  InstallEditStyleHandler(Self);
end;
{$ENDIF}

procedure Register;
begin
  RegisterComponents('JR', [TNewEdit, TNewPathEdit, TNewMemo, TNewComboBox, TNewListBox,
    TNewButton, TNewCheckBox, TNewRadioButton]);
end;

{ TNewPathEdit }

constructor TNewPathEdit.Create(AOwner: TComponent);
begin
  inherited;
  ParentBidiMode := False;
  BidiMode := bdLeftToRight;
end;

procedure TNewPathEdit.CreateWnd;
const
  SHACF_FILESYS_ONLY = $00000010;
  SHACF_FILESYS_DIRS = $00000020;
var
  Flags: DWORD;
begin
  inherited;
  if not(csDesigning in ComponentState) then begin
    if FAutoCompleteFiles then
      Flags := SHACF_FILESYS_ONLY
    else
      Flags := SHACF_FILESYS_DIRS;
    SHAutoComplete(Handle, Flags);
  end;
end;

procedure TNewPathEdit.SetAutoCompleteFiles(const Value: Boolean);
begin
  if FAutoCompleteFiles <> Value then begin
    FAutoCompleteFiles := Value;
    {$IFDEF FPC}RecreateWnd(Self){$ELSE}RecreateWnd{$ENDIF};
  end;
end;

{ TNewButton }

{$IFDEF FPC}
const
  NativeButtonStyles: array[TButtonStyle] of DWORD = (BS_PUSHBUTTON, $000E, $000C);
  NativeDefaultButtonStyles: array[TButtonStyle] of DWORD = (BS_DEFPUSHBUTTON, $000F, $000D);
  ButtonTypeMask = $000F;
  BCM_SETNOTE = $1609;
  BCM_SETSHIELD = $160C;

type
  TWin32WSNewButton = class(TWin32WSButton)
  public
    class procedure SetDefault(const AButton: TCustomButton; ADefault: Boolean); override;
  end;

class procedure TWin32WSNewButton.SetDefault(const AButton: TCustomButton; ADefault: Boolean);
var
  Style: DWORD;
begin
  if not AButton.HandleAllocated then
    Exit;
  Style := GetWindowLongW(AButton.Handle, GWL_STYLE) and not ButtonTypeMask;
  if ADefault then
    Style := Style or NativeDefaultButtonStyles[TNewButton(AButton).Style]
  else
    Style := Style or NativeButtonStyles[TNewButton(AButton).Style];
  SendMessageW(AButton.Handle, BM_SETSTYLE, Style, 1);
end;

class procedure TNewButton.WSRegisterClass;
begin
  inherited WSRegisterClass;
  RegisterWSComponent(TNewButton, TWin32WSNewButton);
end;

procedure TNewButton.CreateWnd;
begin
  inherited CreateWnd;
  if FStyle = bsCommandLink then
    SendMessageW(Handle, BCM_SETNOTE, 0, LPARAM(PWideChar(FCommandLinkHint)));
  SendMessageW(Handle, BCM_SETSHIELD, 0, LPARAM(FElevationRequired));
end;

procedure TNewButton.CNNotify(var Message: TLMNotify);
var
  Draw: PNMCustomDraw;
begin
  if Assigned(DrawNewButtonStyle) and (FStyle = bsPushButton) and not FElevationRequired and
     (Message.NMHdr <> nil) and (Message.NMHdr^.code = NM_CUSTOMDRAW) then begin
    Draw := PNMCustomDraw(Message.NMHdr);
    if (Draw^.dwDrawStage = CDDS_PREPAINT) and
       DrawNewButtonStyle(Self, Draw^.hdc, Draw^.rc, Draw^.uItemState) then begin
      Message.Result := CDRF_SKIPDEFAULT;
      Exit;
    end;
  end;
  inherited;
end;

function DrawCheckStyleNotification(const Control: TCustomCheckBox; var Message: TLMNotify): Boolean;
var
  Draw: PNMCustomDraw;
begin
  Result := False;
  if not Assigned(DrawNewCheckStyle) or (Message.NMHdr = nil) or
     (Message.NMHdr^.code <> NM_CUSTOMDRAW) then
    Exit;
  Draw := PNMCustomDraw(Message.NMHdr);
  if (Draw^.dwDrawStage = CDDS_PREPAINT) and
     DrawNewCheckStyle(Control, Draw^.hdc, Draw^.rc, Draw^.uItemState) then begin
    Message.Result := CDRF_SKIPDEFAULT;
    Result := True;
  end;
end;

procedure TNewCheckBox.CNNotify(var Message: TLMNotify);
begin
  if not DrawCheckStyleNotification(Self, Message) then
    inherited;
end;

procedure TNewRadioButton.CNNotify(var Message: TLMNotify);
begin
  if not DrawCheckStyleNotification(Self, Message) then
    inherited;
end;

procedure TNewButton.SetStyle(const Value: TButtonStyle);
begin
  if FStyle <> Value then begin
    FStyle := Value;
    RecreateWnd(Self);
  end;
end;

procedure TNewButton.SetCommandLinkHint(const Value: String);
begin
  FCommandLinkHint := Value;
  if HandleAllocated and (FStyle = bsCommandLink) then
    SendMessageW(Handle, BCM_SETNOTE, 0, LPARAM(PWideChar(Value)));
end;

procedure TNewButton.SetElevationRequired(const Value: Boolean);
begin
  FElevationRequired := Value;
  if HandleAllocated then
    SendMessageW(Handle, BCM_SETSHIELD, 0, LPARAM(Value));
end;
{$ELSE}
class constructor TNewButton.Create;
begin
  TCustomStyleEngine.RegisterStyleHook(TNewButton, TNewButtonStyleHook);
end;

{$ENDIF}

procedure TNewButton.CreateParams(var Params: TCreateParams);
begin
  inherited;
  {$IFDEF FPC}
  Params.Style := (Params.Style and not ButtonTypeMask) or NativeButtonStyles[Style];
  {$ENDIF}
  if (Style = bsCommandLink) and IsRightToLeft then begin
    { Command link buttons need to have WS_EX_LAYOUTRTL enabled for full RTL, in addition to
      WS_EX_RTLREADING and WS_EX_LEFTSCROLLBAR, but not WS_EX_RIGHT. This can be confirmed by
      inspecting the style of a task dialog command link button. However, if VCL Styles is
      active, this should not be done since the style hook does not expect it at all. }
    {$IFNDEF FPC}if not IsCustomStyleActive then{$ENDIF}
      Params.ExStyle := Params.ExStyle or WS_EX_LAYOUTRTL;
  end;
end;

{$IFNDEF FPC}
class destructor TNewButton.Destroy;
begin
  TCustomStyleEngine.UnregisterStyleHook(TNewButton, TNewButtonStyleHook);
end;

{$ENDIF}

function TNewButton.AdjustHeightIfCommandLink: Integer;
var
  OldHeight: Integer;
  IdealSize: TSize;
begin
  Result := 0;
  if Style = bsCommandLink then begin
    OldHeight := Height;

    {$IFDEF VCLSTYLES}
    var LStyle := StyleServices(Self);
    if not LStyle.Enabled or LStyle.IsSystemStyle then
      LStyle := nil;

    if LStyle <> nil then begin
      const IdealHeight = TNewButtonStyleHook.GetIdealHeightIfCommandLink(Self, LStyle);
      if IdealHeight <> 0 then begin
        Height := IdealHeight;
        Exit(Height - OldHeight);
      end;
    end;
    {$ENDIF}

    IdealSize.cx := Width;
    IdealSize.cy := 0; { Not needed according to docs and tests, but clearing anyway }
    if SendMessage(Handle, BCM_GETIDEALSIZE, 0, LPARAM(@IdealSize)) <> 0 then begin
      Height := IdealSize.cy;
      Result := Height - OldHeight;
    end;
  end;
end;

{$IFDEF FPC}
const
  LM_GETIDEALSIZE = WM_USER + $301;
  LWS_USEVISUALSTYLE = $0008;
  LWS_RIGHT = $0020;

type
  TWin32WSLinkLabel = class(TWin32WSWinControl)
  public
    class function CreateHandle(const AWinControl: TWinControl;
      const AParams: TCreateParams): HWND; override;
  end;

function LinkLabelParentMessage(const AWinControl: TWinControl; Window: HWND;
  Msg: UINT; WParam: Windows.WPARAM; LParam: Windows.LPARAM;
  var MsgResult: Windows.LRESULT; var WinProcess: Boolean): Boolean;
var
  LinkLabel: TCustomLinkLabel;
  Notification: PNMLink;
begin
  Result := False;
  if Msg <> WM_NOTIFY then
    Exit;
  Notification := PNMLink(LParam);
  if (Notification^.hdr.code <> NM_CLICK) and (Notification^.hdr.code <> NM_RETURN) then
    Exit;

  LinkLabel := TCustomLinkLabel(AWinControl);
  if Assigned(LinkLabel.FOnLinkClick) then begin
    if Notification^.item.szUrl[0] <> #0 then
      LinkLabel.FOnLinkClick(LinkLabel, PWideChar(@Notification^.item.szUrl[0]), sltURL)
    else
      LinkLabel.FOnLinkClick(LinkLabel, PWideChar(@Notification^.item.szID[0]), sltID);
  end;
  MsgResult := 0;
  WinProcess := False;
  Result := True;
end;

class function TWin32WSLinkLabel.CreateHandle(const AWinControl: TWinControl;
  const AParams: TCreateParams): HWND;
var
  Params: TCreateWindowExParams;
  CommonControls: TInitCommonControlsEx;
begin
  CommonControls.dwSize := SizeOf(CommonControls);
  CommonControls.dwICC := $00008000; { ICC_LINK_CLASS }
  InitCommonControlsEx(CommonControls);
  PrepareCreateWindow(AWinControl, AParams, Params);
  Params.pClassName := 'SysLink';
  Params.WindowTitle := Params.StrCaption;
  FinishCreateWindow(AWinControl, Params, False);
  Params.WindowInfo^.ParentMsgHandler := @LinkLabelParentMessage;
  Result := Params.Window;
end;

class procedure TCustomLinkLabel.WSRegisterClass;
begin
  inherited WSRegisterClass;
  RegisterWSComponent(TCustomLinkLabel, TWin32WSLinkLabel);
end;

procedure TCustomLinkLabel.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if FAlignment = taRightJustify then
    Params.Style := Params.Style or LWS_RIGHT;
  if FUseVisualStyle then
    Params.Style := Params.Style or LWS_USEVISUALSTYLE;
end;

procedure TCustomLinkLabel.SetAlignment(const Value: TAlignment);
begin
  if FAlignment <> Value then begin
    FAlignment := Value;
    RecreateWnd(Self);
  end;
end;

procedure TCustomLinkLabel.SetUseVisualStyle(const Value: Boolean);
begin
  if FUseVisualStyle <> Value then begin
    FUseVisualStyle := Value;
    RecreateWnd(Self);
  end;
end;
{$ENDIF}

{ TNewLinkLabel }

function TNewLinkLabel.AdjustHeight: Integer;
var
  OldHeight: Integer;
  IdealSize: TSize;
begin
  OldHeight := Height;
  { According to the documentation LM_GETIDEALSIZE always succeeds }
  SendMessage(Handle, LM_GETIDEALSIZE, Width, LPARAM(@IdealSize));
  Height := IdealSize.cy;
  Result := Height - OldHeight;
end;

{$IFDEF VCLSTYLES}

{ TNewButtonStyleHook - same as Vcl.StdCtrls' TButtonStyleHook except that for command links it:
  -Adds support for measuring height
  -Fixes RTL support for CommandLinkHint
  -Actually flips the text and icons on RTL
  -Improves alignment of shield icons, especially at high dpi
  -Avoids drawing empty notes
  -Respects the font of the control
  -Properly centers glyphs vertically on the first text line
  For other button styles it just calls the original code, and the code for those styles is not copied here }

class function TNewButtonStyleHook.DrawOrMeasureCommandLink(const Draw: Boolean;
  const Control: TNewButton; const LStyle: TCustomStyleServices; const FPressed: Boolean;
  const ACanvas: TCanvas; const AMouseInControl: Boolean): Integer;
var
  Details:  TThemedElementDetails;
  LParentRect, DrawRect, R, RSingleLine: TRect;
  LIsRightToLeft: Boolean;
  IL: BUTTON_IMAGELIST;
  IW, IH: Integer;
  TextFormat: TTextFormatFlags;
  ThemeTextColor: TColor;
  Buffer: string;
  BufferLength: Integer;
  ImgIndex: Integer;
  BCaption: String;
  IsDefault: Boolean;
  IsElevationRequired: Boolean;
  LPPI: Integer;
begin
  const Handle = Control.Handle;

  LPPI := Control.CurrentPPI;

  LParentRect := Control.ClientRect;
  LIsRightToLeft := Control.IsRightToLeft;

  BCaption := Control.Caption;
  ImgIndex := 0;
  IsDefault := Control.Active;
  IsElevationRequired := CheckWin32Version(6, 0) and Control.ElevationRequired;
  if not Control.Enabled then
  begin
    Details := LStyle.GetElementDetails(tbPushButtonDisabled);
    ImgIndex := 3;
  end
  else
  if FPressed then
  begin
    Details := LStyle.GetElementDetails(tbPushButtonPressed);
    ImgIndex := 2;
  end
  else if AMouseInControl then
  begin
    Details := LStyle.GetElementDetails(tbPushButtonHot);
    ImgIndex := 1;
  end
  else if Control.Focused or IsDefault then
  begin
    Details := LStyle.GetElementDetails(tbPushButtonDefaulted);
    ImgIndex := 4;
  end
  else if Control.Enabled then
    Details := LStyle.GetElementDetails(tbPushButtonNormal);

  DrawRect := LParentRect;
  if Draw then
    LStyle.DrawElement(ACanvas.Handle, Details, DrawRect);

  IW := MulDiv(35, LPPI, Screen.DefaultPixelsPerInch);
  Inc(DrawRect.Left, IW);
  Inc(DrawRect.Top, 15);
  Inc(DrawRect.Left, 5);
  ACanvas.Font := Control.Font;
  R := DrawRect;
  TextFormat := TTextFormatFlags(UINT(Control.DrawTextBiDiModeFlags(Integer(DT_LEFT or DT_WORDBREAK or DT_CALCRECT))));
  LStyle.DrawText(ACanvas.Handle, Details, BCaption, R, TextFormat, ACanvas.Font.Color); { R is used directly below for measuring, and later also for the note }
  Result := R.Bottom;
  if Draw then begin
    RSingleLine := DrawRect;
    TextFormat := TTextFormatFlags(UINT(Control.DrawTextBiDiModeFlags(Integer(DT_LEFT or DT_SINGLELINE or DT_CALCRECT))));
    LStyle.DrawText(ACanvas.Handle, Details, BCaption, RSingleLine, TextFormat, ACanvas.Font.Color); { RSingleLine is used below for the glyphs }
    { Following does not use any DT_CALCRECT results }
    TextFormat := TTextFormatFlags(UINT(Control.DrawTextBiDiModeFlags(Integer(DT_LEFT or DT_WORDBREAK))));
    if (seFont in Control.StyleElements) and LStyle.GetElementColor(Details, ecTextColor, ThemeTextColor) then
      ACanvas.Font.Color := ThemeTextColor;
    var R2 := DrawRect;
    FlipRect(R2, LParentRect, LIsRightToLeft);
    LStyle.DrawText(ACanvas.Handle, Details, BCaption, R2, TextFormat, ACanvas.Font.Color);
  end;
  SetLength(Buffer, Button_GetNoteLength(Handle) + 1);
  if Length(Buffer) > 1 then
  begin
    BufferLength := Length(Buffer);
    if Button_GetNote(Handle, PChar(Buffer), BufferLength) then { BufferLength is a var parameter with an undocumented value on success }
    begin
      SetLength(Buffer, Length(Buffer) - 1);
      Inc(DrawRect.Top, R.Height + 2); { R is the DT_CALCRECT result } 
      ACanvas.Font.Height := MulDiv(ACanvas.Font.Height, 2, 3);
      R := DrawRect;
      TextFormat := TTextFormatFlags(UINT(Control.DrawTextBiDiModeFlags(Integer(DT_LEFT or DT_WORDBREAK or DT_CALCRECT))));
      LStyle.DrawText(ACanvas.Handle, Details, Buffer, R, TextFormat, ACanvas.Font.Color);  { R is used directly below for measuring }
      if R.Bottom > Result then
        Result := R.Bottom;
      if Draw then begin
        { Following does not use any DT_CALCRECT results }
        TextFormat := TTextFormatFlags(UINT(Control.DrawTextBiDiModeFlags(Integer(DT_LEFT or DT_WORDBREAK))));
        FlipRect(DrawRect, LParentRect, LIsRightToLeft);
        LStyle.DrawText(ACanvas.Handle, Details, Buffer, DrawRect, TextFormat, ACanvas.Font.Color);
      end;
    end;
  end;

  Inc(Result, 15);

  if not Draw then
    Exit;

  if Button_GetImageList(handle, IL) and (IL.himl <> 0) and
     ImageList_GetIconSize(IL.himl, IW, IH) then
  begin
    R.Left := 2;
    R.Top := RSingleLine.Top + (RSingleLine.Height - IH) div 2;
    if IsElevationRequired then
    begin
      ImgIndex := 0;
      Inc(R.Left, MulDiv(8, LPPI, Screen.DefaultPixelsPerInch));
    end;
    R.Right := R.Left + IW;
    R.Bottom := R.Top + IH;
    FlipRect(R, LParentRect, LIsRightToLeft);
    ImageList_Draw(IL.himl, ImgIndex, ACanvas.Handle, R.Left, R.Top, ILD_NORMAL);
  end else begin
    if not Control.Enabled then
      Details := LStyle.GetElementDetails(tbCommandLinkGlyphDisabled)
    else
    if FPressed then
      Details := LStyle.GetElementDetails(tbCommandLinkGlyphPressed)
    else if Control.Focused then
      Details := LStyle.GetElementDetails(tbCommandLinkGlyphDefaulted)
    else if AMouseInControl then
      Details := LStyle.GetElementDetails(tbCommandLinkGlyphHot)
    else
      Details := LStyle.GetElementDetails(tbCommandLinkGlyphNormal);

    DrawRect.Right := IW;
    DrawRect.Left := 3;
    DrawRect.Top := RSingleLine.Top + (RSingleLine.Height - IW) div 2;
    DrawRect.Bottom := DrawRect.Top + IW;
    if LIsRightToLeft then begin
      FlipRect(DrawRect, LParentRect, True);
      var FlipBitmap := TBitmap.Create;
      try
        FlipBitmap.Width := DrawRect.Width;
        FlipBitmap.Height := DrawRect.Height;
        BitBlt(FlipBitmap.Canvas.Handle, 0, 0, DrawRect.Width, DrawRect.Height, ACanvas.Handle, DrawRect.Left, DrawRect.Top, SRCCOPY);
        LStyle.DrawElement(FlipBitmap.Canvas.Handle, Details, Rect(0, 0, DrawRect.Width, DrawRect.Height), nil, LPPI);
        StretchBlt(ACanvas.Handle, DrawRect.Left, DrawRect.Top, DrawRect.Width, DrawRect.Height,
          FlipBitmap.Canvas.Handle, FlipBitmap.Width-1, 0, -FlipBitmap.Width, FlipBitmap.Height, SRCCOPY);
      finally
        FlipBitmap.Free;
      end;
    end else
      LStyle.DrawElement(ACanvas.Handle, Details, DrawRect, nil, LPPI);
  end;
end;

class function TNewButtonStyleHook.GetIdealHeightIfCommandLink(const Control: TNewButton; const Style: TCustomStyleServices): Integer;
begin
  const Canvas = TCanvas.Create;
  try
    Canvas.Handle := GetDC(0);
    try
      Result := DrawOrMeasureCommandLink(False, Control, Style, False, Canvas, False);
    finally
      ReleaseDC(0, Canvas.Handle);
    end;
  finally
    Canvas.Handle := 0;
    Canvas.Free;
  end;
end;

procedure TNewButtonStyleHook.DrawButton(ACanvas: TCanvas; AMouseInControl: Boolean);
begin
  const LControlStyle = GetWindowLong(Handle, GWL_STYLE);
  if (LControlStyle and BS_COMMANDLINK) <> BS_COMMANDLINK then begin
    inherited;
    Exit;
  end;

  DrawOrMeasureCommandLink(True, TNewButton(Control), StyleServices, FPressed, ACanvas, AMouseInControl);
end;

{$ENDIF}

end.
