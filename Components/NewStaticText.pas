unit NewStaticText;

{
  TNewStaticText - similar to TStaticText but with multi-line AutoSize
  support and a WordWrap property.

  Define VCLSTYLES for full VCL Styles support, and for transparency support.
}

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms,
  {$IFDEF FPC} LCLType, LMessages, StdCtrls,
  {$ELSE} {$IFDEF VCLSTYLES} Vcl.Themes, {$ELSE} Themes, {$ENDIF} {$ENDIF}
  Graphics;

{$IFDEF VCLSTYLES}
  {$DEFINE TRANSPARENCYSUPPORT}
{$ENDIF}

type
  {$IFDEF FPC}
  TStaticTextStyleElement = (seFont, seClient, seBorder);
  TStaticTextStyleElements = set of TStaticTextStyleElement;
  {$ENDIF}

  TNewStaticText = class({$IFDEF FPC}TCustomStaticText{$ELSE}TWinControl{$ENDIF})
  private
    {$IFNDEF FPC}
    FAlignment: TAlignment;
    FFocusControl: TWinControl;
    FShowAccelChar: Boolean;
    {$ENDIF}
    FAutoSize: Boolean;
    FForceLTRReading: Boolean;
    FLastAdjustBoundsRTL: Boolean;
    {$IF not Defined(FPC) and not Defined(TRANSPARENCYSUPPORT)}
    FTransparent: Boolean;
    {$IFEND}
    FWordWrap: Boolean;
    {$IFDEF FPC}
    FStyleElements: TStaticTextStyleElements;
    procedure SetStyleElements(const Value: TStaticTextStyleElements);
    procedure RemoveInheritedStyleColor;
    {$ENDIF}
    {$IFNDEF FPC}
    class constructor Create;
    class destructor Destroy;
    {$IFDEF TRANSPARENCYSUPPORT}
    procedure CNCtlColorStatic(var Message: TWMCtlColorStatic); message CN_CTLCOLORSTATIC;
    {$ENDIF}
    procedure CMDialogChar(var Message: TCMDialogChar); message CM_DIALOGCHAR;
    {$ENDIF}
    procedure CMFontChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF}); message CM_FONTCHANGED;
    procedure CMParentFontChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF}); message CM_PARENTFONTCHANGED;
    procedure CMTextChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF}); message CM_TEXTCHANGED;
    procedure AdjustBounds;
    function CalcBounds: TPoint;
    function GetDrawTextFlags: UINT;
    {$IFNDEF FPC}
    procedure SetAlignment(Value: TAlignment);
    procedure SetFocusControl(Value: TWinControl);
    procedure SetShowAccelChar(Value: Boolean);
    procedure SetTransparent(const Value: Boolean);
    function GetTransparent: Boolean;
    {$ENDIF}
    procedure SetForceLTRReading(Value: Boolean);
    procedure SetWordWrap(Value: Boolean);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Loaded; override;
    {$IFDEF FPC}
    procedure SetShowAccelChar(Value: Boolean); override;
    {$ELSE}
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    {$ENDIF}
    procedure SetAutoSize(Value: Boolean); override;
  public
    {$IFDEF FPC}
    class var InheritedStyleColor: TColor;
    {$ENDIF}
    constructor Create(AOwner: TComponent); override;
    function AdjustHeight: Integer;
    {$IFDEF FPC}
    function UseRightToLeftReading: Boolean; override;
    {$ELSE}
    function GetControlsAlignment: TAlignment; override;
    {$ENDIF}
  published
    property Align;
    {$IFDEF FPC}
    property Alignment;
    {$ELSE}
    property Alignment: TAlignment read FAlignment write SetAlignment
      default taLeftJustify;
    {$ENDIF}
    property Anchors;
    property AutoSize: Boolean read FAutoSize write SetAutoSize default True;
    property Caption;
    property Color;
    property DragCursor;
    property DragMode;
    property Enabled;
    {$IFDEF FPC} property FocusControl; {$ELSE}
    property FocusControl: TWinControl read FFocusControl write SetFocusControl;
    {$ENDIF}
    property Font;
    property ForceLTRReading: Boolean read FForceLTRReading write SetForceLTRReading
      default False;
    property ParentColor;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    {$IFDEF FPC} property ShowAccelChar; {$ELSE}
    property ShowAccelChar: Boolean read FShowAccelChar write SetShowAccelChar
      default True;
    {$ENDIF}
    property ShowHint;
    {$IFDEF FPC}
    property StyleElements: TStaticTextStyleElements read FStyleElements write SetStyleElements
      default [seFont, seClient, seBorder];
    {$ELSE}
    property StyleElements;
    property StyleName;
    {$ENDIF}
    property TabOrder;
    property TabStop;
    {$IFDEF FPC} property Transparent; {$ELSE}
    property Transparent: Boolean read GetTransparent write SetTransparent
      default True;
    {$ENDIF}
    property Visible;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    property OnClick;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDrag;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnStartDrag;
  end;

  {$IFNDEF FPC}
  TNewStaticTextStyleHook = class(TStyleHook)
{$IFDEF VCLSTYLES}
  strict protected
    procedure Paint(Canvas: TCanvas); override;
  public
    constructor Create(AControl: TWinControl); override;
{$ENDIF}
  end;
  {$ENDIF}

procedure Register;

implementation

uses
  {$IFNDEF FPC}StdCtrls,{$ENDIF} Types, BidiUtils;

procedure Register;
begin
  RegisterComponents('JR', [TNewStaticText]);
end;

{ TNewStaticText }

{$IFNDEF FPC}
class constructor TNewStaticText.Create;
begin
  TCustomStyleEngine.RegisterStyleHook(TNewStaticText, TNewStaticTextStyleHook);
end;

{$ENDIF}

constructor TNewStaticText.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  {$IFDEF FPC}
  FStyleElements := [seFont, seClient, seBorder];
  {$ELSE}
  ControlStyle := [csCaptureMouse, csClickEvents, csSetCaption,
    csReplicatable, csDoubleClicks, csGestures {$IF RtlVersion >= 35.0}, csNeedsDesignDisabledState{$ENDIF}];
  {$IFNDEF TRANSPARENCYSUPPORT}
  ControlStyle := ControlStyle + [csOpaque];
  FTransparent := True;  { Even though Transparent is ignored, we still want it to work as if it isn't at design time }
  {$ENDIF}
  FShowAccelChar := True;
  {$ENDIF}
  Width := 65;
  Height := 17;
  FAutoSize := True;
  AdjustBounds;
end;

procedure TNewStaticText.CreateParams(var Params: TCreateParams);
{$IFNDEF FPC}
const
  Alignments: array[Boolean, TAlignment] of DWORD =
    ((SS_LEFT, SS_RIGHT, SS_CENTER), (SS_RIGHT, SS_LEFT, SS_CENTER));
{$ENDIF}
begin
  inherited CreateParams(Params);
  {$IFDEF FPC}
  { The Win32 LCL widget already creates the STATIC window and sets its alignment }
  if (Alignment = taLeftJustify) and not FWordWrap then
    Params.Style := Params.Style or SS_LEFTNOWORDWRAP;
  {$ELSE}
  CreateSubClass(Params, 'STATIC');
  with Params do
  begin
    const AlignmentStyle = Alignments[UseRightToLeftAlignment, FAlignment];
    Style := Style or SS_NOTIFY or AlignmentStyle;
    { Quirk: There are no SS_RIGHTNOWORDWRAP and SS_CENTERNOWORDWRAP styles.
      WordWrap=False still affects AdjustBounds, though. }
    if (AlignmentStyle = SS_LEFT) and not FWordWrap then Style := Style or SS_LEFTNOWORDWRAP;
    if not FShowAccelChar then Style := Style or SS_NOPREFIX;
    if FForceLTRReading then ExStyle := ExStyle and not WS_EX_RTLREADING;
    WindowClass.style := WindowClass.style and not CS_VREDRAW;
  end;
  {$ENDIF}
end;

{$IFNDEF FPC}
class destructor TNewStaticText.Destroy;
begin
  TCustomStyleEngine.UnregisterStyleHook(TNewStaticText, TNewStaticTextStyleHook);
end;

procedure TNewStaticText.CMDialogChar(var Message: TCMDialogChar);
begin
  if (FFocusControl <> nil) and Enabled and ShowAccelChar and
    IsAccel(Message.CharCode, Caption) then
    with FFocusControl do
      if CanFocus then
      begin
        SetFocus;
        Message.Result := 1;
      end;
end;

{$ENDIF}

procedure TNewStaticText.CMFontChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF});
begin
  inherited;
  AdjustBounds;
end;

{$IFDEF FPC}
procedure TNewStaticText.RemoveInheritedStyleColor;
begin
  if not (seFont in FStyleElements) and ParentFont and
     (InheritedStyleColor <> clNone) and (Font.Color = InheritedStyleColor) then
    Font.Color := clWindowText;
end;

procedure TNewStaticText.SetStyleElements(const Value: TStaticTextStyleElements);
begin
  if FStyleElements <> Value then begin
    FStyleElements := Value;
    RemoveInheritedStyleColor;
    Invalidate;
  end;
end;
{$ENDIF}

procedure TNewStaticText.CMParentFontChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF});
begin
  inherited;
  {$IFDEF FPC}
  RemoveInheritedStyleColor;
  {$ENDIF}
  { What we're really trapping here is changes to Parent. Recalculate size
    if the new Parent's RTL setting is different. }
  if IsRightToLeft <> FLastAdjustBoundsRTL then
    AdjustBounds;
end;

procedure TNewStaticText.CMTextChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF});
begin
  inherited;
  Invalidate;
  AdjustBounds;
end;

procedure TNewStaticText.Loaded;
begin
  inherited Loaded;
  AdjustBounds;
end;

{$IFDEF FPC}
function TNewStaticText.UseRightToLeftReading: Boolean;
begin
  Result := not FForceLTRReading and inherited UseRightToLeftReading;
end;
{$ELSE}
function TNewStaticText.GetControlsAlignment: TAlignment;
begin
  { This is needed to suppress the WS_EX_RIGHT style when BiDiMode is
    bdRightToLeft and Alignment is not taLeftJustify }
  Result := FAlignment;
end;

{$ENDIF}

function TNewStaticText.GetDrawTextFlags: UINT;
const
  Alignments: array[Boolean, TAlignment] of Word =
    ((DT_LEFT, DT_RIGHT, DT_CENTER), (DT_RIGHT, DT_LEFT, DT_CENTER));
var
  AlignmentFlag: UINT;
begin
  AlignmentFlag := Alignments[UseRightToLeftAlignment, Alignment];
  Result := DT_EXPANDTABS or DT_NOCLIP or AlignmentFlag;
  if FWordWrap then Result := Result or DT_WORDBREAK;
  if not ShowAccelChar then Result := Result or DT_NOPREFIX;
  if UseRightToLeftReading then begin
    { Note: DT_RTLREADING must be included even when just calculating the
      size, since on certain fonts it can affect the width of characters.
      (Consider the Hebrew string: 'a '#$F9' b'. On 2000 with Lucida Console
      as the font, the spaces aren't drawn as wide with RTLREADING.) }
    if not FForceLTRReading then
      Result := Result or DT_RTLREADING;
  end;
end;

function TNewStaticText.CalcBounds: TPoint;
var
  R: TRect;
  S: String;
  DC: HDC;
begin
  { Note: The calculated width/height is actually one pixel wider/taller
    than the size of the text, so that when Enabled=False the white shadow
    does not get clipped }
  R := Rect(0, 0, Width, 0);
  if R.Right > 0 then Dec(R.Right);

  S := {$IFDEF FPC}UTF8Decode(Caption){$ELSE}Caption{$ENDIF};
  if (S = '') or (ShowAccelChar and (S[1] = '&') and (Length(S) = 1)) then
    S := S + ' ';

  DC := GetDC(0);
  try
    SelectObject(DC, Font.Handle);
    DrawTextW(DC, PWideChar(S), Length(S), R, DT_CALCRECT or GetDrawTextFlags);
  finally
    ReleaseDC(0, DC);
  end;

  Result.X := R.Right + 1;
  Result.Y := R.Bottom + 1;
end;

procedure TNewStaticText.AdjustBounds;
var
  NewBounds: TPoint;
  NewLeft, NewWidth: Integer;
begin
  if not (csLoading in ComponentState) and FAutoSize then
  begin
    FLastAdjustBoundsRTL := IsRightToLeft;

    NewBounds := CalcBounds;

    NewLeft := Left;
    NewWidth := Width;
    if not FWordWrap then begin
      NewWidth := NewBounds.X;
      if IsParentFlipped(Self) then
        Inc(NewLeft, Width - NewWidth);
    end;
    SetBounds(NewLeft, Top, NewWidth, NewBounds.Y);
  end;
end;

function TNewStaticText.AdjustHeight: Integer;
var
  OldHeight: Integer;
begin
  OldHeight := Height;
  Height := CalcBounds.Y;
  Result := Height - OldHeight;
end;

{$IFNDEF FPC}
procedure TNewStaticText.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FFocusControl) then
    FFocusControl := nil;
end;

procedure TNewStaticText.SetAlignment(Value: TAlignment);
begin
  if FAlignment <> Value then
  begin
    FAlignment := Value;
    RecreateWnd;
  end;
end;

{$ENDIF}

procedure TNewStaticText.SetAutoSize(Value: Boolean);
begin
  if FAutoSize <> Value then
  begin
    FAutoSize := Value;
    if Value then AdjustBounds;
  end;
end;

{$IFNDEF FPC}
procedure TNewStaticText.SetFocusControl(Value: TWinControl);
begin
  FFocusControl := Value;
  if Value <> nil then Value.FreeNotification(Self);
end;

{$ENDIF}

procedure TNewStaticText.SetForceLTRReading(Value: Boolean);
begin
  if FForceLTRReading <> Value then begin
    FForceLTRReading := Value;
    {$IFDEF FPC}RecreateWnd(Self){$ELSE}RecreateWnd{$ENDIF};
    AdjustBounds;
  end;
end;

procedure TNewStaticText.SetShowAccelChar(Value: Boolean);
begin
  {$IFDEF FPC}
  if ShowAccelChar <> Value then begin
    inherited SetShowAccelChar(Value);
    AdjustBounds;
  end;
  {$ELSE}
  if FShowAccelChar <> Value then
  begin
    FShowAccelChar := Value;
    RecreateWnd;
    AdjustBounds;
  end;
  {$ENDIF}
end;

{$IFDEF TRANSPARENCYSUPPORT}
procedure TNewStaticText.CNCtlColorStatic(var Message: TWMCtlColorStatic);
begin
  { Vcl.StdCtrls' TCustomStaticText.CNCtlColorStatic uses StyleServices(Self).Enabled
    instead of IsCustomStyleActive, but that can return True even when no style is active,
    which is undesirable because when no style is active the inherited call is required to
    support the Font and Brush colors }
  if IsCustomStyleActive and Transparent then
  begin
    SetBkMode(Message.ChildDC, Windows.TRANSPARENT);
    StyleServices(Self).DrawParentBackground(Handle, Message.ChildDC, nil, False);
    { Return an empty brush to prevent Windows from overpainting what we just have created. }
    Message.Result := LRESULT(GetStockObject(NULL_BRUSH));
  end
  else
    inherited;
end;
{$ENDIF}

{$IFNDEF FPC}
procedure TNewStaticText.SetTransparent(const Value: Boolean);
begin
{$IFDEF TRANSPARENCYSUPPORT}
  if Transparent <> Value then
  begin
    if Value then
      ControlStyle := ControlStyle - [csOpaque]
    else
      ControlStyle := ControlStyle + [csOpaque];
    Invalidate;
  end;
{$ELSE}
  FTransparent := Value;
{$ENDIF}
end;

function TNewStaticText.GetTransparent: Boolean;
begin
{$IFDEF TRANSPARENCYSUPPORT}
  Result := not (csOpaque in ControlStyle);
{$ELSE}
  Result := FTransparent;
{$ENDIF}
end;

{$ENDIF}

procedure TNewStaticText.SetWordWrap(Value: Boolean);
begin
  if FWordWrap <> Value then
  begin
    FWordWrap := Value;
    {$IFDEF FPC}RecreateWnd(Self){$ELSE}RecreateWnd{$ENDIF};
    AdjustBounds;
  end;
end;

{$IFDEF VCLSTYLES}

{ TNewStaticTextStyleHook - same as Vcl.StdCtrls' TStaticTextStyleHook
  except that it accesses the Control property as a TNewStaticText instead
  of a TCustomStaticText or TStaticText, and that it uses the control's
  Color property }

constructor TNewStaticTextStyleHook.Create(AControl: TWinControl);
begin
  inherited;
  OverridePaint := True;
  OverrideEraseBkgnd := True;
  PaintOnEraseBkgnd := True;
  DoubleBuffered := True;
end;

procedure TNewStaticTextStyleHook.Paint(Canvas: TCanvas);
const
  States: array[Boolean] of TThemedTextLabel = (ttlTextLabelDisabled, ttlTextLabelNormal);
var
  Details: TThemedElementDetails;
  R: TRect;
  S: String;
  LStyle: TCustomStyleServices;
begin
  LStyle := StyleServices;

  if LStyle.Available then begin
    R := Control.ClientRect;
    {$IFDEF TRANSPARENCYSUPPORT}
    if TNewStaticText(Control).Transparent then begin
      Details := LStyle.GetElementDetails(tbCheckBoxUncheckedNormal);
      LStyle.DrawParentBackground(Handle, Canvas.Handle, Details, False);
      Canvas.Brush.Style := bsClear;
    end else {$ENDIF} begin
      Canvas.Brush.Color := TNewStaticText(Control).Color;
      Canvas.FillRect(R);
    end;
    Details := LStyle.GetElementDetails(States[Control.Enabled]);
    S := TNewStaticText(Control).Caption;
    if (S = '') or (TNewStaticText(Control).ShowAccelChar and (S[1] = '&') and (Length(S) = 1)) then
      S := S + ' ';
    if seFont in Control.StyleElements then
      DrawControlText(Canvas, Details, S, R, TNewStaticText(Control).GetDrawTextFlags)
    else begin
      Canvas.Font := TNewStaticText(Control).Font;
      DrawText(Canvas.Handle, S, Length(S), R, TNewStaticText(Control).GetDrawTextFlags);
    end;
  end;
end;

{$ENDIF}

end.
