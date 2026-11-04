unit Setup.NewDiskForm;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  New Disk form
}

interface

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms,
  Setup.SetupForm, StdCtrls, NewStaticText, BitmapImage, NewCtrls;

type
  TNewDiskForm = class(TSetupForm)
    DiskBitmapImage: TBitmapImage;
    SelectDiskLabel: TNewStaticText;
    PathLabel: TNewStaticText;
    PathEdit: TNewPathEdit;
    BrowseButton: TNewButton;
    OKButton: TNewButton;
    CancelButton: TNewButton;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure BrowseButtonClick(Sender: TObject);
  private
    FFilename: string;
    function GetSanitizedPath: String;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function SelectDisk(const DiskNumber: Integer; const AFilename: String; var Path: String): Boolean;

implementation

uses
  ShellAPI,
  PathFunc, BrowseFunc,
  Shared.SetupMessageIDs, Shared.CommonFunc.Vcl, Shared.CommonFunc,
  SetupLdrAndSetup.Messages, Setup.MainFunc, Setup.WizardForm;

{$R *.dfm}

{$IFDEF FPC}
const
  SIID_MEDIABLANKCD = 59;
{$ENDIF}

function SelectDisk(const DiskNumber: Integer; const AFilename: String;
  var Path: String): Boolean;
begin
  Application.Restore;  { see comments in MsgBox }

  with TNewDiskForm.Create(Application) do
    try
      FFilename := AFilename;
      SelectDiskLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}FmtSetupMessage(msgSelectDiskLabel2, [IntToStr(DiskNumber)]){$IFDEF FPC}){$ENDIF};
      PathEdit.Text := {$IFDEF FPC}UTF8Encode({$ENDIF}Path{$IFDEF FPC}){$ENDIF};
      ActiveControl := OKButton;
      Result := ShowModal = mrOK;
      if Result then
        Path := GetSanitizedPath;
    finally
      Free;
    end;
end;

{ TNewDiskForm }

constructor TNewDiskForm.Create(AOwner: TComponent);
begin
  inherited;

  InitializeFont(False, True);

  Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgChangeDiskTitle]{$IFDEF FPC}){$ENDIF};
  PathLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgPathLabel]{$IFDEF FPC}){$ENDIF};
  BrowseButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonBrowse]{$IFDEF FPC}){$ENDIF};
  OKButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonOK]{$IFDEF FPC}){$ENDIF};
  CancelButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonCancel]{$IFDEF FPC}){$ENDIF};

  DiskBitmapImage.InitializeFromStockIcon(SIID_MEDIABLANKCD, clNone, [48, 64]);

  SetForeground := True;

  { WizardForm will not exist yet if we're being called from [Code]'s
    ExtractTemporaryFile in InitializeSetup }
  FlipAndCenterIfNeeded(Assigned(WizardForm), WizardForm, False);
end;

function TNewDiskForm.GetSanitizedPath: String;
begin
  Result := PathExpand(RemoveBackslashUnlessRoot(Trim({$IFDEF FPC}UTF8Decode(PathEdit.Text){$ELSE}PathEdit.Text{$ENDIF})));
end;

procedure TNewDiskForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Path: String;
begin
  case ModalResult of
    mrOK: begin
        Path := GetSanitizedPath;
        if (Path = '') or not NewFileExists(AddBackslash(Path) + FFilename) then begin
          CanClose := False;
          LoggedMsgBox(FmtSetupMessage(msgFileNotInDir2, [FFilename, Path]),
            '', mbError, MB_OK, False, 0);
        end;
      end;
    mrCancel: CanClose := ExitSetupMsgBox;
  end;
end;

procedure TNewDiskForm.BrowseButtonClick(Sender: TObject);
var
  Dir: String;
begin
  Dir := GetSanitizedPath;
  if BrowseForFolder(SetupMessages[msgSelectDirectoryLabel], Dir, Handle) then
    PathEdit.Text := {$IFDEF FPC}UTF8Encode({$ENDIF}Dir{$IFDEF FPC}){$ENDIF};
end;

end.
