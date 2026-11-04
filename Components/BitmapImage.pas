unit BitmapImage;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  A TImage-like component for bitmaps and png files without the TPicture bloat
  
  Also supports other TGraphic types which can be assigned to a TBitmap

  Also see TBitmapButton which is the TWinControl version
}

interface

uses
  Windows, ShellAPI, Controls, Graphics, Classes, {$IFDEF FPC}InnoPngImage{$ELSE}Imaging.pngimage{$ENDIF};

type
  {$IFDEF FPC}
  SHSTOCKICONID = Integer;
  {$ENDIF}

  TPaintEvent = procedure(Sender: TObject; Canvas: TCanvas; var ARect: TRect) of object;

  TBitmapImageImplementation = record
  private
    FControl: TControl;
    FStretching: Boolean;
  public
    AutoSize: Boolean;
    ExtraWidth, ExtraHeight: Integer;
    BackColor: TColor;
    Bitmap: TBitmap;
    Center: Boolean;
    Opacity: Byte;
    PngImage: TPngImage;
    ReplaceColor: TColor;
    ReplaceWithColor: TColor;
    Stretch: Boolean;
    StretchedBitmap: TBitmap;
    StretchedBitmapValid: Boolean;
    OnPaint: TPaintEvent;
    procedure Init(const AControl: TControl; const AExtraWidth: Integer = 0;
      const AExtraHeight: Integer = 0);
    procedure DeInit;
    class function AdjustColorForStyle(const Control: TControl; const Color: TColor): TColor; static;
    function GetInitializeSize(const AscendingTrySizes: array of Integer): Integer;
    function InitializeFromIcon(const Instance: HINST; const Name: PChar; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
    function InitializeFromStockIcon(const Siid: SHSTOCKICONID; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
    procedure BitmapChanged(Sender: TObject);
    procedure PngImageChanged(Sender: TObject);
    procedure SetAutoSize(Sender: TObject; Value: Boolean);
    procedure SetBackColor(Sender: TObject; Value: TColor);
    procedure SetBitmap(Value: TBitmap);
    procedure SetCenter(Sender: TObject; Value: Boolean);
    procedure SetGraphic(Value: TGraphic);
    procedure SetOpacity(Sender: TObject; Value: Byte);
    procedure SetPngImage(Value: TPngImage);
    procedure SetReplaceColor(Sender: TObject; Value: TColor);
    procedure SetReplaceWithColor(Sender: TObject; Value: TColor);
    procedure SetStretch(Sender: TObject; Value: Boolean);
    function GetPalette: HPALETTE;
    procedure Paint(const Sender: TObject; const Canvas: TCanvas; var R: TRect);
  end;

  TBitmapImage = class(TGraphicControl)
  private
    FImpl: TBitmapImageImplementation;
    procedure SetBackColor(Value: TColor);
    procedure SetBitmap(Value: TBitmap);
    procedure SetCenter(Value: Boolean);
    procedure SetOpacity(Value: Byte);
    procedure SetGraphic(Value: TGraphic);
    procedure SetPngImage(Value: TPngImage);
    procedure SetReplaceColor(Value: TColor);
    procedure SetReplaceWithColor(Value: TColor);
    procedure SetStretch(Value: Boolean);
  protected
    function GetPalette: HPALETTE; override;
    procedure Paint; override;
    procedure SetAutoSize(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function InitializeFromIcon(const Instance: HINST; const Name: PChar; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
    function InitializeFromStockIcon(const Siid: SHSTOCKICONID; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
    property Bitmap: TBitmap read FImpl.Bitmap write SetBitmap;
    property Graphic: TGraphic write SetGraphic;
  published
    property Align;
    property Anchors;
    property AutoSize: Boolean read FImpl.AutoSize write SetAutoSize default False;
    property BackColor: TColor read FImpl.BackColor write SetBackColor default clBtnFace;
    property Center: Boolean read FImpl.Center write SetCenter default False;
    property DragCursor;
    property DragMode;
    property Enabled;
    property Opacity: Byte read FImpl.Opacity write SetOpacity default 255;
    property ParentShowHint;
    property PngImage: TPngImage read FImpl.PngImage write SetPngImage;
    property PopupMenu;
    property ShowHint;
    property Stretch: Boolean read FImpl.Stretch write SetStretch default False;
    property ReplaceColor: TColor read FImpl.ReplaceColor write SetReplaceColor default clNone;
    property ReplaceWithColor: TColor read FImpl.ReplaceWithColor write SetReplaceWithColor default clNone;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDrag;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnPaint: TPaintEvent read FImpl.OnPaint write FImpl.OnPaint;
    property OnStartDrag;
  end;

procedure Register;

implementation

uses
  CommCtrl, SysUtils, Math, {$IFDEF FPC}IntfGraphics, GraphType, FPImage,{$ELSE}Themes,{$ENDIF} Resample;

procedure Register;
begin
  RegisterComponents('JR', [TBitmapImage]);
end;

{ TBitmapImageImplementation }

procedure TBitmapImageImplementation.Init(const AControl: TControl;
  const AExtraWidth, AExtraHeight: Integer);
begin
  FControl := AControl;
  ExtraWidth := AExtraWidth;
  ExtraHeight := AExtraHeight;
  BackColor := clNone;
  Bitmap := TBitmap.Create;
  Bitmap.OnChange := BitmapChanged;
  Opacity := 255;
  PngImage := TPngImage.Create;
  PngImage.OnChange := PngImageChanged;
  ReplaceColor := clNone;
  ReplaceWithColor := clNone;
  StretchedBitmap := TBitmap.Create;
end;

procedure TBitmapImageImplementation.DeInit;
begin
  FreeAndNil(StretchedBitmap);
  FreeAndNil(PngImage);
  FreeAndNil(Bitmap);
end;

class function TBitmapImageImplementation.AdjustColorForStyle(const Control: TControl;
  const Color: TColor): TColor;
begin
  Result := Color;
  {$IFNDEF FPC}
  if (Result = clBtnFace) or (Result = clWindow) then begin
    var LStyle := StyleServices(Control);
    if not LStyle.Enabled or LStyle.IsSystemStyle then
      LStyle := nil;
    if LStyle <> nil then begin
      if Result = clBtnFace then
        Result := LStyle.GetStyleColor(scPanel)
      else
        Result := LStyle.GetStyleColor(scWindow);
    end;
  end;
  {$ENDIF}
end;

function TBitmapImageImplementation.GetInitializeSize(const AscendingTrySizes: array of Integer): Integer;
var
  I: Integer;
begin
  { Find the largest regular icon size smaller than the scaled image }
  Result := 0;
  for I := Length(AscendingTrySizes)-1 downto 0 do begin
    if (FControl.Width >= AscendingTrySizes[I]) and (FControl.Height >= AscendingTrySizes[I]) then begin
      Result := AscendingTrySizes[I];
      Break;
    end;
  end;
  if Result = 0 then
    Result := Min(FControl.Width, FControl.Height);
end;

function TBitmapImageImplementation.InitializeFromIcon(const Instance: HINST; const Name: PChar; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
var
  Size: Integer;
  Flags: UINT;
  Handle: HICON;
  Icon: TIcon;
begin
  Size := GetInitializeSize(AscendingTrySizes);

  { Load the desired icon }
  Flags := LR_DEFAULTCOLOR;
  if Instance = 0 then
    Flags := Flags or LR_LOADFROMFILE;
  Handle := LoadImageW(Instance, Name, IMAGE_ICON, Size, Size, Flags);
  if Handle = 0 then
    Handle := LoadImageW(Instance, Name, IMAGE_ICON, 0, 0, Flags);
  if Handle <> 0 then begin
    Icon := TIcon.Create;
    try
      Icon.Handle := Handle;

      { Set sizes (overrides any scaling) }
      FControl.Width := Icon.Width + ExtraWidth;
      FControl.Height := Icon.Height + ExtraHeight;

      { Set bitmap }
      AutoSize := False;
      BackColor := BkColor;
      Stretch := True;
      Bitmap.Assign(Icon);

      Result := True;
    finally
      Icon.Free;
    end;
  end else
    Result := False;
end;

const
  IID_IImageList: TGUID = '{46EB5926-582E-4017-9FDF-E8998DAA0950}';

{$IFDEF FPC}
const
  SHGSI_SYSICONINDEX = SHGFI_SYSICONINDEX;
  SHIL_JUMBO = 4;

type
  TSHStockIconInfo = record
    cbSize: DWORD;
    hIcon: HICON;
    iSysImageIndex: Integer;
    iIcon: Integer;
    szPath: array[0..MAX_PATH-1] of WideChar;
  end;

function SHGetStockIconInfo(const Siid: SHSTOCKICONID; const Flags: UINT;
  var Info: TSHStockIconInfo): HRESULT; stdcall; external 'shell32.dll';
{$ENDIF}

function TBitmapImageImplementation.InitializeFromStockIcon(const Siid: SHSTOCKICONID; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
var
  StockIconInfo: TSHStockIconInfo;
  Size, ImageListSize: Integer;
  ImageListIntf: IUnknown;
  ImageList: HIMAGELIST;
  Handle: HICON;
  Icon: TIcon;
begin
  { Currently this function always fails on Wine: SHGetStockIconInfo succeeds but simply always
    returns -1 as iSysImageIndex, which makes ImageList_GetIcon fail }

  Result := False;

  StockIconInfo.cbSize := SizeOf(StockIconInfo);
  if Succeeded(SHGetStockIconInfo(siid, SHGSI_SYSICONINDEX, StockIconInfo)) then begin
    { The SHGetImageList documentation remarks that SHIL_SMALL and SHIL_LARGE are DPI-aware. However
      because this does not provide per-monitor DPI awareness, we always use SHIL_JUMBO and perform
      scaling ourselves. }
    Size := GetInitializeSize(AscendingTrySizes);
    if Size > 24 then
      ImageListSize := SHIL_JUMBO
    else
      ImageListSize := SHIL_EXTRALARGE; { For small images use SHIL_EXTRALARGE, which should be 48x48 at least }
    { Keep the interface alive while using its HIMAGELIST view }
    if Succeeded(SHGetImageList(ImageListSize, IID_IImageList, {$IFDEF FPC}@ImageListIntf{$ELSE}Pointer(ImageListIntf){$ENDIF})) then begin
      { The SHGetImageList documentation also remarks that "the IImageList pointer type can be cast as an
        HIMAGELIST as needed", and we make use of that }
      ImageList := HIMAGELIST(Pointer(ImageListIntf));
      Handle := ImageList_GetIcon(ImageList, StockIconInfo.iSysImageIndex, ILD_TRANSPARENT);
      if Handle <> 0 then begin
        Icon := TIcon.Create;
        try
          Icon.Handle := Handle;

          { Set sizes (overrides any scaling) }
          FControl.Width := Size + ExtraWidth;
          FControl.Height := Size + ExtraHeight;

          { Set bitmap }
          AutoSize := False;
          BackColor := BkColor;
          Stretch := True;
          Bitmap.Assign(Icon);

          Result := True;
        finally
          Icon.Free;
        end;
      end;
    end;
  end;
end;

procedure TBitmapImageImplementation.BitmapChanged(Sender: TObject);
begin
  if FStretching then
    Exit;
  StretchedBitmapValid := False;
  if AutoSize and (Bitmap.Width > 0) and (Bitmap.Height > 0) then
    FControl.SetBounds(FControl.Left, FControl.Top, Bitmap.Width + ExtraWidth,
      Bitmap.Height + ExtraHeight);
  FControl.Invalidate;
end;

procedure TBitmapImageImplementation.PngImageChanged(Sender: TObject);
begin
  Bitmap.Assign(PngImage);
end;

procedure TBitmapImageImplementation.SetAutoSize(Sender: TObject; Value: Boolean);
begin
  AutoSize := Value;
  BitmapChanged(Sender);
end;

procedure TBitmapImageImplementation.SetBackColor(Sender: TObject; Value: TColor);
begin
  if BackColor <> Value then begin
    BackColor := Value;
    BitmapChanged(Sender);
  end;
end;

procedure TBitmapImageImplementation.SetBitmap(Value: TBitmap);
begin
  Bitmap.Assign(Value);
end;

procedure TBitmapImageImplementation.SetCenter(Sender: TObject; Value: Boolean);
begin
  if Center <> Value then begin
    Center := Value;
    BitmapChanged(Sender);
  end;
end;

procedure TBitmapImageImplementation.SetGraphic(Value: TGraphic);
begin
  if Value is TPngImage then
    SetPngImage(Value as TPngImage)
  else
    Bitmap.Assign(Value);
end;

procedure TBitmapImageImplementation.SetOpacity(Sender: TObject; Value: Byte);
begin
  if Opacity <> Value then begin
    Opacity := Value;
    BitmapChanged(Sender);
  end;
end;

procedure TBitmapImageImplementation.SetPngImage(Value: TPngImage);
begin
  PngImage.Assign(Value);
end;

procedure TBitmapImageImplementation.SetReplaceColor(Sender: TObject; Value: TColor);
begin
  if ReplaceColor <> Value then begin
    ReplaceColor := Value;
    BitmapChanged(Sender);
  end;
end;

procedure TBitmapImageImplementation.SetReplaceWithColor(Sender: TObject; Value: TColor);
begin
  if ReplaceWithColor <> Value then begin
    ReplaceWithColor := Value;
    BitmapChanged(Sender);
  end;
end;

procedure TBitmapImageImplementation.SetStretch(Sender: TObject; Value: Boolean);
begin
  if Stretch <> Value then begin
    Stretch := Value;
    StretchedBitmap.Assign(nil);
    BitmapChanged(Sender);
  end;
end;

function TBitmapImageImplementation.GetPalette: HPALETTE;
begin
  Result := Bitmap.Palette;
end;

procedure TBitmapImageImplementation.Paint(const Sender: TObject; const Canvas: TCanvas; var R: TRect);
var
  Is32bit: Boolean;
  W, H, X, Y: Integer;
  Bmp: TBitmap;
  BrushColor: TColor;

  function DoStretchBmp(const W, H: Integer; const Is32bit: Boolean): Boolean;
  begin
    FStretching := True; { StretchBmp may fire OnChange due to PixelFormat changing }
    try
      Result := StretchBmp(Bitmap, StretchedBitmap, W, H, Is32bit);
    finally
      FStretching := False;
    end;
  end;

  {$IFDEF FPC}
  procedure DrawWithOpacity;
  var
    Source, Output: TLazIntfImage;
    Desc: TRawImageDescription;
    OutputBitmap: TBitmap;
    Column, Row: Integer;
    Color: TFPColor;
    HasVisiblePixels: Boolean;
  begin
    if Opacity = 0 then
      Exit;
    Source := Bmp.CreateIntfImage;
    Output := nil;
    OutputBitmap := nil;
    try
      if Opacity = 255 then begin
        { The Win32 widget set treats all-zero alpha as an opaque DIB }
        for Row := 0 to Bmp.Height - 1 do
          for Column := 0 to Bmp.Width - 1 do
            if Source.Colors[Column, Row].Alpha shr 8 <> 0 then begin
              Canvas.Draw(X, Y, Bmp);
              Exit;
            end;
        Exit;
      end;
      Output := TLazIntfImage.Create(0, 0);
      Desc.Init_BPP32_B8G8R8A8_BIO_TTB(Bmp.Width, Bmp.Height);
      Output.DataDescription := Desc;
      HasVisiblePixels := False;
      for Row := 0 to Bmp.Height - 1 do
        for Column := 0 to Bmp.Width - 1 do begin
          Color := Source.Colors[Column, Row];
          if not Is32bit then
            Color.Alpha := High(Word);
          Color.Alpha := (Cardinal(Color.Alpha) * Opacity + 127) div 255;
          HasVisiblePixels := HasVisiblePixels or (Color.Alpha shr 8 <> 0);
          Output.Colors[Column, Row] := Color;
        end;
      if HasVisiblePixels then begin
        OutputBitmap := TBitmap.Create;
        OutputBitmap.LoadFromIntfImage(Output);
        Canvas.Draw(X, Y, OutputBitmap);
      end;
    finally
      OutputBitmap.Free;
      Output.Free;
      Source.Free;
    end;
  end;
  {$ENDIF}

begin
  Is32bit := {$IFDEF FPC}Bitmap.RawImage.Description.AlphaPrec > 0{$ELSE}Bitmap.SupportsPartialTransparency{$ENDIF};
  if Stretch and not Bitmap.Empty then begin
    W := R.Width;
    H := R.Height;
    Bmp := StretchedBitmap;
    if not StretchedBitmapValid or (StretchedBitmap.Width <> W) or
        (StretchedBitmap.Height <> H) then begin
      StretchedBitmapValid := True;
      if (Bitmap.Width = W) and (Bitmap.Height = H) then
        StretchedBitmap.Assign(Bitmap)
      else begin
        StretchedBitmap.Assign(nil);
        if not DoStretchBmp(W, H, Is32bit) then begin
          if Is32bit then begin
            StretchedBitmapValid := False;
            Bmp := Bitmap;
            W := Bmp.Width;
            H := Bmp.Height;
          end else begin
            {$IFNDEF FPC}StretchedBitmap.Palette := CopyPalette(Bitmap.Palette);{$ENDIF}
            StretchedBitmap.Width := W;
            StretchedBitmap.Height := H;
            StretchedBitmap.Canvas.StretchDraw(Rect(0, 0, W, H), Bitmap);
          end;
        end;
      end;
    end;
  end else begin
    Bmp := Bitmap;
    W := Bmp.Width;
    H := Bmp.Height;
  end;

  if (BackColor <> clNone) and (Is32Bit or (Opacity <> 255) or (Bmp.Width < R.Width) or (Bmp.Height < R.Height)) then begin
    BrushColor := BackColor;
    if Sender is TControl then
      BrushColor := AdjustColorForStyle(TControl(Sender), BrushColor);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := BrushColor;
    Canvas.FillRect(R);
  end;

  if csDesigning in FControl.ComponentState then begin
    Canvas.Pen.Style := psDash;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(0, 0, FControl.Width, FControl.Height);
  end;


  if not Bmp.Empty then begin
    X := R.Left;
    Y := R.Top;
    if Center then begin
      Inc(X, (R.Width - W) div 2);
      if X < R.Left then
        X := R.Left;
      Inc(Y, (R.Height - H) div 2);
      if Y < R.Top then
        Y := R.Top;
    end;

    if not Is32bit and (ReplaceColor <> clNone) and (ReplaceWithColor <> clNone) then begin
      Canvas.Brush.Color := ReplaceWithColor;
      Canvas.BrushCopy(Rect(X, Y, X + W, Y + H), Bmp, Rect(0, 0, Bmp.Width, Bmp.Height), ReplaceColor);
    {$IFDEF FPC}
    end else if Is32bit or (Opacity <> 255) then
      DrawWithOpacity
    {$ELSE}
    end else if Opacity <> 255 then
      Canvas.Draw(X, Y, Bmp, Opacity)
    {$ENDIF}
    else
      Canvas.Draw(X, Y, Bmp);
  end;

  if Assigned(OnPaint) then
    OnPaint(Sender, Canvas, R);
end;

{ TBitmapImage }

constructor TBitmapImage.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csParentBackground, csReplicatable];
  FImpl.Init(Self);
  {$IFNDEF FPC}
  if IsCustomStyleActive then
    FImpl.BackColor := StyleServices(Self).GetStyleColor(scWindow)
  else
  {$ENDIF}
    FImpl.BackColor := clBtnFace;
  Width := 105;
  Height := 105;
end;

destructor TBitmapImage.Destroy;
begin
  FImpl.DeInit;
  inherited;
end;

function TBitmapImage.InitializeFromIcon(const Instance: HINST; const Name: PChar; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
begin
  Result := FImpl.InitializeFromIcon(Instance, Name, BkColor, AscendingTrySizes);
end;

function TBitmapImage.InitializeFromStockIcon(const Siid: SHSTOCKICONID; const BkColor: TColor; const AscendingTrySizes: array of Integer): Boolean;
begin
  Result := FImpl.InitializeFromStockIcon(siid, BkColor, AscendingTrySizes);
end;

procedure TBitmapImage.SetAutoSize(Value: Boolean);
begin
  FImpl.SetAutoSize(Self, Value);
end;

procedure TBitmapImage.SetBackColor(Value: TColor);
begin
  FImpl.SetBackColor(Self, Value);
end;

procedure TBitmapImage.SetBitmap(Value: TBitmap);
begin
  FImpl.SetBitmap(Value);
end;

procedure TBitmapImage.SetCenter(Value: Boolean);
begin
  FImpl.SetCenter(Self, Value);
end;

procedure TBitmapImage.SetGraphic(Value: TGraphic);
begin
  FImpl.SetGraphic(Value);
end;

procedure TBitmapImage.SetOpacity(Value: Byte);
begin
  FImpl.SetOpacity(Self, Value);
end;

procedure TBitmapImage.SetPngImage(Value: TPngImage);
begin
  FImpl.SetPngImage(Value);
end;

procedure TBitmapImage.SetReplaceColor(Value: TColor);
begin
  FImpl.SetReplaceColor(Self, Value);
end;

procedure TBitmapImage.SetReplaceWithColor(Value: TColor);
begin
  FImpl.SetReplaceWithColor(Self, Value);
end;

procedure TBitmapImage.SetStretch(Value: Boolean);
begin
  FImpl.SetStretch(Self, Value);
end;

function TBitmapImage.GetPalette: HPALETTE;
begin
  Result := FImpl.GetPalette;
end;

procedure TBitmapImage.Paint;
var
  R: TRect;
begin
  R := ClientRect;
  FImpl.Paint(Self, Canvas, R);
end;

end.