unit Setup.DownloadFileFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  Installation procedures: downloading files
}

{$IFDEF FPC}{$MODESWITCH NESTEDPROCVARS}{$ENDIF}

interface

uses
  Shared.FileClass, Shared.Struct;

type
  TOnDownloadProgress = function(const Url, BaseName: string; const Progress, ProgressMax: Int64): Boolean of object;
  TOnSimpleDownloadProgress = procedure(const Bytes, Param: Int64);
  TOnDownloadNoProgress = function: Boolean of object;
  TOnSimpleDownloadNoProgress = procedure;

function DownloadFile(const Url, CustomUserName, CustomPassword: String;
  const DestF: TFile; {$IFDEF FPC}constref{$ELSE}[ref] const{$ENDIF} Verification: TSetupFileVerification; const ISSigSourceFilename: String;
  const OnSimpleDownloadProgress: TOnSimpleDownloadProgress;
  const OnSimpleDownloadProgressParam: Int64;
  const OnSimpleDownloadNoProgress: TOnSimpleDownloadNoProgress): Int64;

function DownloadTemporaryFile(const Url, BaseName: String;
  {$IFDEF FPC}constref{$ELSE}[ref] const{$ENDIF} Verification: TSetupFileVerification; const OnDownloadProgress: TOnDownloadProgress;
  const OnDownloadNoProgress: TOnDownloadNoProgress): Int64; overload;
function DownloadTemporaryFile(const Url, BaseName: String;
  {$IFDEF FPC}constref{$ELSE}[ref] const{$ENDIF} Verification: TSetupFileVerification; const OnDownloadProgress: TOnDownloadProgress;
  const OnDownloadNoProgress: TOnDownloadNoProgress; out DestFile: String): Int64; overload;
function DownloadTemporaryFileSize(const Url: String): Int64;
function DownloadTemporaryFileDate(const Url: String): String;
procedure SetDownloadTemporaryFileCredentials(const User, Pass: String);

function GetISSigUrl(const Url, ISSigUrl: String): String;

implementation

uses
  Windows, Classes, Forms, SysUtils, SyncObjs,
  {$IFDEF FPC}URIParser, Setup.WinHttp,{$ELSE}Net.HttpClient, Net.URLClient, NetEncoding,{$ENDIF}
  ISSigFunc, PathFunc, SHA256,
  Shared.CommonFunc, Shared.SetupMessageIDs, Shared.SetupTypes,
  SetupLdrAndSetup.InstFunc, SetupLdrAndSetup.Messages,
  Setup.InstFunc, Setup.ISSigVerifyFunc, Setup.LoggingFunc, Setup.MainFunc;

type
  THTTPDataReceiver = class
  private
    type
      TResult = record
        SavedFatalException: TObject;
        HTTPStatusCode: Integer;
        HTTPStatusText: String;
        FileSize: Int64;
      end;
    var
      FBaseName, FCleanUrl: String;
      FHasCredentials: Boolean;
      FUser, FPass: String;
      FDestFile: TFile;
      FOnDownloadProgress: TOnDownloadProgress;
      FOnDownloadNoProgress: TOnDownloadNoProgress;
      FOnSimpleDownloadProgress: TOnSimpleDownloadProgress;
      FOnSimpleDownloadProgressParam: Int64;
      FOnSimpleDownloadNoProgress: TOnSimpleDownloadNoProgress;
      FLock: TCriticalSection;
      FProgress, FProgressMax: Int64;
      FProgressSet: Boolean;
      FLastReportedProgress: Int64;
      FAbort: Boolean;
      FResult: TResult;
  protected
    procedure DoDownload;
    procedure HandleProgress;
    procedure HandleResult(const UseSetupMessagesForErrors: Boolean);
  public
    constructor Create(const Url, CustomUser, CustomPass: String; const DestFile: TFile);
    destructor Destroy; override;
    property BaseName: String write FBaseName;
    property OnDownloadProgress: TOnDownloadProgress write FOnDownloadProgress;
    property OnDownloadNoProgress: TOnDownloadNoProgress write FOnDownloadNoProgress;
    property OnSimpleDownloadProgress: TOnSimpleDownloadProgress write FOnSimpleDownloadProgress;
    property OnSimpleDownloadProgressParam: Int64 write FOnSimpleDownloadProgressParam;
    property OnSimpleDownloadNoProgress: TOnSimpleDownloadNoProgress write FOnSimpleDownloadNoProgress;
    property Aborted: Boolean read FAbort;
    property Progress: Int64 read FProgress;
    property ProgressMax: Int64 read FProgressMax;
    procedure OnReceiveData(const Sender: TObject; AContentLength: Int64; AReadCount: Int64; var Abort: Boolean);
    function Download(const UseSetupMessagesForErrors: Boolean): Int64;
  end;

{$IFDEF FPC}
procedure FindUrlCredentials(const Url: String; out StartIndex, AtIndex: Integer);
var
  I: Integer;
begin
  StartIndex := Pos('://', Url);
  AtIndex := 0;
  if StartIndex = 0 then
    Exit;
  Inc(StartIndex, 3);
  for I := StartIndex to Length(Url) do begin
    if CharInSet(Url[I], ['/', '?', '#']) then
      Break;
    if Url[I] = '@' then
      AtIndex := I;
  end;
end;
{$ENDIF}

function GetCredentialsAndCleanUrl(const Url, CustomUser, CustomPass: String; var User, Pass, CleanUrl: String) : Boolean;
{$IFDEF FPC}
var
  Uri: TURI;
  StartIndex, AtIndex: Integer;
{$ENDIF}
begin
  {$IFDEF FPC}
  FindUrlCredentials(Url, StartIndex, AtIndex);
  CleanUrl := Url;
  if AtIndex <> 0 then
    Delete(CleanUrl, StartIndex, AtIndex - StartIndex + 1);
  Uri := ParseURI(UTF8Encode(Url));
  if CustomUser = '' then
    User := UTF8Decode(Uri.Username)
  else
    User := CustomUser;
  if CustomPass = '' then
    Pass := UTF8Decode(Uri.Password)
  else
    Pass := CustomPass;
  {$ELSE}
  const Uri = TUri.Create(Url); { This is a record so no need to free }
  if CustomUser = '' then
    User := TNetEncoding.URL.Decode(Uri.Username, [])
  else
    User := CustomUser;
  if CustomPass = '' then
    Pass := TNetEncoding.URL.Decode(Uri.Password, [])
  else
    Pass := CustomPass;
  Uri.Username := '';
  Uri.Password := '';
  CleanUrl := Uri.ToString;
  {$ENDIF}
  Result := (User <> '') or (Pass <> '');
  if Result then
    LogFmt('Download is using basic authentication: %s, ***', [User])
  else
    Log('Download is not using basic authentication');
end;

{$IFNDEF FPC}
procedure SetUserAgentAndSecureProtocols(const AHTTPClient: THTTPClient);
begin
  AHTTPClient.UserAgent := SetupTitle + ' ' + SetupVersion;
  AHTTPClient.SecureProtocols := [THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13];
end;

{$ENDIF}

{ THTTPDataReceiver }

constructor THTTPDataReceiver.Create(const Url, CustomUser, CustomPass: String; const DestFile: TFile);
begin
  inherited Create;
  FDestFile := DestFile;
  FHasCredentials := GetCredentialsAndCleanUrl(Url, CustomUser, CustomPass, FUser, FPass, FCleanUrl);
  FLock := TCriticalSection.Create;
end;

destructor THTTPDataReceiver.Destroy;
begin
  FResult.SavedFatalException.Free;
  FLock.Free;
  inherited;
end;

procedure THTTPDataReceiver.OnReceiveData(const Sender: TObject; AContentLength: Int64; AReadCount: Int64; var Abort: Boolean);
begin
  if FAbort then
    Abort := True;

  FLock.Acquire;
  try
    FProgress := AReadCount;
    FProgressMax := AContentLength;
    FProgressSet := True;
  finally
    FLock.Release;
  end;
end;

procedure THTTPDataReceiver.DoDownload;
{$IFDEF FPC}
var
  HandleStream: THandleStream;
  Response: TWinHttpResponse;
{$ENDIF}
begin
  {$IFDEF FPC}
  HandleStream := THandleStream.Create(FDestFile.Handle);
  try
    Response := RequestWinHttp(FCleanUrl, SetupTitle + ' ' + SetupVersion,
      FUser, FPass, HandleStream, OnReceiveData);
    FResult.HTTPStatusCode := Response.StatusCode;
    FResult.HTTPStatusText := Response.StatusText;
    FResult.FileSize := HandleStream.Size;
  finally
    HandleStream.Free;
  end;
  {$ELSE}
  const HTTPClient = THTTPClient.Create; { http://docwiki.embarcadero.com/RADStudio/Rio/en/Using_an_HTTP_Client }
  try
    SetUserAgentAndSecureProtocols(HTTPClient);
    HTTPClient.OnReceiveData := OnReceiveData;

    const HandleStream = THandleStream.Create(FDestFile.Handle);
    try
      if FHasCredentials then begin
        const Base64 = TBase64Encoding.Create(0);
        try
          HTTPClient.CustomHeaders['Authorization'] := 'Basic ' + Base64.Encode(FUser + ':' + FPass);
        finally
          Base64.Free;
        end;
      end;
      
      const HTTPResponse = HTTPClient.Get(FCleanUrl, HandleStream);
      
      FResult.HTTPStatusCode := HTTPResponse.StatusCode;
      FResult.HTTPStatusText := HTTPResponse.StatusText;
      FResult.FileSize := HandleStream.Size;
    finally
      HandleStream.Free;
    end;
  finally
    HTTPClient.Free;
  end;
  {$ENDIF}
end;

procedure THTTPDataReceiver.HandleProgress;
var
  Progress, ProgressMax: Int64;
  ProgressSet: Boolean;
begin

  FLock.Acquire;
  try
    Progress := FProgress;
    ProgressMax := FProgressMax;
    ProgressSet := FProgressSet;
  finally
    FLock.Release;
  end;

  try
    if ProgressSet then begin
      if Assigned(FOnDownloadProgress) then begin
        if not FOnDownloadProgress(FCleanUrl, FBaseName, Progress, ProgressMax) then
          FAbort := True; { Atomic so no lock }
      end else if Assigned(FOnSimpleDownloadProgress) then begin
        try
          FOnSimpleDownloadProgress(Progress-FLastReportedProgress, FOnSimpleDownloadProgressParam);
        finally
          FLastReportedProgress := Progress;
        end;
      end;
    end else begin
      if Assigned(FOnDownloadNoProgress) then begin
        if not FOnDownloadNoProgress then
          FAbort := True; { Atomic so no lock }
      end else if Assigned(FOnSimpleDownloadNoProgress) then
        FOnSimpleDownloadNoProgress;
    end;
  except
    if ExceptObject is EAbort then { FOnSimpleDownload(No)Progress always uses Abort to abort }
      FAbort := True { Atomic so no lock }
    else
      raise;
  end;

  if DownloadTemporaryFileOrExtractArchiveProcessMessages then
    Application.ProcessMessages;
end;

procedure THTTPDataReceiver.HandleResult(const UseSetupMessagesForErrors: Boolean);
var
  Msg: String;
begin
  if Assigned(FResult.SavedFatalException) then begin
    if FResult.SavedFatalException is Exception then
      Msg := (FResult.SavedFatalException as Exception).Message
    else
      Msg := FResult.SavedFatalException.ClassName;
    raise Exception.Create(Msg);
  end else begin
    if Aborted then begin
      if UseSetupMessagesForErrors then
        raise Exception.Create(SetupMessages[msgErrorDownloadAborted])
      else
        Abort;
    end else if (FResult.HTTPStatusCode < 200) or (FResult.HTTPStatusCode > 299) then begin
      if UseSetupMessagesForErrors then
        raise Exception.Create(FmtSetupMessage(msgErrorDownloadFailed, [IntToStr(FResult.HTTPStatusCode), FResult.HTTPStatusText]))
      else
        raise Exception.Create(Format('%d %s', [FResult.HTTPStatusCode, FResult.HTTPStatusText]));
    end;
  end;
end;

function DownloadThreadFunc(Parameter: Pointer): {$IFDEF FPC}PtrInt{$ELSE}Integer{$ENDIF};
var
  D: THTTPDataReceiver;
begin
  D := THTTPDataReceiver(Parameter);
  try
    D.DoDownload;
  except
    D.FResult.SavedFatalException := TObject(AcquireExceptionObject);
  end;
  {$IFDEF FPC}ReadWriteBarrier{$ELSE}MemoryBarrier{$ENDIF};
  Result := 0;
end;

function THTTPDataReceiver.Download(const UseSetupMessagesForErrors: Boolean): Int64;
var
  ThreadID: TThreadID;
  ThreadHandle: THandle;
begin
  ThreadHandle := BeginThread(nil, 0, DownloadThreadFunc, Self, 0, ThreadID);
  if ThreadHandle = 0 then
    raise Exception.Create('Failed to create download thread: ' + SysErrorMessage(GetLastError));

  try
    try
      while True do begin
        case WaitForSingleObject(ThreadHandle, 50) of
          WAIT_OBJECT_0: Break;
          WAIT_TIMEOUT: HandleProgress;
          WAIT_FAILED: raise Exception.Create('WaitForSingleObject failed: ' + SysErrorMessage(GetLastError));
        else
          raise Exception.Create('WaitForSingleObject returned unknown value');
        end;
      end;
    except
    	{ If an exception was raised during the loop (most likely it would
        be from the user's OnDownloadProgress handler), request abort
        and make one more attempt to wait on the thread. }
      FAbort := True; { Atomic so no lock }
      WaitForSingleObject(ThreadHandle, INFINITE);
      raise;
    end;
  finally
    CloseHandle(ThreadHandle);
  end;

  HandleProgress;
  HandleResult(UseSetupMessagesForErrors);

  Result := FResult.FileSize;
end;

function MaskPasswordInUrl(const Url: String): String;
var
  {$IFDEF FPC}
  StartIndex, AtIndex, ColonIndex: Integer;
  {$ELSE}
  Uri: TUri;
  {$ENDIF}
begin
  {$IFDEF FPC}
  Result := Url;
  FindUrlCredentials(Url, StartIndex, AtIndex);
  if AtIndex <> 0 then begin
    ColonIndex := Pos(':', Url, StartIndex);
    if (ColonIndex > 0) and (ColonIndex < AtIndex - 1) then begin
      Delete(Result, ColonIndex + 1, AtIndex - ColonIndex - 1);
      Insert('***', Result, ColonIndex + 1);
    end;
  end;
  {$ELSE}
  Uri := TUri.Create(Url);
  if Uri.Password <> '' then begin
    Uri.Password := '***';
    Result := Uri.ToString;
  end else
    Result := URL;
  {$ENDIF}
end;

var
  DownloadTemporaryFileUser, DownloadTemporaryFilePass: String;

procedure SetDownloadTemporaryFileCredentials(const User, Pass: String);
begin
  DownloadTemporaryFileUser := User;
  DownloadTemporaryFilePass := Pass;
end;

function GetISSigUrl(const Url, ISSigUrl: String): String;
{$IFDEF FPC}
var
  I: Integer;
{$ENDIF}
begin
  if ISSigUrl <> '' then
    Result := ISSigUrl
  else begin
    {$IFDEF FPC}
    Result := Url;
    I := Pos('://', Result);
    if I > 0 then
      Inc(I, 3)
    else
      I := 1;
    while (I <= Length(Result)) and not CharInSet(Result[I], ['?', '#']) do
      Inc(I);
    Insert(ISSigExt, Result, I);
    {$ELSE}
    const Uri = TUri.Create(Url); { This is a record so no need to free }
    Uri.Path := Uri.Path + ISSigExt;
    Result := Uri.ToString;
    {$ENDIF}
  end;
end;

function DownloadFile(const Url, CustomUserName, CustomPassword: String;
  const DestF: TFile; {$IFDEF FPC}constref{$ELSE}[ref] const{$ENDIF} Verification: TSetupFileVerification; const ISSigSourceFilename: String;
  const OnSimpleDownloadProgress: TOnSimpleDownloadProgress;
  const OnSimpleDownloadProgressParam: Int64;
  const OnSimpleDownloadNoProgress: TOnSimpleDownloadNoProgress): Int64;
var
  HTTPDataReceiver: THTTPDataReceiver;
  ExpectedFileHash, FileHash: TSHA256Digest;
begin
  if Url = '' then
    InternalError('DownloadFile: Invalid Url value');

  LogFmt('Downloading file from %s', [MaskPasswordInURL(Url)]);

  HTTPDataReceiver := THTTPDataReceiver.Create(Url, CustomUserName, CustomPassword, DestF);
  try
    HTTPDataReceiver.OnSimpleDownloadProgress := OnSimpleDownloadProgress;
    HTTPDataReceiver.OnSimpleDownloadProgressParam := OnSimpleDownloadProgressParam;
    HTTPDataReceiver.OnSimpleDownloadNoProgress := OnSimpleDownloadNoProgress;

    { Download to specified handle }
    Result := HTTPDataReceiver.Download(False);
    
    { Check verification if specified, otherwise check everything else we can check }
    if Verification.Typ <> fvNone then begin
      if Verification.Typ = fvHash then
        ExpectedFileHash := Verification.Hash
      else
        DoISSigVerify(DestF, nil, ISSigSourceFilename, False, Verification.ISSigAllowedKeys, ExpectedFileHash);
      FileHash := GetSHA256OfFile(DestF);
      if not SHA256DigestsEqual(FileHash, ExpectedFileHash) then
        VerificationError(veFileHashIncorrect);
      Log(VerificationSuccessfulLogMessage);
    end else begin
      if HTTPDataReceiver.ProgressMax > 0 then begin
        if HTTPDataReceiver.Progress <> HTTPDataReceiver.ProgressMax then
          raise Exception.Create(FmtSetupMessage(msgErrorProgress, [IntToStr(HTTPDataReceiver.Progress), IntToStr(HTTPDataReceiver.ProgressMax)]))
        else if HTTPDataReceiver.ProgressMax <> Result then
          raise Exception.Create(FmtSetupMessage(msgErrorFileSize, [IntToStr(HTTPDataReceiver.ProgressMax), IntToStr(Result)]));
      end;
    end;
  finally
    HTTPDataReceiver.Free;
  end;
end;

function DownloadTemporaryFile(const Url, BaseName: String;
  {$IFDEF FPC}constref{$ELSE}[ref] const{$ENDIF} Verification: TSetupFileVerification; const OnDownloadProgress: TOnDownloadProgress;
  const OnDownloadNoProgress: TOnDownloadNoProgress; out DestFile: String): Int64;
var
  TempFile, ExistingFileName, CapturableDestFile: String;
  ExistingFileSize: Int64;
  ExistingFileHash: TSHA256Digest;
  DestF: TFile;
  DidJustDeleteDestFile: Boolean;
  TempF: TFile;
  TempFileLeftOver: Boolean;
  HTTPDataReceiver: THTTPDataReceiver;
  ExpectedFileHash, FileHash: TSHA256Digest;

  {$IFDEF FPC}
  function MoveTemporaryFile(out LastError: Cardinal): Boolean;
  begin
    Result := MoveFileW(PWideChar(TempFile), PWideChar(CapturableDestFile));
    if not Result then
      LastError := GetLastError;
  end;

  procedure RetryMove(const LastError: Cardinal);
  begin
    LogFmt('  The existing file appears to be in use (%d). Retrying.', [LastError]);
    Sleep(1000);
  end;

  procedure MoveFailed(const LastError: Cardinal; var TryOnceMore: Boolean);
  begin
    SetLastError(LastError);
    Win32ErrorMsg('MoveFile');
  end;
  {$ENDIF}

begin
  if Url = '' then
    InternalError('DownloadTemporaryFile: Invalid Url value');
  if BaseName = '' then
    InternalError('DownloadTemporaryFile: Invalid BaseName value');

  DestFile := AddBackslash(TempInstallDir) + BaseName;

  LogFmt('Downloading temporary file from %s: %s', [MaskPasswordInURL(Url), DestFile]);

  { Does not disable FS redirection, like everything else working on the temp dir }

  { Prepare directory }
  DidJustDeleteDestFile := False;
  if NewFileExists(DestFile) then begin
    if Verification.Typ = fvHash then begin
      if SHA256DigestsEqual(GetSHA256OfFile(DestFile), Verification.Hash) then begin
        Log('  File already downloaded.');
        Result := 0;
        Exit;
      end;
    end else if Verification.Typ = fvISSig then begin
      if ISSigVerifySignature(DestFile, GetISSigAllowedKeys(ISSigAvailableKeys, Verification.ISSigAllowedKeys),
           ExistingFileName, ExistingFileSize, ExistingFileHash, nil, nil, nil) then begin
        DestF := TFile.Create(DestFile, fdOpenExisting, faRead, fsReadWrite);
        try
          { Not checking ExistingFileName because we can't be sure what the original filename was }
          if (DestF.Size = ExistingFileSize) and
             (SHA256DigestsEqual(GetSHA256OfFile(DestF), ExistingFileHash)) then begin
            Log('  File already downloaded.');
            Result := 0;
            Exit;
          end;
        finally
          DestF.Free;
        end;
      end;
    end;

    SetFileAttributesW(PWideChar(DestFile), GetFileAttributesW(PWideChar(DestFile)) and not FILE_ATTRIBUTE_READONLY);
    DelayDeleteFile(DestFile, 13, 50, 250);
    DidJustDeleteDestFile := True;
  end else
    NewForceDirectories(PathExtractDir(DestFile));

  { Create temporary file }
  TempFile := GenerateUniqueName(PathExtractPath(DestFile), '.tmp');
  TempF := TFile.Create(TempFile, fdCreateAlways, faWrite, fsNone);
  TempFileLeftOver := True;

  HTTPDataReceiver := nil;
  try
    HTTPDataReceiver := THTTPDataReceiver.Create(Url,
      DownloadTemporaryFileUser, DownloadTemporaryFilePass, TempF);
    HTTPDataReceiver.BaseName := BaseName;
    HTTPDataReceiver.OnDownloadProgress := OnDownloadProgress;
    HTTPDataReceiver.OnDownloadNoProgress := OnDownloadNoProgress;

    { To test redirects: https://jrsoftware.org/download.php/is.exe
      To test expired certificates: https://expired.badssl.com/
      To test self-signed certificates: https://self-signed.badssl.com/
      To test basic authentication: https://guest:guest@jigsaw.w3.org/HTTP/Basic/
      To test 100 MB file: https://speed.hetzner.de/100MB.bin
      To test 1 GB file: https://speed.hetzner.de/1GB.bin
      To test file without a content length: https://github.com/jrsoftware/issrc/archive/main.zip }

    { Download to temporary file}
    Result := HTTPDataReceiver.Download(True);

    { Check verification if specified, otherwise check everything else we can check }
    if Verification.Typ <> fvNone then begin
      if Verification.Typ = fvHash then
        ExpectedFileHash := Verification.Hash
      else
        DoISSigVerify(TempF, nil, DestFile, False, Verification.ISSigAllowedKeys, ExpectedFileHash);
      FreeAndNil(TempF);
      FileHash := GetSHA256OfFile(TempFile);
      if not SHA256DigestsEqual(FileHash, ExpectedFileHash) then
        VerificationError(veFileHashIncorrect);
      Log(VerificationSuccessfulLogMessage);
    end else begin
        FreeAndNil(TempF);
      if HTTPDataReceiver.ProgressMax > 0 then begin
        if HTTPDataReceiver.Progress <> HTTPDataReceiver.ProgressMax then
          raise Exception.Create(FmtSetupMessage(msgErrorProgress, [IntToStr(HTTPDataReceiver.Progress), IntToStr(HTTPDataReceiver.ProgressMax)]))
        else if HTTPDataReceiver.ProgressMax <> Result then
          raise Exception.Create(FmtSetupMessage(msgErrorFileSize, [IntToStr(HTTPDataReceiver.ProgressMax), IntToStr(Result)]));
      end;
    end;

    { Rename the temporary file to the new name now, with retries if needed }
    CapturableDestFile := DestFile;
    {$IFDEF FPC}
    PerformFileOperationWithRetries(4, DidJustDeleteDestFile,
      MoveTemporaryFile, RetryMove, MoveFailed);
    {$ELSE}
    PerformFileOperationWithRetries(4, DidJustDeleteDestFile,
      function(out LastError: Cardinal): Boolean
      begin
        Result := MoveFile(PChar(TempFile), PChar(CapturableDestFile));
        if not Result then
          LastError := GetLastError;
      end,
      procedure(const LastError: Cardinal)
      begin
        LogFmt('  The existing file appears to be in use (%d). ' +
          'Retrying.', [LastError]);
        Sleep(1000);
      end,
      procedure(const LastError: Cardinal; var TryOnceMore: Boolean)
      begin
        Win32ErrorMsg('MoveFile'); { Throws an exception }
      end);
    {$ENDIF}
    TempFileLeftOver := False;
  finally
    TempF.Free;
    HTTPDataReceiver.Free;
    if TempFileLeftOver then
      DeleteFileW(PWideChar(TempFile));
  end;
end;

function DownloadTemporaryFile(const Url, BaseName: String;
  {$IFDEF FPC}constref{$ELSE}[ref] const{$ENDIF} Verification: TSetupFileVerification; const OnDownloadProgress: TOnDownloadProgress;
  const OnDownloadNoProgress: TOnDownloadNoProgress): Int64;
var
  DestFile: String;
begin
  Result := DownloadTemporaryFile(Url, BaseName, Verification, OnDownloadProgress, OnDownloadNoProgress, DestFile);
end;

procedure DownloadTemporaryFileSizeAndDate(const Url: String; var FileSize: Int64; var FileDate: String);
var
  {$IFDEF FPC}
  HTTPResponse: TWinHttpResponse;
  User, Pass, CleanUrl: String;
  {$ELSE}
  HTTPClient: THTTPClient;
  HTTPResponse: IHTTPResponse;
  User, Pass, CleanUrl: string;
  HasCredentials : Boolean;
  Base64: TBase64Encoding;
  {$ENDIF}
begin
  {$IFDEF FPC}
  GetCredentialsAndCleanUrl(Url, DownloadTemporaryFileUser, DownloadTemporaryFilePass,
    User, Pass, CleanUrl);
  HTTPResponse := RequestWinHttp(CleanUrl, SetupTitle + ' ' + SetupVersion, User, Pass, nil, nil);
  if (HTTPResponse.StatusCode < 200) or (HTTPResponse.StatusCode > 299) then
    raise Exception.Create(FmtSetupMessage(msgErrorDownloadSizeFailed,
      [IntToStr(HTTPResponse.StatusCode), HTTPResponse.StatusText]));
  FileSize := HTTPResponse.ContentLength;
  FileDate := HTTPResponse.LastModified;
  {$ELSE}
  HTTPClient := THTTPClient.Create;
  Base64 := nil;
  try
    HasCredentials := GetCredentialsAndCleanUrl(Url,
      DownloadTemporaryFileUser, DownloadTemporaryFilePass, User, Pass, CleanUrl);
    if HasCredentials then begin
      Base64 := TBase64Encoding.Create(0);
      HTTPClient.CustomHeaders['Authorization'] := 'Basic ' + Base64.Encode(User + ':' + Pass);
    end;
    SetUserAgentAndSecureProtocols(HTTPClient);
    HTTPResponse := HTTPClient.Head(CleanUrl);
    if (HTTPResponse.StatusCode < 200) or (HTTPResponse.StatusCode > 299) then
      raise Exception.Create(FmtSetupMessage(msgErrorDownloadSizeFailed, [IntToStr(HTTPResponse.StatusCode), HTTPResponse.StatusText]))
    else begin
      FileSize := HTTPResponse.ContentLength;
      FileDate := HTTPResponse.LastModified;
    end;
  finally
    Base64.Free;
    HTTPClient.Free;
  end;
  {$ENDIF}
end;

function DownloadTemporaryFileSize(const Url: String): Int64;
var
  FileSize: Int64;
  FileDate: String;
begin
  if Url = '' then
    InternalError('DownloadTemporaryFileSize: Invalid Url value');
  LogFmt('Getting size of %s.', [MaskPasswordInUrl(Url)]);
  DownloadTemporaryFileSizeAndDate(Url, FileSize, FileDate);
  Result := FileSize;
end;

function DownloadTemporaryFileDate(const Url: String): String;
var
  FileSize: Int64;
  FileDate: String;
begin
  if Url = '' then
    InternalError('DownloadTemporaryFileDate: Invalid Url value');
  LogFmt('Getting last modified date of %s.', [MaskPasswordInUrl(Url)]);
  DownloadTemporaryFileSizeAndDate(Url, FileSize, FileDate);
  Result := FileDate;
end;

end.
