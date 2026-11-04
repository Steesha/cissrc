unit Setup.UninstallProgressForm;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Uninstaller progress form
}

interface

uses
  Windows, {$IFDEF FPC}LCLType,{$ENDIF} Classes, Graphics, Controls, Forms,
  Setup.SetupForm, StdCtrls, ExtCtrls, BitmapImage, NewProgressBar, NewStaticText,
  NewNotebook, NewCtrls;

type
  TUninstallProgressForm = class(TSetupForm)
    FOuterNotebook: TNewNotebook;
    FInnerPage: TNewNotebookPage;
    FInnerNotebook: TNewNotebook;
    FInstallingPage: TNewNotebookPage;
    FMainPanel: TPanel;
    FPageNameLabel: TNewStaticText;
    FPageDescriptionLabel: TNewStaticText;
    FWizardSmallBitmapImage: TBitmapImage;
    FBevel1: TBevel;
    FStatusLabel: TNewStaticText;
    FProgressBar: TNewProgressBar;
    FBeveledLabel: TNewStaticText;
    FBevel: TBevel;
    FCancelButton: TNewButton;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Initialize(const ATitle, AAppName: String);
    procedure UpdateProgress(const AProgress, ARange: Integer);
  published
    property OuterNotebook: TNewNotebook read FOuterNotebook;
    property InnerPage: TNewNotebookPage read FInnerPage;
    property InnerNotebook: TNewNotebook read FInnerNotebook;
    property InstallingPage: TNewNotebookPage read FInstallingPage;
    property MainPanel: TPanel read FMainPanel;
    property PageNameLabel: TNewStaticText read FPageNameLabel;
    property PageDescriptionLabel: TNewStaticText read FPageDescriptionLabel;
    property WizardSmallBitmapImage: TBitmapImage read FWizardSmallBitmapImage;
    property Bevel1: TBevel read FBevel1;
    property StatusLabel: TNewStaticText read FStatusLabel;
    property ProgressBar: TNewProgressBar read FProgressBar;
    property BeveledLabel: TNewStaticText read FBeveledLabel;
    property Bevel: TBevel read FBevel;
    property CancelButton: TNewButton read FCancelButton;
  end;

var
  UninstallProgressForm: TUninstallProgressForm;

implementation

uses
  Themes,
  TaskbarProgressFunc,
  Shared.SetupMessageIDs, Shared.CommonFunc.Vcl, Shared.Struct,
  SetupLdrAndSetup.Messages,
  Setup.MainFunc, Setup.InstFunc;

{$R *.dfm}

{ TUninstallProgressForm }

procedure UninstallMessageBoxCallback(const Flags: Cardinal; const After: Boolean;
  const Param: NativeInt);
const
  States: array [TNewProgressBarState] of TTaskbarProgressState =
    (tpsNormal, tpsError, tpsPaused);
var
  UninstallProgressForm: TUninstallProgressForm;
  NewState: TNewProgressBarState;
begin
  UninstallProgressForm := TUninstallProgressForm(Param);

  if After then
    NewState := npbsNormal
  else if (Flags and MB_ICONSTOP) <> 0 then
    NewState := npbsError
  else
    NewState := npbsPaused;

  with UninstallProgressForm.ProgressBar do begin
    State := NewState;
    Invalidate;
  end;
  SetAppTaskbarProgressState(States[NewState]);
end;

constructor TUninstallProgressForm.Create(AOwner: TComponent);
var
  I: Integer;
  {$IFNDEF FPC}
  LStyle: TCustomStyleServices;
  {$ENDIF}
begin
  inherited;

  SetMessageBoxCallbackFunc(UninstallMessageBoxCallback, NativeInt(Self));

  {$IFNDEF FPC}
  LStyle := StyleServices(Self);
  if not LStyle.Enabled or LStyle.IsSystemStyle then
    LStyle := nil;
  {$ENDIF}

  if not CustomWizardBackground or (SetupHeader.WizardBackColor = clWindow) then
    MainPanel.ParentBackGround := False;

  InitializeFont;
  PageNameLabel.Font.Style := [fsBold];
  PageNameLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgWizardUninstalling]{$IFDEF FPC}){$ENDIF};

  { Initialize wizard style: not done here but in TUninstallProgressForm.Initialize }

  { Adjust page name and description label - also see TWizardForm.Create }
  I := FPageNameLabel.AdjustHeight;
  FPageDescriptionLabel.Top := FPageDescriptionLabel.Top + I;

  { Initialize BeveledLabel }
  if SetupMessages[msgBeveledLabel] <> '' then begin
    BeveledLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}' ' + SetupMessages[msgBeveledLabel] + ' '{$IFDEF FPC}){$ENDIF};
    BeveledLabel.Top := Bevel.Top - ((BeveledLabel.Height - 1) div 2);
    if not CustomWizardBackground then begin
      {$IFNDEF FPC}
      if LStyle <> nil then
        BeveledLabel.Color := LStyle.GetStyleColor(scWindow);
      {$ENDIF}
    end else
      BeveledLabel.Color := TBitmapImageImplementation.AdjustColorForStyle(Self, SetupHeader.WizardBackColor);
    BeveledLabel.Visible := True;
  end;

  CancelButton.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonCancel]{$IFDEF FPC}){$ENDIF};
end;

destructor TUninstallProgressForm.Destroy;
begin
  SetMessageBoxCallbackFunc(nil, 0);
  SetAppTaskbarProgressState(tpsNoProgress);

  inherited;
end;

procedure TUninstallProgressForm.Initialize(const ATitle, AAppName: String);
var
  I: Integer;
  {$IFNDEF FPC}
  LStyle: TCustomStyleServices;
  {$ENDIF}
begin
  {$IFNDEF FPC}
  LStyle := StyleServices(Self);
  if not LStyle.Enabled or LStyle.IsSystemStyle then
    LStyle := nil;
  {$ENDIF}

  Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}ATitle{$IFDEF FPC}){$ENDIF};
  PageDescriptionLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}FmtSetupMessage1(msgUninstallStatusLabel, AAppName){$IFDEF FPC}){$ENDIF};
  StatusLabel.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}FmtSetupMessage1(msgStatusUninstalling, AAppName){$IFDEF FPC}){$ENDIF};

  { Initialize wizard style - also see TWizardForm.Create }
  if not CustomWizardBackground then begin
    {$IFNDEF FPC}
    if LStyle <> nil then begin
      { TNewNotebook ignores VCL Styles so it needs a bit of help }
      OuterNotebook.ParentColor := True;
      Color := LStyle.GetStyleColor(scWindow);
    end;
    {$ENDIF}
  end else begin
    OuterNotebook.ParentBackground := True;
    for I := 0 to OuterNotebook.PageCount-1 do
      OuterNotebook.Pages[I].ParentBackground := True;
    InnerNotebook.ParentBackground := True;
    for I := 0 to InnerNotebook.PageCount-1 do
      InnerNotebook.Pages[I].ParentBackground := True;
  end;
  if lfWizardModern in MessagesLangOptions.Flags then begin
    {$IFDEF FPC}
    if not CustomWizardBackground then
      OuterNotebook.Color := clWindow;
    {$ELSE}
    if LStyle = nil then begin
      if CustomWizardBackground then
        InternalError('Unexpected CustomWizardBackground value');
      OuterNotebook.Color := clWindow;
    end;
    {$ENDIF}
    Bevel1.Visible := False;
  end;
  if lfWizardBevelsHidden in MessagesLangOptions.Flags then begin
    Bevel1.Visible := False;
    Bevel.Visible := False;
  end;

  { Initialize image }
  if not WizardSmallBitmapImage.InitializeFromIcon(HInstance, PChar('Z_UNINSTALLICON' + WizardIconsPostfix), clNone, [32, 48, 64]) then {don't localize}
    WizardSmallBitmapImage.InitializeFromIcon(HInstance, PChar('MAINICON' + MainIconPostfix), clNone, [32, 48, 64]); {don't localize}
end;

procedure TUninstallProgressForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.style := Params.WindowClass.style or CS_NOCLOSE;
end;

procedure TUninstallProgressForm.UpdateProgress(const AProgress, ARange: Integer);
var
  NewPos: Integer;
begin
  NewPos := MulDiv(AProgress, ProgressBar.Max, ARange);
  if ProgressBar.Position <> NewPos then begin
    ProgressBar.Position := NewPos;
    SetAppTaskbarProgressValue(UInt64(NewPos), UInt64(ProgressBar.Max));
  end;
end;

end.
