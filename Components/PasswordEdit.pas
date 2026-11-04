unit PasswordEdit;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  This unit provides a true password edit.
}

interface

uses
  Windows, Classes, Controls, StdCtrls{$IFDEF FPC}, LCLType{$ENDIF};

type
  TPasswordEdit = class(TCustomEdit)
  private
    FPassword: Boolean;
    procedure SetPassword(Value: Boolean);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    {$IFDEF FPC}
    procedure InitializeWnd; override;
    {$ENDIF}
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Anchors;
    property AutoSelect;
    property AutoSize;
    property BorderStyle;
    property CharCase;
    property Color;
    {$IFNDEF FPC}property Ctl3D;{$ENDIF}
    property DragCursor;
    property DragMode;
    property Enabled;
    property Font;
    property HideSelection;
    property MaxLength;
    {$IFNDEF FPC}property OEMConvert;{$ENDIF}
    property ParentColor;
    {$IFNDEF FPC}property ParentCtl3D;{$ENDIF}
    property ParentFont;
    property ParentShowHint;
    property Password: Boolean read FPassword write SetPassword default True;
    property PopupMenu;
    property ReadOnly;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property Text;
    property Visible;
    property OnChange;
    property OnClick;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDrag;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnStartDrag;
  end;

procedure Register;

implementation

{$IFDEF FPC}
uses
  NewCtrls;
{$ENDIF}

procedure Register;
begin
  RegisterComponents('JR', [TPasswordEdit]);
end;

{ TPasswordEdit }

constructor TPasswordEdit.Create(AOwner: TComponent);
begin
  inherited;
  FPassword := True;
end;

procedure TPasswordEdit.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if FPassword then
    Params.Style := Params.Style or ES_PASSWORD;
end;

{$IFDEF FPC}
procedure TPasswordEdit.InitializeWnd;
var
  Mask: WPARAM;
begin
  Mask := 0;
  if FPassword then
    Mask := SendMessageW(Handle, EM_GETPASSWORDCHAR, 0, 0);
  inherited InitializeWnd;
  { LCL applies its PasswordChar during initialization. Restore the mask
    chosen by the native ES_PASSWORD edit. }
  if FPassword then
    SendMessageW(Handle, EM_SETPASSWORDCHAR, Mask, 0);
  InstallEditStyleHandler(Self);
end;
{$ENDIF}

procedure TPasswordEdit.SetPassword(Value: Boolean);
begin
  if FPassword <> Value then begin
    FPassword := Value;
    {$IFDEF FPC}RecreateWnd(Self){$ELSE}RecreateWnd{$ENDIF};
  end;
end;

end.
