unit Compiler.StringDictionary;

{
  Inno Setup
  Copyright (C) 2026 Inno Setup contributors
  For conditions of distribution and use, see LICENSE.TXT.

  String dictionary specialization shared by compiler units
}

{$IFDEF FPC}
{$MODE DELPHIUNICODE}
{ FPC 3.2.2 initializes concrete dictionary enumerators through their abstract
  base constructor. The warning is spurious and emitted at the end of this unit }
{$WARN 4046 OFF}
{$ENDIF}

interface

uses Generics.Collections;

type
  TCompilerStringDictionary = TDictionary<String, String>;

implementation

end.
