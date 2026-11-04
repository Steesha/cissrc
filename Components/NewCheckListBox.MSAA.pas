unit NewCheckListBox.MSAA;

{
  Inno Setup
  Copyright (C) 1997-2026 Jordan Russell
  Portions by Martijn Laan
  For conditions of distribution and use, see LICENSE.TXT.

  MSAA support for NewCheckListBox
}

interface

uses
  Windows, Messages,
  NewCheckListBox;

type
  TNewCheckListBoxMSAAHelper = class helper for TNewCheckListBox
    procedure AnnounceStateChangeToMSAA(const AIndex: Integer);
    procedure DisconnectMSAAObject;
    function HandleMSAAGetObject(var Message: TMessage): Boolean;
  end;

implementation

uses
  ActiveX, {$IFDEF FPC}Variants, VarUtils,{$ELSE}oleacc,{$ENDIF} SysUtils, Classes, StdCtrls, OleAccFunc;

{$IFDEF FPC}
const
  CHILDID_SELF = 0;
  OBJID_CLIENT = DWORD($FFFFFFFC);
  EVENT_OBJECT_STATECHANGE = $800A;
  STATE_SYSTEM_UNAVAILABLE = $01;
  STATE_SYSTEM_CHECKED = $10;
  STATE_SYSTEM_MIXED = $20;
  ROLE_SYSTEM_OUTLINE = $23;
  ROLE_SYSTEM_STATICTEXT = $29;
  ROLE_SYSTEM_CHECKBUTTON = $2C;
  ROLE_SYSTEM_RADIOBUTTON = $2D;

type
  { COM takes the child VARIANT by value. Use the unmanaged record for that
    ABI so FPC does not apply managed-parameter lifetime rules. }
  TMSAAChild = TVarData;
  TMSAAVariant = TVarData;
  TMSAABstr = PWideChar;
  TMSAADispatch = Pointer;
  {$IFDEF CPU64}
    {$IF SizeOf(TMSAAChild) <> 24}{$FATAL Unexpected Win64 VARIANT size}{$ENDIF}
  {$ELSE}
    {$IF SizeOf(TMSAAChild) <> 16}{$FATAL Unexpected Win32 VARIANT size}{$ENDIF}
  {$ENDIF}

  { Method order follows IAccessible in oleacc.h }
  IAccessible = interface(IDispatch)
    ['{618736E0-3C3D-11CF-810C-00AA00389B71}']
    function get_accParent(out ppdispParent: TMSAADispatch): HRESULT; stdcall;
    function get_accChildCount(out pcountChildren: Integer): HRESULT; stdcall;
    function get_accChild(varChild: TMSAAChild; out ppdispChild: TMSAADispatch): HRESULT; stdcall;
    function get_accName(varChild: TMSAAChild; out pszName: TMSAABstr): HRESULT; stdcall;
    function get_accValue(varChild: TMSAAChild; out pszValue: TMSAABstr): HRESULT; stdcall;
    function get_accDescription(varChild: TMSAAChild; out pszDescription: TMSAABstr): HRESULT; stdcall;
    function get_accRole(varChild: TMSAAChild; out pvarRole: TMSAAVariant): HRESULT; stdcall;
    function get_accState(varChild: TMSAAChild; out pvarState: TMSAAVariant): HRESULT; stdcall;
    function get_accHelp(varChild: TMSAAChild; out pszHelp: TMSAABstr): HRESULT; stdcall;
    function get_accHelpTopic(out pszHelpFile: TMSAABstr; varChild: TMSAAChild; out pidTopic: Integer): HRESULT; stdcall;
    function get_accKeyboardShortcut(varChild: TMSAAChild; out pszKeyboardShortcut: TMSAABstr): HRESULT; stdcall;
    function get_accFocus(out pvarID: TMSAAVariant): HRESULT; stdcall;
    function get_accSelection(out pvarChildren: TMSAAVariant): HRESULT; stdcall;
    function get_accDefaultAction(varChild: TMSAAChild; out pszDefaultAction: TMSAABstr): HRESULT; stdcall;
    function accSelect(flagsSelect: Integer; varChild: TMSAAChild): HRESULT; stdcall;
    function accLocation(out pxLeft: Integer; out pyTop: Integer; out pcxWidth: Integer;
      out pcyHeight: Integer; varChild: TMSAAChild): HRESULT; stdcall;
    function accNavigate(navDir: Integer; varStart: TMSAAChild; out pvarEnd: TMSAAVariant): HRESULT; stdcall;
    function accHitTest(xLeft: Integer; yTop: Integer; out pvarID: TMSAAVariant): HRESULT; stdcall;
    function accDoDefaultAction(varChild: TMSAAChild): HRESULT; stdcall;
    function put_accName(varChild: TMSAAChild; pszName: TMSAABstr): HRESULT; stdcall;
    function put_accValue(varChild: TMSAAChild; pszValue: TMSAABstr): HRESULT; stdcall;
  end;

function AllocMSAABstr(const Value: PWideChar; Length: Cardinal): TMSAABstr;
  stdcall; external 'oleaut32.dll' name 'SysAllocStringLen';
{$ELSE}
type
  TMSAAChild = OleVariant;
  TMSAAVariant = OleVariant;
  TMSAABstr = WideString;
  TMSAADispatch = IDispatch;
{$ENDIF}

type
  TNewCheckListBoxAccess = class(TNewCheckListBox);

  TAccObject = class(TInterfacedObject, IDispatch, IAccessible)
  private
    FControl: TNewCheckListBoxAccess;
    FStdAcc: IAccessible;
    { IDispatch }
    function GetTypeInfoCount(out ctinfo: Integer): HRESULT; stdcall;
    function GetTypeInfo(itinfo: Integer; lcid: Integer; out tinfo): HRESULT; stdcall;
    function GetIDsOfNames(const iid: TIID; rgszNames: Pointer;
      cNames: Integer; lcid: Integer; rgdispid: Pointer): HRESULT; stdcall;
    function Invoke(dispIDMember: TDispID; const iid: TIID; lcid: Integer;
      flags: Word; var dispParams; varResult: Pointer;
      excepInfo: Pointer; argErr: Pointer): HRESULT; stdcall;
    { IAccessible }
    function get_accParent(out ppdispParent: TMSAADispatch): HRESULT; stdcall;
    function get_accChildCount(out pcountChildren: Integer): HRESULT; stdcall;
    function get_accChild(varChild: TMSAAChild; out ppdispChild: TMSAADispatch): HRESULT; stdcall;
    function get_accName(varChild: TMSAAChild; out pszName: TMSAABstr): HRESULT; stdcall;
    function get_accValue(varChild: TMSAAChild; out pszValue: TMSAABstr): HRESULT; stdcall;
    function get_accDescription(varChild: TMSAAChild; out pszDescription: TMSAABstr): HRESULT; stdcall;
    function get_accRole(varChild: TMSAAChild; out pvarRole: TMSAAVariant): HRESULT; stdcall;
    function get_accState(varChild: TMSAAChild; out pvarState: TMSAAVariant): HRESULT; stdcall;
    function get_accHelp(varChild: TMSAAChild; out pszHelp: TMSAABstr): HRESULT; stdcall;
    function get_accHelpTopic(out pszHelpFile: TMSAABstr; varChild: TMSAAChild; out pidTopic: Integer): HRESULT; stdcall;
    function get_accKeyboardShortcut(varChild: TMSAAChild; out pszKeyboardShortcut: TMSAABstr): HRESULT; stdcall;
    function get_accFocus(out pvarID: TMSAAVariant): HRESULT; stdcall;
    function get_accSelection(out pvarChildren: TMSAAVariant): HRESULT; stdcall;
    function get_accDefaultAction(varChild: TMSAAChild; out pszDefaultAction: TMSAABstr): HRESULT; stdcall;
    function accSelect(flagsSelect: Integer; varChild: TMSAAChild): HRESULT; stdcall;
    function accLocation(out pxLeft: Integer; out pyTop: Integer; out pcxWidth: Integer;
      out pcyHeight: Integer; varChild: TMSAAChild): HRESULT; stdcall;
    function accNavigate(navDir: Integer; varStart: TMSAAChild; out pvarEnd: TMSAAVariant): HRESULT; stdcall;
    function accHitTest(xLeft: Integer; yTop: Integer; out pvarID: TMSAAVariant): HRESULT; stdcall;
    function accDoDefaultAction(varChild: TMSAAChild): HRESULT; stdcall;
    function put_accName(varChild: TMSAAChild; {$IFNDEF FPC}const{$ENDIF} pszName: TMSAABstr): HRESULT; stdcall;
    function put_accValue(varChild: TMSAAChild; {$IFNDEF FPC}const{$ENDIF} pszValue: TMSAABstr): HRESULT; stdcall;
    {$IFNDEF FPC}
    function IAccessible.Set_accName = put_accName;
    function IAccessible.Set_accValue = put_accValue;
    {$ENDIF}
  public
    constructor Create(AControl: TNewCheckListBox);
    destructor Destroy; override;
    procedure ControlDestroying;
  end;

{ TNewCheckListBoxMSAAHelper }

procedure TNewCheckListBoxMSAAHelper.AnnounceStateChangeToMSAA(
  const AIndex: Integer);
{ Notify MSAA of the state change. Works for NVDA, but not for Narrator;
  it requires a focus event as well. }
begin
  if Assigned(NotifyWinEventFunc) then
    NotifyWinEventFunc(EVENT_OBJECT_STATECHANGE, Handle, OBJID_CLIENT,
      1 + AIndex);
end;

procedure TNewCheckListBoxMSAAHelper.DisconnectMSAAObject;
begin
  if Assigned(FAccObjectInstance) then begin
    { Detach from FAccObjectInstance if someone still has a reference to it }
    TAccObject(FAccObjectInstance).ControlDestroying;
    FAccObjectInstance := nil;
  end;
end;

function TNewCheckListBoxMSAAHelper.HandleMSAAGetObject(var Message: TMessage): Boolean;
var
  AccObject: IAccessible;
begin
  { Per docs, lParam must be casted to DWORD (32 bits) because it may be
    sign-extended in a 64-bit process. Bail when destroying: the window
    outlives the DisconnectMSAAObject call in Destroy. }
  Result := (DWORD(Message.LParam) = OBJID_CLIENT) and
    not (csDestroying in ComponentState) and InitializeOleAcc;
  if Result then begin
    if FAccObjectInstance = nil then begin
      try
        FAccObjectInstance := TAccObject.Create(Self);
      except
        Exit(False);
      end;
    end;
    { Keep our own reference to ensure release even if LresultFromObject fails }
    AccObject := TAccObject(FAccObjectInstance);
    Message.Result := LresultFromObjectFunc(IAccessible, Message.WParam,
      AccObject);
  end;
end;

{ TAccObject }

constructor TAccObject.Create(AControl: TNewCheckListBox);
begin
  inherited Create;
  if CreateStdAccessibleObjectFunc(AControl.Handle, Integer(OBJID_CLIENT),
     IAccessible, Pointer(FStdAcc)) <> S_OK then begin
    { Note: The user will never actually see this message since the call to
      TAccObject.Create in HandleMSAAGetObject is protected by a
      try..except. }
    raise Exception.Create('CreateStdAccessibleObject failed');
  end;
  FControl := TNewCheckListBoxAccess(AControl);
end;

destructor TAccObject.Destroy;
begin
  { If FControl is assigned, then we are being destroyed before the control --
    the usual case. Clear FControl's reference to us. }
  if Assigned(FControl) then begin
    FControl.FAccObjectInstance := nil;
    FControl := nil;
  end;
  inherited;
end;

procedure TAccObject.ControlDestroying;
begin
  { Set FControl to nil, since it's no longer valid }
  FControl := nil;
  { Take this opportunity to disconnect remote clients, i.e. don't allow them
    to call us anymore. This prevents invalid memory accesses if this unit's
    code is in a DLL, and the application subsequently unloads the DLL while
    remote clients still hold (and are using) references to this TAccObject. }
  CoDisconnectObject(Self, 0);
  { NOTE: Don't access Self in any way at this point. The CoDisconnectObject
    call likely caused all references to be relinquished and Self to be
    destroyed. }
end;

function TAccObject.GetTypeInfoCount(out ctinfo: Integer): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TAccObject.GetTypeInfo(itinfo: Integer; lcid: Integer; out tinfo): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TAccObject.GetIDsOfNames(const iid: TIID; rgszNames: Pointer;
  cNames: Integer; lcid: Integer; rgdispid: Pointer): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TAccObject.Invoke(dispIDMember: TDispID; const iid: TIID; lcid: Integer;
  flags: Word; var dispParams; varResult: Pointer;
  excepInfo: Pointer; argErr: Pointer): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function TAccObject.accDoDefaultAction(varChild: TMSAAChild): HRESULT;
begin
  { A list box's default action is Double Click, which is useless for a
    list of check boxes }
  Result := DISP_E_MEMBERNOTFOUND;
end;

function TAccObject.accHitTest(xLeft, yTop: Integer;
  out pvarID: TMSAAVariant): HRESULT;
begin
  Result := FStdAcc.accHitTest(xLeft, yTop, pvarID);
end;

function TAccObject.accLocation(out pxLeft, pyTop, pcxWidth,
  pcyHeight: Integer; varChild: TMSAAChild): HRESULT;
begin
  Result := FStdAcc.accLocation(pxLeft, pyTop, pcxWidth, pcyHeight, varChild);
end;

function TAccObject.accNavigate(navDir: Integer; varStart: TMSAAChild;
  out pvarEnd: TMSAAVariant): HRESULT;
begin
  Result := FStdAcc.accNavigate(navDir, varStart, pvarEnd);
end;

function TAccObject.accSelect(flagsSelect: Integer;
  varChild: TMSAAChild): HRESULT;
begin
  Result := FStdAcc.accSelect(flagsSelect, varChild);
end;

function TAccObject.get_accChild(varChild: TMSAAChild;
  out ppdispChild: TMSAADispatch): HRESULT;
begin
  Result := FStdAcc.get_accChild(varChild, ppdispChild);
end;

function TAccObject.get_accChildCount(out pcountChildren: Integer): HRESULT;
begin
  Result := FStdAcc.get_accChildCount(pcountChildren);
end;

function TAccObject.get_accDefaultAction(varChild: TMSAAChild;
  out pszDefaultAction: TMSAABstr): HRESULT;
begin
  { See accDoDefaultAction }
  pszDefaultAction := '';
  Result := S_FALSE;
end;

function TAccObject.get_accDescription(varChild: TMSAAChild;
  out pszDescription: TMSAABstr): HRESULT;
begin
  Result := FStdAcc.get_accDescription(varChild, pszDescription);
end;

function TAccObject.get_accFocus(out pvarID: TMSAAVariant): HRESULT;
begin
  Result := FStdAcc.get_accFocus(pvarID);
end;

function TAccObject.get_accHelp(varChild: TMSAAChild;
  out pszHelp: TMSAABstr): HRESULT;
begin
  Result := FStdAcc.get_accHelp(varChild, pszHelp);
end;

function TAccObject.get_accHelpTopic(out pszHelpFile: TMSAABstr;
  varChild: TMSAAChild; out pidTopic: Integer): HRESULT;
begin
  Result := FStdAcc.get_accHelpTopic(pszHelpFile, varChild, pidTopic);
end;

function TAccObject.get_accKeyboardShortcut(varChild: TMSAAChild;
  out pszKeyboardShortcut: TMSAABstr): HRESULT;
begin
  Result := FStdAcc.get_accKeyboardShortcut(varChild, pszKeyboardShortcut);
end;

function TAccObject.get_accName(varChild: TMSAAChild;
  out pszName: TMSAABstr): HRESULT;
begin
  Result := FStdAcc.get_accName(varChild, pszName);
end;

function TAccObject.get_accParent(out ppdispParent: TMSAADispatch): HRESULT;
begin
  Result := FStdAcc.get_accParent(ppdispParent);
end;

function TAccObject.get_accRole(varChild: TMSAAChild;
  out pvarRole: TMSAAVariant): HRESULT;
begin
  VariantInit({$IFDEF FPC}TVarData(pvarRole){$ELSE}pvarRole{$ENDIF});
  if FControl = nil then begin
    Result := E_FAIL;
    Exit;
  end;
  if TVarData(varChild).VType <> VT_I4 then begin
    Result := E_INVALIDARG;
    Exit;
  end;
  if TVarData(varChild).VInteger = CHILDID_SELF then begin
    TVarData(pvarRole).VInteger := ROLE_SYSTEM_OUTLINE;
    TVarData(pvarRole).VType := VT_I4;
    Result := S_OK;
  end else begin
    try
      case FControl.ItemStates[TVarData(varChild).VInteger-1].ItemType of
        itCheck: TVarData(pvarRole).VInteger := ROLE_SYSTEM_CHECKBUTTON;
        itRadio: TVarData(pvarRole).VInteger := ROLE_SYSTEM_RADIOBUTTON;
      else
        TVarData(pvarRole).VInteger := ROLE_SYSTEM_STATICTEXT;
      end;
      TVarData(pvarRole).VType := VT_I4;
      Result := S_OK;
    except
      Result := E_INVALIDARG;
    end;
  end;
end;

function TAccObject.get_accSelection(out pvarChildren: TMSAAVariant): HRESULT;
begin
  Result := FStdAcc.get_accSelection(pvarChildren);
end;

function TAccObject.get_accState(varChild: TMSAAChild;
  out pvarState: TMSAAVariant): HRESULT;
var
  IsItem: Boolean;
  Item: Integer;
  ItemState: TItemState;
begin
  IsItem := (TVarData(varChild).VType = VT_I4) and
    (TVarData(varChild).VInteger <> CHILDID_SELF);
  Item := TVarData(varChild).VInteger;

  Result := FStdAcc.get_accState(varChild, pvarState);
  { ^ On 64-bit, Delphi passes our own copy of varChild, and
      FStdAcc.get_accState changes it (by decrementing VInteger),
      so don't read from it anymore }

  try
    if (Result = S_OK) and IsItem and
       (TVarData(pvarState).VType = VT_I4) and
       Assigned(FControl) then begin
      ItemState := FControl.ItemStates[Item-1];
      if ItemState.ItemType <> itGroup then begin
        case ItemState.State of
          cbChecked: TVarData(pvarState).VInteger := TVarData(pvarState).VInteger or STATE_SYSTEM_CHECKED;
          cbGrayed: TVarData(pvarState).VInteger := TVarData(pvarState).VInteger or STATE_SYSTEM_MIXED;
        end;
      end;
      if not ItemState.Enabled then
        TVarData(pvarState).VInteger := TVarData(pvarState).VInteger or STATE_SYSTEM_UNAVAILABLE;
    end;
  except
    Result := E_INVALIDARG;
  end;
end;

function TAccObject.get_accValue(varChild: TMSAAChild;
  out pszValue: TMSAABstr): HRESULT;
{$IFDEF FPC}
var
  Value: UnicodeString;
{$ENDIF}
begin
  pszValue := {$IFDEF FPC}nil{$ELSE}''{$ENDIF};
  if FControl = nil then begin
    Result := E_FAIL;
    Exit;
  end;
  if TVarData(varChild).VType <> VT_I4 then begin
    Result := E_INVALIDARG;
    Exit;
  end;
  if TVarData(varChild).VInteger = CHILDID_SELF then
    Result := S_FALSE
  else begin
    { Return the level as the value, like standard tree view controls do.
      Not sure if any screen readers will actually use this, seeing as we
      aren't a real tree view control. }
    try
      {$IFDEF FPC}
      Value := IntToStr(FControl.ItemStates[TVarData(varChild).VInteger-1].Level);
      pszValue := AllocMSAABstr(PWideChar(Value), Length(Value));
      if pszValue = nil then
        Exit(E_OUTOFMEMORY);
      {$ELSE}
      pszValue := IntToStr(FControl.ItemStates[TVarData(varChild).VInteger-1].Level);
      {$ENDIF}
      Result := S_OK;
    except
      Result := E_INVALIDARG;
    end;
  end;
end;

function TAccObject.put_accName(varChild: TMSAAChild;
  {$IFNDEF FPC}const{$ENDIF} pszName: TMSAABstr): HRESULT;
begin
  Result := S_FALSE;
end;

function TAccObject.put_accValue(varChild: TMSAAChild;
  {$IFNDEF FPC}const{$ENDIF} pszValue: TMSAABstr): HRESULT;
begin
  Result := S_FALSE;
end;

end.
