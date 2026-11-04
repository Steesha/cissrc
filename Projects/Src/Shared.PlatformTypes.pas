unit Shared.PlatformTypes;

{
  Inno Setup native compiler port
  For conditions of distribution and use, see LICENSE.TXT.

  Fixed-width Windows data types used by host-independent format/interface units.
  This unit contains no emulation of Windows APIs.
}

interface

type
  DWORD = Cardinal;
  BOOL = LongBool;
  TFileTime = record
    dwLowDateTime: Cardinal;
    dwHighDateTime: Cardinal;
  end;
  PFileTime = ^TFileTime;
  TSIDIdentifierAuthority = record
    Value: array[0..5] of Byte;
  end;

const
  FILE_ATTRIBUTE_READONLY = $00000001;
  FILE_ATTRIBUTE_HIDDEN = $00000002;
  FILE_ATTRIBUTE_SYSTEM = $00000004;

  HKEY_CLASSES_ROOT = $80000000;
  HKEY_CURRENT_USER = $80000001;
  HKEY_LOCAL_MACHINE = $80000002;
  HKEY_USERS = $80000003;
  HKEY_CURRENT_CONFIG = $80000005;

  HOTKEYF_SHIFT = 1;
  HOTKEYF_CONTROL = 2;
  HOTKEYF_ALT = 4;

  SW_HIDE = 0;
  SW_SHOWNORMAL = 1;
  SW_SHOWMAXIMIZED = 3;
  SW_SHOWMINNOACTIVE = 7;

implementation

end.
