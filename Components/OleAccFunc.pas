unit OleAccFunc;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  MSAA function loading
}

interface

uses
  {$IFDEF FPC}Windows{$ELSE}Winapi.Windows{$ENDIF};

var
  NotifyWinEventFunc: procedure(event: DWORD; hwnd: HWND; idObject: DWORD;
    idChild: Integer); stdcall;
  LresultFromObjectFunc: function(const riid: TGUID; wParam: WPARAM;
    punk: IUnknown): LRESULT; stdcall;
  CreateStdAccessibleObjectFunc: function(hwnd: HWND; idObject: Integer;
    const riid: TGUID; out ppvObject: Pointer): HRESULT; stdcall;

function InitializeOleAcc: Boolean;

implementation

uses
  {$IFDEF FPC}ActiveX, SysUtils,{$ELSE}Winapi.ActiveX, System.SysUtils,{$ENDIF} PathFunc;

var
  OleAccInited: Boolean;
  OleAccAvailable: Boolean;

function InitializeOleAcc: Boolean;

  function GetSystemDir: String;
  var
    Buf: array[0..MAX_PATH-1] of WideChar;
    Count: Cardinal;
  begin
    Count := GetSystemDirectoryW(@Buf[0], Length(Buf));
    if (Count = 0) or (Count >= Length(Buf)) then
      Exit('');
    SetString(Result, PWideChar(@Buf[0]), Count);
  end;

var
  M: HMODULE;
  SystemDir: String;
begin
  if not OleAccInited then begin
    M := 0;
    SystemDir := GetSystemDir;
    if SystemDir <> '' then
      M := LoadLibraryW(PWideChar(AddBackslash(SystemDir) + 'oleacc.dll'));
    if M <> 0 then begin
      {$IFDEF FPC}PPointer(@@LresultFromObjectFunc)^{$ELSE}LresultFromObjectFunc{$ENDIF} := GetProcAddress(M, 'LresultFromObject');
      {$IFDEF FPC}PPointer(@@CreateStdAccessibleObjectFunc)^{$ELSE}CreateStdAccessibleObjectFunc{$ENDIF} := GetProcAddress(M, 'CreateStdAccessibleObject');
      if Assigned(LresultFromObjectFunc) and
         Assigned(CreateStdAccessibleObjectFunc) then
        OleAccAvailable := True;
    end;
    OleAccInited := True;
  end;
  Result := OleAccAvailable;
end;

{ Note: This COM initialization code based on code from DBTables }
var
  {$IFNDEF FPC}SaveInitProc: Pointer;{$ENDIF}
  NeedToUninitialize: Boolean;

procedure InitCOM;
begin
  {$IFNDEF FPC}
  if SaveInitProc <> nil then TProcedure(SaveInitProc);
  {$ENDIF}
  NeedToUninitialize := SUCCEEDED(CoInitialize(nil));
end;

initialization
  if not IsLibrary then begin
    {$IFDEF FPC}
    InitCOM;
    {$ELSE}
    SaveInitProc := InitProc;
    InitProc := @InitCOM;
    {$ENDIF}
  end;
  {$IFDEF FPC}PPointer(@@NotifyWinEventFunc)^{$ELSE}NotifyWinEventFunc{$ENDIF} := GetProcAddress(GetModuleHandle(user32), 'NotifyWinEvent');

finalization
  if NeedToUninitialize then
    CoUninitialize;
end.
