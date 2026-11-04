"""Cross-build Inno Setup's three archive DLLs from an is7z source checkout."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
from tempfile import TemporaryDirectory


BUNDLES = {
  "Format7zFInno": ("7z", (), ("Aes", "Crc", "Crc64", "LzFindOpt", "Sha1", "Sha256", "Sort")),
  "Format7zExtract": ("7zxa", ("-DZ7_EXTRACT_ONLY",), ("Aes", "Crc", "Sha256")),
  "Format7zExtractR": ("7zxr", ("-DZ7_EXTRACT_ONLY", "-DZ7_NO_CRYPTO"), ("Crc",)),
}


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("source_directory", type=Path)
  parser.add_argument("output_directory", type=Path)
  parser.add_argument("--arch", choices=("x64", "x86"), default="x64")
  parser.add_argument("--jobs", type=int, default=4)
  args = parser.parse_args()
  if args.jobs < 1:
    parser.error("--jobs must be positive")

  source = args.source_directory.resolve() / "CPP" / "7zip"
  output = args.output_directory.resolve()
  prefix = "x86_64-w64-mingw32" if args.arch == "x64" else "i686-w64-mingw32"
  suffix = "-x64" if args.arch == "x64" else ""
  for tool in ("make", f"{prefix}-gcc", f"{prefix}-g++", f"{prefix}-windres"):
    if not shutil.which(tool):
      parser.error(f"Required native tool not found: {tool}")
  output.mkdir(parents=True, exist_ok=True)
  for bundle, (program, defines, fragments) in BUNDLES.items():
    directory = source / "Bundles" / bundle
    object_lists = [directory / "makefile", *(source / f"{name}.mak" for name in fragments)]
    if bundle == "Format7zFInno":
      object_lists.append(directory / "Arc.mak")
    # Use the exact upstream bundle manifests, with portable C implementations
    # for CRC and LZMA. The GNU make rules resolve each object's source path.
    objects = sorted({name for path in object_lists
                      for name in re.findall(r"\$O\\(\w+)\.obj", path.read_text())})
    makefile = f"""PROG = {program}
DEF_FILE = ../../Archive/Archive2.def
LOCAL_FLAGS = -DZ7_EXTERNAL_CODECS {' '.join(defines)}
OBJS = $O/resource.o {' '.join(f'$O/{name}.o' for name in objects)}
include ../../7zip_gcc.mak
"""
    with TemporaryDirectory(prefix=f".{bundle}-{args.arch}-", dir=output) as scratch:
      build = Path(scratch)
      rules = build / "cross.gmk"
      rules.write_text(makefile, encoding="ascii")
      subprocess.run([
        "make", "-C", str(directory), "-f", str(rules), f"-j{args.jobs}",
        f"O={build}", "IS_MINGW=1", "MSYSTEM=MINGW64",
        f"CC={prefix}-gcc", f"CXX={prefix}-g++", f"RC={prefix}-windres",
        "CFLAGS_WARN_WALL=-Wall -Wextra",
        "LDFLAGS=-shared -static ../../Archive/Archive2.def",
      ], check=True)
      shutil.copyfile(build / f"{program}.dll", output / f"is{program}{suffix}.dll")


if __name__ == "__main__":
  main()
