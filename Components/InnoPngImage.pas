unit InnoPngImage;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  For conditions of distribution and use, see LICENSE.TXT.
}

{$MODE DELPHIUNICODE}

interface

uses
  Classes, Graphics;

type
  TPngImage = class(TPortableNetworkGraphic)
  public
    class function CanLoadFromStream(const Stream: TStream): Boolean; static;
    procedure LoadFromStream(Stream: TStream); override;
  end;

implementation

class function TPngImage.CanLoadFromStream(const Stream: TStream): Boolean;
begin
  Result := (Stream.Size - Stream.Position >= 8) and IsStreamFormatSupported(Stream);
end;

procedure TPngImage.LoadFromStream(Stream: TStream);
begin
  inherited LoadFromStream(Stream);
end;

end.
