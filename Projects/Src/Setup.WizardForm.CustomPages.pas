unit Setup.WizardForm.CustomPages;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Custom wizard pages
}

interface

uses
  Windows, SysUtils, Classes, Controls, Forms, StdCtrls, Generics.Collections,
  Shared.Struct, Shared.CommonFunc.Vcl,
  Setup.WizardForm, Setup.DownloadFileFunc, Setup.ISSigVerifyFunc, Setup.InstFunc, Compression.SevenZipDecoder,
  NewCheckListBox, NewStaticText, NewProgressBar, PasswordEdit, RichEditViewer,
  NewCtrls, TaskbarProgressFunc;

type
  TInputQueryWizardPage = class(TWizardPage)
    private
      FEdits: TList<TPasswordEdit>;
      FPromptLabels: TList<TNewStaticText>;
      FSubCaptionLabel: TNewStaticText;
      FY: Integer;
      function GetEdit(Index: NativeInt): TPasswordEdit;
      function GetPromptLabel(Index: NativeInt): TNewStaticText;
      function GetValue(Index: NativeInt): String;
      procedure SetValue(Index: NativeInt; const Value: String);
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      function Add(const APrompt: String; const APassword: Boolean): NativeInt;
      property Edits[Index: NativeInt]: TPasswordEdit read GetEdit;
      procedure Initialize(const SubCaption: String);
      property PromptLabels[Index: NativeInt]: TNewStaticText read GetPromptLabel;
      property Values[Index: NativeInt]: String read GetValue write SetValue;
    published
      property SubCaptionLabel: TNewStaticText read FSubCaptionLabel;
  end;

  TInputOptionWizardPage = class(TWizardPage)
    private
      FCheckListBox: TNewCheckListBox;
      FExclusive: Boolean;
      FSubCaptionLabel: TNewStaticText;
      function GetSelectedValueIndex: Integer;
      function GetValue(Index: Integer): Boolean;
      procedure SetSelectedValueIndex(Value: Integer);
      procedure SetValue(Index: Integer; Value: Boolean);
    public
      function Add(const ACaption: String): Integer;
      function AddEx(const ACaption: String; const ALevel: Byte; const AExclusive: Boolean): Integer;
      procedure Initialize(const SubCaption: String; const Exclusive, ListBox: Boolean);
      property SelectedValueIndex: Integer read GetSelectedValueIndex write SetSelectedValueIndex;
      property Values[Index: Integer]: Boolean read GetValue write SetValue;
    published
      property CheckListBox: TNewCheckListBox read FCheckListBox;
      property SubCaptionLabel: TNewStaticText read FSubCaptionLabel;
  end;

  TInputDirWizardPage = class(TWizardPage)
    private
      FAppendDir: Boolean;
      FButtons: TList<TNewButton>;
      FEdits: TList<TNewPathEdit>;
      FNewFolderName: String;
      FPromptLabels: TList<TNewStaticText>;
      FSubCaptionLabel: TNewStaticText;
      FY: Integer;
      procedure ButtonClick(Sender: TObject);
      function GetButton(Index: NativeInt): TNewButton;
      function GetEdit(Index: NativeInt): TNewPathEdit;
      function GetPromptLabel(Index: NativeInt): TNewStaticText;
      function GetValue(Index: NativeInt): String;
      procedure SetValue(Index: NativeInt; const Value: String);
    protected
      procedure NextButtonClick(var Continue: Boolean); override;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      function Add(const APrompt: String): NativeInt;
      property Buttons[Index: NativeInt]: TNewButton read GetButton;
      property Edits[Index: NativeInt]: TNewPathEdit read GetEdit;
      procedure Initialize(const SubCaption: String; const AppendDir: Boolean;
        const NewFolderName: String);
      property PromptLabels[Index: NativeInt]: TNewStaticText read GetPromptLabel;
      property Values[Index: NativeInt]: String read GetValue write SetValue;
    published
      property NewFolderName: String read FNewFolderName write FNewFolderName;
      property SubCaptionLabel: TNewStaticText read FSubCaptionLabel;
  end;

  TInputFileWizardPage = class(TWizardPage)
    private
      FButtons: TList<TNewButton>;
      FEdits: TList<TNewPathEdit>;
      FInputFileDefaultExtensions: TStringList;
      FInputFileFilters: TStringList;
      FPromptLabels: TList<TNewStaticText>;
      FSubCaptionLabel: TNewStaticText;
      FY: Integer;
      procedure ButtonClick(Sender: TObject);
      function GetButton(Index: NativeInt): TNewButton;
      function GetEdit(Index: NativeInt): TNewPathEdit;
      function GetPromptLabel(Index: NativeInt): TNewStaticText;
      function GetValue(Index: NativeInt): String;
      procedure SetValue(Index: NativeInt; const Value: String);
      function GetIsSaveButton(Index: NativeInt): Boolean;
      procedure SetIsSaveButton(Index: NativeInt; const IsSaveButton: Boolean);
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      function Add(const APrompt, AFilter, ADefaultExtension: String): NativeInt;
      property Buttons[Index: NativeInt]: TNewButton read GetButton;
      property Edits[Index: NativeInt]: TNewPathEdit read GetEdit;
      procedure Initialize(const SubCaption: String);
      property PromptLabels[Index: NativeInt]: TNewStaticText read GetPromptLabel;
      property Values[Index: NativeInt]: String read GetValue write SetValue;
      property IsSaveButton[Index: NativeInt]: Boolean read GetIsSaveButton write SetIsSaveButton;
    published
      property SubCaptionLabel: TNewStaticText read FSubCaptionLabel;
  end;

  TOutputMsgWizardPage = class(TWizardPage)
    private
      FMsgLabel: TNewStaticText;
    public
      procedure Initialize(const Msg: String);
    published
      property MsgLabel: TNewStaticText read FMsgLabel;
  end;

  TOutputMsgMemoWizardPage = class(TWizardPage)
    private
      FRichEditViewer: TRichEditViewer;
      FSubCaptionLabel: TNewStaticText;
    public
      procedure Initialize(const SubCaption: String; const Msg: AnsiString);
    published
      property RichEditViewer: TRichEditViewer read FRichEditViewer;
      property SubCaptionLabel: TNewStaticText read FSubCaptionLabel;
  end;

  TOutputProgressWizardPage = class(TWizardPage)
    private
      FMsg1Label: TNewStaticText;
      FMsg2Label: TNewStaticText;
      FProgressBar: TNewProgressBar;
      FUseMarqueeStyle: Boolean;
      FSavePageID: Integer;
      FSaveMessageBoxCallbackFunc: TMsgBoxCallbackFunc;
      FSaveMessageBoxCallbackParam: NativeInt;
      procedure ProcessMsgs;
    public
      constructor Create(AOwner: TComponent); override;
      procedure Hide;
      procedure Initialize; virtual;
      procedure SetProgress(const Position, Max: Integer);
      procedure SetText(const Msg1, Msg2: String);
      procedure Show; virtual;
    published
      property Msg1Label: TNewStaticText read FMsg1Label;
      property Msg2Label: TNewStaticText read FMsg2Label;
      property ProgressBar: TNewProgressBar read FProgressBar;
  end;

  TOutputMarqueeProgressWizardPage = class(TOutputProgressWizardPage)
    public
      constructor Create(AOwner: TComponent); override;
      procedure Animate;
      procedure Initialize; override;
      procedure SetProgress(const Position, Max: Integer);
  end;

  TDownloadFile = class
    Url, BaseName, UserName, Password: String;
    Verification: TSetupFileVerification;
    DotISSigEntry: Boolean;
    Data: NativeInt; { Only valid if DotISSigEntry is False }
  end;
  TDownloadFiles = TObjectList<TDownloadFile>;

  TDownloadFileCompleted = {$IFNDEF FPC}reference to{$ENDIF} procedure(const DownloadedFile: TDownloadFile;
    const DestFile: String; var Remove: Boolean);

  TDownloadWizardPage = class(TOutputProgressWizardPage)
    private
      FFiles: TDownloadFiles;
      FOnDownloadProgress: TOnDownloadProgress;
      FShowBaseNameInsteadOfUrl: Boolean;
      FAbortButton: TNewButton;
      FShowProgressControlsOnNextProgress, FAbortedByUser: Boolean;
      FThrottler: TProgressThrottler;
      FLastBaseNameOrUrl: String;
      function DoAdd(const Url, BaseName, RequiredSHA256OfFile: String;
        const UserName, Password: String; const ISSigVerify: Boolean;
        const ISSigAllowedKeys: AnsiString; const DotISSigEntry: Boolean; const Data: NativeInt): NativeInt;
      procedure AbortButtonClick(Sender: TObject);
      function InternalOnDownloadProgress(const Url, BaseName: string; const Progress, ProgressMax: Int64): Boolean;
      function InternalOnDownloadNoProgress: Boolean;
      function InternalThrottledOnDownloadProgress(const Url, BaseName: string; const Progress, ProgressMax: Int64): Boolean;
      procedure ShowProgressControls(const AVisible: Boolean);
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      procedure Initialize; override;
      function Add(const Url, BaseName, RequiredSHA256OfFile: String): NativeInt;
      function AddWithISSigVerify(const Url, ISSigUrl, BaseName: String;
        const AllowedKeysRuntimeIDs: TStringList): NativeInt;
      function AddEx(const Url, BaseName, RequiredSHA256OfFile, UserName, Password: String;
        const Data: NativeInt): NativeInt;
      function AddExWithISSigVerify(const Url, ISSigUrl, BaseName, UserName, Password: String;
        const AllowedKeysRuntimeIDs: TStringList; const Data: NativeInt): NativeInt; overload;
      function AddExWithISSigVerify(const Url, ISSigUrl, BaseName, UserName, Password: String;
        const ISSigAllowedKeys: AnsiString; const Data: NativeInt): NativeInt; overload;
      procedure Clear;
      function Download(const OnDownloadFileCompleted: TDownloadFileCompleted): Int64;
      property OnDownloadProgress: TOnDownloadProgress write FOnDownloadProgress;
      procedure Show; override;
    published
      property AbortButton: TNewButton read FAbortButton;
      property AbortedByUser: Boolean read FAbortedByUser;
      property LastBaseNameOrUrl: String read FLastBaseNameOrUrl;
      property ShowBaseNameInsteadOfUrl: Boolean read FShowBaseNameInsteadOfUrl write FShowBaseNameInsteadOfUrl;
  end;
  
  TArchive = class
    FileName, DestDir, Password: String;
    FullPaths: Boolean;
  end;
  TArchives = TObjectList<TArchive>;

  TExtractionWizardPage = class(TOutputProgressWizardPage)
    private
      FArchives: TArchives;
      FOnExtractionProgress: TOnExtractionProgress;
      FShowArchiveInsteadOfFile: Boolean;
      FAbortButton: TNewButton;
      FShowProgressControlsOnNextProgress, FAbortedByUser: Boolean;
      FThrottler: TProgressThrottler;
      procedure AbortButtonClick(Sender: TObject);
      function InternalOnExtractionProgress(const ArchiveName, FileName: string; const Progress, ProgressMax: Int64): Boolean;
      function InternalThrottledOnExtractionProgress(const ArchiveName, FileName: string; const Progress, ProgressMax: Int64): Boolean;
      procedure ShowProgressControls(const AVisible: Boolean);
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      procedure Initialize; override;
      function Add(const ArchiveFileName, DestDir: String; const FullPaths: Boolean): NativeInt;
      function AddEx(const ArchiveFileName, DestDir, Password: String; const FullPaths: Boolean): NativeInt;
      procedure Clear;
      procedure Extract;
      property OnExtractionProgress: TOnExtractionProgress write FOnExtractionProgress;
      procedure Show; override;
    published
      property AbortButton: TNewButton read FAbortButton;
      property AbortedByUser: Boolean read FAbortedByUser;
      property ShowArchiveInsteadOfFile: Boolean read FShowArchiveInsteadOfFile write FShowArchiveInsteadOfFile;
  end;

function ConvertAllowedKeysRuntimeIDsToISSigAllowedKeys(const AllowedKeysRuntimeIDs: TStringList): AnsiString;

implementation

uses
  StrUtils, ISSigFunc, SHA256,
  Shared.SetupTypes, Setup.MainFunc, Setup.SelectFolderForm,
  SetupLdrAndSetup.Messages, Shared.SetupMessageIDs, PathFunc,
  Shared.CommonFunc, BrowseFunc, Setup.LoggingFunc, Setup.SetupForm,
  Compression.SevenZipDLLDecoder;

const
  DefaultLabelHeight = 14;
  DefaultBoxTop = 24;       { relative to top of InnerNotebook }
  DefaultBoxBottom = DefaultBoxTop + 205;

{------}

procedure SetCtlParentAtBack(const AControl, AParent: TWinControl);
{ Like assigning to AControl.Parent, but puts the control at the *bottom* of
  the z-order instead of the top, for MSAA compatibility }
var
  OldVisible: Boolean;
begin
  { Hide the control so the handle won't be created yet, so that unnecessary
    "OBJ_REORDER" MSAA events don't get sent }
  OldVisible := AControl.Visible;
  AControl.Visible := False;
  TSetupForm.SetCtlParent(AControl, AParent);
  AControl.SendToBack;
  AControl.Visible := OldVisible;
end;

{--- InputQuery ---}

constructor TInputQueryWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  FEdits := TList<TPasswordEdit>.Create;
  FPromptLabels := TList<TNewStaticText>.Create;
end;

destructor TInputQueryWizardPage.Destroy;
begin
  FPromptLabels.Free;
  FEdits.Free;
  inherited;
end;

procedure TInputQueryWizardPage.Initialize(const SubCaption: String);
begin
  FSubCaptionLabel := TNewStaticText.Create(Self);
  with FSubCaptionLabel do begin
    AutoSize := False;
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
    WordWrap := True;
    Caption := {$IFDEF FPC}UTF8Encode(SubCaption){$ELSE}SubCaption{$ENDIF};
  end;
  TSetupForm.SetCtlParent(FSubCaptionLabel, Surface);
  FY := WizardForm.AdjustLabelHeight(FSubCaptionLabel) + WizardForm.ScalePixelsY(DefaultBoxTop);
end;

function TInputQueryWizardPage.Add(const APrompt: String;
  const APassword: Boolean): NativeInt;
var
  PromptLabel: TNewStaticText;
  Edit: TPasswordEdit;
begin
  if APrompt <> '' then begin
    PromptLabel := TNewStaticText.Create(Self);
    with PromptLabel do begin
      AutoSize := False;
      Top := FY;
      Width := SurfaceWidth;
      Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
      WordWrap := True;
      Caption := {$IFDEF FPC}UTF8Encode(APrompt){$ELSE}APrompt{$ENDIF};
    end;
    SetCtlParentAtBack(PromptLabel, Surface);
    Inc(FY, WizardForm.AdjustLabelHeight(PromptLabel) + WizardForm.ScalePixelsY(16));
  end else
    PromptLabel := nil;

  Edit := TPasswordEdit.Create(Self);
  with Edit do begin
    Password := APassword;
    Top := FY;
    Width := SurfaceWidth;
  end;
  SetCtlParentAtBack(Edit, Surface);
  Inc(FY, WizardForm.ScalePixelsY(36));

  if PromptLabel <> nil then
    PromptLabel.FocusControl := Edit;

  FPromptLabels.Add(PromptLabel);
  Result := FEdits.Add(Edit);
end;

function TInputQueryWizardPage.GetEdit(Index: NativeInt): TPasswordEdit;
begin
  Result := FEdits[Index];
end;

function TInputQueryWizardPage.GetPromptLabel(Index: NativeInt): TNewStaticText;
begin
  Result := FPromptLabels[Index];
end;

function TInputQueryWizardPage.GetValue(Index: NativeInt): String;
begin
  Result := {$IFDEF FPC}UTF8Decode(GetEdit(Index).Text){$ELSE}GetEdit(Index).Text{$ENDIF};
end;

procedure TInputQueryWizardPage.SetValue(Index: NativeInt; const Value: String);
begin
  GetEdit(Index).Text := {$IFDEF FPC}UTF8Encode(Value){$ELSE}Value{$ENDIF};
end;

{--- InputOption ---}

procedure TInputOptionWizardPage.Initialize(const SubCaption: String;
  const Exclusive, ListBox: Boolean);
var
  CaptionYDiff: Integer;
begin
  FSubCaptionLabel := TNewStaticText.Create(Self);
  with SubCaptionLabel do begin
    AutoSize := False;
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
    WordWrap := True;
    Caption := {$IFDEF FPC}UTF8Encode(SubCaption){$ELSE}SubCaption{$ENDIF};
  end;
  TSetupForm.SetCtlParent(FSubCaptionLabel, Surface);
  CaptionYDiff := WizardForm.AdjustLabelHeight(SubCaptionLabel);

  FCheckListBox := TNewCheckListBox.Create(Self);
  with FCheckListBox do begin
    Top := CaptionYDiff + WizardForm.ScalePixelsY(DefaultBoxTop);
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultBoxBottom) + SurfaceExtraHeight - Top;
    Flat := ListBox and (shFlatComponentsList in SetupHeader.Options);
  end;
  SetCtlParentAtBack(FCheckListBox, Surface);

  FExclusive := Exclusive;
  if not ListBox then begin
    FCheckListBox.BorderStyle := bsNone;
    FCheckListBox.Color := SurfaceColor;
    FCheckListBox.MinItemHeight := WizardForm.ScalePixelsY(22);
    FCheckListBox.WantTabs := True;
  end;
end;

function TInputOptionWizardPage.Add(const ACaption: String): Integer;
begin
  Result := AddEx(ACaption, 0, FExclusive);
end;

function TInputOptionWizardPage.AddEx(const ACaption: String;
  const ALevel: Byte; const AExclusive: Boolean): Integer;
begin
  if AExclusive then
    Result := FCheckListBox.AddRadioButton(ACaption, '', ALevel, False, True, nil)
  else
    Result := FCheckListBox.AddCheckBox(ACaption, '', ALevel, False, True, True,
      True, nil);
end;

function TInputOptionWizardPage.GetSelectedValueIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to FCheckListBox.Items.Count-1 do
    if (FCheckListBox.ItemLevel[I] = 0) and FCheckListBox.Checked[I] then begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function TInputOptionWizardPage.GetValue(Index: Integer): Boolean;
begin
  Result := FCheckListBox.Checked[Index];
end;

procedure TInputOptionWizardPage.SetSelectedValueIndex(Value: Integer);
var
  I: Integer;
begin
  for I := 0 to FCheckListBox.Items.Count-1 do
    if FCheckListBox.ItemLevel[I] = 0 then
      FCheckListBox.Checked[I] := (I = Value);
end;

procedure TInputOptionWizardPage.SetValue(Index: Integer; Value: Boolean);
begin
  FCheckListBox.Checked[Index] := Value;
end;

{--- InputDir ---}

constructor TInputDirWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  FButtons := TList<TNewButton>.Create;
  FEdits := TList<TNewPathEdit>.Create;
  FPromptLabels := TList<TNewStaticText>.Create;
end;

destructor TInputDirWizardPage.Destroy;
begin
  FPromptLabels.Free;
  FEdits.Free;
  FButtons.Free;
  inherited;
end;

procedure TInputDirWizardPage.ButtonClick(Sender: TObject);
var
  I: NativeInt;
  Edit: TNewPathEdit;
  S: String;
begin
  if Sender is TNewButton then begin
    I := FButtons.IndexOf(Sender as TNewButton);
    if I <> -1 then begin
      Edit := FEdits[I];
      S := {$IFDEF FPC}UTF8Decode(Edit.Text){$ELSE}Edit.Text{$ENDIF};
      if ShowSelectFolderDialog(False, FAppendDir, S, FNewFolderName) then
        Edit.Text := {$IFDEF FPC}UTF8Encode(S){$ELSE}S{$ENDIF};
    end;
  end;
end;

procedure TInputDirWizardPage.NextButtonClick(var Continue: Boolean);
var
  I: Integer;
  Edit: TNewPathEdit;
begin
  for I := 0 to FEdits.Count-1 do begin
    Edit := FEdits[I];
    if not ValidateCustomDirEdit(Edit, True, True, True) then begin
      if WizardForm.Visible then
        Edit.SetFocus;
      Continue := False;
      Exit;
    end;
  end;
  inherited;
end;

procedure TInputDirWizardPage.Initialize(const SubCaption: String;
  const AppendDir: Boolean; const NewFolderName: String);
begin
  FSubCaptionLabel := TNewStaticText.Create(Self);
  with FSubCaptionLabel do begin
    AutoSize := False;
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
    WordWrap := True;
    Caption := {$IFDEF FPC}UTF8Encode(SubCaption){$ELSE}SubCaption{$ENDIF};
  end;
  TSetupForm.SetCtlParent(FSubCaptionLabel, Surface);
  FY := WizardForm.AdjustLabelHeight(FSubCaptionLabel) + WizardForm.ScalePixelsY(DefaultBoxTop);

  FAppendDir := AppendDir;
  FNewFolderName := NewFolderName;
end;

function TInputDirWizardPage.Add(const APrompt: String): NativeInt;
var
  ButtonWidth: Integer;
  PromptLabel: TNewStaticText;
  Edit: TNewPathEdit;
  Button: TNewButton;
begin
  ButtonWidth := WizardForm.CalculateButtonWidth([SetupMessages[msgButtonWizardBrowse]]);

  if APrompt <> '' then begin
    PromptLabel := TNewStaticText.Create(Self);
    with PromptLabel do begin
      AutoSize := False;
      Top := FY;
      Width := SurfaceWidth;
      Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
      WordWrap := True;
      Caption := {$IFDEF FPC}UTF8Encode(APrompt){$ELSE}APrompt{$ENDIF};
    end;
    SetCtlParentAtBack(PromptLabel, Surface);
    Inc(FY, WizardForm.AdjustLabelHeight(PromptLabel) + WizardForm.ScalePixelsY(16));
  end else
    PromptLabel := nil;

  Edit := TNewPathEdit.Create(Self);
  with Edit do begin
    Top := FY;
    Width := SurfaceWidth-ButtonWidth-WizardForm.ScalePixelsX(10);
  end;
  SetCtlParentAtBack(Edit, Surface);

  if PromptLabel <> nil then
    PromptLabel.FocusControl := Edit;

  Button := TNewButton.Create(Self);
  with Button do begin
    Left := SurfaceWidth-ButtonWidth;
    Top := Edit.Top-1;
    Width := ButtonWidth;
    Height := WizardForm.NextButton.Height;
    if FEdits.Count = 0 then
      Caption := {$IFDEF FPC}UTF8Encode(SetupMessages[msgButtonWizardBrowse]){$ELSE}SetupMessages[msgButtonWizardBrowse]{$ENDIF}
    else
      { Can't use the same accel key for secondary buttons... }
      Caption := {$IFDEF FPC}UTF8Encode(RemoveAccelChar(SetupMessages[msgButtonWizardBrowse])){$ELSE}RemoveAccelChar(SetupMessages[msgButtonWizardBrowse]){$ENDIF};
    OnClick := ButtonClick;
  end;
  SetCtlParentAtBack(Button, Surface);
  Inc(FY, WizardForm.ScalePixelsY(36));

  FButtons.Add(Button);
  FPromptLabels.Add(PromptLabel);
  Result := FEdits.Add(Edit);
end;

function TInputDirWizardPage.GetButton(Index: NativeInt): TNewButton;
begin
  Result := FButtons[Index];
end;

function TInputDirWizardPage.GetEdit(Index: NativeInt): TNewPathEdit;
begin
  Result := FEdits[Index];
end;

function TInputDirWizardPage.GetPromptLabel(Index: NativeInt): TNewStaticText;
begin
  Result := FPromptLabels[Index];
end;

function TInputDirWizardPage.GetValue(Index: NativeInt): String;
begin
  Result := {$IFDEF FPC}UTF8Decode(GetEdit(Index).Text){$ELSE}GetEdit(Index).Text{$ENDIF};
end;

procedure TInputDirWizardPage.SetValue(Index: NativeInt; const Value: String);
begin
  GetEdit(Index).Text := {$IFDEF FPC}UTF8Encode(RemoveBackslashUnlessRoot(PathExpand(Value))){$ELSE}RemoveBackslashUnlessRoot(PathExpand(Value)){$ENDIF};
end;

{--- InputFile ---}

constructor TInputFileWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  FButtons := TList<TNewButton>.Create;
  FEdits := TList<TNewPathEdit>.Create;
  FInputFileDefaultExtensions := TStringList.Create;
  FInputFileFilters := TStringList.Create;
  FPromptLabels := TList<TNewStaticText>.Create;
end;

destructor TInputFileWizardPage.Destroy;
begin
  FPromptLabels.Free;
  FInputFileFilters.Free;
  FInputFileDefaultExtensions.Free;
  FEdits.Free;
  FButtons.Free;
  inherited;
end;

procedure TInputFileWizardPage.ButtonClick(Sender: TObject);
var
  I: Integer;
  Edit: TNewPathEdit;
  FileName, Filter, DefaultExtension: String;
begin
  if Sender is TNewButton then begin
    { Casting to Integer because TStringList is used below, and TStringList
      indexes are still Integer in 64-bit (unlike TList, which uses NativeInt) }
    I := Integer(FButtons.IndexOf(Sender as TNewButton));
    if I <> -1 then begin
      Edit := FEdits[I];
      FileName := {$IFDEF FPC}UTF8Decode(Edit.Text){$ELSE}Edit.Text{$ENDIF};
      Filter := {$IFDEF FPC}UTF8Decode(FInputFileFilters[I]){$ELSE}FInputFileFilters[I]{$ENDIF};
      DefaultExtension := {$IFDEF FPC}UTF8Decode(FInputFileDefaultExtensions[I]){$ELSE}FInputFileDefaultExtensions[I]{$ENDIF};
      if (not IsSaveButton[I] and NewGetOpenFileName(RemoveAccelChar(SetupMessages[msgButtonWizardBrowse]),
          FileName, PathExtractPath(FileName), Filter, DefaultExtension, Surface.Handle)) or
         (IsSaveButton[I] and NewGetSaveFileName(RemoveAccelChar(SetupMessages[msgButtonWizardBrowse]),
          FileName, PathExtractPath(FileName), Filter, DefaultExtension, Surface.Handle)) then
        Edit.Text := {$IFDEF FPC}UTF8Encode(FileName){$ELSE}FileName{$ENDIF};
    end;
  end;
end;

procedure TInputFileWizardPage.Initialize(const SubCaption: String);
begin
  FSubCaptionLabel := TNewStaticText.Create(Self);
  with FSubCaptionLabel do begin
    AutoSize := False;
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
    WordWrap := True;
    Caption := {$IFDEF FPC}UTF8Encode(SubCaption){$ELSE}SubCaption{$ENDIF};
  end;
  TSetupForm.SetCtlParent(FSubCaptionLabel, Surface);
  FY := WizardForm.AdjustLabelHeight(FSubCaptionLabel) + WizardForm.ScalePixelsY(DefaultBoxTop);
end;

function TInputFileWizardPage.Add(const APrompt, AFilter,
  ADefaultExtension: String): NativeInt;
var
  ButtonWidth: Integer;
  PromptLabel: TNewStaticText;
  Edit: TNewPathEdit;
  Button: TNewButton;
begin
  ButtonWidth := WizardForm.CalculateButtonWidth([SetupMessages[msgButtonWizardBrowse]]);

  if APrompt <> '' then begin
    PromptLabel := TNewStaticText.Create(Self);
    with PromptLabel do begin
      AutoSize := False;
      Top := FY;
      Width := SurfaceWidth;
      Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
      WordWrap := True;
      Caption := {$IFDEF FPC}UTF8Encode(APrompt){$ELSE}APrompt{$ENDIF};
    end;
    SetCtlParentAtBack(PromptLabel, Surface);
    Inc(FY, WizardForm.AdjustLabelHeight(PromptLabel) + WizardForm.ScalePixelsY(16));
  end else
    PromptLabel := nil;

  Edit := TNewPathEdit.Create(Self);
  with Edit do begin
    AutoCompleteFiles := True;
    Top := FY;
    Width := SurfaceWidth-ButtonWidth-WizardForm.ScalePixelsX(10);
  end;
  SetCtlParentAtBack(Edit, Surface);

  if PromptLabel <> nil then
    PromptLabel.FocusControl := Edit;

  Button := TNewButton.Create(Self);
  with Button do begin
    Left := SurfaceWidth-ButtonWidth;
    Top := Edit.Top-1;
    Width := ButtonWidth;
    Height := WizardForm.NextButton.Height;
    if FButtons.Count = 0 then
      Caption := {$IFDEF FPC}UTF8Encode(SetupMessages[msgButtonWizardBrowse]){$ELSE}SetupMessages[msgButtonWizardBrowse]{$ENDIF}
    else
      { Can't use the same accel key for secondary buttons... }
      Caption := {$IFDEF FPC}UTF8Encode(RemoveAccelChar(SetupMessages[msgButtonWizardBrowse])){$ELSE}RemoveAccelChar(SetupMessages[msgButtonWizardBrowse]){$ENDIF};
    OnClick := ButtonClick;
  end;
  SetCtlParentAtBack(Button, Surface);
  Inc(FY, WizardForm.ScalePixelsY(36));

  FInputFileFilters.Add({$IFDEF FPC}UTF8Encode(AFilter){$ELSE}AFilter{$ENDIF});
  FInputFileDefaultExtensions.Add({$IFDEF FPC}UTF8Encode(ADefaultExtension){$ELSE}ADefaultExtension{$ENDIF});
  FButtons.Add(Button);
  FPromptLabels.Add(PromptLabel);
  Result := FEdits.Add(Edit);
end;

function TInputFileWizardPage.GetButton(Index: NativeInt): TNewButton;
begin
  Result := FButtons[Index];
end;

function TInputFileWizardPage.GetEdit(Index: NativeInt): TNewPathEdit;
begin
  Result := FEdits[Index];
end;

function TInputFileWizardPage.GetPromptLabel(Index: NativeInt): TNewStaticText;
begin
  Result := FPromptLabels[Index];
end;

function TInputFileWizardPage.GetValue(Index: NativeInt): String;
begin
  Result := {$IFDEF FPC}UTF8Decode(GetEdit(Index).Text){$ELSE}GetEdit(Index).Text{$ENDIF};
end;

procedure TInputFileWizardPage.SetValue(Index: NativeInt; const Value: String);
begin
  GetEdit(Index).Text := {$IFDEF FPC}UTF8Encode(Value){$ELSE}Value{$ENDIF};
end;

function TInputFileWizardPage.GetIsSaveButton(Index: NativeInt): Boolean;
begin
  Result := GetButton(Index).Tag = 1;
end;

procedure TInputFileWizardPage.SetIsSaveButton(Index: NativeInt; const IsSaveButton: Boolean);
begin
  if IsSaveButton then
    GetButton(Index).Tag := 1
  else
    GetButton(Index).Tag := 0;
end;


{--- OutputMsg ---}

procedure TOutputMsgWizardPage.Initialize(const Msg: String);
begin
  FMsgLabel := TNewStaticText.Create(Self);
  with FMsgLabel do begin
    AutoSize := False;
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
    WordWrap := True;
    Caption := {$IFDEF FPC}UTF8Encode(Msg){$ELSE}Msg{$ENDIF};
  end;
  TSetupForm.SetCtlParent(FMsgLabel, Surface);
  WizardForm.AdjustLabelHeight(MsgLabel);
end;

{--- OutputMsgMemo ---}

procedure TOutputMsgMemoWizardPage.Initialize(const SubCaption: String; const Msg: AnsiString);
var
  Y: Integer;
begin
  Y := 0;
  if SubCaption <> '' then begin
    FSubCaptionLabel := TNewStaticText.Create(Self);
    with FSubCaptionLabel do begin
      AutoSize := False;
      Width := SurfaceWidth;
      Height := WizardForm.ScalePixelsY(DefaultLabelHeight);
      WordWrap := True;
      Caption := {$IFDEF FPC}UTF8Encode(SubCaption){$ELSE}SubCaption{$ENDIF};
    end;
    TSetupForm.SetCtlParent(FSubCaptionLabel, Surface);
    Inc(Y, WizardForm.ScalePixelsY(DefaultBoxTop) +
      WizardForm.AdjustLabelHeight(FSubCaptionLabel));
  end else
    FSubCaptionLabel := nil;

  FRichEditViewer := TRichEditViewer.Create(Self);
  with FRichEditViewer do begin
    Top := Y;
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(DefaultBoxBottom) + SurfaceExtraHeight - Y;
    {$IFDEF FPC}
    BorderStyle := bsSingle;
    {$ELSE}
    BevelKind := bkFlat;
    BorderStyle := bsNone;
    {$ENDIF}
    ReadOnly := True;
    ScrollBars := ssVertical;
    WantReturns := False;
  end;
  SetCtlParentAtBack(FRichEditViewer, Surface);
  with FRichEditViewer do begin
    UseRichEdit := True;
    RTFText := Msg;
  end;
end;

{--- OutputProgress ---}

constructor TOutputProgressWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  Style := Style + [psAlwaysSkip, psNoButtons];
end;

procedure TOutputProgressWizardPage.Initialize;
begin
  FMsg1Label := TNewStaticText.Create(Self);
  with FMsg1Label do begin
    AutoSize := False;
    ShowAccelChar := False;
    Width := SurfaceWidth;
    Height := WizardForm.StatusLabel.Height;
    WordWrap := WizardForm.StatusLabel.WordWrap;
  end;
  TSetupForm.SetCtlParent(FMsg1Label, Surface);

  FMsg2Label := TNewStaticText.Create(Self);
  with FMsg2Label do begin
    AutoSize := False;
    ForceLTRReading := True;
    ShowAccelChar := False;
    Top := WizardForm.ScalePixelsY(16);
    Width := SurfaceWidth;
    Height := WizardForm.FileNameLabel.Height;
  end;
  SetCtlParentAtBack(FMsg2Label, Surface);

  FProgressBar := TNewProgressBar.Create(Self);
  with FProgressBar do begin
    Top := WizardForm.ScalePixelsY(42);
    Width := SurfaceWidth;
    Height := WizardForm.ScalePixelsY(21);
    Visible := False;
  end;
  SetCtlParentAtBack(FProgressBar, Surface);
end;

procedure TOutputProgressWizardPage.Hide;
begin
  if (WizardForm.CurPageID = ID) and (FSavePageID <> 0) then begin
    SetMessageBoxCallbackFunc(FSaveMessageBoxCallbackFunc, FSaveMessageBoxCallbackParam);
    SetAppTaskbarProgressState(tpsNoProgress);
    WizardForm.SetCurPage(FSavePageID);
    FSavePageID := 0;
  end;
end;

procedure TOutputProgressWizardPage.ProcessMsgs;
{ Process messages to repaint and keep Windows from thinking the process is
  hung. This is safe; due to the psNoButtons style the user shouldn't be able
  to cancel or do anything else during this time. }
begin
  if WizardForm.CurPageID = ID then
    Application.ProcessMessages;
end;

procedure TOutputProgressWizardPage.SetProgress(const Position, Max: Integer);
begin
  if Max > 0 then begin
    FProgressBar.Style := npbstNormal;
    FProgressBar.Max := Max;
    FProgressBar.Position := Position;
    FProgressBar.Visible := True;
    SetAppTaskbarProgressState(tpsNormal);
    SetAppTaskbarProgressValue(UInt64(Position), UInt64(Max));
  end else begin
    if FUseMarqueeStyle then
      FProgressBar.Style := npbstMarquee
    else
      FProgressBar.Visible := False;
    SetAppTaskbarProgressState(tpsNoProgress);
  end;
  ProcessMsgs;
end;

procedure TOutputProgressWizardPage.SetText(const Msg1, Msg2: String);
begin
  FMsg1Label.Caption := Msg1;
  FMsg2Label.Caption := MinimizePathName(Msg2, FMsg2Label.Font,
    FMsg2Label.Width);
  ProcessMsgs;
end;

procedure OutputProgressWizardPageMessageBoxCallback(const Flags: Cardinal; const After: Boolean;
  const Param: NativeInt);
const
  States: array [TNewProgressBarState] of TTaskbarProgressState =
    (tpsNormal, tpsError, tpsPaused);
var
  OutputProgressWizardPage: TOutputProgressWizardPage;
  NewState: TNewProgressBarState;
begin
  OutputProgressWizardPage := TOutputProgressWizardPage(Param);
  if After then
    NewState := npbsNormal
  else if (Flags and MB_ICONSTOP) <> 0 then
    NewState := npbsError
  else
    NewState := npbsPaused;

  with OutputProgressWizardPage.ProgressBar do begin
    State := NewState;
    Invalidate;
  end;
  SetAppTaskbarProgressState(States[NewState]);
end;

procedure TOutputProgressWizardPage.Show;
begin
  if WizardForm.CurPageID <> ID then begin
    FSavePageID := WizardForm.CurPageID;
    WizardForm.SetCurPage(ID);
    GetMessageBoxCallbackFunc(FSaveMessageBoxCallbackFunc, FSaveMessageBoxCallbackParam);
    SetMessageBoxCallbackFunc(OutputProgressWizardPageMessageBoxCallback, NativeInt(Self));
    ProcessMsgs;
  end;
end;

constructor TOutputMarqueeProgressWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  FUseMarqueeStyle := True;
end;

procedure TOutputMarqueeProgressWizardPage.Animate;
begin
  ProcessMsgs;
end;

procedure TOutputMarqueeProgressWizardPage.Initialize;
begin
  inherited;
  FProgressBar.Visible := True;
  inherited SetProgress(0, 0);
end;

procedure TOutputMarqueeProgressWizardPage.SetProgress(const Position, Max: Integer);
begin
  InternalError('Cannot call TOutputMarqueeProgressWizardPage.SetProgress');
end;

{--- Download ---}

procedure TDownloadWizardPage.AbortButtonClick(Sender: TObject);
begin
  FAbortedByUser := LoggedMsgBox(SetupMessages[msgStopDownload], '', mbConfirmation, MB_YESNO, True, IDYES) = IDYES;
end;

function TDownloadWizardPage.InternalOnDownloadProgress(const Url, BaseName: string; const Progress, ProgressMax: Int64): Boolean;
var
  Progress32, ProgressMax32: Integer;
begin
  if FAbortedByUser then begin
    Log('Need to abort download.');
    Result := False;
  end else begin
    FMsg2Label.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}IfThen(FShowBaseNameInsteadOfUrl, PathExtractName(BaseName), Url){$IFDEF FPC}){$ENDIF};
    if ProgressMax > MaxInt then begin
      Progress32 := Integer(Round((Progress / ProgressMax) * MaxInt));
      ProgressMax32 := MaxInt;
    end else begin
      Progress32 := Integer(Progress);
      ProgressMax32 := Integer(ProgressMax);
    end;
    SetProgress(Progress32, ProgressMax32); { This will process messages which we need for the abort button to work }

    if FShowProgressControlsOnNextProgress then begin
      ShowProgressControls(True);
      FShowProgressControlsOnNextProgress := False;
      ProcessMsgs;
    end;

    { This will call InternalThrottledOnDownloadProgress, which will log progress and call the script's FOnDownloadProgress, but throttled }
    if FThrottler = nil then begin
      FThrottler := TProgressThrottler.Create(InternalThrottledOnDownloadProgress);
    end;
    Result := FThrottler.OnDownloadProgress(Url, BaseName, Progress, ProgressMax);
  end;
end;

function TDownloadWizardPage.InternalOnDownloadNoProgress: Boolean;
begin
  if FAbortedByUser then begin
    Log('Need to abort download.');
    Result := False;
  end else begin
    ProcessMsgs;
    Result := True;
  end;
end;

function TDownloadWizardPage.InternalThrottledOnDownloadProgress(const Url, BaseName: string; const Progress, ProgressMax: Int64): Boolean;
begin
  if ProgressMax > 0 then
    Log(Format('  %d of %d bytes done.', [Progress, ProgressMax]))
  else
    Log(Format('  %d bytes done.', [Progress]));

  if Assigned(FOnDownloadProgress) then
    Result := FOnDownloadProgress(Url, BaseName, Progress, ProgressMax)
  else
    Result := True;
end;

constructor TDownloadWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  FUseMarqueeStyle := True;
  FFiles := TDownloadFiles.Create;
end;

destructor TDownloadWizardPage.Destroy;
begin
  FThrottler.Free;
  FFiles.Free;
  inherited;
end;

procedure TDownloadWizardPage.Initialize;
begin
  inherited;

  FMsg1Label.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgDownloadingLabel2]{$IFDEF FPC}){$ENDIF};

  FAbortButton := TNewButton.Create(Self);
  with FAbortButton do begin
    Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonStopDownload]{$IFDEF FPC}){$ENDIF};
    Top := FProgressBar.Top + FProgressBar.Height + WizardForm.ScalePixelsY(8);
    Width := WizardForm.CalculateButtonWidth([{$IFDEF FPC}UTF8Decode(Caption){$ELSE}Caption{$ENDIF}]);
    Height := WizardForm.CancelButton.Height;
    OnClick := AbortButtonClick;
  end;
  SetCtlParentAtBack(FAbortButton, Surface);
end;

procedure TDownloadWizardPage.Show;
begin
  if WizardForm.CurPageID <> ID then begin
    ShowProgressControls(False);
    FShowProgressControlsOnNextProgress := True;
  end;
  inherited;
end;

procedure TDownloadWizardPage.ShowProgressControls(const AVisible: Boolean);
begin
  FMsg2Label.Visible := AVisible;
  FProgressBar.Visible := AVisible;
end;

function TDownloadWizardPage.DoAdd(const Url, BaseName, RequiredSHA256OfFile, UserName, Password: String;
  const ISSigVerify: Boolean; const ISSigAllowedKeys: AnsiString; const DotISSigEntry: Boolean;
  const Data: NativeInt): NativeInt;
var
  Verification: TSetupFileVerification;
  F: TDownloadFile;
begin
  if ISSigVerify and DotISSigEntry then
    InternalError('ISSigVerify and DotISSigEntry');
  Verification := NoVerification;
  if RequiredSHA256OfFile <> '' then begin
    Verification.Typ := fvHash;
    Verification.Hash := SHA256DigestFromString(RequiredSHA256OfFile)
  end else if ISSigVerify then begin
    Verification.Typ := fvISSig;
    Verification.ISSigAllowedKeys := ISSigAllowedKeys
  end;
  F := TDownloadFile.Create;
  F.Url := Url;
  F.BaseName := BaseName;
  F.UserName := UserName;
  F.Password := Password;
  F.Verification := Verification;
  F.DotISSigEntry := DotISSigEntry;
  F.Data := Data;
  Result := FFiles.Add(F);
end;

function ConvertAllowedKeysRuntimeIDsToISSigAllowedKeys(const AllowedKeysRuntimeIDs: TStringList): AnsiString;
var
  I, KeyIndex: Integer;
  RuntimeID: String;
  Found: Boolean;
  ISSigKeyEntry: PSetupISSigKeyEntry;
begin
  Result := '';
  if AllowedKeysRuntimeIDs <> nil then begin
    for I := 0 to AllowedKeysRuntimeIDs.Count-1 do begin
      RuntimeID := AllowedKeysRuntimeIDs[I];
      if RuntimeID = '' then
        InternalError('RuntimeID cannot be empty');
      Found := False;
      for KeyIndex := 0 to Entries[seISSigKey].Count-1 do begin
        ISSigKeyEntry := PSetupISSigKeyEntry(Entries[seISSigKey][KeyIndex]);
        if SameText(ISSigKeyEntry.RuntimeID, RuntimeID) then begin
          SetISSigAllowedKey(Result, Integer(KeyIndex));
          Found := True;
          Break;
        end;
      end;
      if not Found then
        InternalError(Format('Unknown RuntimeID ''%s''', [RuntimeID]));
    end;
  end;
end;

function TDownloadWizardPage.Add(const Url, BaseName, RequiredSHA256OfFile: String): NativeInt;
begin
  Result := DoAdd(Url, BaseName, RequiredSHA256OfFile, '', '', False, '', False, 0);
end;

function TDownloadWizardPage.AddWithISSigVerify(const Url, ISSigUrl, BaseName: String;
  const AllowedKeysRuntimeIDs: TStringList): NativeInt;
begin
  Result := AddExWithISSigVerify(Url, ISSigUrl, BaseName, '', '', AllowedKeysRuntimeIDs, 0);
end;

function TDownloadWizardPage.AddEx(const Url, BaseName, RequiredSHA256OfFile, UserName, Password: String;
  const Data: NativeInt): NativeInt;
begin
  Result := DoAdd(Url, BaseName, RequiredSHA256OfFile, UserName, Password, False, '', False, Data);
end;

function TDownloadWizardPage.AddExWithISSigVerify(const Url, ISSigUrl, BaseName, UserName,
  Password: String; const AllowedKeysRuntimeIDs: TStringList; const Data: NativeInt): NativeInt;
var
  ISSigAllowedKeys: AnsiString;
begin
  ISSigAllowedKeys := ConvertAllowedKeysRuntimeIDsToISSigAllowedKeys(AllowedKeysRuntimeIDs);
  Result := AddExWithISSigVerify(Url, ISSigUrl, BaseName, UserName, Password, ISSigAllowedKeys, Data);
end;

function TDownloadWizardPage.AddExWithISSigVerify(const Url, ISSigUrl, BaseName, UserName,
  Password: String; const ISSigAllowedKeys: AnsiString; const Data: NativeInt): NativeInt;
begin
  { Also see Setup.ScriptFunc DownloadTemporaryFileWithISSigVerify }
  DoAdd(GetISSigUrl(Url, ISSigUrl), BaseName + ISSigExt, '', UserName, Password, False, '', True, 0);
  Result := DoAdd(Url, BaseName, '', UserName, Password, True, ISSigAllowedKeys, False, Data);
end;

procedure TDownloadWizardPage.Clear;
begin
  FFiles.Clear;
end;

function TDownloadWizardPage.Download(const OnDownloadFileCompleted: TDownloadFileCompleted): Int64;
var
  I: Integer;
  F: TDownloadFile;
  DestFile: String;
  Remove: Boolean;
begin
  FAbortedByUser := False;

  Result := 0;

  try
    for I := 0 to FFiles.Count-1 do begin
      if FThrottler <> nil then
        FThrottler.Reset;
      { Don't need to set DownloadTemporaryFileOrExtractArchiveProcessMessages before downloading since we already process messages ourselves }
      F := FFiles[I];
      FLastBaseNameOrUrl := IfThen(FShowBaseNameInsteadOfUrl, PathExtractName(F.BaseName), F.Url);
      SetDownloadTemporaryFileCredentials(F.UserName, F.Password);
      Result := Result + DownloadTemporaryFile(F.Url, F.BaseName, F.Verification,
        InternalOnDownloadProgress, InternalOnDownloadNoProgress, DestFile);
      if Assigned(OnDownloadFileCompleted) then begin
        Remove := False;
        OnDownloadFileCompleted(F, DestFile, Remove);
        if Remove then
          FFiles[I] := nil;
      end;
    end;
  finally
    SetDownloadTemporaryFileCredentials('', '');
    {$IFDEF FPC}
    for I := FFiles.Count-1 downto 0 do
      if FFiles[I] = nil then
        FFiles.Delete(I);
    {$ELSE}
    FFiles.Pack;
    {$ENDIF}
  end;
end;

{--- Extraction ---}

procedure TExtractionWizardPage.AbortButtonClick(Sender: TObject);
begin
  FAbortedByUser := LoggedMsgBox(SetupMessages[msgStopExtraction], '', mbConfirmation, MB_YESNO, True, IDYES) = IDYES;
end;

function TExtractionWizardPage.InternalOnExtractionProgress(const ArchiveName, FileName: string; const Progress, ProgressMax: Int64): Boolean;
var
  Progress32, ProgressMax32: Integer;
begin
  if FAbortedByUser then begin
    Log('Need to abort extraction.');
    Result := False;
  end else begin
    { Unlike TDownloadWizardPage we don't log progress here. This is because 7zMain.c already logs output dirs and names. }

    FMsg2Label.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}IfThen(FShowArchiveInsteadOfFile, ArchiveName, FileName){$IFDEF FPC}){$ENDIF};
    if ProgressMax > MaxInt then begin
      Progress32 := Integer(Round((Progress / ProgressMax) * MaxInt));
      ProgressMax32 := MaxInt;
    end else begin
      Progress32 := Integer(Progress);
      ProgressMax32 := Integer(ProgressMax);
    end;
    SetProgress(Progress32, ProgressMax32); { This will process messages which we need for the abort button to work }

    if FShowProgressControlsOnNextProgress then begin
      ShowProgressControls(True);
      FShowProgressControlsOnNextProgress := False;
      ProcessMsgs;
    end;

    { This will call InternalThrottledOnExtractionProgress, which will call the script's FOnExtractionProgress, but throttled
      Because it does nothing else we first check if FOnExtractionProgress is actually assigned }
    if Assigned(FOnExtractionProgress) then begin
      if FThrottler = nil then begin
        FThrottler := TProgressThrottler.Create(InternalThrottledOnExtractionProgress);
      end;
      Result := FThrottler.OnExtractionProgress(ArchiveName, FileName, Progress, ProgressMax);
    end else
      Result := True;
  end;
end;

function TExtractionWizardPage.InternalThrottledOnExtractionProgress(const ArchiveName, FileName: string; const Progress, ProgressMax: Int64): Boolean;
begin
  if Assigned(FOnExtractionProgress) then { Always True, see above }
    Result := FOnExtractionProgress(ArchiveName, FileName, Progress, ProgressMax)
  else
    Result := True;
end;

constructor TExtractionWizardPage.Create(AOwner: TComponent);
begin
  inherited;
  FUseMarqueeStyle := True;
  FArchives := TArchives.Create;
end;

destructor TExtractionWizardPage.Destroy;
begin
  FThrottler.Free;
  FArchives.Free;
  inherited;
end;

procedure TExtractionWizardPage.Initialize;
begin
  inherited;

  FMsg1Label.Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgExtractingLabel]{$IFDEF FPC}){$ENDIF};

  FAbortButton := TNewButton.Create(Self);
  with FAbortButton do begin
    Caption := {$IFDEF FPC}UTF8Encode({$ENDIF}SetupMessages[msgButtonStopExtraction]{$IFDEF FPC}){$ENDIF};
    Top := FProgressBar.Top + FProgressBar.Height + WizardForm.ScalePixelsY(8);
    Width := WizardForm.CalculateButtonWidth([{$IFDEF FPC}UTF8Decode(Caption){$ELSE}Caption{$ENDIF}]);
    Height := WizardForm.CancelButton.Height;
    OnClick := AbortButtonClick;
  end;
  SetCtlParentAtBack(FAbortButton, Surface);
end;

procedure TExtractionWizardPage.Show;
begin
  if WizardForm.CurPageID <> ID then begin
    ShowProgressControls(False);
    FShowProgressControlsOnNextProgress := True;
  end;
  inherited;
end;

procedure TExtractionWizardPage.ShowProgressControls(const AVisible: Boolean);
begin
  FMsg2Label.Visible := AVisible;
  FProgressBar.Visible := AVisible;
end;

function TExtractionWizardPage.Add(const ArchiveFileName, DestDir: String; const FullPaths: Boolean): NativeInt;
begin
  Result := AddEx(ArchiveFileName, DestDir, '', FullPaths);
end;

function TExtractionWizardPage.AddEx(const ArchiveFileName, DestDir, Password: String; const FullPaths: Boolean): NativeInt;
var
  A: TArchive;
begin
  A := TArchive.Create;
  A.FileName := ArchiveFileName;
  A.DestDir := DestDir;
  A.Password := Password;
  A.FullPaths := FullPaths;
  Result := FArchives.Add(A);
end;

procedure TExtractionWizardPage.Clear;
begin
  FArchives.Clear;
end;

procedure TExtractionWizardPage.Extract;
var
  A: TArchive;
begin
  FAbortedByUser := False;

  try
    for A in FArchives do begin
      if FThrottler <> nil then
        FThrottler.Reset;
      { Don't need to set DownloadTemporaryFileOrExtractArchiveProcessMessages before extraction since we already process messages ourselves }
      if SetupHeader.SevenZipLibraryName <> '' then
        ExtractArchive(A.FileName, A.DestDir, A.Password, A.FullPaths, InternalOnExtractionProgress)
      else
        Extract7ZipArchive(A.FileName, A.DestDir, A.Password, A.FullPaths, InternalOnExtractionProgress);
    end;
  except
    on E: EAbort do
      raise Exception.Create(SetupMessages[msgErrorExtractionAborted])
    else
      raise Exception.Create(FmtSetupMessage1(msgErrorExtractionFailed, GetExceptMessage));
  end;
end;

end.
