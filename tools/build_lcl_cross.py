"""Build Lazarus LCL Win32 widgetset units for Windows on a Unix host."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request


VERSION = "4.0"
ARCHIVE = "lazarus-4.0.tar.gz"
SHA256 = "a916723c40ee354a998382a740010c1b639b0b4f2cb4b8b7e8a27dbff489a5a3"
URL = "https://codeload.github.com/fpc/Lazarus/tar.gz/refs/tags/lazarus_4_0"


def patch_window_callback(lcl):
  """Preserve message results in the pinned Lazarus 4.0 Win32 widgetset."""
  path = lcl / "interfaces/win32/win32lclintf.inc"
  text = path.read_text()
  old = "procedure CallbackAllocateHWnd(Ahwnd: HWND; uMsg: UINT; wParam: WParam; lParam: LParam); stdcall;"
  new = "function CallbackAllocateHWnd(Ahwnd: HWND; uMsg: UINT; wParam: WParam; lParam: LParam): LRESULT; stdcall;"
  old_dispatch = """  if Assigned(PMethod) then PMethod^(Msg);
  Windows.DefWindowProc(ahwnd, uMsg, wParam, lParam);"""
  new_dispatch = """  if Assigned(PMethod) then
  begin
    PMethod^(Msg);
    Result := Msg.Result;
  end
  else
    Result := Windows.DefWindowProc(ahwnd, uMsg, wParam, lParam);"""
  if old in text and old_dispatch in text:
    path.write_text(text.replace(old, new, 1).replace(old_dispatch, new_dispatch, 1))
  elif new not in text or new_dispatch not in text:
    raise RuntimeError("Unexpected Lazarus AllocateHWnd callback implementation")


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("build_directory", type=Path)
  parser.add_argument("fpc_cross_root", type=Path)
  parser.add_argument("--arch", choices=("x64", "x86"), default="x64")
  args = parser.parse_args()
  cpu, target_os, compiler_name, binutils_prefix = {
    "x64": ("x86_64", "win64", "ppcrossx64", "x86_64-w64-mingw32-"),
    "x86": ("i386", "win32", "ppcross386", "i686-w64-mingw32-"),
  }[args.arch]
  root = args.build_directory.resolve()
  root.mkdir(parents=True, exist_ok=True)

  fpc_root = args.fpc_cross_root.resolve() / "lib" / "fpc" / "3.2.2"
  compiler = fpc_root / compiler_name
  rtl_dir = fpc_root / "units" / f"{cpu}-{target_os}"
  assembler = shutil.which(binutils_prefix + "as")
  linker = shutil.which(binutils_prefix + "ld")
  if not compiler.is_file() or not rtl_dir.is_dir():
    parser.error(f"Build the Windows {args.arch} FPC compiler and RTL first: {fpc_root}")
  if not assembler or not linker or Path(assembler).parent != Path(linker).parent:
    parser.error("The MinGW assembler and linker must be on PATH in the same directory")

  archive = root / ARCHIVE
  if not archive.is_file():
    partial = archive.with_suffix(".partial")
    with urllib.request.urlopen(URL, timeout=90) as response, partial.open("wb") as output:
      shutil.copyfileobj(response, output)
    partial.replace(archive)
  if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    parser.error(f"Lazarus {VERSION} source checksum mismatch: {archive}")
  source_root = root / "source"
  source = source_root / "Lazarus-lazarus_4_0"
  if not (source / "lcl" / "forms.pp").is_file():
    if not hasattr(tarfile, "data_filter"):
      parser.error("Python with tarfile.data_filter is required for safe extraction")
    with tarfile.open(archive) as package:
      package.extractall(source_root, filter="data")

  output = root / "units"
  lcl = source / "lcl"
  patch_window_callback(lcl)
  # -Ur units are never rebuilt from changed includes, even with -B.
  # Recreate this generated directory so callback fixes reach every consumer.
  if output.exists():
    shutil.rmtree(output)
  output.mkdir()
  command = [str(compiler), "-B", "-n", f"-T{target_os}", f"-XP{binutils_prefix}",
    f"-FD{Path(assembler).parent}", "-Ur", "-MObjFPC", "-Sh", "-Sc",
    "-dLCL", "-dLCLwin32", f"-FU{output}", f"-FE{output}",
    f"-Fi{lcl / 'include'}", f"-Fi{lcl / 'interfaces' / 'win32'}"]
  # Free Vision contains units named Dialogs and Menus, which conflict with LCL.
  command.extend(f"-Fu{unit}" for unit in sorted(rtl_dir.iterdir())
                 if unit.is_dir() and unit.name != "fv")
  command.extend(f"-Fu{unit}" for unit in (
    lcl, lcl / "widgetset", lcl / "interfaces" / "win32", lcl / "interfaces",
    lcl / "forms", source / "components" / "lazutils",
    source / "packager" / "registration"))

  # Compile the widgetset-independent dependency graph before Interfaces.
  subprocess.run([*command, str(lcl / "forms.pp")], check=True)
  subprocess.run([*command, str(lcl / "interfaces" / "win32" / "interfaces.pp")], check=True)
  print(f"LCL {VERSION} Windows {args.arch} units: {output}")


if __name__ == "__main__":
  main()
