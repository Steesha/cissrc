"""Build the Windows ZIP and BZip2 codecs with native MinGW tools."""

import argparse
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory


def set_callback_conventions(header: Path, callbacks: tuple[str, ...]) -> None:
  contents = header.read_bytes()
  for name in callbacks:
    declaration = f"(*{name})".encode("ascii")
    if contents.count(declaration) != 1:
      raise ValueError(f"Unexpected callback declaration for {name} in {header}")
    contents = contents.replace(declaration, f"(__stdcall *{name})".encode("ascii"))
  header.write_bytes(contents)


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("source_directory", type=Path)
  parser.add_argument("output_directory", type=Path)
  parser.add_argument("--arch", choices=("x64", "x86"), default="x64")
  args = parser.parse_args()
  source = args.source_directory.resolve()
  output = args.output_directory.resolve()
  x86 = args.arch == "x86"
  compiler = ("i686" if x86 else "x86_64") + "-w64-mingw32-gcc"
  if not shutil.which(compiler):
    parser.error(f"Required native tool not found: {compiler}")
  suffix = "" if x86 else "-x64"
  output.mkdir(parents=True, exist_ok=True)
  command = [compiler, "-O2", "-shared", "-static"]
  if x86:
    command.append("-Wl,--enable-stdcall-fixup")

  with TemporaryDirectory(prefix="inno-codecs-") as scratch:
    work = Path(scratch)
    zlib = work / "zlib"
    bzlib = work / "bzlib"
    shutil.copytree(source / "zlib", zlib)
    shutil.copytree(source / "bzlib", bzlib)
    if x86:
      # MSVC uses /Gz for these function pointers. Keep the MinGW CRT's
      # default convention and apply stdcall to Inno Setup callbacks only.
      set_callback_conventions(zlib / "zlib.h", ("alloc_func", "free_func"))
      set_callback_conventions(bzlib / "bzlib.h", ("bzalloc", "bzfree"))
      bz_source = bzlib / "bzlib.c"
      contents = bz_source.read_bytes()
      for name in (b"default_bzalloc", b"default_bzfree"):
        declaration = b" " + name + b" ("
        if contents.count(declaration) != 1:
          raise ValueError(f"Unexpected default callback declaration in {bz_source}")
        contents = contents.replace(declaration, b" __stdcall" + declaration)
      bz_source.write_bytes(contents)
    (bzlib / "inno_error.c").write_text(
      "#include <windows.h>\n"
      "void bz_internal_error(int code) { RaiseException(0x06E15C8B, 0, 0, NULL); }\n",
      encoding="ascii")
    zlib_flags = ["-DZ_SOLO", "-DNO_GZIP", "-DZLIB_WINAPI", "adler32.c", "zutil.c"]
    bzlib_flags = ["-DBZ_NO_STDIO", "blocksort.c", "bzlib.c", "compress.c",
                   "crctable.c", "decompress.c", "huffman.c", "randtable.c", "inno_error.c"]
    codecs = (
      ("isunzlib", zlib, [*zlib_flags, "inffast.c", "inflate.c", "inftrees.c", "isunzlib.def"]),
      ("iszlib", zlib, [*zlib_flags, "deflate.c", "trees.c", "iszlib.def"]),
      ("isbunzip", bzlib, [*bzlib_flags, "isbz2decomp.def"]),
      ("isbzip", bzlib, [*bzlib_flags, "isbz2comp.def"]),
    )
    for name, directory, flags in codecs:
      subprocess.run([*command, *flags, "-o", str(work / f"{name}{suffix}.dll")],
                     cwd=directory, check=True)
    for name, _, _ in codecs:
      filename = f"{name}{suffix}.dll"
      shutil.copyfile(work / filename, output / filename)


if __name__ == "__main__":
  main()
