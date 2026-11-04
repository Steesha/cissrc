unit Resample;
interface
uses
  Windows, Math, Graphics{$IFDEF FPC}, IntfGraphics, GraphType, FPImage{$ENDIF};

function StretchBmp(SrcBitmap, DstBitmap: TBitmap;
  DstWidth, DstHeight: Integer; Is32bit: Boolean): Boolean;

implementation

const
  FixedBits = 16;
  FixedOne = 1 shl FixedBits;
  FixedOneHalf = FixedOne shr 1;
type
  TWeight = packed record
    Offset: Integer; //Byte offset to pixel data
    case Integer of
      0: (Weight: Integer); //Pixel weight in Q16.16 fixed point format
      1: (Temp: Single); //same thing in float format
  end;
  TWeightArray = array [0..MaxInt div SizeOf(TWeight) - 1] of TWeight;
  TPutPixelProc = procedure(const Weights: array of TWeight; Bits, Pixel: Pointer);

procedure ResampleBits(DstSize, SrcSize: Integer; SrcLine, DstLine: Pointer;
  PixelSize, LineCount, SrcLineSize, DstLineSize: Integer; PutPixelProc: TPutPixelProc);
var
  I, J, Count: Integer;
  Limit, Scale, X, Y, Center, Sup, Sum: Single;
  Weights: ^TWeightArray;
  Src, Dst: Pointer;
const
  FilterWidth = 2.0;
begin
  Scale := SrcSize / DstSize;
  if Scale < 1.0 then
    Limit := 1.0
  else
    Limit := 1.0 / Scale;
  Sup := FilterWidth / Limit;
  GetMem(Weights, Trunc(Sup * 2.0 + 2.0) * SizeOf(TWeight));
  try
    for I := 0 to DstSize - 1 do begin
      Count := 0;
      Sum := 0;
      Center := (I + 0.5) * Scale;
      for J := Floor(Center - Sup) to Ceil(Center + Sup) do begin
        X := Abs(J - Center + 0.5);
        if X > Sup then Continue;
        X := X * Limit;
        {Resampling filter}
        if X < 1.0 then //SPLINE16
          Y := Sqr(X) * (X - 9 / 5) - 1 / 5 * X + 1
        else
          Y := Sqr(X - 1) * (-1 / 3 * (X - 1) + 4 / 5) - 7 / 15 * (X - 1);
        {The code from above must be kept in sync with FilterWidth value}
        if (Y = 0) or (J < 0) or (J >= SrcSize) then Continue;
        with Weights[Count] do begin
          Temp := Y;
          Offset := J * PixelSize;
        end;
        Sum := Sum + Y;
        Inc(Count);
      end;
      if Sum <> 0 then begin
        Sum := FixedOne / Sum;
        for J := 0 to Count - 1 do
          with Weights[J] do
            Weight := Integer(Round(Temp * Sum));
      end else
        Count := 0;
      Src := SrcLine;
      Dst := DstLine;
      for J := 0 to LineCount - 1 do begin
        PutPixelProc(Slice(Weights^, Count), Src, Dst);
        Inc(PByte(Src), SrcLineSize);
        Inc(PByte(Dst), DstLineSize);
      end;
      Inc(PByte(DstLine), PixelSize);
    end;
  finally
    FreeMem(Weights);
  end;
end;

//Process pixel in BGR format
procedure PutPixel24(const Weights: array of TWeight; Bits, Pixel: Pointer);
type
  PRGBTriple = ^TRGBTriple;
var
  I, R, G, B: Integer;
begin
  R := FixedOneHalf;
  G := FixedOneHalf;
  B := FixedOneHalf;
  for I := 0 to High(Weights) do
    with Weights[I], PRGBTriple(PAnsiChar(Bits) + Offset)^ do begin
      Inc(R, rgbtRed * Weight);
      Inc(G, rgbtGreen * Weight);
      Inc(B, rgbtBlue * Weight);
    end;
  with PRGBTriple(Pixel)^ do begin
    //Clamps all channels to values between 0 and 255
    if R > 0 then if R < 255 shl FixedBits then rgbtRed   := Byte(R shr FixedBits) else rgbtRed   := 255 else rgbtRed   := 0;
    if G > 0 then if G < 255 shl FixedBits then rgbtGreen := Byte(G shr FixedBits) else rgbtGreen := 255 else rgbtGreen := 0;
    if B > 0 then if B < 255 shl FixedBits then rgbtBlue  := Byte(B shr FixedBits) else rgbtBlue  := 255 else rgbtBlue  := 0;
  end;
end;

//Process pixel in BGRA premultiplied alpha format
procedure PutPixel32P(const Weights: array of TWeight; Bits, Pixel: Pointer);
var
  I, R, G, B, A, AlphaLimit: Integer;
  AByte: Byte;
begin
  R := FixedOneHalf;
  G := FixedOneHalf;
  B := FixedOneHalf;
  A := FixedOneHalf;
  for I := 0 to High(Weights) do
    with Weights[I], PRGBQuad(PAnsiChar(Bits) + Offset)^ do begin
      Inc(R, rgbRed * Weight);
      Inc(G, rgbGreen * Weight);
      Inc(B, rgbBlue * Weight);
      Inc(A, rgbReserved * Weight);
    end;
  //Clamps alpha channel to values between 0 and 255
  if A > 0 then if A < 255 shl FixedBits then AByte := Byte(A shr FixedBits) else AByte := 255 else AByte := 0;
  with PRGBQuad(Pixel)^ do begin
    rgbReserved := AByte;
    AlphaLimit := AByte shl FixedBits;
    //Clamps other channels to values between 0 and Alpha
    if R > 0 then if R < AlphaLimit then rgbRed   := Byte(R shr FixedBits) else rgbRed   := AByte else rgbRed   := 0;
    if G > 0 then if G < AlphaLimit then rgbGreen := Byte(G shr FixedBits) else rgbGreen := AByte else rgbGreen := 0;
    if B > 0 then if B < AlphaLimit then rgbBlue  := Byte(B shr FixedBits) else rgbBlue  := AByte else rgbBlue  := 0;
  end;
end;


{$IFDEF FPC}
procedure ReadPixels(const Image: TLazIntfImage; const Bits: Pointer;
  const PixelSize: Integer);
var
  X, Y, Alpha: Integer;
  Color: TFPColor;
  Pixel: PByte;
begin
  Pixel := Bits;
  for Y := 0 to Image.Height - 1 do
    for X := 0 to Image.Width - 1 do begin
      Color := Image.Colors[X, Y];
      if PixelSize = 4 then begin
        Alpha := Color.Alpha shr 8;
        PRGBQuad(Pixel)^.rgbBlue := ((Color.Blue shr 8) * Alpha + 127) div 255;
        PRGBQuad(Pixel)^.rgbGreen := ((Color.Green shr 8) * Alpha + 127) div 255;
        PRGBQuad(Pixel)^.rgbRed := ((Color.Red shr 8) * Alpha + 127) div 255;
        PRGBQuad(Pixel)^.rgbReserved := Alpha;
      end else begin
        PRGBTriple(Pixel)^.rgbtBlue := Color.Blue shr 8;
        PRGBTriple(Pixel)^.rgbtGreen := Color.Green shr 8;
        PRGBTriple(Pixel)^.rgbtRed := Color.Red shr 8;
      end;
      Inc(Pixel, PixelSize);
    end;
end;

procedure WritePixels(const Image: TLazIntfImage; const Bits: Pointer;
  const PixelSize: Integer);
var
  X, Y, Alpha: Integer;
  Color: TFPColor;
  Pixel: PByte;
begin
  Pixel := Bits;
  for Y := 0 to Image.Height - 1 do
    for X := 0 to Image.Width - 1 do begin
      if PixelSize = 4 then begin
        Alpha := PRGBQuad(Pixel)^.rgbReserved;
        Color.Alpha := Alpha * 257;
        if Alpha > 0 then begin
          Color.Blue := (Integer(PRGBQuad(Pixel)^.rgbBlue) * 65535 + Alpha div 2) div Alpha;
          Color.Green := (Integer(PRGBQuad(Pixel)^.rgbGreen) * 65535 + Alpha div 2) div Alpha;
          Color.Red := (Integer(PRGBQuad(Pixel)^.rgbRed) * 65535 + Alpha div 2) div Alpha;
        end else begin
          Color.Blue := 0;
          Color.Green := 0;
          Color.Red := 0;
        end;
      end else begin
        Color.Blue := PRGBTriple(Pixel)^.rgbtBlue * 257;
        Color.Green := PRGBTriple(Pixel)^.rgbtGreen * 257;
        Color.Red := PRGBTriple(Pixel)^.rgbtRed * 257;
        Color.Alpha := $FFFF;
      end;
      Image.Colors[X, Y] := Color;
      Inc(Pixel, PixelSize);
    end;
end;
{$ENDIF}


function StretchBmp(SrcBitmap, DstBitmap: TBitmap;
  DstWidth, DstHeight: Integer; Is32bit: Boolean): Boolean;
var
  SrcWidth, SrcHeight, SrcLineSize, DstLineSize, PixelSize: Integer;
  SrcBits, DstBits, TmpBits: Pointer;
  {$IFDEF FPC}
  SrcImage, DstImage: TLazIntfImage;
  Desc: TRawImageDescription;
  {$ELSE}
  PixelFormat: TPixelFormat;
  {$ENDIF}
  Proc: TPutPixelProc;
begin
  Result := False;
  try
    if (DstWidth <= 0) or (DstHeight <= 0) then Exit;
    SrcWidth := SrcBitmap.Width;
    SrcHeight := SrcBitmap.Height;
    if (SrcWidth <= 0) or (SrcHeight <= 0) then Exit;
    if Is32bit then begin
      {$IFNDEF FPC}PixelFormat := pf32bit;{$ENDIF}
      PixelSize := 4;
      Proc := PutPixel32P;
    end else begin
      {$IFNDEF FPC}PixelFormat := pf24bit;{$ENDIF}
      PixelSize := 3;
      Proc := PutPixel24;
    end;
    {$IFDEF FPC}
    SrcBits := nil;
    DstBits := nil;
    SrcImage := nil;
    DstImage := nil;
    try
      SrcLineSize := SrcWidth * PixelSize;
      DstLineSize := DstWidth * PixelSize;
      GetMem(SrcBits, NativeUInt(SrcHeight) * NativeUInt(SrcLineSize));
      GetMem(DstBits, NativeUInt(DstHeight) * NativeUInt(DstLineSize));
      SrcImage := SrcBitmap.CreateIntfImage;
      ReadPixels(SrcImage, SrcBits, PixelSize);
    {$ELSE}
    //NOTE: Irreversible change of SrcBitmap pixel format
    SrcBitmap.PixelFormat := PixelFormat;
    if SrcHeight > 1 then
      SrcLineSize := Integer(PByte(SrcBitmap.ScanLine[0]) - PByte(SrcBitmap.ScanLine[1])) {Could be negative, see below }
    else
      SrcLineSize := SrcWidth * PixelSize;
    if SrcLineSize >= 0 then
      SrcBits := SrcBitmap.ScanLine[SrcHeight - 1]
    else begin
      SrcLineSize := -SrcLineSize;
      SrcBits := SrcBitmap.ScanLine[0];
    end;
    DstBitmap.PixelFormat := PixelFormat;
    DstBitmap.AlphaFormat := SrcBitmap.AlphaFormat;
    DstBitmap.Width := DstWidth;
    DstBitmap.Height := DstHeight;
    if DstHeight > 1 then
      DstLineSize := Integer(PByte(DstBitmap.ScanLine[0]) - PByte(DstBitmap.ScanLine[1])) {Could be negative, see below }
    else
      DstLineSize := DstWidth * PixelSize;
    if DstLineSize >= 0 then
      DstBits := DstBitmap.ScanLine[DstHeight - 1]
    else begin
      DstLineSize := -DstLineSize;
      DstBits := DstBitmap.ScanLine[0];
    end;
    {$ENDIF}
    TmpBits := nil;
    try
      //Minimize temporary allocations by choosing right stretch order
      if DstWidth * SrcHeight < DstHeight * SrcWidth then begin
        GetMem(TmpBits, SrcHeight * DstLineSize);
        //Stretch horizontally
        ResampleBits(DstWidth, SrcWidth, SrcBits, TmpBits, PixelSize,
          SrcHeight, SrcLineSize, DstLineSize, Proc);
        //Stretch vertically
        ResampleBits(DstHeight, SrcHeight, TmpBits, DstBits, DstLineSize,
          DstWidth, PixelSize, PixelSize, Proc);
      end else begin
        GetMem(TmpBits, DstHeight * SrcLineSize);
        //Stretch vertically
        ResampleBits(DstHeight, SrcHeight, SrcBits, TmpBits, SrcLineSize,
          SrcWidth, PixelSize, PixelSize, Proc);
        //Stretch horizontally
        ResampleBits(DstWidth, SrcWidth, TmpBits, DstBits, PixelSize,
          DstHeight, SrcLineSize, DstLineSize, Proc);
      end;
      {$IFDEF FPC}
      DstImage := TLazIntfImage.Create(0, 0);
      if Is32bit then
        Desc.Init_BPP32_B8G8R8A8_BIO_TTB(DstWidth, DstHeight)
      else
        Desc.Init_BPP24_B8G8R8_BIO_TTB(DstWidth, DstHeight);
      DstImage.DataDescription := Desc;
      WritePixels(DstImage, DstBits, PixelSize);
      DstBitmap.LoadFromIntfImage(DstImage);
      {$ENDIF}
      Result := True;
    finally
      FreeMem(TmpBits);
    end;
    {$IFDEF FPC}
    finally
      DstImage.Free;
      SrcImage.Free;
      FreeMem(DstBits);
      FreeMem(SrcBits);
    end;
    {$ENDIF}
  except
  end;
end;

end.