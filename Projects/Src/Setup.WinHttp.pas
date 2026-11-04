unit Setup.WinHttp;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  For conditions of distribution and use, see LICENSE.TXT.
}

{$MODE DELPHIUNICODE}

interface

uses
  Classes;

type
  TWinHttpProgress = procedure(const Sender: TObject; ContentLength, ReadCount: Int64;
    var Abort: Boolean) of object;

  TWinHttpResponse = record
    StatusCode: Integer;
    StatusText: String;
    ContentLength: Int64;
    LastModified: String;
  end;

function RequestWinHttp(const Url, UserAgent, UserName, Password: String;
  const Destination: TStream; const Progress: TWinHttpProgress): TWinHttpResponse;

implementation

uses
  Windows, WinHttp, SysUtils;

type
  THttpUrl = record
    Host, Path: String;
    Port: INTERNET_PORT;
    Secure: Boolean;
  end;

function ParseHttpUrl(const Url: String): THttpUrl;
var
  Parts: URL_COMPONENTS;
  Extra: String;
  Fragment: Integer;
begin
  Parts := Default(URL_COMPONENTS);
  Parts.dwStructSize := SizeOf(Parts);
  Parts.dwHostNameLength := DWORD(-1);
  Parts.dwUrlPathLength := DWORD(-1);
  Parts.dwExtraInfoLength := DWORD(-1);
  Parts.dwUserNameLength := DWORD(-1);
  Parts.dwPasswordLength := DWORD(-1);
  if not WinHttpCrackUrl(PWideChar(Url), Length(Url), 0, @Parts) then
    RaiseLastOSError;
  if (Parts.nScheme <> INTERNET_SCHEME_HTTP) and
     (Parts.nScheme <> INTERNET_SCHEME_HTTPS) then
    raise EArgumentException.Create('Expected an HTTP or HTTPS URL');
  if (Parts.dwUserNameLength <> 0) or (Parts.dwPasswordLength <> 0) then
    raise EArgumentException.Create('HTTP credentials must be supplied separately');

  SetString(Result.Host, Parts.lpszHostName, Parts.dwHostNameLength);
  SetString(Result.Path, Parts.lpszUrlPath, Parts.dwUrlPathLength);
  SetString(Extra, Parts.lpszExtraInfo, Parts.dwExtraInfoLength);
  if Result.Path = '' then
    Result.Path := '/';
  Fragment := Pos('#', Extra);
  if Fragment > 0 then
    SetLength(Extra, Fragment - 1);
  Result.Path := Result.Path + Extra;
  Result.Port := Parts.nPort;
  Result.Secure := Parts.nScheme = INTERNET_SCHEME_HTTPS;
end;

function RequestWinHttp(const Url, UserAgent, UserName, Password: String;
  const Destination: TStream; const Progress: TWinHttpProgress): TWinHttpResponse;
const
  SecureProtocolTLS13 = $00002000;
var
  ParsedUrl, ResponseUrl: THttpUrl;
  Session, Connection, Request: HINTERNET;
  Verb: PWideChar;
  Flags, Protocols, Status, Size, BytesRead, SupportedAuth, FirstAuth, AuthTarget: DWORD;
  Buffer: array[0..65535] of Byte;
  ReadCount: Int64;
  Aborted: Boolean;
  EffectiveUrl: String;

  function QueryHeader(const Kind: DWORD; const Optional: Boolean): String;
  var
    LengthInBytes, ErrorCode: DWORD;
  begin
    Result := '';
    LengthInBytes := 0;
    if not WinHttpQueryHeaders(Request, Kind, nil, nil, @LengthInBytes, nil) then begin
      ErrorCode := GetLastError;
      if Optional and (ErrorCode = ERROR_WINHTTP_HEADER_NOT_FOUND) then
        Exit;
      if ErrorCode <> ERROR_INSUFFICIENT_BUFFER then
        RaiseLastOSError(ErrorCode);
    end;
    if LengthInBytes = 0 then
      Exit;
    SetLength(Result, LengthInBytes div SizeOf(WideChar));
    if not WinHttpQueryHeaders(Request, Kind, nil, PWideChar(Result), @LengthInBytes, nil) then
      RaiseLastOSError;
    SetLength(Result, LengthInBytes div SizeOf(WideChar));
  end;

  function SendRequest: DWORD;
  var
    StatusSize: DWORD;
  begin
    if not WinHttpSendRequest(Request, nil, 0, nil, 0, 0, 0) then
      RaiseLastOSError;
    if not WinHttpReceiveResponse(Request, nil) then
      RaiseLastOSError;
    StatusSize := SizeOf(Result);
    if not WinHttpQueryHeaders(Request, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
      nil, @Result, @StatusSize, nil) then
      RaiseLastOSError;
  end;

begin
  ParsedUrl := ParseHttpUrl(Url);
  if Destination = nil then
    Verb := 'HEAD'
  else
    Verb := 'GET';
  Flags := 0;
  if ParsedUrl.Secure then
    Flags := WINHTTP_FLAG_SECURE;

  Session := WinHttpOpen(PWideChar(UserAgent), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if Session = nil then
    RaiseLastOSError;
  try
    Protocols := WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 or SecureProtocolTLS13;
    if not WinHttpSetOption(Session, WINHTTP_OPTION_SECURE_PROTOCOLS, @Protocols, SizeOf(Protocols)) then begin
      Protocols := WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
      if not WinHttpSetOption(Session, WINHTTP_OPTION_SECURE_PROTOCOLS, @Protocols, SizeOf(Protocols)) then
        RaiseLastOSError;
    end;

    Connection := WinHttpConnect(Session, PWideChar(ParsedUrl.Host), ParsedUrl.Port, 0);
    if Connection = nil then
      RaiseLastOSError;
    try
      Request := WinHttpOpenRequest(Connection, Verb, PWideChar(ParsedUrl.Path), nil, nil, nil, Flags);
      if Request = nil then
        RaiseLastOSError;
      try
        Status := SendRequest;
        if (Status = 401) and ((UserName <> '') or (Password <> '')) and
          WinHttpQueryAuthSchemes(Request, @SupportedAuth, @FirstAuth, @AuthTarget) and
          (AuthTarget = WINHTTP_AUTH_TARGET_SERVER) and
          (SupportedAuth and WINHTTP_AUTH_SCHEME_BASIC <> 0) then begin
          Size := 0;
          if WinHttpQueryOption(Request, WINHTTP_OPTION_URL, nil, @Size) or
            (GetLastError <> ERROR_INSUFFICIENT_BUFFER) then
            RaiseLastOSError;
          SetLength(EffectiveUrl, Size div SizeOf(WideChar));
          if not WinHttpQueryOption(Request, WINHTTP_OPTION_URL, PWideChar(EffectiveUrl), @Size) then
            RaiseLastOSError;
          SetLength(EffectiveUrl, StrLen(PWideChar(EffectiveUrl)));
          ResponseUrl := ParseHttpUrl(EffectiveUrl);
          if (ResponseUrl.Secure = ParsedUrl.Secure) and (ResponseUrl.Port = ParsedUrl.Port) and
            SameText(ResponseUrl.Host, ParsedUrl.Host) then begin
            if not WinHttpSetCredentials(Request, WINHTTP_AUTH_TARGET_SERVER, WINHTTP_AUTH_SCHEME_BASIC,
              PWideChar(UserName), PWideChar(Password), nil) then
              RaiseLastOSError;
            Status := SendRequest;
          end;
        end;

        Result.StatusCode := Integer(Status);
        Result.StatusText := QueryHeader(WINHTTP_QUERY_STATUS_TEXT, True);
        Result.ContentLength := StrToInt64Def(QueryHeader(WINHTTP_QUERY_CONTENT_LENGTH, True), -1);
        Result.LastModified := QueryHeader(WINHTTP_QUERY_LAST_MODIFIED, True);
        if (Destination = nil) or (Status < 200) or (Status > 299) then
          Exit;

        ReadCount := 0;
        repeat
          Aborted := False;
          if Assigned(Progress) then
            Progress(nil, Result.ContentLength, ReadCount, Aborted);
          if Aborted then
            Exit;
          if not WinHttpReadData(Request, @Buffer[0], SizeOf(Buffer), @BytesRead) then
            RaiseLastOSError;
          if BytesRead = 0 then
            Break;
          Destination.WriteBuffer(Buffer, BytesRead);
          Inc(ReadCount, BytesRead);
        until False;
      finally
        WinHttpCloseHandle(Request);
      end;
    finally
      WinHttpCloseHandle(Connection);
    end;
  finally
    WinHttpCloseHandle(Session);
  end;
end;

end.
