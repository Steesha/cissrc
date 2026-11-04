unit Setup.SetupForm;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  TSetupForm, a TUIStateForm descendant

  Also used by UninstallProgressForm and UninstallSharedFileForm!

  Requires following globals to be set:
  -IsDarkInstallMode
  -LangOptions.RightToLeft
  -LangOptions.DialogFontName
  -LangOptions.DialogFontSize
  -LangOptions.DialogFontBaseScaleWidth
  -LangOptions.DialogFontBaseScaleHeight
  -SetupHeader.WizardLightControlStyling
  -shWizardKeepAspectRatio in SetupHeader.Options
  Also requires following globals to be set, but 0 is allowed:
  -SetupHeader.WizardSizePercentX
  -SetupHeader.WizardSizePercentY
}

interface

uses
  Windows, MultiMon, SysUtils, Messages, Classes, Graphics, Controls, Forms,
  {$IFDEF FPC}LCLType, LMessages,{$ENDIF}
  UIStateForm, {$IFDEF FPC}BitmapImage,{$ENDIF}
  Setup.MainFunc;

type
  TSetupForm = class(TUIStateForm)
  private
    FOrigBaseUnitX, FOrigBaseUnitY: Integer;
    FBaseUnitX, FBaseUnitY: Integer;
    FRightToLeft: Boolean;
    FFlipControlsOnShow: Boolean;
    FCenterOnShow: Boolean;
    FControlsFlipped: Boolean;
    FKeepSizeX, FKeepSizeY: Boolean;
    FOrigClientWidthAfterScale, FOrigClientHeightAfterScale: Integer;
    FSetForeground: Boolean;
    {$IFDEF FPC}
    FBackgroundImage: TBitmapImageImplementation;
    FBackgroundImageInitialized: Boolean;
    {$ENDIF}
    {$IFNDEF FPC}
    FDidDisableChildControlsStylesAsNeeded: Boolean;
    class function ShouldDisableControlStylesAsNeeded: Boolean; static;
    class procedure DisableControlStyleAsNeeded(const Ctl: TControl); static;
    {$ENDIF}
    procedure CMShowingChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF}); message CM_SHOWINGCHANGED;
    procedure WMQueryEndSession(var Message: TWMQueryEndSession); message WM_QUERYENDSESSION;
  protected
    {$IFDEF FPC}
    procedure ActiveChanged; override;
    procedure Paint; override;
    {$ENDIF}
    procedure Center;
    procedure CenterInsideControl(const Ctl: TWinControl;
      const InsideClientArea: Boolean);
    procedure CenterInsideRect(const InsideRect: TRect);
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    function GetExtraClientWidth: Integer;
    function GetExtraClientHeight: Integer;
    procedure VisibleChanging; override;
    procedure WndProc(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF}); override;
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    {$IFDEF FPC}destructor Destroy; override;{$ENDIF}
    function CalculateButtonWidth(const ButtonCaptions: array of String): Integer;
    function CalculateButtonWidthWithExtraWidths(const ButtonCaptions: array of String;
      const ExtraWidths: array of Integer): Integer;
    procedure InitializeFont(const KeepSizeX: Boolean = False; const KeepSizeY: Boolean = False);
    class function ScalePixelsX(const OrigBaseUnitX, BaseUnitX, N: Integer): Integer; overload; static;
    class function ScalePixelsY(const OrigBaseUnitY, BaseUnitY, N: Integer): Integer; overload; static;
    class procedure SetCtlParent(const AControl: TControl; const AParent: TWinControl); static;
    function ScalePixelsX(const N: Integer): Integer; overload;
    function ScalePixelsY(const N: Integer): Integer; overload;
    procedure SetBackImage(const BackImages: TWizardImages; const Stretch, Center: Boolean; const Opacity: Byte; const Redraw: Boolean); overload;
    function ShouldSizeX: Boolean;
    function ShouldSizeY: Boolean;
    function ShowModal: Integer; override;
    procedure FlipAndCenterIfNeeded(const ACenterInsideControl: Boolean = False;
      const CenterInsideControlCtl: TWinControl = nil;
      const CenterInsideControlInsideClientArea: Boolean = False); virtual;
    property BaseUnitX: Integer read FBaseUnitX;
  published
    property CenterOnShow: Boolean read FCenterOnShow write FCenterOnShow;
    property ControlsFlipped: Boolean read FControlsFlipped;
    property ExtraClientWidth: Integer read GetExtraClientWidth;
    property ExtraClientHeight: Integer read GetExtraClientHeight;
    property FlipControlsOnShow: Boolean read FFlipControlsOnShow write FFlipControlsOnShow;
    property KeepSizeX: Boolean read FKeepSizeX;
    property KeepSizeY: Boolean read FKeepSizeY;
    property RightToLeft: Boolean read FRightToLeft;
    property SetForeground: Boolean read FSetForeground write FSetForeground;
  end;

procedure CalculateBaseUnitsFromFont(const Font: TFont; var X, Y: Integer);
function SetFontNameSize(const AFont: TFont; const AName: String;
  const ASize: Integer; const AFallbackName: String;
  const AFallbackSize: Integer): Boolean;

{$IFDEF FPC}
function HasActiveLclStyle: Boolean;
procedure ApplyVclStyleFormColors(var BackgroundColor: Integer; const DynamicDark: Boolean);
{$ENDIF}

implementation

uses
  Generics.Collections, {$IFNDEF FPC}UITypes, WinXPanels,{$ENDIF} Themes, StdCtrls, ExtCtrls,
  BidiUtils, BitmapButton, {$IFNDEF FPC}BitmapImage,{$ENDIF} NewNotebook, NewStaticText, NewCheckListBox, {$IFNDEF FPC}FormBackgroundStyleHook,{$ENDIF}
  Shared.Struct, Shared.CommonFunc, Shared.CommonFunc.Vcl,
  Setup.InstFunc{$IFDEF FPC}, Shared.VclStyle, IntfGraphics, GraphType, FPImage, NewCtrls, NewProgressBar, ComCtrls, CommCtrl, DwmApi{$ENDIF};

{$IFDEF FPC}
type
  TStyleCheckKind = (sckCheckBox, sckRadio);
  TStyleCheckAccess = class(TCustomCheckBox);
  TStyleListColor = (slcWindow, slcWindowText, slcDisabledText, slcSelection, slcSelectionText);
  TStyleProgressAxis = pbHorizontal..pbVertical;

  TStyleClientImage = record
    Bitmap: TBitmap;
    Region: TVclStyleBitmapRegion;
  end;
{$ENDIF}

{$IFDEF FPC}
const
  StyleListSystemColors: array[TStyleListColor] of TColor =
    (clWindow, clWindowText, clGrayText, clHighlight, clHighlightText);
{$ENDIF}

var
  WM_QueryCancelAutoPlay: UINT;
  {$IFDEF FPC}
  LclStyleActive: Boolean;
  StyleFormTextColor: TColor = clNone;
  StyleClientImages: array[Boolean] of TStyleClientImage;
  StyleBorderImages: array[Boolean, TVclStyleBorderPart] of TStyleClientImage;
  HasStyleBorderImages: Boolean;
  StyleTitleImages: array[Boolean] of TStyleClientImage;
  StyleTitleTextColors: array[Boolean] of TColor;
  StyleCaptionButtons: array[TVclStyleCaptionButton, TVclStyleBitmapState] of TStyleClientImage;
  HasStyleCaptionButtons: Boolean;
  StyleButtonImages: array[TVclStyleBitmapState] of TStyleClientImage;
  StyleButtonTextColors: array[TVclStyleBitmapState] of TColor;
  StyleCheckImages: array[TStyleCheckKind, TCheckBoxState, TVclStyleBitmapState] of TStyleClientImage;
  StyleCheckText: array[TStyleCheckKind, TVclStyleBitmapState] of TColor;
  StyleListColors: array[TStyleListColor] of TColor;
  StyleEditWindowBrush, StyleEditFaceBrush: TBrush;
  StyleProgressFrames: array[TStyleProgressAxis] of TStyleClientImage;
  StyleProgressFills: array[TStyleProgressAxis, TNewProgressBarState] of TStyleClientImage;
  StyleProgressBackground: TColor;
  {$ENDIF}

{$IFDEF FPC}
function LoadStyleImage(const Decoded: TStream; const Assets: TVclStyleAssets;
  const Regions: TVclStyleBitmapRegions; const Background: TColor;
  const ObjectPath: String; const State: TVclStyleBitmapState;
  const TintColorRef: Cardinal = 0; const TintOpacity: Byte = 0;
  const AllowCenter: Boolean = False; const PreserveAlpha: Boolean = False): TStyleClientImage;
var
  Region: TVclStyleBitmapRegion;
  Atlas: TVclStyleBitmap;
  Image: TLazIntfImage;
  Description: TRawImageDescription;
  RowData: TBytes;
  Color: TFPColor;
  X, Y, Width, Height, Pixel: Integer;
  BackgroundColorRef: Cardinal;
  HasVisiblePixels: Boolean;
begin
  Result := Default(TStyleClientImage);
  for Region in Regions do begin
    if (Region.ObjectPath <> ObjectPath) or (Region.State <> State) or
       ((Region.TileStyle <> 'tsTile') and (Region.TileStyle <> 'tsStretch') and
        (not AllowCenter or (Region.TileStyle <> 'tsCenter'))) then
      Continue;
    Atlas := Assets.Bitmaps[Region.BitmapIndex];
    Width := Region.Bounds.Right - Region.Bounds.Left;
    Height := Region.Bounds.Bottom - Region.Bounds.Top;
    if (Region.Margins.Left < 0) or (Region.Margins.Top < 0) or
       (Region.Margins.Right < 0) or (Region.Margins.Bottom < 0) or
       (Int64(Region.Margins.Left) + Region.Margins.Right >= Width) or
       (Int64(Region.Margins.Top) + Region.Margins.Bottom >= Height) then
      Continue;
    if (Region.BorderTileStyle <> '') and (Region.BorderTileStyle <> 'tsTile') and
       (Region.BorderTileStyle <> 'tsStretch') and (not AllowCenter or
        (Region.BorderTileStyle <> 'tsCenter')) then
      Continue;
    SetLength(RowData, Width * 4);
    BackgroundColorRef := Cardinal(ColorToRGB(Background));
    Image := TLazIntfImage.Create(0, 0);
    try
      Description.Init_BPP32_B8G8R8A8_BIO_TTB(Width, Height);
      Image.DataDescription := Description;
      HasVisiblePixels := False;
      for Y := 0 to Height - 1 do begin
        ReadVclStyleBitmapRow(Decoded, Atlas, Region.Bounds.Left, Region.Bounds.Top + Y,
          RowData, BackgroundColorRef, TintColorRef, TintOpacity, PreserveAlpha);
        for X := 0 to Width - 1 do begin
          Pixel := X * 4;
          Color.Alpha := RowData[Pixel + 3] * 257;
          HasVisiblePixels := HasVisiblePixels or (Color.Alpha <> 0);
          Color.Blue := RowData[Pixel] * 257;
          Color.Green := RowData[Pixel + 1] * 257;
          Color.Red := RowData[Pixel + 2] * 257;
          Image.Colors[X, Y] := Color;
        end;
      end;
      if not HasVisiblePixels then
        Continue;
      Result.Bitmap := TBitmap.Create;
      try
        Result.Bitmap.LoadFromIntfImage(Image);
        Result.Region := Region;
      except
        FreeAndNil(Result.Bitmap);
        raise;
      end;
      Exit;
    finally
      Image.Free;
    end;
  end;
end;

procedure ClearStyleButtonImages;
var
  State: TVclStyleBitmapState;
begin
  for State := Low(State) to High(State) do
    FreeAndNil(StyleButtonImages[State].Bitmap);
end;

procedure LoadStyleButtonImages(const Decoded: TStream; const Assets: TVclStyleAssets;
  const BackgroundColor: TColor);
var
  Regions: TVclStyleBitmapRegions;
  State: TVclStyleBitmapState;
  Color, Fallback: TColor;
  TextColors: TVclStyleTextColors;
  PaletteName: String;

  function SystemColor(const Name: String; const Fallback: TColor): TColor;
  begin
    Result := StringToColorDef(UTF8Encode(ReadVclStyleSystemColor(Decoded, Assets, Name)), Fallback);
    if (Result = clNone) or (Result = clDefault) then
      Result := Fallback;
  end;

begin
  Regions := ReadVclStyleBitmapRegions(Decoded, Assets, 'Button', 'Button.Text', TextColors);
  if Length(Regions) = 0 then
    Exit;
  Color := BackgroundColor;
  if Color = clNone then
    Color := SystemColor('clWindow', clBtnFace);
  for State := Low(State) to High(State) do begin
    if State = vbsDisabled then
      Fallback := SystemColor('clGrayText', clGrayText)
    else if State = vbsNormal then
      Fallback := SystemColor('clBtnText', clBtnText)
    else
      Fallback := StyleButtonTextColors[vbsNormal];
    PaletteName := TextColors[State];
    if PaletteName = '' then
      StyleButtonTextColors[State] := Fallback
    else begin
      StyleButtonTextColors[State] := SystemColor(PaletteName,
        StringToColorDef(UTF8Encode(PaletteName), Fallback));
      if (StyleButtonTextColors[State] = clNone) or (StyleButtonTextColors[State] = clDefault) then
        StyleButtonTextColors[State] := Fallback;
    end;
    StyleButtonImages[State] := LoadStyleImage(Decoded, Assets, Regions, Color, 'Button.Face', State);
  end;
end;

function GetStyleCheckListColor(const Color: TColor): TColor;
var
  Entry: TStyleListColor;
begin
  for Entry := Low(Entry) to High(Entry) do
    if Color = StyleListSystemColors[Entry] then
      Exit(StyleListColors[Entry]);
  Result := Color;
end;

procedure LoadStyleCheckListColors(const Decoded: TStream; const Assets: TVclStyleAssets);
const
  Names: array[TStyleListColor] of String =
    ('clWindow', 'clWindowText', 'clGrayText', 'clHighlight', 'clHighlightText');
var
  Entry: TStyleListColor;
  Color: TColor;
  HasColors: Boolean;
begin
  HasColors := False;
  for Entry := Low(Entry) to High(Entry) do begin
    Color := StringToColorDef(UTF8Encode(ReadVclStyleSystemColor(Decoded, Assets, Names[Entry])), clNone);
    if (Color = clDefault) and (Entry = slcSelectionText) then
      Color := StyleListColors[slcWindowText]
    else if (Color = clNone) or (Color = clDefault) then
      Color := StyleListSystemColors[Entry]
    else
      HasColors := True;
    StyleListColors[Entry] := Color;
  end;
  if HasColors then
    ResolveCheckListStyleColor := @GetStyleCheckListColor;
end;

function GetStyleEditBrush(const Background, Foreground: TColor;
  out TextColor, BackColor: TColor): HBRUSH;
var
  Brush: TBrush;
begin
  if Background = clBtnFace then
    Brush := StyleEditFaceBrush
  else if (Background = clWindow) or (Background = clDefault) then
    Brush := StyleEditWindowBrush
  else
    Exit(0);
  if Brush = nil then
    Exit(0);
  BackColor := Brush.Color;
  TextColor := Foreground;
  if (TextColor = clWindowText) or (TextColor = clDefault) or (TextColor = StyleFormTextColor) then
    TextColor := GetStyleCheckListColor(clWindowText);
  Result := Brush.Handle;
end;

procedure ClearStyleEditColors;
begin
  ResolveEditStyleBrush := nil;
  FreeAndNil(StyleEditWindowBrush);
  FreeAndNil(StyleEditFaceBrush);
end;

procedure LoadStyleEditColors(const Decoded: TStream; const Assets: TVclStyleAssets);
var
  FaceColor: TColor;
begin
  if not Assigned(ResolveCheckListStyleColor) then
    Exit;
  StyleEditWindowBrush := TBrush.Create;
  StyleEditWindowBrush.Color := GetStyleCheckListColor(clWindow);
  FaceColor := StringToColorDef(UTF8Encode(ReadVclStyleSystemColor(Decoded, Assets, 'clBtnFace')), clBtnFace);
  if (FaceColor = clDefault) or (FaceColor = clNone) then
    FaceColor := clBtnFace;
  StyleEditFaceBrush := TBrush.Create;
  StyleEditFaceBrush.Color := FaceColor;
  ResolveEditStyleBrush := @GetStyleEditBrush;
end;

procedure ClearStyleCheckImages;
var
  Kind: TStyleCheckKind;
  Check: TCheckBoxState;
  State: TVclStyleBitmapState;
begin
  for Kind := Low(Kind) to High(Kind) do
    for Check := Low(Check) to High(Check) do
      for State := Low(State) to High(State) do
        FreeAndNil(StyleCheckImages[Kind, Check, State].Bitmap);
end;

procedure LoadStyleCheckImages(const Decoded: TStream; const Assets: TVclStyleAssets);
const
  Roots: array[TStyleCheckKind] of String = ('CheckBox', 'RadioButton');
  CheckNames: array[TCheckBoxState] of String = ('Unchecked', 'Checked', 'Mixed');
var
  Kind: TStyleCheckKind;
  Check: TCheckBoxState;
  State: TVclStyleBitmapState;
  Regions: TVclStyleBitmapRegions;
  TextColors: TVclStyleTextColors;
  Name, Palette: String;
  Fallback: TColor;
begin
  for Kind := Low(Kind) to High(Kind) do begin
    Regions := ReadVclStyleBitmapRegions(Decoded, Assets, Roots[Kind], Roots[Kind] + '.Text', TextColors);
    if Length(Regions) = 0 then
      Continue;
    for State := Low(State) to High(State) do begin
      Name := TextColors[State];
      if Name = '' then
        Name := TextColors[vbsNormal];
      Fallback := clWindowText;
      if State = vbsDisabled then
        Fallback := clGrayText;
      Palette := ReadVclStyleSystemColor(Decoded, Assets, Name);
      if Palette <> '' then
        Name := Palette;
      StyleCheckText[Kind, State] := StringToColorDef(UTF8Encode(Name), Fallback);
      if (StyleCheckText[Kind, State] = clNone) or (StyleCheckText[Kind, State] = clDefault) then
        StyleCheckText[Kind, State] := Fallback;
      for Check := Low(Check) to High(Check) do
        StyleCheckImages[Kind, Check, State] := LoadStyleImage(Decoded, Assets, Regions,
          clWindow, Roots[Kind] + '.' + CheckNames[Check], State, 0, 0, True, True);
    end;
  end;
end;

procedure DrawSetupStyleProgressBar(const ProgressBar: TNewProgressBar; const DC: HDC); forward;

procedure ClearStyleProgressImages;
var
  Orientation: TStyleProgressAxis;
  State: TNewProgressBarState;
begin
  DrawNewProgressBarStyle := nil;
  NewProgressBarStyleOrientations := [];
  for Orientation := Low(Orientation) to High(Orientation) do begin
    FreeAndNil(StyleProgressFrames[Orientation].Bitmap);
    for State := Low(State) to High(State) do
      FreeAndNil(StyleProgressFills[Orientation, State].Bitmap);
  end;
end;

procedure LoadStyleProgressImages(const Decoded: TStream; const Assets: TVclStyleAssets;
  const BackgroundColor: TColor);
const
  Frames: array[TStyleProgressAxis] of String = ('ProgressBar.Frame', 'ProgressBar.FrameVert');
  Fills: array[TStyleProgressAxis] of String = ('ProgressBar.BarHorz', 'ProgressBar.BarVert');
  Tints: array[TNewProgressBarState] of TColor = (clNone, clRed, clYellow);
var
  Regions: TVclStyleBitmapRegions;
  Orientation: TStyleProgressAxis;
  State: TNewProgressBarState;
  Opacity: Byte;
  Tint: Cardinal;
begin
  Regions := ReadVclStyleBitmapRegions(Decoded, Assets, 'ProgressBar');
  if Length(Regions) = 0 then
    Exit;
  StyleProgressBackground := BackgroundColor;
  if StyleProgressBackground = clNone then
    StyleProgressBackground := StringToColorDef(
      UTF8Encode(ReadVclStyleSystemColor(Decoded, Assets, 'clWindow')), clBtnFace);
  if (StyleProgressBackground = clDefault) or (StyleProgressBackground = clNone) then
    StyleProgressBackground := clBtnFace;
  for Orientation := Low(Orientation) to High(Orientation) do begin
    StyleProgressFrames[Orientation] := LoadStyleImage(Decoded, Assets, Regions,
      StyleProgressBackground, Frames[Orientation], vbsNormal);
    if StyleProgressFrames[Orientation].Bitmap = nil then
      Continue;
    for State := Low(State) to High(State) do begin
      Opacity := 0;
      Tint := 0;
      if State <> npbsNormal then begin
        Opacity := 130;
        Tint := ColorToRGB(Tints[State]);
      end;
      StyleProgressFills[Orientation, State] := LoadStyleImage(Decoded, Assets, Regions,
        StyleProgressBackground, Fills[Orientation], vbsNormal, Tint, Opacity);
    end;
    if StyleProgressFills[Orientation, npbsNormal].Bitmap <> nil then
      Include(NewProgressBarStyleOrientations, Orientation);
  end;
  if pbHorizontal in NewProgressBarStyleOrientations then
    Include(NewProgressBarStyleOrientations, pbRightToLeft);
  if pbVertical in NewProgressBarStyleOrientations then
    Include(NewProgressBarStyleOrientations, pbTopDown);
  if NewProgressBarStyleOrientations <> [] then
    DrawNewProgressBarStyle := @DrawSetupStyleProgressBar;
end;

function SetupStyleBorderSubclass(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM;
  SubclassID: UINT_PTR; RefData: DWORD_PTR): LRESULT; stdcall; forward;

procedure ClearStyleBorderImages;
var
  Active: Boolean;
  Part: TVclStyleBorderPart;
  Button: TVclStyleCaptionButton;
  State: TVclStyleBitmapState;
begin
  HasStyleBorderImages := False;
  HasStyleCaptionButtons := False;
  for Button := Low(Button) to High(Button) do
    for State := Low(State) to High(State) do
      FreeAndNil(StyleCaptionButtons[Button, State].Bitmap);
  for Active := False to True do begin
    FreeAndNil(StyleTitleImages[Active].Bitmap);
    for Part := Low(Part) to High(Part) do
      FreeAndNil(StyleBorderImages[Active, Part].Bitmap);
  end;
end;

procedure LoadStyleBorderImages(const Decoded: TStream; const Assets: TVclStyleAssets;
  const Regions: TVclStyleBitmapRegions; const TextColors: TVclStyleTextColors);
const
  Paths: array[TVclStyleBorderPart] of String =
    ('Form.Image.LeftBorder', 'Form.Image.RightBorder', 'Form.Image.BottomBorder');
  ButtonNames: array[TVclStyleCaptionButton] of String = ('btnMin', 'btnMax', 'btnHelp', 'btnClose', 'btnRes');
  ButtonPath = 'Form.Image.Title.Caption.sysButtons.';
var
  Part: TVclStyleBorderPart;
  Button: TVclStyleCaptionButton;
  Active: Boolean;
  State: TVclStyleBitmapState;
  Background, Fallback: TColor;
  Name, PaletteColor: String;
begin
  for Active := False to True do begin
    if Active then begin
      State := vbsActive;
      Background := clActiveCaption;
      Fallback := clCaptionText;
    end else begin
      State := vbsNormal;
      Background := clInactiveCaption;
      Fallback := clInactiveCaptionText;
    end;
    StyleTitleImages[Active] := LoadStyleImage(Decoded, Assets, Regions, Background,
      'Form.Image.Title', State);
    Name := TextColors[State];
    if Name = '' then
      Name := TextColors[vbsNormal];
    if Name <> '' then begin
      PaletteColor := ReadVclStyleSystemColor(Decoded, Assets, Name);
      if PaletteColor <> '' then
        Name := PaletteColor;
    end;
    StyleTitleTextColors[Active] := StringToColorDef(UTF8Encode(Name), Fallback);
    if (StyleTitleTextColors[Active] = clNone) or (StyleTitleTextColors[Active] = clDefault) then
      StyleTitleTextColors[Active] := Fallback;
    HasStyleBorderImages := HasStyleBorderImages or (StyleTitleImages[Active].Bitmap <> nil);
  end;
  for Part := Low(Part) to High(Part) do begin
    StyleBorderImages[False, Part] := LoadStyleImage(Decoded, Assets, Regions,
      clInactiveBorder, Paths[Part], vbsNormal);
    StyleBorderImages[True, Part] := LoadStyleImage(Decoded, Assets, Regions,
      clActiveBorder, Paths[Part], vbsActive);
    HasStyleBorderImages := HasStyleBorderImages or (StyleBorderImages[False, Part].Bitmap <> nil) or
      (StyleBorderImages[True, Part].Bitmap <> nil);
  end;
  for Button := Low(Button) to High(Button) do
    for State := Low(State) to High(State) do begin
      if State = vbsNormal then
        Background := clInactiveCaption
      else
        Background := clActiveCaption;
      StyleCaptionButtons[Button, State] := LoadStyleImage(Decoded, Assets, Regions,
        Background, ButtonPath + ButtonNames[Button], State, 0, 0, True);
      HasStyleCaptionButtons := HasStyleCaptionButtons or (StyleCaptionButtons[Button, State].Bitmap <> nil);
    end;
  HasStyleBorderImages := HasStyleBorderImages or HasStyleCaptionButtons;
end;

function HasActiveLclStyle: Boolean;
begin
  Result := LclStyleActive;
end;

procedure ApplyVclStyleFormColors(var BackgroundColor: Integer; const DynamicDark: Boolean);
var
  ResourceName: String;
  Style: TResourceStream;
  Decoded: TMemoryStream;
  Info: TVclStyleInfo;
  Assets: TVclStyleAssets;
  Regions: TVclStyleBitmapRegions;
  TitleTextColors: TVclStyleTextColors;
  BackgroundName, ForegroundName, PaletteColor: String;
  Color: TColor;
begin
  LclStyleActive := False;
  StyleFormTextColor := clNone;
  TNewStaticText.InheritedStyleColor := clNone;
  FreeAndNil(StyleClientImages[False].Bitmap);
  FreeAndNil(StyleClientImages[True].Bitmap);
  ClearStyleButtonImages;
  ClearStyleCheckImages;
  ResolveCheckListStyleColor := nil;
  ClearStyleEditColors;
  ClearStyleProgressImages;
  ClearStyleBorderImages;
  ResourceName := 'MYSTYLE1';
  if DynamicDark then
    ResourceName := 'MYSTYLE1_DARK';
  if FindResourceW(HInstance, PWideChar(ResourceName), 'VCLSTYLE') = 0 then
    Exit;
  try
    Style := TResourceStream.Create(HInstance, UTF8Encode(ResourceName), PAnsiChar('VCLSTYLE'));
    try
      Decoded := TMemoryStream.Create;
      try
        ReadVclStyle(Style, Decoded, Info);
        ReadVclStyleAssets(Decoded, Assets);
        LclStyleActive := True;
        try
          LoadStyleButtonImages(Decoded, Assets, BackgroundColor);
        except
          on EVclStyleError do
            ClearStyleButtonImages;
          on EStreamError do
            ClearStyleButtonImages;
        end;
        try
          LoadStyleCheckListColors(Decoded, Assets);
        except
          on EVclStyleError do
            ResolveCheckListStyleColor := nil;
          on EStreamError do
            ResolveCheckListStyleColor := nil;
        end;
        try
          LoadStyleEditColors(Decoded, Assets);
        except
          on EVclStyleError do
            ClearStyleEditColors;
          on EStreamError do
            ClearStyleEditColors;
        end;
        try
          LoadStyleCheckImages(Decoded, Assets);
        except
          on EVclStyleError do
            ClearStyleCheckImages;
          on EStreamError do
            ClearStyleCheckImages;
        end;
        try
          LoadStyleProgressImages(Decoded, Assets, BackgroundColor);
        except
          on EVclStyleError do
            ClearStyleProgressImages;
          on EStreamError do
            ClearStyleProgressImages;
        end;
        Regions := ReadVclStyleBitmapRegions(Decoded, Assets, 'Form', 'Form.Image.Title.Caption', TitleTextColors);
        if shWizardBorderStyled in SetupHeader.Options then
          try
            LoadStyleBorderImages(Decoded, Assets, Regions, TitleTextColors);
          except
            on EVclStyleError do
              ClearStyleBorderImages;
            on EStreamError do
              ClearStyleBorderImages;
          end;
        if BackgroundColor <> clNone then
          Exit;
        ReadVclStyleFormColors(Decoded, Assets, BackgroundName, ForegroundName);
        Color := StringToColorDef(UTF8Encode(BackgroundName), clNone);
        if (Color <> clNone) and (Color <> clDefault) then begin
          BackgroundColor := Color;
          Color := StringToColorDef(UTF8Encode(ForegroundName), clNone);
          if Color <> clDefault then
            StyleFormTextColor := Color;
          if Color = clWindowText then begin
            PaletteColor := ReadVclStyleSystemColor(Decoded, Assets, ForegroundName);
            Color := StringToColorDef(UTF8Encode(PaletteColor), clNone);
            if (Color = clNone) or (Color = clDefault) then
              Exit;
          end;
          StyleClientImages[False] := LoadStyleImage(Decoded, Assets, Regions, BackgroundColor, 'Form.Image.Client', vbsNormal);
          StyleClientImages[True] := LoadStyleImage(Decoded, Assets, Regions, BackgroundColor, 'Form.Image.Client', vbsActive);
          if (StyleClientImages[False].Bitmap <> nil) or (StyleClientImages[True].Bitmap <> nil) then
            StyleFormTextColor := Color;
        end;
      finally
        Decoded.Free;
      end;
    finally
      Style.Free;
    end;
  except
    on EVclStyleError do
      LclStyleActive := False;
    on EStreamError do
      LclStyleActive := False;
    on EResNotFound do
      LclStyleActive := False;
  end;
end;
{$ENDIF}

function GetRectOfPrimaryMonitor(const WorkArea: Boolean): TRect;
begin
  if not WorkArea or
     not SystemParametersInfo(SPI_GETWORKAREA, 0, @Result, 0) then
    Result := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
end;

function SetFontNameSize(const AFont: TFont; const AName: String;
  const ASize: Integer; const AFallbackName: String;
  const AFallbackSize: Integer): Boolean;
{ Returns True if AName <> '' and it used AName as the font name,
  False otherwise. }

  function SizeToHeight(const S: Integer): Integer;
  begin
    Result := MulDiv(-S, Screen.PixelsPerInch, 72);
  end;

begin
  Result := False;
  if AName <> '' then begin
    if FontExists(AName) then begin
      AFont.Name := AName;
      AFont.Height := SizeToHeight(ASize);
      Result := True;
      Exit;
    end;
    { Note: AFallbackName is not used if the user specified an empty string for
      AName because in that case they want the default font used always }
    if (AFallbackName <> '') and FontExists(AFallbackName) then begin
      AFont.Name := AFallbackName;
      AFont.Height := SizeToHeight(AFallbackSize);
      Exit;
    end;
  end;
  AFont.Name := 'Segoe UI';
  AFont.Height := SizeToHeight(AFallbackSize);
end;

procedure CalculateBaseUnitsFromFont(const Font: TFont; var X, Y: Integer);
var
  DC: HDC;
  Size: TSize;
  TM: Windows.TTextMetricW;
begin
  DC := GetDC(0);
  try
    SelectObject(DC, Font.Handle);
    { Based on code from Q145994: }
    GetTextExtentPoint(DC,
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', 52, Size);
    X := (Size.cx div 26 + 1) div 2;
    GetTextMetricsW(DC, {$IFDEF FPC}@{$ENDIF}TM);
    Y := TM.tmHeight;
  finally
    ReleaseDC(0, DC);
  end;
end;

function IsParentSetupFormFlipped(AControl: TControl): Boolean;

  function GetParentSetupForm(AControl: TControl): TSetupForm;
  begin
    { Note: Unlike GetParentForm, this checks all levels, not just the top }
    repeat
      if AControl is TSetupForm then begin
        Result := TSetupForm(AControl);
        Exit;
      end;
      AControl := AControl.Parent;
    until AControl = nil;
    Result := nil;
  end;

var
  ParentForm: TSetupForm;
begin
  ParentForm := GetParentSetupForm(AControl);
  if Assigned(ParentForm) then
    Result := ParentForm.ControlsFlipped
  else
    Result := False;
end;

function GetPPI(const Wnd: HWND): Integer;
begin
  {$IFNDEF FPC}
  { Based on TSysStyleHook.GetCurrentPPI }
  if CheckPerMonitorV2SupportForWindow(Wnd) then begin { Currently always False in Setup }
    { GetDPIForWindow requires Windows 10 version 1607. However, because it is delay-loaded and it's
      never executed on older versions of Windows, it does not cause entry point not found errors. }
    Result := Integer(GetDPIForWindow(Wnd))
  end else
  {$ENDIF}
    Result := Screen.PixelsPerInch;
end;

{ TSetupForm }

constructor TSetupForm.Create(AOwner: TComponent);
begin
  { Must initialize FRightToLeft here in addition to CreateNew because
    CreateNew isn't virtual on Delphi 2 and 3 }
  FRightToLeft := LangOptions.RightToLeft;
  FFlipControlsOnShow := FRightToLeft;
  FCenterOnShow := True;
  inherited;
   { Setting BidiMode before inherited causes an AV when TControl tries to
     send CM_BIDIMODECHANGED. This is why we have additional RTL code in
     CreateParams below. }
  if FRightToLeft then
    BiDiMode := bdRightToLeft;
  { In Delphi 2005 and later, Position defaults to poDefaultPosOnly, but we
    don't want the form to be changing positions whenever its handle is
    recreated, so change it to the D7 and earlier default of poDesigned. }
  if Position = poDefaultPosOnly then
    Position := poDesigned;
end;

constructor TSetupForm.CreateNew(AOwner: TComponent; Dummy: Integer = 0);
begin
  { Note: On Delphi 2 and 3, CreateNew isn't virtual, so this is only reached
    when TSetupForm.CreateNew is called explicitly }
  FRightToLeft := LangOptions.RightToLeft;
  FFlipControlsOnShow := FRightToLeft;
  FCenterOnShow := True;
  inherited;
  if FRightToLeft then
    BiDiMode := bdRightToLeft;
end;

function TSetupForm.CalculateButtonWidth(const ButtonCaptions: array of String): Integer;
begin
  Result := CalculateButtonWidthWithExtraWidths(ButtonCaptions, []);
end;

function TSetupForm.CalculateButtonWidthWithExtraWidths(const ButtonCaptions: array of String;
  const ExtraWidths: array of Integer): Integer;
var
  DC: HDC;
  I, W: Integer;
begin
  { Also see TIDEForm.CalculateButtonWidth }
  Result := ScalePixelsX(75);
  { Increase the button size if there are unusually long button captions }
  DC := GetDC(0);
  try
    SelectObject(DC, Font.Handle);
    for I := Low(ButtonCaptions) to High(ButtonCaptions) do begin
      W := GetTextWidth(DC, ButtonCaptions[I], True) + ScalePixelsX(20);
      if I <= High(ExtraWidths) then
        Inc(W, ExtraWidths[I]);
      if Result < W then
        Result := W;
    end;
  finally
    ReleaseDC(0, DC);
  end;
end;

procedure TSetupForm.CenterInsideControl(const Ctl: TWinControl;
  const InsideClientArea: Boolean);
var
  R: TRect;
  CtlForm: TCustomForm;
begin
  CtlForm := GetParentForm(Ctl);
  if (CtlForm = nil) or not IsWindowVisible(CtlForm.Handle) or
     IsIconic(CtlForm.Handle) then begin
    Center;
    Exit;
  end;

  if not InsideClientArea then begin
    if GetWindowRect(Ctl.Handle, R) then
      CenterInsideRect(R);
  end
  else begin
    R := Ctl.ClientRect;
    MapWindowPoints(Ctl.Handle, 0, R, 2);
    CenterInsideRect(R);
  end;
end;

procedure TSetupForm.CenterInsideRect(const InsideRect: TRect);

  function GetRectOfMonitorContainingRect(const R: TRect): TRect;
  { Returns bounding rectangle of monitor containing or nearest to R }
  var
    Info: TMonitorInfo;
    M: HMONITOR;
  begin
    M := MonitorFromRect(@R, MONITOR_DEFAULTTONEAREST);
    Info.cbSize := SizeOf(Info);
    if GetMonitorInfo(M, @Info) then
      Result := Info.rcWork
    else
      Result := GetRectOfPrimaryMonitor(True);
  end;

var
  R, MR: TRect;
begin
  R := Bounds(InsideRect.Left + ((InsideRect.Right - InsideRect.Left) - Width) div 2,
    InsideRect.Top + ((InsideRect.Bottom - InsideRect.Top) - Height) div 2,
    Width, Height);

  { Clip to nearest monitor }
  MR := GetRectOfMonitorContainingRect(R);
  if R.Right > MR.Right then
    OffsetRect(R, MR.Right - R.Right, 0);
  if R.Bottom > MR.Bottom then
    OffsetRect(R, 0, MR.Bottom - R.Bottom);
  if R.Left < MR.Left then
    OffsetRect(R, MR.Left - R.Left, 0);
  if R.Top < MR.Top then
    OffsetRect(R, 0, MR.Top - R.Top);

  BoundsRect := R;
end;

procedure TSetupForm.Center;
begin
  CenterInsideRect(GetRectOfPrimaryMonitor(True));
end;

procedure TSetupForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  { With Application.MainFormOnTaskBar=True, by default, a form won't get a
    taskbar button if the main form hasn't been created yet (due to the owner
    being an invisible Application.Handle), or if the main form exists but
    isn't visible (e.g., because it's a silent install). Force it to have a
    taskbar button in those cases by specifying no owner for the window.
    (Another method is to set WS_EX_APPWINDOW and leave WndParent set to
    Application.Handle, but it doesn't quite work correctly: if the form
    displays a message box, and you activate another app's window, clicking on
    the form's taskbar button activates the message box again, but the taskbar
    button doesn't change to a "selected" state.) }
  if (Params.WndParent <> 0) and
     (Application.MainFormOnTaskBar or (Params.WndParent <> Application.Handle)) and
     not IsWindowOnTaskbar(Params.WndParent) then
    Params.WndParent := 0;

  { See comment in Create. Also: The following does not make the title bar RTL.
    Achieving this requires adding WS_EX_LAYOUTRTL, which VCL does not support. }
  if FRightToLeft then
    Params.ExStyle := Params.ExStyle or (WS_EX_RTLREADING or WS_EX_LEFTSCROLLBAR or WS_EX_RIGHT);
end;

{$IFNDEF FPC}
class function TSetupForm.ShouldDisableControlStylesAsNeeded: Boolean;
begin
  Result := not IsDarkInstallMode and (SetupHeader.WizardLightControlStyling <> wcsAll);
  if Result then begin
    const LStyle = StyleServices;
    Result := LStyle.Enabled and not LStyle.IsSystemStyle;
  end;
end;

class procedure TSetupForm.DisableControlStyleAsNeeded(const Ctl: TControl);
{ Call ShouldDisableControlStylesAsNeeded first }
begin
  { SetupHeader.WizardLightControlStyling is either wcsAllButButtons or wcsOnlyRequired,
    so for buttons the style must always be disabled. }
  if Ctl is TCustomButton then
    Ctl.StyleName := TStyleManager.SystemStyleName
  else if SetupHeader.WizardLightControlStyling = wcsOnlyRequired then begin
    if (Ctl is TNewCheckListBox) and TNewCheckListBox(Ctl).TransparentIfStyled then begin
      { Requires VCL Styles for transparency, but can be told to use native checkboxes and radiobuttons }
      TNewCheckListBox(Ctl).DisableStyledButtons := True;
    end else begin
      const KeepStyle =
        (Ctl is TCustomPanel) or
        (Ctl is TBitmapButton) or (Ctl is TBitmapImage) or             { Don't use VCL Styles }
        (Ctl is TNewNotebook) or (Ctl is TNewNotebookPage) or          { Don't use VCL Styles }
        ((Ctl is TNewStaticText) and TNewStaticText(Ctl).Transparent); { Requires VCL Styles for transparency }
      if not KeepStyle then
        Ctl.StyleName := TStyleManager.SystemStyleName;
    end;
  end;
end;

{$ENDIF}

{$IFDEF FPC}
procedure EnableSetupStyleNonClientPainting(const Wnd: HWND);
var
  Value: BOOL;
  Loaded: Boolean;
begin
  if not SetWindowSubclass(Wnd, @SetupStyleBorderSubclass, 0, 0) then
    Exit;
  Loaded := InitDwmLibrary;
  try
    if Loaded and Assigned(DwmSetWindowAttribute) then begin
      Value := True;
      DwmSetWindowAttribute(Wnd, DWMWA_ALLOW_NCPAINT, @Value, SizeOf(Value));
    end;
  finally
    FreeDwmLibrary;
  end;
end;
{$ENDIF}

procedure TSetupForm.CreateWnd;
{$IFNDEF FPC}

  procedure DisableChildControlsStylesAsNeeded(const ParentCtl: TWinControl);
  { Call ShouldDisableControlStylesAsNeeded first }
  begin
    for var I := 0 to ParentCtl.ControlCount-1 do begin
      const Ctl = ParentCtl.Controls[I];

      if Ctl is TWinControl then begin
        const WinCtl = Ctl as TWinControl;
        { Sanity check that the control's handle isn't already allocated,
          because otherwise it would run TWinControl.UpdateStyleElements
          which does a RecreateWnd. Might work but isn't efficient. }
        if WinCtl.HandleAllocated then
          InternalError('Unexpected HandleAllocated');
        { Update children }
        DisableChildControlsStylesAsNeeded(WinCtl);
      end;

      { Update self }
      DisableControlStyleAsNeeded(Ctl);
    end;
  end;

  procedure SetControlsCurrentPPI(const Ctl: TWinControl; const PPI: Integer);
  begin
    for var I := 0 to Ctl.ControlCount-1 do begin
      const C = Ctl.Controls[I];
      if C is TWinControl then begin
        SetControlsCurrentPPI(TWinControl(C), PPI);
        C.SetCurrentPPI(PPI);
      end else
        C.SetCurrentPPI(PPI)
    end;
  end;

{$ENDIF}
begin
  {$IFNDEF FPC}
  { DisableChildControlsStylesAsNeeded works both before and after
    calling inherited. But it does require the child controls to have
    no handle allocated, which is why it's in CreateWnd and not in
    Create: in Create it can't be before inherited since it wouldn't
    yet know about the children, and also not after since the
    handles might be allocated. }
  if ShouldDisableControlStylesAsNeeded and not FDidDisableChildControlsStylesAsNeeded then begin
    DisableChildControlsStylesAsNeeded(Self);
    { Don't need to disable again if the window is recreated }
    FDidDisableChildControlsStylesAsNeeded := True;
  end;
  {$ENDIF}

  inherited;

  {$IFDEF FPC}
  if HasStyleBorderImages and (shWizardBorderStyled in SetupHeader.Options) then
    EnableSetupStyleNonClientPainting(Handle);
  {$ENDIF}

  if WM_QueryCancelAutoPlay <> 0 then
    AddToWindowMessageFilterEx(Handle, WM_QueryCancelAutoPlay);

  { SetDarkTitleBar requires Handle to be allocated, which is why we
    we call it after calling inherited. }
  {$IFNDEF FPC}if (TStyleManager.FormBorderStyle = fbsSystemStyle) or not (seBorder in StyleElements) then{$ENDIF}
    SetDarkTitleBar(Self, IsDarkInstallMode);

  {$IFNDEF FPC}

  { We don't use the Scaled property for scaling and this means the CurrentPPI property will not be
    set correctly. This causes problems when VCL code inspects it, for example in THintWindow.CalcHintRect
    and FormStyleHook.GetBorderSize. So we should update it ourselves by directly writing to the
    FCurrentPPI private variable of the form and all controls on it, which we can do using a class
    helper. Note: Doing it later for the form causes issues with incorrect non-client vs. client size
    when styled title bars are enabled. }

  const PPI = GetPPI(Handle);
  SetCurrentPPI(PPI);
  SetControlsCurrentPPI(Self, PPI);

  { Now that CurrentPPI of the form is set you must make sure that any controls you later parent to
    the form already have the same CurrentPPI, otherwise VCL will scale the controls. Currently this
    is done in:
    -Setup.ScriptClasses's TNewNotebookPageNotebook_W
    -TSetupForm.SetCtlParent
    -TWizardForm.AddPage
    To debug/detect scaling add a breakpoint in Vcl.Controls' TWinControl.ChangeScale and set project
    option Building->Delphi Compiler->Compiling->Debugging->Use debug .dcus. }
  {$ENDIF}
end;

function TSetupForm.ShouldSizeX: Boolean;
begin
  Result := not FKeepSizeX and (SetupHeader.WizardSizePercentX > 100);
end;

function TSetupForm.ShouldSizeY: Boolean;
begin
  Result := not FKeepSizeY and (SetupHeader.WizardSizePercentY > 100);
end;

procedure TSetupForm.FlipAndCenterIfNeeded(const ACenterInsideControl: Boolean;
  const CenterInsideControlCtl: TWinControl; const CenterInsideControlInsideClientArea: Boolean);

  procedure FlipControlsIfNeeded;
  begin
    if FFlipControlsOnShow then begin
      FFlipControlsOnShow := False;
      FControlsFlipped := not FControlsFlipped;
      FlipControls(Self);
    end;
  end;

  procedure CenterIfNeeded;
  begin
    if FCenterOnShow then begin
      FCenterOnShow := False;
      { Center }
      if ACenterInsideControl and (CenterInsideControlCtl <> nil) then
        CenterInsideControl(CenterInsideControlCtl, CenterInsideControlInsideClientArea)
      else
        Center;
    end;
  end;

begin
  FlipControlsIfNeeded;
  CenterIfNeeded;
end;

type
  {$IFDEF FPC}
  TWinControlAccess = class(TWinControl);
  {$ELSE}
  TControlAccess = class(TControl);
  {$ENDIF}

procedure TSetupForm.InitializeFont(const KeepSizeX, KeepSizeY: Boolean);
type
  TControlAnchorsList = TDictionary<TControl, TAnchors>;
var
  ControlAnchorsList: TControlAnchorsList;
  R: TRect;
  W, H: Integer;

  procedure NewChangeScale(const Ctl: TControl; const XM, XD, YM, YD: Integer);
  var
    X, Y, W, H: Integer;
  begin
    X := MulDiv(Ctl.Left, XM, XD);
    Y := MulDiv(Ctl.Top, YM, YD);
    if not(csFixedWidth in Ctl.ControlStyle) then
      W := MulDiv(Ctl.Width, XM, XD)
    else
      W := Ctl.Width;
    if not(csFixedHeight in Ctl.ControlStyle) then
      H := MulDiv(Ctl.Height, YM, YD)
    else
      H := Ctl.Height;
    Ctl.SetBounds(X, Y, W, H);
  end;

  procedure NewScaleControls(const Ctl: TWinControl; const XM, XD, YM, YD: Integer);
  { This is like TControl.ScaleControls, except it allows the width and height
    to be scaled independently }
  var
    I: Integer;
    C: TControl;
  begin
    for I := 0 to Ctl.ControlCount-1 do begin
      C := Ctl.Controls[I];
      if C is TWinControl then begin
        TWinControl(C).DisableAlign;
        try
          NewScaleControls(TWinControl(C), XM, XD, YM, YD);
          NewChangeScale(C, XM, XD, YM, YD);
        finally
          TWinControl(C).EnableAlign;
        end;
      end
      else
        NewChangeScale(C, XM, XD, YM, YD);
    end;
  end;

  procedure StripAndStoreChildControlCustomAnchors(const ParentCtl: TControl; const AnchorsList: TControlAnchorsList);
  var
    ParentWinCtl: TWinControl;
    Ctl: TControl;
    I: Integer;
  begin
    if ParentCtl is TWinControl then begin
      ParentWinCtl := TWinControl(ParentCtl);
      for I := 0 to ParentWinCtl.ControlCount-1 do begin
        Ctl := ParentWinCtl.Controls[I];

        if Ctl.Anchors <> [akLeft, akTop] then begin
          AnchorsList.Add(Ctl, Ctl.Anchors);
          {$IFNDEF FPC}
          { Before we can set Anchors to [akLeft, akTop] (which has a special
            'no anchors' meaning to VCL), we first need to update the Explicit*
            properties so the control doesn't get moved back to an old position }
          TControlAccess(Ctl).UpdateExplicitBounds;
          {$ENDIF}
          Ctl.Anchors := [akLeft, akTop];
        end;

        StripAndStoreChildControlCustomAnchors(Ctl, AnchorsList);
      end;
    end;
  end;

  procedure RestoreAnchors(const AnchorsList: TControlAnchorsList);
  var
    Item: TPair<TControl, TAnchors>;
  begin
    { The order in which we restore the anchors shouldn't matter, so just
      enumerate the list }
    for Item in AnchorsList do
      Item.Key.Anchors := Item.Value;
  end;

  function ExcludeFromParentHandlesNeeded(const ParentCtl: TWinControl): Boolean;
  begin
    { Right-aligned TStackPanels are excluded. For example, calling
      HandleNeeded on TaskDialogForm's BottomStackPanel causes it to become
      left-aligned instead of right-aligned. This occurs regardless of the
      timing of the HandleNeeded call, such as before or after sizing. }
    Result := {$IFDEF FPC}False{$ELSE}
      (ParentCtl is TStackPanel) and (TStackPanel(ParentCtl).Align = alRight){$ENDIF};
  end;

  procedure ParentHandlesNeeded(const ParentCtl: TControl);
  var
    ParentWinCtl: TWinControl;
    I: Integer;
  begin
    if ParentCtl is TWinControl then begin
      ParentWinCtl := TWinControl(ParentCtl);
      if (ParentWinCtl.ControlCount > 0) and not ExcludeFromParentHandlesNeeded(ParentWinCtl) then begin
        if not (ParentWinCtl is TNewNotebook) then { For notebooks: only need handles on pages }
          ParentWinCtl.HandleNeeded;
        for I := 0 to ParentWinCtl.ControlCount-1 do
          ParentHandlesNeeded(ParentWinCtl.Controls[I]);
      end;
    end;
  end;

  {$IFDEF FPC}
  procedure LayoutBeforeShow(const ParentCtl: TWinControl);
  var
    Client: TRect;
    I: Integer;
  begin
    Client := ParentCtl.ClientRect;
    TWinControlAccess(ParentCtl).AlignControls(nil, Client);
    for I := 0 to ParentCtl.ControlCount-1 do
      if ParentCtl.Controls[I] is TWinControl then
        LayoutBeforeShow(TWinControl(ParentCtl.Controls[I]));
  end;
  {$ENDIF}

begin
  { Create parent handles.

    Various things related to positioning and anchoring don't work without this:
    you get positions of child controls back as if there was no anchoring until
    handles are automatically created.

    Initially we did this only when sizing the form (for WizardForm it worked if
    done after sizing but for UninstallProgressForm it had be done before sizing,
    for unknown reasons).

    For WizardForm's BeveledLabel though, it needs it before the font name/size
    change (again for unknown reasons), otherwise the label will end up in the
    wrong position, even if all we do is changing the font. Setting AutoSize to
    False also causes it to stay in the correct position. (To see the bad
    positioning for WizardForm.BeveledLabel you would first have to disable next
    ParentHandlesNeeded call and then also the automatic vertical recentering in
    WizardForm.)

    Doing it always, instead of only before or after sizing, also helps
    TaskDialogForm which does its own sizing (so KeepSizeX and KeepSizeY are
    both True), but still needs parent handles to be created to avoid the issue.

    Note: Caller should make sure the created handles do not get lost again. For
    example, setting StyleElements to [] on a parent would cause the handle to
    get deallocated again, and would reintroduce the issue. So this must be done
    before calling us, and not after. }

  ParentHandlesNeeded(Self); { Also see ShowModal }
  {$IFDEF FPC}
  { DFM notebook pages have no stored bounds. Lay them out before scaling so
    restoring child anchors records the actual parent size instead of zero. }
  LayoutBeforeShow(Self);
  {$ENDIF}

  { Set font. Note: Must keep the following lines in synch with Setup.ScriptFunc.HelperFunc's
    InitializeScaleBaseUnits }

  SetFontNameSize(Font, LangOptions.DialogFontName, LangOptions.DialogFontSize, '', 9);
  {$IFDEF FPC}
  TNewStaticText.InheritedStyleColor := StyleFormTextColor;
  if (StyleFormTextColor <> clNone) and (Font.Color = clWindowText) then
    Font.Color := StyleFormTextColor;
  {$ENDIF}

  CalculateBaseUnitsFromFont(Font, FBaseUnitX, FBaseUnitY);

  FOrigBaseUnitX := LangOptions.DialogFontBaseScaleWidth;
  FOrigBaseUnitY := LangOptions.DialogFontBaseScaleHeight;

  if shWizardKeepAspectRatio in SetupHeader.Options then begin
    if FBaseUnitX * FOrigBaseUnitY > FBaseUnitY * FOrigBaseUnitX then begin
      FBaseUnitY := FBaseUnitX;
      FOrigBaseUnitY := FOrigBaseUnitX;
    end else begin
      FBaseUnitX := FBaseUnitY;
      FOrigBaseUnitX := FOrigBaseUnitY;
    end;
  end;

  { Scale }

  if (FBaseUnitX <> FOrigBaseUnitX) or (FBaseUnitY <> FOrigBaseUnitY) then begin
    ControlAnchorsList := TControlAnchorsList.Create;
    try
      { Custom anchors interfere with our scaling code, so strip them and restore
        afterward }
      StripAndStoreChildControlCustomAnchors(Self, ControlAnchorsList);
      { Loosely based on scaling code from TForm.ReadState: }
      NewScaleControls(Self, FBaseUnitX, FOrigBaseUnitX, FBaseUnitY, FOrigBaseUnitY);
      R := ClientRect;
      W := MulDiv(R.Right, FBaseUnitX, FOrigBaseUnitX);
      H := MulDiv(R.Bottom, FBaseUnitY, FOrigBaseUnitY);
      SetBounds(Left, Top, W + (Width - R.Right), H + (Height - R.Bottom));
    finally
      RestoreAnchors(ControlAnchorsList);
      ControlAnchorsList.Free;
    end;
  end;

  { Size }

  FKeepSizeX := KeepSizeX;
  FKeepSizeY := KeepSizeY;
  FOrigClientWidthAfterScale := ClientWidth;
  FOrigClientHeightAfterScale := ClientHeight;

  if ShouldSizeX then
    ClientWidth := MulDiv(ClientWidth, SetupHeader.WizardSizePercentX, 100);
  if ShouldSizeY then
    ClientHeight := MulDiv(ClientHeight, SetupHeader.WizardSizePercentY, 100);
  {$IFDEF FPC}
  { LCL defers alignment of hidden forms, but callers need the final bounds
    during initialization, before the form and its notebook pages are shown. }
  LayoutBeforeShow(Self);
  {$ENDIF}
end;

function TSetupForm.GetExtraClientWidth: Integer;
begin
  Result := ClientWidth - FOrigClientWidthAfterScale;
end;

function TSetupForm.GetExtraClientHeight: Integer;
begin
  Result := ClientHeight - FOrigClientHeightAfterScale;
end;

class function TSetupForm.ScalePixelsX(const OrigBaseUnitX, BaseUnitX, N: Integer): Integer;
begin
  Result := MulDiv(N, BaseUnitX, OrigBaseUnitX);
end;

function TSetupForm.ScalePixelsX(const N: Integer): Integer;
begin
  Result := ScalePixelsX(FOrigBaseUnitX, FBaseUnitX, N);
end;

class function TSetupForm.ScalePixelsY(const OrigBaseUnitY, BaseUnitY, N: Integer): Integer;
begin
  Result := MulDiv(N, BaseUnitY, OrigBaseUnitY);
end;

function TSetupForm.ScalePixelsY(const N: Integer): Integer;
begin
  Result := ScalePixelsY(FOrigBaseUnitY, FBaseUnitY, N);
end;

{$IFDEF FPC}
destructor TSetupForm.Destroy;
begin
  if FBackgroundImageInitialized then
    FBackgroundImage.DeInit;
  inherited;
end;

procedure TSetupForm.ActiveChanged;
begin
  inherited;
  if CustomWizardBackground and (StyleClientImages[True].Bitmap <> nil) then
    Invalidate;
end;

procedure PaintStyleBitmap(const Canvas: TCanvas; const Bounds: TRect;
  const Image: TStyleClientImage);
var
  SourceX, SourceY, DestX, DestY: TVclStyleSliceAxis;
  Column, Row: Integer;
  SourceRect, DestRect: TRect;
  Tile: Boolean;

  procedure PaintSlice(const Source, Dest: TRect; const TileX, TileY: Boolean);
  var
    X, Y, Width, Height, StepX, StepY, CopyWidth, CopyHeight: Integer;
    PartSource, PartDest: TRect;
  begin
    Width := Source.Right - Source.Left;
    Height := Source.Bottom - Source.Top;
    if (Width <= 0) or (Height <= 0) or (Dest.Right <= Dest.Left) or (Dest.Bottom <= Dest.Top) then
      Exit;
    StepX := Dest.Right - Dest.Left;
    StepY := Dest.Bottom - Dest.Top;
    if TileX then
      StepX := Width;
    if TileY then
      StepY := Height;
    Y := Dest.Top;
    while Y < Dest.Bottom do begin
      CopyHeight := StepY;
      if CopyHeight > Dest.Bottom - Y then
        CopyHeight := Dest.Bottom - Y;
      X := Dest.Left;
      while X < Dest.Right do begin
        CopyWidth := StepX;
        if CopyWidth > Dest.Right - X then
          CopyWidth := Dest.Right - X;
        PartSource := Source;
        if TileX then
          PartSource.Right := Source.Left + CopyWidth;
        if TileY then
          PartSource.Bottom := Source.Top + CopyHeight;
        PartDest := Rect(X, Y, X + CopyWidth, Y + CopyHeight);
        Canvas.CopyRect(PartDest, Image.Bitmap.Canvas, PartSource);
        Inc(X, CopyWidth);
      end;
      Inc(Y, CopyHeight);
    end;
  end;

begin
  if (Image.Bitmap = nil) or (Bounds.Right <= Bounds.Left) or (Bounds.Bottom <= Bounds.Top) then
    Exit;
  SourceX := SplitVclStyleAxis(0, Image.Bitmap.Width,
    Image.Region.Margins.Left, Image.Region.Margins.Right);
  SourceY := SplitVclStyleAxis(0, Image.Bitmap.Height,
    Image.Region.Margins.Top, Image.Region.Margins.Bottom);
  DestX := SplitVclStyleAxis(Bounds.Left, Bounds.Right - Bounds.Left,
    Image.Region.Margins.Left, Image.Region.Margins.Right);
  DestY := SplitVclStyleAxis(Bounds.Top, Bounds.Bottom - Bounds.Top,
    Image.Region.Margins.Top, Image.Region.Margins.Bottom);
  for Row := 0 to 2 do
    for Column := 0 to 2 do begin
      SourceRect := Rect(SourceX[Column], SourceY[Row], SourceX[Column + 1], SourceY[Row + 1]);
      DestRect := Rect(DestX[Column], DestY[Row], DestX[Column + 1], DestY[Row + 1]);
      if (Row = 1) and (Column = 1) then
        Tile := Image.Region.TileStyle = 'tsTile'
      else
        Tile := Image.Region.BorderTileStyle = 'tsTile';
      PaintSlice(SourceRect, DestRect, Tile and (Column = 1), Tile and (Row = 1));
    end;
end;

function SetWindowDCLayout(DC: HDC; Layout: DWORD): DWORD; stdcall;
  external 'gdi32.dll' name 'SetLayout';

function DrawCenteredStyleGlyph(const Canvas: TCanvas; const Slot: TRect; const Bitmap: TBitmap): Boolean;
var
  Bounds: TRect;
  Width, Height, SlotWidth, SlotHeight: Integer;
begin
  if (Bitmap = nil) or (Slot.Right <= Slot.Left) or (Slot.Bottom <= Slot.Top) then
    Exit(False);
  Bounds := Slot;
  SlotWidth := Bounds.Right - Bounds.Left;
  SlotHeight := Bounds.Bottom - Bounds.Top;
  Width := Bitmap.Width;
  Height := Bitmap.Height;
  if Width > SlotWidth then begin
    Height := MulDiv(Height, SlotWidth, Width);
    Width := SlotWidth;
  end;
  if Height > SlotHeight then begin
    Width := MulDiv(Width, SlotHeight, Height);
    Height := SlotHeight;
  end;
  if (Width <= 0) or (Height <= 0) then
    Exit(False);
  Inc(Bounds.Left, (SlotWidth - Width) div 2);
  Inc(Bounds.Top, (SlotHeight - Height) div 2);
  Bounds.Right := Bounds.Left + Width;
  Bounds.Bottom := Bounds.Top + Height;
  Canvas.StretchDraw(Bounds, Bitmap);
  Result := True;
end;

procedure PaintSetupStyleCaptionButton(const Canvas: TCanvas; const ScreenWindow, ScreenButton: TRect;
  const Button: TVclStyleCaptionButton; const ButtonFlags: DWORD; const Active, Hot: Boolean);
const
  UnavailableState = $00000001;
  PressedState = $00000008;
  HotTrackedState = $00000080;
var
  State: TVclStyleBitmapState;
  Bitmap: TBitmap;
  Bounds: TRect;
begin
  State := VclStyleCaptionButtonState(Active, Hot or (ButtonFlags and HotTrackedState <> 0),
    ButtonFlags and PressedState <> 0, ButtonFlags and UnavailableState <> 0);
  Bitmap := StyleCaptionButtons[Button, State].Bitmap;
  if (Bitmap = nil) and (State = vbsActive) then
    Bitmap := StyleCaptionButtons[Button, vbsNormal].Bitmap;
  if Bitmap = nil then
    Exit;
  Bounds := ScreenButton;
  OffsetRect(Bounds, -ScreenWindow.Left, -ScreenWindow.Top);
  DrawCenteredStyleGlyph(Canvas, Bounds, Bitmap);
end;

procedure PaintSetupStyleTitle(const Wnd: HWND; const Canvas: TCanvas;
  const ScreenWindow: TRect; const ClientTop: Integer; const Active, Maximized: Boolean);
type
  TExtendedTitleBarInfo = record
    Size: DWORD;
    Title: TRect;
    States: array[0..5] of DWORD;
    Parts: array[0..5] of TRect;
  end;
  TCaptionMetrics = record
    Size: UINT;
    BorderWidth, ScrollWidth, ScrollHeight, CaptionWidth, CaptionHeight: Integer;
    CaptionFont: TLogFontW;
    SmallCaptionWidth, SmallCaptionHeight: Integer;
    SmallCaptionFont: TLogFontW;
    MenuWidth, MenuHeight: Integer;
    MenuFont, StatusFont, MessageFont: TLogFontW;
    PaddedBorderWidth: Integer;
  end;
const
  HiddenState = $00008000 or $00010000;
var
  Info: TExtendedTitleBarInfo;
  CaptionBounds, Button: TRect;
  CaptionButton: TVclStyleCaptionButton;
  Metrics: TCaptionMetrics;
  Caption: String;
  Font: HFONT;
  I, Count, SavedDC: Integer;
  Cursor: TPoint;
  HasCursor: Boolean;
  Flags: Cardinal;
  UseActive, HasButtons: Boolean;
begin
  UseActive := Active and (StyleTitleImages[True].Bitmap <> nil);
  if (StyleTitleImages[UseActive].Bitmap = nil) and not HasStyleCaptionButtons then
    Exit;
  Info := Default(TExtendedTitleBarInfo);
  Info.Size := SizeOf(Info);
  SendMessageW(Wnd, WM_GETTITLEBARINFOEX, 0, LPARAM(@Info));
  CaptionBounds := Info.Title;
  if (Info.States[0] and HiddenState <> 0) or
     (CaptionBounds.Left < ScreenWindow.Left) or (CaptionBounds.Right > ScreenWindow.Right) or
     (CaptionBounds.Top < ScreenWindow.Top) or
     (CaptionBounds.Bottom > ScreenWindow.Top + ClientTop) or
     (CaptionBounds.Right <= CaptionBounds.Left) or (CaptionBounds.Bottom <= CaptionBounds.Top) then
    Exit;
  HasButtons := False;
  HasCursor := GetCursorPos(Cursor);
  for I := 2 to High(Info.Parts) do begin
    Button := Info.Parts[I];
    if (Info.States[I] and HiddenState <> 0) or (Button.Right <= Button.Left) or
       (Button.Bottom <= CaptionBounds.Top) or (Button.Top >= CaptionBounds.Bottom) or
       (Button.Right <= Info.Title.Left) or (Button.Left >= Info.Title.Right) then
      Continue;
    HasButtons := True;
    if GetVclStyleCaptionButton(I, Maximized, CaptionButton) then
      PaintSetupStyleCaptionButton(Canvas, ScreenWindow, Button, CaptionButton,
        Info.States[I], Active, HasCursor and PtInRect(Button, Cursor));
    ExcludeVclStyleTitleButton(CaptionBounds, Info.Title, Button);
  end;
  if (StyleTitleImages[UseActive].Bitmap = nil) or
     (not HasButtons and (GetWindowLongW(Wnd, GWL_STYLE) and WS_SYSMENU <> 0)) or
     (CaptionBounds.Right <= CaptionBounds.Left) then
    Exit;
  OffsetRect(CaptionBounds, -ScreenWindow.Left, -ScreenWindow.Top);

  Metrics := Default(TCaptionMetrics);
  Metrics.Size := SizeOf(Metrics);
  if not SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, SizeOf(Metrics), @Metrics, 0) then
    Exit;
  Font := CreateFontIndirectW(Metrics.CaptionFont);
  if Font = 0 then
    Exit;
  try
    Count := GetWindowTextLengthW(Wnd);
    Caption := '';
    if Count > 0 then begin
      SetLength(Caption, Count + 1);
      SetLength(Caption, GetWindowTextW(Wnd, PWideChar(Caption), Count + 1));
    end;
    SavedDC := SaveDC(Canvas.Handle);
    if SavedDC = 0 then
      Exit;
    try
      PaintStyleBitmap(Canvas, CaptionBounds, StyleTitleImages[UseActive]);
      SelectObject(Canvas.Handle, Font);
      SetBkMode(Canvas.Handle, TRANSPARENT);
      SetTextColor(Canvas.Handle, ColorToRGB(StyleTitleTextColors[Active]));
      InflateRect(CaptionBounds, -2, 0);
      Flags := DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX;
      if GetWindowLongW(Wnd, GWL_EXSTYLE) and (WS_EX_RTLREADING or WS_EX_LAYOUTRTL) <> 0 then
        Flags := Flags or DT_RTLREADING or DT_RIGHT;
      DrawTextW(Canvas.Handle, PWideChar(Caption), Length(Caption), CaptionBounds, Flags);
    finally
      RestoreDC(Canvas.Handle, SavedDC);
    end;
  finally
    DeleteObject(Font);
  end;
end;

procedure PaintSetupStyleBorders(const Wnd: HWND; const Active: Boolean; const CaptionOnly: Boolean = False);
var
  Window, ScreenWindow, Client: TRect;
  Bounds: TVclStyleBorderBounds;
  Part: TVclStyleBorderPart;
  UseActive, Maximized, PaintEdges: Boolean;
  DC: HDC;
  Canvas: TCanvas;
begin
  if not HasStyleBorderImages or IsIconic(Wnd) or
     not GetWindowRect(Wnd, Window) or not GetClientRect(Wnd, Client) then
    Exit;
  SetLastError(0);
  if (MapWindowPoints(Wnd, 0, PPoint(@Client), 2) = 0) and (GetLastError <> 0) then
    Exit;
  ScreenWindow := Window;
  OffsetRect(Client, -Window.Left, -Window.Top);
  OffsetRect(Window, -Window.Left, -Window.Top);
  Maximized := IsZoomed(Wnd);
  PaintEdges := not (CaptionOnly or Maximized);
  if PaintEdges and not GetVclStyleBorderBounds(Window, Client, Bounds) then
    Exit;
  if (Client.Top < 0) or (Client.Top >= Window.Bottom) then
    Exit;
  DC := GetWindowDC(Wnd);
  if DC = 0 then
    Exit;
  try
    if SetWindowDCLayout(DC, 0) = GDI_ERROR then
      Exit;
    Canvas := TCanvas.Create;
    try
      Canvas.Handle := DC;
      try
        if PaintEdges then
          for Part := Low(Part) to High(Part) do begin
            UseActive := Active and (StyleBorderImages[True, Part].Bitmap <> nil);
            PaintStyleBitmap(Canvas, Bounds[Part], StyleBorderImages[UseActive, Part]);
          end;
        PaintSetupStyleTitle(Wnd, Canvas, ScreenWindow, Client.Top, Active, Maximized);
      finally
        Canvas.Handle := 0;
      end;
    finally
      Canvas.Free;
    end;
  finally
    ReleaseDC(Wnd, DC);
  end;
end;

function SetupStyleBorderSubclass(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM;
  SubclassID: UINT_PTR; RefData: DWORD_PTR): LRESULT; stdcall;
var
  Track: TTrackMouseEvent;
begin
  if Msg = WM_NCDESTROY then
    RemoveWindowSubclass(Wnd, @SetupStyleBorderSubclass, SubclassID);
  Result := DefSubclassProc(Wnd, Msg, WParam, LParam);
  if (Msg = WM_NCMOUSEMOVE) and HasStyleCaptionButtons then begin
    Track := Default(TTrackMouseEvent);
    Track.cbSize := SizeOf(Track);
    Track.dwFlags := TME_NONCLIENT or TME_LEAVE;
    Track.hwndTrack := Wnd;
    Windows.TrackMouseEvent(@Track);
  end;
  if (Msg = WM_NCPAINT) or (Msg = WM_SETTEXT) then
    PaintSetupStyleBorders(Wnd, GetActiveWindow = Wnd)
  else if HasStyleCaptionButtons and
          ((Msg = WM_NCMOUSEMOVE) or (Msg = WM_NCMOUSELEAVE) or (Msg = WM_NCLBUTTONUP)) then
    PaintSetupStyleBorders(Wnd, GetActiveWindow = Wnd, True)
  else if (Msg = WM_NCACTIVATE) and (LParam <> -1) and (Result <> 0) then
    PaintSetupStyleBorders(Wnd, WParam <> 0);
end;

procedure DrawSetupStyleProgressBar(const ProgressBar: TNewProgressBar; const DC: HDC);
var
  Canvas: TCanvas;
  Bounds, FillBounds: TRect;
  FillSize: Integer;
  Orientation: TProgressBarOrientation;
  Axis: TStyleProgressAxis;

  procedure PaintMarquee(const Track: TRect);
  var
    MovingBounds: TRect;
    Extent, Chunk, Offset, SavedDC: Integer;
  begin
    if Axis = pbVertical then
      Extent := Track.Bottom - Track.Top
    else
      Extent := Track.Right - Track.Left;
    if (Extent <= 0) or (Track.Right <= Track.Left) or (Track.Bottom <= Track.Top) then
      Exit;
    Chunk := MulDiv(125, Screen.PixelsPerInch, 96);
    if Chunk > Extent then
      Chunk := Extent;
    Offset := VclStyleMarqueeOffset(Extent, Chunk, ProgressBar.MarqueeElapsed);
    MovingBounds := Track;
    if Axis = pbVertical then begin
      if Orientation = pbTopDown then begin
        MovingBounds.Top := Track.Top + Offset;
        MovingBounds.Bottom := MovingBounds.Top + Chunk;
      end else begin
        MovingBounds.Bottom := Track.Bottom - Offset;
        MovingBounds.Top := MovingBounds.Bottom - Chunk;
      end;
    end else if (Orientation = pbRightToLeft) or (ProgressBar.BiDiMode = bdRightToLeft) then begin
      MovingBounds.Right := Track.Right - Offset;
      MovingBounds.Left := MovingBounds.Right - Chunk;
    end else begin
      MovingBounds.Left := Track.Left + Offset;
      MovingBounds.Right := MovingBounds.Left + Chunk;
    end;
    SavedDC := SaveDC(DC);
    if SavedDC <> 0 then
    try
      if IntersectClipRect(DC, Track.Left, Track.Top, Track.Right, Track.Bottom) > NULLREGION then
        PaintStyleBitmap(Canvas, MovingBounds, StyleProgressFills[Axis, npbsNormal]);
    finally
      RestoreDC(DC, SavedDC);
    end;
  end;

begin
  Bounds := ProgressBar.ClientRect;
  Orientation := ProgressBar.Orientation;
  if Orientation in [pbVertical, pbTopDown] then
    Axis := pbVertical
  else
    Axis := pbHorizontal;
  Canvas := TCanvas.Create;
  try
    Canvas.Handle := DC;
    try
      Canvas.Brush.Color := StyleProgressBackground;
      Canvas.FillRect(Bounds);
      PaintStyleBitmap(Canvas, Bounds, StyleProgressFrames[Axis]);
      FillBounds := Bounds;
      InflateRect(FillBounds, -1, -1);
      if ProgressBar.Style = npbstMarquee then begin
        PaintMarquee(FillBounds);
        Exit;
      end;
      if Axis = pbVertical then begin
        FillSize := VclStyleProgressWidth(FillBounds.Bottom - FillBounds.Top,
          ProgressBar.Min, ProgressBar.Max, ProgressBar.Position);
        if Orientation = pbTopDown then
          FillBounds.Bottom := FillBounds.Top + FillSize
        else
          FillBounds.Top := FillBounds.Bottom - FillSize;
      end else begin
        FillSize := VclStyleProgressWidth(FillBounds.Right - FillBounds.Left,
          ProgressBar.Min, ProgressBar.Max, ProgressBar.Position);
        if (Orientation = pbRightToLeft) or (ProgressBar.BiDiMode = bdRightToLeft) then
          FillBounds.Left := FillBounds.Right - FillSize
        else
          FillBounds.Right := FillBounds.Left + FillSize;
      end;
      PaintStyleBitmap(Canvas, FillBounds, StyleProgressFills[Axis, ProgressBar.State]);
    finally
      Canvas.Handle := 0;
    end;
  finally
    Canvas.Free;
  end;
end;

function DrawSetupStyleButton(const Button: TNewButton; const DC: HDC;
  const Bounds: TRect; const ItemState: Cardinal): Boolean;
var
  State, ImageState: TVclStyleBitmapState;
  Canvas: TCanvas;
  Caption: String;
  TextBounds: TRect;
  TextFlags: Cardinal;
  TextColor: TColor;
  SavedDC: Integer;
begin
  Result := False;
  if (StyleButtonImages[vbsNormal].Bitmap = nil) or
     (Bounds.Right <= Bounds.Left) or (Bounds.Bottom <= Bounds.Top) then
    Exit;
  if not Button.Enabled or (ItemState and CDIS_DISABLED <> 0) then
    State := vbsDisabled
  else if ItemState and CDIS_SELECTED <> 0 then
    State := vbsPressed
  else if ItemState and CDIS_HOT <> 0 then
    State := vbsHot
  else if (ItemState and (CDIS_FOCUS or CDIS_DEFAULT) <> 0) or Button.Focused then
    State := vbsFocused
  else
    State := vbsNormal;
  ImageState := State;
  if StyleButtonImages[ImageState].Bitmap = nil then
    ImageState := vbsNormal;

  SavedDC := SaveDC(DC);
  if SavedDC = 0 then
    Exit;
  try
    Canvas := TCanvas.Create;
    try
      Canvas.Handle := DC;
      try
        PaintStyleBitmap(Canvas, Bounds, StyleButtonImages[ImageState]);
      finally
        Canvas.Handle := 0;
      end;
    finally
      Canvas.Free;
    end;
    if not Button.Enabled or (ItemState and CDIS_DISABLED <> 0) then
      TextColor := StyleButtonTextColors[vbsDisabled]
    else begin
      TextColor := Button.Font.Color;
      if (TextColor = clDefault) or (TextColor = clWindowText) or (TextColor = clBtnText) or
         (TextColor = StyleFormTextColor) then
        TextColor := StyleButtonTextColors[State];
    end;
    SelectObject(DC, Button.Font.Handle);
    SetBkMode(DC, TRANSPARENT);
    SetTextColor(DC, ColorToRGB(TextColor));
    Caption := UTF8Decode(Button.Caption);
    TextBounds := Bounds;
    InflateRect(TextBounds, -2, 0);
    TextFlags := DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS;
    if SendMessageW(Button.Handle, WM_QUERYUISTATE, 0, 0) and UISF_HIDEACCEL <> 0 then
      TextFlags := TextFlags or DT_HIDEPREFIX;
    if Button.BiDiMode = bdRightToLeft then
      TextFlags := TextFlags or DT_RTLREADING;
    DrawTextW(DC, PWideChar(Caption), Length(Caption), TextBounds, TextFlags);
    if Button.Focused and (SendMessageW(Button.Handle, WM_QUERYUISTATE, 0, 0) and UISF_HIDEFOCUS = 0) then begin
      TextBounds := Bounds;
      InflateRect(TextBounds, -3, -3);
      if (TextBounds.Right > TextBounds.Left) and (TextBounds.Bottom > TextBounds.Top) then
        DrawFocusRect(DC, TextBounds);
    end;
    Result := True;
  finally
    RestoreDC(DC, SavedDC);
  end;
end;

function FindStyleCheckGlyph(const Kind: TStyleCheckKind; const Check: TCheckBoxState;
  const State: TVclStyleBitmapState): TBitmap;
begin
  Result := StyleCheckImages[Kind, Check, State].Bitmap;
  if Result = nil then
    Result := StyleCheckImages[Kind, Check, vbsNormal].Bitmap;
end;

function DrawSetupCheckListStyleGlyph(const Canvas: TCanvas; const Bounds: TRect;
  const ItemType: TItemType; const CheckState: TCheckBoxState;
  const DrawState: TCheckBoxState2): Boolean;
const
  States: array[TCheckBoxState2] of TVclStyleBitmapState = (vbsNormal, vbsHot, vbsPressed, vbsDisabled);
var
  Kind: TStyleCheckKind;
  Glyph: TBitmap;
begin
  Result := False;
  if ItemType = itGroup then
    Exit;
  Kind := sckCheckBox;
  if ItemType = itRadio then
    Kind := sckRadio;
  Glyph := FindStyleCheckGlyph(Kind, CheckState, States[DrawState]);
  Result := DrawCenteredStyleGlyph(Canvas, Bounds, Glyph);
end;

function DrawCheckParentBackground(Wnd: HWND; DC: HDC; Bounds: PRect): HRESULT; stdcall;
  external 'uxtheme.dll' name 'DrawThemeParentBackground';

function DrawSetupStyleCheck(const Control: TCustomCheckBox; const DC: HDC;
  const Bounds: TRect; const ItemState: Cardinal): Boolean;
var
  Kind: TStyleCheckKind;
  State: TVclStyleBitmapState;
  Glyph: TBitmap;
  Canvas: TCanvas;
  GlyphBounds, TextBounds: TRect;
  Caption: String;
  Flags: Cardinal;
  TextColor: TColor;
  SavedDC: Integer;
  GlyphOnRight: Boolean;
begin
  Result := False;
  Kind := sckCheckBox;
  if Control is TRadioButton then
    Kind := sckRadio;
  if not Control.Enabled or (ItemState and CDIS_DISABLED <> 0) then
    State := vbsDisabled
  else if ItemState and CDIS_SELECTED <> 0 then
    State := vbsPressed
  else if ItemState and CDIS_HOT <> 0 then
    State := vbsHot
  else if Control.Focused then
    State := vbsFocused
  else
    State := vbsNormal;
  Glyph := FindStyleCheckGlyph(Kind, Control.State, State);
  if (Glyph = nil) or (Bounds.Right - Bounds.Left < Glyph.Width) or
     (Bounds.Bottom - Bounds.Top < Glyph.Height) then
    Exit;
  SavedDC := SaveDC(DC);
  if SavedDC = 0 then
    Exit;
  try
    TextBounds := Bounds;
    if DrawCheckParentBackground(Control.Handle, DC, @TextBounds) < 0 then
      Exit;
    GlyphOnRight := (Control.Alignment = taLeftJustify) xor (Control.BiDiMode = bdRightToLeft);
    GlyphBounds.Top := Bounds.Top + (Bounds.Bottom - Bounds.Top - Glyph.Height) div 2;
    GlyphBounds.Bottom := GlyphBounds.Top + Glyph.Height;
    if GlyphOnRight then begin
      GlyphBounds.Right := Bounds.Right;
      GlyphBounds.Left := GlyphBounds.Right - Glyph.Width;
      TextBounds.Right := GlyphBounds.Left - 4;
    end else begin
      GlyphBounds.Left := Bounds.Left;
      GlyphBounds.Right := GlyphBounds.Left + Glyph.Width;
      TextBounds.Left := GlyphBounds.Right + 4;
    end;
    Canvas := TCanvas.Create;
    try
      Canvas.Handle := DC;
      try
        Canvas.Draw(GlyphBounds.Left, GlyphBounds.Top, Glyph);
      finally
        Canvas.Handle := 0;
      end;
    finally
      Canvas.Free;
    end;
    Caption := UTF8Decode(TStyleCheckAccess(Control).Caption);
    TextColor := TStyleCheckAccess(Control).Font.Color;
    if (State = vbsDisabled) or (TextColor = clDefault) or (TextColor = clWindowText) or
       (TextColor = clBtnText) or (TextColor = StyleFormTextColor) then
      TextColor := StyleCheckText[Kind, State];
    SelectObject(DC, TStyleCheckAccess(Control).Font.Handle);
    SetBkMode(DC, TRANSPARENT);
    SetTextColor(DC, ColorToRGB(TextColor));
    Flags := DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS;
    if GlyphOnRight then
      Flags := Flags or DT_RIGHT;
    if Control.BiDiMode = bdRightToLeft then
      Flags := Flags or DT_RTLREADING;
    if SendMessageW(Control.Handle, WM_QUERYUISTATE, 0, 0) and UISF_HIDEACCEL <> 0 then
      Flags := Flags or DT_HIDEPREFIX;
    if TextBounds.Right > TextBounds.Left then begin
      DrawTextW(DC, PWideChar(Caption), Length(Caption), TextBounds, Flags);
      if Control.Focused and (SendMessageW(Control.Handle, WM_QUERYUISTATE, 0, 0) and UISF_HIDEFOCUS = 0) then
        DrawFocusRect(DC, TextBounds);
    end;
    Result := True;
  finally
    RestoreDC(DC, SavedDC);
  end;
end;

procedure TSetupForm.Paint;
var
  Bounds: TRect;
begin
  if CustomWizardBackground then begin
    Bounds := ClientRect;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := SetupHeader.WizardBackColor;
    Canvas.FillRect(Bounds);
    PaintStyleBitmap(Canvas, Bounds,
      StyleClientImages[Active and (StyleClientImages[True].Bitmap <> nil)]);
    if FBackgroundImageInitialized then
      FBackgroundImage.Paint(Self, Canvas, Bounds);
  end;
  inherited;
end;
{$ENDIF}

procedure TSetupForm.SetBackImage(const BackImages: TWizardImages; const Stretch, Center: Boolean;
  const Opacity: Byte; const Redraw: Boolean);
var
  Graphic: TGraphic;
begin
  if not CustomWizardBackground then
    InternalError('Cannot set a background image at this time: custom wizard background not active');
  Graphic := SelectBestImage(BackImages, ClientWidth, ClientHeight);
  {$IFDEF FPC}
  if not FBackgroundImageInitialized then begin
    FBackgroundImageInitialized := True;
    FBackgroundImage.Init(Self);
  end;
  FBackgroundImage.Stretch := Stretch;
  FBackgroundImage.Center := Center;
  FBackgroundImage.Opacity := Opacity;
  FBackgroundImage.SetGraphic(Graphic);
  {$ELSE}
  TFormBackgroundStyleHook.Graphic := Graphic;
  TFormBackgroundStyleHook.GraphicTarget := Self;
  TFormBackgroundStyleHook.Stretch := Stretch;
  TFormBackgroundStyleHook.Center := Center;
  TFormBackgroundStyleHook.Opacity := Opacity;
  {$ENDIF}
  TNewCheckListBox.ComplexParentBackground := Graphic <> nil;
  if Redraw and HandleAllocated then
    RedrawWindow(Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_UPDATENOW or RDW_ALLCHILDREN);
end;

class procedure TSetupForm.SetCtlParent(const AControl: TControl; const AParent: TWinControl);
{ To be called when a control is added after the form has already been created }
begin
  {$IFNDEF FPC}
  { Disable style if needed }
  if ShouldDisableControlStylesAsNeeded then
    DisableControlStyleAsNeeded(AControl);

  { Set CurrentPPI of the control to be parented to the CurrentPPI of the parent, preventing VCL
    from scaling the control. Also see TSetupForm.CreateWnd. }
  if AParent <> nil then { Could happen if called by [Code] }
    AControl.SetCurrentPPI(AParent.CurrentPPI);
  {$ENDIF}
  AControl.Parent := AParent;
end;

function TSetupForm.ShowModal: Integer;
begin
  { Work around VCL issue (Delphi 11.3): ShowModal calls DisableTaskWindows
    without ensuring the form's handle has been created first. If the handle
    is created after DisableTaskWindows, PopupMode=pmAuto breaks;
    TCustomForm.CreateParams finds that the active window is disabled, and
    doesn't use it as the owner. It then falls back to pmNone behavior, which
    is to use the main form or application window as the owner. }
  HandleNeeded; { Also see InitializeFont }
  Result := inherited;
end;

procedure TSetupForm.VisibleChanging;
begin
  inherited;
  { Note: Unlike DoShow, any exceptions raised in VisibleChanging will be
    propagated out, which is what we want }
  if not Visible then
    FlipAndCenterIfNeeded;
  end;

procedure TSetupForm.CMShowingChanged(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF});
begin
  inherited;
  { This usually just makes the taskbar button flash }
  if FSetForeground and Showing then
    SetForegroundWindow(Handle);
end;

procedure TSetupForm.WMQueryEndSession(var Message: TWMQueryEndSession);
begin
  { TDummyClass.AntiShutdownHook in Setup.Start already denies shutdown attempts
    but we also need to catch WM_QUERYENDSESSION here to suppress the VCL's
    default handling which calls CloseQuery. We do not want to let
    TNewDiskForm display any 'Exit Setup?' message boxes since we're already
    denying shutdown attempts, and also we can't allow them to potentially be
    displayed on top of another dialog box that's already displayed. }

  { Return zero, except if RestartInitiatedByThisProcess is set (which means
    we called RestartComputer previously) }
  if RestartInitiatedByThisProcess then
    Message.Result := 1;
end;

procedure TSetupForm.WndProc(var Message: {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF});
begin
  { When we receive a 'QueryCancelAutoPlay' message as a result of a new CD
    being inserted, return 1 to prevent it from being 'autoplayed'.
    Note: According to the docs, this message is only sent on Shell version
    4.70 and later. }
  if (WM_QueryCancelAutoPlay <> 0) and (Message.Msg = WM_QueryCancelAutoPlay) then
    Message.Result := 1
  else
    inherited;
end;

initialization
  BidiUtils.IsParentFlippedFunc := IsParentSetupFormFlipped;
  WM_QueryCancelAutoPlay := RegisterWindowMessage('QueryCancelAutoPlay');
{$IFDEF FPC}
  DrawNewButtonStyle := @DrawSetupStyleButton;
  DrawNewCheckStyle := @DrawSetupStyleCheck;
  DrawCheckListStyleGlyph := @DrawSetupCheckListStyleGlyph;
finalization
  DrawNewButtonStyle := nil;
  DrawNewCheckStyle := nil;
  DrawCheckListStyleGlyph := nil;
  ResolveCheckListStyleColor := nil;
  ClearStyleEditColors;
  ClearStyleButtonImages;
  ClearStyleCheckImages;
  ClearStyleProgressImages;
  ClearStyleBorderImages;
  StyleClientImages[False].Bitmap.Free;
  StyleClientImages[True].Bitmap.Free;
{$ENDIF}
end.
