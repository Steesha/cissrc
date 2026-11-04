unit Setup.UninstallSharedFileForm;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  "Remove Shared File" form
}

interface

uses
  Windows, {$IFDEF FPC}LCLType,{$ENDIF} Classes, Graphics, Controls, Forms,
  Setup.SetupForm, StdCtrls, NewStaticText, NewCtrls;

type
  TUninstallSharedFileForm = class(TSetupForm)
    BodyLabel: TNewStaticText;
    FilenameLabel: TNewStaticText;
    FilenameEdit: TEdit;
    LocationLabel: TNewStaticText;
    LocationEdit: TEdit;
    YesButton: TNewButton;
    YesToAllButton: TNewButton;
    NoButton: TNewButton;
    NoToAllButton: TNewButton;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function ExecuteRemoveSharedFileDlg(const Filename: String;
  var AAll: Boolean): Boolean;

implementation

uses
  PathFunc, SetupLdrAndSetup.Messages, Shared.SetupMessageIDs;

{$R *.dfm}

function ExecuteRemoveSharedFileDlg(const Filename: String;
  var AAll: Boolean): Boolean;
var
  Form: TUninstallSharedFileForm;
  Res: Integer;
begin
  Form := TUninstallSharedFileForm.Create(nil);
  try
    Form.FilenameEdit.Text := {$IFDEF FPC}UTF8Encode({$ENDIF}PathExtractName(Filename){$IFDEF FPC}){$ENDIF};
    Form.LocationEdit.Text := {$IFDEF FPC}UTF8Encode({$ENDIF}PathExtractDir(Filename){$IFDEF FPC}){$ENDIF};
    Res := Form.ShowModal;
  finally
    Form.Free;
  end;
  Result := (Res = mrYes) or (Res = mrYesToAll);
  AAll := (Res = mrYesToAll) or (Res = mrNoToAll);
end;

{ TUninstallSharedFileForm }

constructor TUninstallSharedFileForm.Create(AOwner: TComponent);
begin
  inherited;

  InitializeFont(False, True);

  Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgConfirmDeleteSharedFileTitle]{$IFDEF FPC}){$ENDIF};
  BodyLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgConfirmDeleteSharedFile2]{$IFDEF FPC}){$ENDIF};
  FilenameLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgSharedFileNameLabel]{$IFDEF FPC}){$ENDIF};
  LocationLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgSharedFileLocationLabel]{$IFDEF FPC}){$ENDIF};
  YesButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonYes]{$IFDEF FPC}){$ENDIF};
  YesToAllButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonYesToAll]{$IFDEF FPC}){$ENDIF};
  NoButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonNo]{$IFDEF FPC}){$ENDIF};
  NoToAllButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonNoToAll]{$IFDEF FPC}){$ENDIF};
end;

procedure TUninstallSharedFileForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.style := Params.WindowClass.style or CS_NOCLOSE;
end;

end.
