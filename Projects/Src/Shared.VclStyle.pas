unit Shared.VclStyle;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  For conditions of distribution and use, see LICENSE.TXT.

  VCL style container reader
}

interface

uses
  Classes, SysUtils, Types;

type
  EVclStyleError = class(Exception);

  TVclStyleInfo = record
    FormatVersion: Integer;
    Name, Version, Author, AuthorEmail, AuthorURL: String;
    MasterStyleOffset: Int64;
  end;

  TVclStyleBitmap = record
    Name: String;
    Width, Height: Cardinal;
    PixelOffset, PixelSize: Int64;
  end;

  TVclStyleObject = record
    ClassName: String;
    DataOffset, DataSize: Int64;
  end;

  TVclStyleAssets = record
    Bitmaps: array of TVclStyleBitmap;
    Objects: array of TVclStyleObject;
    PaletteOffset: Int64;
  end;

  TVclStyleBitmapState = (vbsNormal, vbsActive, vbsHot, vbsFocused, vbsPressed, vbsDisabled);

  TVclStyleBitmapRegion = record
    ObjectPath: String;
    State: TVclStyleBitmapState;
    BitmapIndex: Integer;
    Bounds, Margins: TRect;
    TileStyle, BorderTileStyle: String;
  end;

  TVclStyleBitmapRegions = array of TVclStyleBitmapRegion;
  TVclStyleTextColors = array[TVclStyleBitmapState] of String;
  TVclStyleSliceAxis = array[0..3] of Integer;
  TVclStyleCaptionButton = (scbMinimize, scbMaximize, scbHelp, scbClose, scbRestore);
  TVclStyleBorderPart = (vbpLeft, vbpRight, vbpBottom);
  TVclStyleBorderBounds = array[TVclStyleBorderPart] of TRect;

procedure ReadVclStyle(const Input, Decoded: TStream; out Info: TVclStyleInfo);
procedure ReadVclStyleAssets(const Decoded: TStream; out Assets: TVclStyleAssets);
procedure ReadVclStyleFormColors(const Decoded: TStream; const Assets: TVclStyleAssets;
  out Background, Foreground: String);
function ReadVclStyleSystemColor(const Decoded: TStream; const Assets: TVclStyleAssets;
  const ColorName: String): String;
function ReadVclStyleBitmapRegions(const Decoded: TStream; const Assets: TVclStyleAssets;
  const RootName: String): TVclStyleBitmapRegions; overload;
function ReadVclStyleBitmapRegions(const Decoded: TStream; const Assets: TVclStyleAssets;
  const RootName, TextObjectPath: String; out TextColors: TVclStyleTextColors): TVclStyleBitmapRegions; overload;

procedure ReadVclStyleBitmapRow(const Decoded: TStream; const Bitmap: TVclStyleBitmap;
  const X, Y: Integer; var Pixels: TBytes; const BackgroundColorRef: Cardinal;
  const TintColorRef: Cardinal = 0; const TintOpacity: Byte = 0; const PreserveAlpha: Boolean = False);

function SplitVclStyleAxis(const Origin, Extent, StartMargin, EndMargin: Integer): TVclStyleSliceAxis;

function VclStyleProgressWidth(const Width, Min, Max, Position: Integer): Integer;

function VclStyleMarqueeOffset(const Extent, Chunk: Integer; const Elapsed: UInt64): Integer;

function GetVclStyleBorderBounds(const Window, Client: TRect; out Bounds: TVclStyleBorderBounds): Boolean;

procedure ExcludeVclStyleTitleButton(var Caption: TRect; const Title, Button: TRect);

function VclStyleCaptionButtonState(const Active, Hot, Pressed, Disabled: Boolean): TVclStyleBitmapState;

function GetVclStyleCaptionButton(const TitleBarIndex: Integer; const Maximized: Boolean;
  out Button: TVclStyleCaptionButton): Boolean;

implementation

uses
  ZStream;

function ReadUInt32(const Stream: TStream): Cardinal;
var
  Bytes: array[0..3] of Byte;
begin
  Stream.ReadBuffer(Bytes, SizeOf(Bytes));
  Result := Cardinal(Bytes[0]) or (Cardinal(Bytes[1]) shl 8) or
    (Cardinal(Bytes[2]) shl 16) or (Cardinal(Bytes[3]) shl 24);
end;

function ReadStyleString(const Stream: TStream): String;
var
  LengthInChars: Cardinal;
  I: Integer;
  Bytes: array[0..1] of Byte;
begin
  LengthInChars := ReadUInt32(Stream);
  if (LengthInChars > 4096) or
     (Int64(LengthInChars) * 2 > Stream.Size - Stream.Position) then
    raise EVclStyleError.Create('Invalid VCL style metadata length');
  SetLength(Result, LengthInChars);
  for I := 1 to Integer(LengthInChars) do begin
    Stream.ReadBuffer(Bytes, SizeOf(Bytes));
    Result[I] := WideChar(Word(Bytes[0]) or (Word(Bytes[1]) shl 8));
  end;
end;

procedure ReadVclStyle(const Input, Decoded: TStream; out Info: TVclStyleInfo);
const
  MaxDecodedSize = 64 * 1024 * 1024;
var
  Signature: array[1..13] of AnsiChar;
  Marker: array[1..13] of AnsiChar;
  Decoder: TDecompressionStream;
  Buffer: array[0..16383] of Byte;
  Count: Integer;
  Version2Metadata: array[0..5] of Byte;


begin
  Info := Default(TVclStyleInfo);
  Decoded.Size := 0;
  Decoded.Position := 0;
  try
    Input.ReadBuffer(Signature, SizeOf(Signature));
    if Signature = 'VCL_STYLE 1.0' then
      Info.FormatVersion := 1
    else if Signature = 'VCL_STYLE 2.0' then
      Info.FormatVersion := 2
    else
      raise EVclStyleError.Create('Unsupported VCL style container signature');

    Decoder := TDecompressionStream.Create(Input);
    try
      repeat
        Count := Decoder.Read(Buffer, SizeOf(Buffer));
        if Decoded.Position + Count > MaxDecodedSize then
          raise EVclStyleError.Create('VCL style exceeds the decoded size limit');
        Decoded.WriteBuffer(Buffer, Count);
      until Count < SizeOf(Buffer);
    finally
      Decoder.Free;
    end;

    Decoded.Position := 0;
    Info.Name := ReadStyleString(Decoded);
    Info.Version := ReadStyleString(Decoded);
    Info.Author := ReadStyleString(Decoded);
    Info.AuthorEmail := ReadStyleString(Decoded);
    Info.AuthorURL := ReadStyleString(Decoded);
    if Info.FormatVersion = 2 then
      Decoded.ReadBuffer(Version2Metadata, SizeOf(Version2Metadata));
    if (ReadUInt32(Decoded) <> SizeOf(Marker)) or (ReadUInt32(Decoded) <> 0) then
      raise EVclStyleError.Create('Missing VCL master style block');
    Decoded.ReadBuffer(Marker, SizeOf(Marker));
    if Marker <> 'MasterStyle'#13#10 then
      raise EVclStyleError.Create('Invalid VCL master style marker');
    if Decoded.Position = Decoded.Size then
      raise EVclStyleError.Create('Empty VCL master style block');
    Info.MasterStyleOffset := Decoded.Position;
  except
    on E: EStreamError do
      raise EVclStyleError.Create(E.Message);
    on E: EDecompressionError do
      raise EVclStyleError.Create(E.Message);
  end;
end;

procedure ReadVclStyleAssets(const Decoded: TStream; out Assets: TVclStyleAssets);
var
  BitmapCount, ObjectCount, Width, Height, DataSize: Cardinal;
  I: Integer;
  Signature: array[1..4] of AnsiChar;
  PixelSize, Available: Int64;
begin
  Assets := Default(TVclStyleAssets);
  try
    BitmapCount := ReadUInt32(Decoded);
    if BitmapCount > (Decoded.Size - Decoded.Position) div 18 then
      raise EVclStyleError.Create('Invalid VCL style bitmap count');
    SetLength(Assets.Bitmaps, BitmapCount);
    for I := 0 to Integer(BitmapCount) - 1 do begin
      Assets.Bitmaps[I].Name := ReadStyleString(Decoded);
      Width := ReadUInt32(Decoded);
      Height := ReadUInt32(Decoded);
      { Each pixel is stored in four bytes, followed by a two-byte trailer per bitmap }
      Available := Decoded.Size - Decoded.Position - 2;
      if (Width = 0) or (Height = 0) or (Available < 0) or
         (Width > Available div 4 div Height) then
        raise EVclStyleError.Create('Invalid VCL style bitmap dimensions');
      PixelSize := Int64(Width) * Height * 4;
      Assets.Bitmaps[I].Width := Width;
      Assets.Bitmaps[I].Height := Height;
      Assets.Bitmaps[I].PixelOffset := Decoded.Position;
      Assets.Bitmaps[I].PixelSize := PixelSize;
      Decoded.Seek(PixelSize + 2, soCurrent);
    end;

    ObjectCount := ReadUInt32(Decoded);
    if ObjectCount > (Decoded.Size - Decoded.Position) div 12 then
      raise EVclStyleError.Create('Invalid VCL style object count');
    SetLength(Assets.Objects, ObjectCount);
    for I := 0 to Integer(ObjectCount) - 1 do begin
      Assets.Objects[I].ClassName := ReadStyleString(Decoded);
      DataSize := ReadUInt32(Decoded);
      if (DataSize < SizeOf(Signature)) or (DataSize > Decoded.Size - Decoded.Position) then
        raise EVclStyleError.Create('Invalid VCL style object size');
      Assets.Objects[I].DataOffset := Decoded.Position;
      Assets.Objects[I].DataSize := DataSize;
      Decoded.ReadBuffer(Signature, SizeOf(Signature));
      if Signature <> 'TPF0' then
        raise EVclStyleError.Create('Invalid VCL style object signature');
      Decoded.Seek(DataSize - SizeOf(Signature), soCurrent);
    end;
    Assets.PaletteOffset := Decoded.Position;
  except
    on E: EStreamError do
      raise EVclStyleError.Create(E.Message);
  end;
end;

function ReadColorValue(const Reader: TReader): String;
begin
  case Reader.NextValue of
    vaIdent: Result := Reader.ReadIdent;
    vaInt8, vaInt16, vaInt32: Result := IntToStr(Reader.ReadInteger);
  else
    Reader.Driver.SkipValue;
    Result := '';
  end;
end;
procedure ReadVclStyleFormColors(const Decoded: TStream; const Assets: TVclStyleAssets;
  out Background, Foreground: String);
var
  Entry: TVclStyleObject;
  ObjectData: TMemoryStream;
  Reader: TReader;
  Flags: TFilerFlags;
  ChildPos: Integer;
  ClassName, ObjectName: AnsiString;
  PropertyName, Kind, Color, FontColor: String;


begin
  Background := '';
  Foreground := '';
  ObjectData := TMemoryStream.Create;
  try
    for Entry in Assets.Objects do begin
      if Entry.ClassName <> 'TSeStyleObject' then
        Continue;
      ObjectData.Clear;
      Decoded.Position := Entry.DataOffset;
      ObjectData.CopyFrom(Decoded, Entry.DataSize);
      ObjectData.Position := 0;
      Reader := TReader.Create(ObjectData, 4096);
      try
        Reader.ReadSignature;
        ChildPos := 0;
        Reader.Driver.BeginComponent(Flags, ChildPos, ClassName, ObjectName);
        if (ClassName <> 'TSeStyleObject') or (ObjectName <> 'Form') then
          Continue;
        Kind := '';
        Color := '';
        FontColor := '';
        while not Reader.EndOfList do begin
          PropertyName := Reader.Driver.BeginProperty;
          if (PropertyName = 'Kind') and (Reader.NextValue = vaIdent) then
            Kind := Reader.ReadIdent
          else if PropertyName = 'Color' then
            Color := ReadColorValue(Reader)
          else if PropertyName = 'Font.Color' then
            FontColor := ReadColorValue(Reader)
          else
            Reader.Driver.SkipValue;
        end;
        if (Kind = 'skForm') and ((Color <> '') or (FontColor <> '')) then begin
          Background := Color;
          Foreground := FontColor;
          Exit;
        end;
      finally
        Reader.Free;
      end;
    end;
  finally
    ObjectData.Free;
  end;
end;

function ReadVclStyleSystemColor(const Decoded: TStream; const Assets: TVclStyleAssets;
  const ColorName: String): String;
var
  LastIndex: Byte;
  Count: Cardinal;
  I: Integer;
  Name, Value: String;

  procedure ReadEntry;
  begin
    Name := ReadStyleString(Decoded);
    if ReadStyleString(Decoded) <> ':' then
      raise EVclStyleError.Create('Invalid VCL style palette entry');
    Value := ReadStyleString(Decoded);
  end;

begin
  Result := '';
  if (Assets.PaletteOffset <= 0) or (Assets.PaletteOffset >= Decoded.Size) then
    Exit;
  Decoded.Position := Assets.PaletteOffset;
  try
    Decoded.ReadBuffer(LastIndex, SizeOf(LastIndex));
    for I := 0 to LastIndex do
      ReadEntry;
    Count := ReadUInt32(Decoded);
    if Count > (Decoded.Size - Decoded.Position) div 14 then
      raise EVclStyleError.Create('Invalid VCL style system color count');
    for I := 1 to Integer(Count) do begin
      ReadEntry;
      if Name = ColorName then
        Exit(Value);
    end;
  except
    on E: EStreamError do
      raise EVclStyleError.Create(E.Message);
  end;
end;

function ReadVclStyleBitmapRegions(const Decoded: TStream; const Assets: TVclStyleAssets;
  const RootName: String): TVclStyleBitmapRegions;
var
  TextColors: TVclStyleTextColors;
begin
  Result := ReadVclStyleBitmapRegions(Decoded, Assets, RootName, '', TextColors);
end;

function ReadVclStyleBitmapRegions(const Decoded: TStream; const Assets: TVclStyleAssets;
  const RootName, TextObjectPath: String; out TextColors: TVclStyleTextColors): TVclStyleBitmapRegions;
const
  MaxDepth = 16;
  MaxRegions = 4096;
  BitmapPrefixes: array[TVclStyleBitmapState] of String = ('Bitmap.', 'ActiveBitmap.',
    'BitmapHot.', 'BitmapFocused.', 'BitmapPressed.', 'BitmapDisabled.');
  FontColorProperties: array[TVclStyleBitmapState] of String = ('Font.Color', 'ActiveFont.Color',
    'FontHot.Color', 'FontFocused.Color', 'FontPressed.Color', 'FontDisabled.Color');
type
  TRegionSource = record
    BitmapName: String;
    Bounds: TRect;
  end;
var
  Entry: TVclStyleObject;
  ObjectData: TMemoryStream;
  Regions: TVclStyleBitmapRegions;

  procedure AddRegion(const Path: String; const State: TVclStyleBitmapState; const Source: TRegionSource;
    const Margins: TRect; const TileStyle, BorderTileStyle: String);
  var
    I, Index: Integer;
  begin
    if Source.BitmapName = '' then
      Exit;
    for I := 0 to High(Assets.Bitmaps) do
      if SameText(Assets.Bitmaps[I].Name, Source.BitmapName) then begin
        if (Source.Bounds.Left < 0) or (Source.Bounds.Top < 0) or
           (Source.Bounds.Right <= Source.Bounds.Left) or
           (Source.Bounds.Bottom <= Source.Bounds.Top) or
           (Source.Bounds.Right > Assets.Bitmaps[I].Width) or
           (Source.Bounds.Bottom > Assets.Bitmaps[I].Height) then
          Exit;
        Index := Length(Regions);
        if Index >= MaxRegions then
          raise EVclStyleError.Create('Too many VCL style bitmap regions');
        SetLength(Regions, Index + 1);
        Regions[Index].ObjectPath := Path;
        Regions[Index].State := State;
        Regions[Index].BitmapIndex := I;
        Regions[Index].Bounds := Source.Bounds;
        Regions[Index].Margins := Margins;
        Regions[Index].TileStyle := TileStyle;
        Regions[Index].BorderTileStyle := BorderTileStyle;
        Exit;
      end;
  end;

  procedure ReadObject(const Data: TMemoryStream; const ParentPath: String; const Depth: Integer); forward;

  procedure ReadChildren(const Reader: TReader; const ParentPath: String;
    const ParentSize: Int64; const Depth: Integer);
  var
    Container, Child: TMemoryStream;
    Header, DataSize: Cardinal;
    I: Integer;
    SizeBytes: array[0..3] of Byte;
  begin
    Reader.CheckValue(vaBinary);
    Reader.Read(SizeBytes, SizeOf(SizeBytes));
    DataSize := Cardinal(SizeBytes[0]) or (Cardinal(SizeBytes[1]) shl 8) or
      (Cardinal(SizeBytes[2]) shl 16) or (Cardinal(SizeBytes[3]) shl 24);
    if (DataSize < 4) or (DataSize > ParentSize) then
      raise EVclStyleError.Create('Invalid VCL style child object data size');
    Container := TMemoryStream.Create;
    try
      Container.Size := DataSize;
      Reader.Read(Container.Memory^, DataSize);
      Header := ReadUInt32(Container);
      if Header shr 16 <> 15 then
        Exit;
      if (Header and $FFFF) > (Container.Size - Container.Position) div 12 then
        raise EVclStyleError.Create('Invalid VCL style child object count');
      Child := TMemoryStream.Create;
      try
        for I := 1 to Integer(Header and $FFFF) do begin
          ReadStyleString(Container); { Class name is also stored in the object stream }
          DataSize := ReadUInt32(Container);
          if (DataSize < 4) or (DataSize > Container.Size - Container.Position) then
            raise EVclStyleError.Create('Invalid VCL style child object size');
          Child.Clear;
          Child.CopyFrom(Container, DataSize);
          Child.Position := 0;
          ReadObject(Child, ParentPath, Depth);
        end;
      finally
        Child.Free;
      end;
    finally
      Container.Free;
    end;
  end;

  procedure ReadObject(const Data: TMemoryStream; const ParentPath: String; const Depth: Integer);
  var
    Reader: TReader;
    Flags: TFilerFlags;
    ChildPos: Integer;
    ClassName, ObjectName: AnsiString;
    Path, PropertyName, Field: String;
    Sources: array[TVclStyleBitmapState] of TRegionSource;
    State: TVclStyleBitmapState;
    PrefixLength: Integer;
    IsFontColor: Boolean;
    Margins: TRect;
    TileStyle, BorderTileStyle: String;
  begin
    if Depth > MaxDepth then
      raise EVclStyleError.Create('VCL style object nesting exceeds the depth limit');
    Reader := TReader.Create(Data, 4096);
    try
      Reader.ReadSignature;
      ChildPos := 0;
      Reader.Driver.BeginComponent(Flags, ChildPos, ClassName, ObjectName);
      if (Depth = 0) and not SameText(UTF8Decode(ObjectName), RootName) then
        Exit;
      Path := UTF8Decode(ObjectName);
      if ParentPath <> '' then
        Path := ParentPath + '.' + Path;
      Margins := Default(TRect);
      TileStyle := '';
      BorderTileStyle := '';
      for State := Low(State) to High(State) do
        Sources[State] := Default(TRegionSource);
      while not Reader.EndOfList do begin
        PropertyName := Reader.Driver.BeginProperty;
        if (PropertyName = 'Objects') and (Reader.NextValue = vaBinary) then begin
          ReadChildren(Reader, Path, Data.Size, Depth + 1);
          Continue;
        end;
        if (PropertyName = 'TileStyle') and (Reader.NextValue = vaIdent) then begin
          TileStyle := Reader.ReadIdent;
          Continue;
        end;
        if (PropertyName = 'BorderTileStyle') and (Reader.NextValue = vaIdent) then begin
          BorderTileStyle := Reader.ReadIdent;
          Continue;
        end;
        if (Pos('Margin', PropertyName) = 1) and (Reader.NextValue in [vaInt8, vaInt16, vaInt32]) then begin
          if PropertyName = 'MarginLeft' then
            Margins.Left := Reader.ReadInteger
          else if PropertyName = 'MarginTop' then
            Margins.Top := Reader.ReadInteger
          else if PropertyName = 'MarginRight' then
            Margins.Right := Reader.ReadInteger
          else if PropertyName = 'MarginBottom' then
            Margins.Bottom := Reader.ReadInteger
          else
            Reader.Driver.SkipValue;
          Continue;
        end;
        if Path = TextObjectPath then begin
          IsFontColor := False;
          for State := Low(State) to High(State) do
            if PropertyName = FontColorProperties[State] then begin
              TextColors[State] := ReadColorValue(Reader);
              IsFontColor := True;
              Break;
            end;
          if IsFontColor then
            Continue;
        end;
        PrefixLength := 0;
        for State := Low(State) to High(State) do
          if Pos(BitmapPrefixes[State], PropertyName) = 1 then begin
            PrefixLength := Length(BitmapPrefixes[State]);
            Break;
          end;
        if PrefixLength <> 0 then begin
          Field := Copy(PropertyName, PrefixLength + 1, MaxInt);
          if (Field = 'Name') and (Reader.NextValue in [vaString, vaLString, vaWString, vaUTF8String]) then begin
            Sources[State].BitmapName := Reader.ReadString;
            Continue;
          end;
          if Reader.NextValue in [vaInt8, vaInt16, vaInt32] then begin
            if Field = 'Left' then
              Sources[State].Bounds.Left := Reader.ReadInteger
            else if Field = 'Top' then
              Sources[State].Bounds.Top := Reader.ReadInteger
            else if Field = 'Right' then
              Sources[State].Bounds.Right := Reader.ReadInteger
            else if Field = 'Bottom' then
              Sources[State].Bounds.Bottom := Reader.ReadInteger
            else
              Reader.Driver.SkipValue;
            Continue;
          end;
        end;
        Reader.Driver.SkipValue;
      end;
      for State := Low(State) to High(State) do
        AddRegion(Path, State, Sources[State], Margins, TileStyle, BorderTileStyle);
    finally
      Reader.Free;
    end;
  end;

begin
  TextColors := Default(TVclStyleTextColors);
  Regions := nil;
  ObjectData := TMemoryStream.Create;
  try
    for Entry in Assets.Objects do begin
      ObjectData.Clear;
      Decoded.Position := Entry.DataOffset;
      ObjectData.CopyFrom(Decoded, Entry.DataSize);
      ObjectData.Position := 0;
      ReadObject(ObjectData, '', 0);
    end;
    Result := Regions;
  finally
    ObjectData.Free;
  end;
end;

procedure ReadVclStyleBitmapRow(const Decoded: TStream; const Bitmap: TVclStyleBitmap;
  const X, Y: Integer; var Pixels: TBytes; const BackgroundColorRef, TintColorRef: Cardinal;
  const TintOpacity: Byte; const PreserveAlpha: Boolean);
var
  Offset: Int64;
  Index: Integer;
  Alpha, RemainingAlpha: Cardinal;

  function Composite(const Channel: Byte; const BackgroundShift: Integer): Byte;
  var
    Value: Cardinal;
  begin
    Value := Channel;
    if TintOpacity <> 0 then
      { Weight the tint by source coverage before compositing over the background }
      Value := (Value * (255 - TintOpacity) * 255 +
        ((TintColorRef shr BackgroundShift) and $FF) * Alpha * TintOpacity + 32512) div 65025;
    Inc(Value, (((BackgroundColorRef shr BackgroundShift) and $FF) * RemainingAlpha + 127) div 255);
    if Value > 255 then
      Value := 255;
    Result := Byte(Value);
  end;

  function StraightChannel(const Channel: Byte): Byte;
  var
    Value: Cardinal;
  begin
    if Alpha = 0 then
      Exit(0);
    Value := (Cardinal(Channel) * 255 + Alpha div 2) div Alpha;
    if Value > 255 then
      Value := 255;
    Result := Byte(Value);
  end;

begin
  if (Length(Pixels) = 0) or (Length(Pixels) mod 4 <> 0) or (X < 0) or (Y < 0) or
     (Int64(X) + Length(Pixels) div 4 > Bitmap.Width) or (Y >= Bitmap.Height) then
    raise EVclStyleError.Create('Invalid VCL style bitmap row bounds');
  if (Bitmap.PixelOffset < 0) or (Bitmap.PixelSize > Decoded.Size - Bitmap.PixelOffset) or
     (Bitmap.Width > Bitmap.PixelSize div 4 div Bitmap.Height) then
    raise EVclStyleError.Create('Invalid VCL style bitmap data bounds');
  { The style atlas stores premultiplied BGRA rows in bottom-up order }
  Offset := (Int64(Bitmap.Height - 1 - Y) * Bitmap.Width + X) * 4;
  Decoded.Position := Bitmap.PixelOffset + Offset;
  Decoded.ReadBuffer(Pixels[0], Length(Pixels));
  Index := 0;
  while Index < Length(Pixels) do begin
    Alpha := Pixels[Index + 3];
    RemainingAlpha := 255 - Alpha;
    if PreserveAlpha then begin
      Pixels[Index] := StraightChannel(Pixels[Index]);
      Pixels[Index + 1] := StraightChannel(Pixels[Index + 1]);
      Pixels[Index + 2] := StraightChannel(Pixels[Index + 2]);
    end else if (RemainingAlpha <> 0) or (TintOpacity <> 0) then begin
      Pixels[Index] := Composite(Pixels[Index], 16);
      Pixels[Index + 1] := Composite(Pixels[Index + 1], 8);
      Pixels[Index + 2] := Composite(Pixels[Index + 2], 0);
      Pixels[Index + 3] := 255;
    end;
    Inc(Index, 4);
  end;
end;

function SplitVclStyleAxis(const Origin, Extent, StartMargin, EndMargin: Integer): TVclStyleSliceAxis;
var
  TotalMargin: Int64;
begin
  Result[0] := Origin;
  Result[3] := Origin + Extent;
  TotalMargin := Int64(StartMargin) + EndMargin;
  if TotalMargin > Extent then begin
    Result[1] := Origin + Int64(Extent) * StartMargin div TotalMargin;
    Result[2] := Result[1];
  end else begin
    Result[1] := Origin + StartMargin;
    Result[2] := Result[3] - EndMargin;
  end;
end;

function VclStyleProgressWidth(const Width, Min, Max, Position: Integer): Integer;
var
  Range, Offset: Int64;
begin
  Range := Int64(Max) - Min;
  if (Width <= 0) or (Range <= 0) or (Position <= Min) then
    Exit(0);
  if Position >= Max then
    Exit(Width);
  Offset := Int64(Position) - Min;
  Result := (Int64(Width) * Offset + Range div 2) div Range;
end;

function VclStyleMarqueeOffset(const Extent, Chunk: Integer; const Elapsed: UInt64): Integer;
var
  Travel: UInt64;
begin
  if (Extent <= 0) or (Chunk <= 0) then
    Exit(0);
  Travel := UInt64(Extent) + UInt64(Chunk);
  Result := Int64(((Elapsed div 30) mod Travel) * 5 mod Travel) - Chunk;
end;

function GetVclStyleBorderBounds(const Window, Client: TRect; out Bounds: TVclStyleBorderBounds): Boolean;
begin
  Result := (Client.Left >= Window.Left) and (Client.Top >= Window.Top) and
    (Client.Right <= Window.Right) and (Client.Bottom <= Window.Bottom) and
    (Client.Right > Client.Left) and (Client.Bottom > Client.Top);
  if not Result then
    Exit;
  Bounds[vbpLeft] := Rect(Window.Left, Client.Top, Client.Left, Client.Bottom);
  Bounds[vbpRight] := Rect(Client.Right, Client.Top, Window.Right, Client.Bottom);
  Bounds[vbpBottom] := Rect(Window.Left, Client.Bottom, Window.Right, Window.Bottom);
end;

procedure ExcludeVclStyleTitleButton(var Caption: TRect; const Title, Button: TRect);
begin
  if (Button.Right <= Button.Left) or (Button.Bottom <= Title.Top) or
     (Button.Top >= Title.Bottom) or (Button.Right <= Title.Left) or (Button.Left >= Title.Right) then
    Exit;
  if Int64(Button.Left) + Button.Right < Int64(Title.Left) + Title.Right then begin
    if Button.Right > Caption.Left then
      Caption.Left := Button.Right;
  end else if Button.Left < Caption.Right then
    Caption.Right := Button.Left;
end;

function VclStyleCaptionButtonState(const Active, Hot, Pressed, Disabled: Boolean): TVclStyleBitmapState;
begin
  if Disabled then
    Result := vbsDisabled
  else if Pressed then
    Result := vbsPressed
  else if Hot then
    Result := vbsHot
  else if Active then
    Result := vbsActive
  else
    Result := vbsNormal;
end;

function GetVclStyleCaptionButton(const TitleBarIndex: Integer; const Maximized: Boolean;
  out Button: TVclStyleCaptionButton): Boolean;
begin
  case TitleBarIndex of
    2: Button := scbMinimize;
    3:
      if Maximized then
        Button := scbRestore
      else
        Button := scbMaximize;
    4: Button := scbHelp;
    5: Button := scbClose;
  else
    Exit(False);
  end;
  Result := True;
end;

end.
