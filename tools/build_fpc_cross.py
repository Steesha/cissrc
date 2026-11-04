"""Build a Windows FPC compiler and RTL using only native host tools.

Requires FPC 3.2.2, make, MinGW-w64 and Python with tarfile.data_filter.
All downloads, source and outputs stay under the supplied build directory.
"""

import argparse
import hashlib
import os
import sys
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import urllib.request


VERSION = "3.2.2"
SHA256 = "d542e349de246843d4f164829953d1f5b864126c5b62fd17c9b45b33e23d2f44"
URL = f"https://downloads.sourceforge.net/project/freepascal/Source/{VERSION}/fpc-{VERSION}.source.tar.gz"


def patch_linux_startup(source: Path, machine: str) -> None:
  libc, version = platform.libc_ver()
  if libc != "glibc" or tuple(map(int, version.split(".")[:2])) < (2, 34):
    return
  # Match Debian's glibc 2.34 fix for the host RTL used by fpmake.
  # https://gitlab.com/freepascal.org/fpc/source/-/issues/39295
  if machine in ("aarch64", "arm64"):
    arch = "aarch64"
    original = (b"\tadrp\tx3,:got:__libc_csu_init\n"
                b"\tldr\tx3,[x3,#:got_lo12:__libc_csu_init]\n"
                b"\tadrp\tx4,:got:__libc_csu_fini\n"
                b"\tldr\tx4,[x4,#:got_lo12:__libc_csu_fini]\n")
    replacement = b"\tmov\tx3, #0\n\tmov\tx4, #0\n"
  elif machine == "x86_64":
    arch = machine
    original = (b"\t/* Pass address of our own entry points to .fini and .init.  */\n"
                b"\tmovq __libc_csu_init@GOTPCREL(%rip), %rcx\n"
                b"\tmovq __libc_csu_fini@GOTPCREL(%rip), %r8\n")
    replacement = b"\txorl %ecx, %ecx\n\txorl %r8d, %r8d\n"
  else:
    return
  startup = source / "rtl" / "linux" / arch / "cprt0.as"
  contents = startup.read_bytes()
  if replacement not in contents:
    if contents.count(original) != 1:
      raise ValueError(f"Unexpected glibc startup code in {startup}")
    startup.write_bytes(contents.replace(original, replacement))


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("build_directory", type=Path)
  parser.add_argument("--arch", choices=("x64", "x86"), default="x64")
  parser.add_argument("--host-linker", type=Path)
  parser.add_argument("--jobs", type=int, default=1)
  args = parser.parse_args()
  if args.jobs < 1:
    parser.error("--jobs must be positive")
  cpu, target_os, compiler_name, binutils_prefix = {
    "x64": ("x86_64", "win64", "ppcrossx64", "x86_64-w64-mingw32-"),
    "x86": ("i386", "win32", "ppcross386", "i686-w64-mingw32-"),
  }[args.arch]
  root = args.build_directory.resolve()
  root.mkdir(parents=True, exist_ok=True)
  for tool in ("fpc", "make", binutils_prefix + "as", binutils_prefix + "ld"):
    if not shutil.which(tool):
      parser.error(f"Required native tool not found: {tool}")
  version = subprocess.check_output(["fpc", "-iV"], text=True).strip()
  if version != VERSION:
    parser.error(f"Expected FPC {VERSION} bootstrap compiler, found {version}")
  compiler = subprocess.check_output(["fpc", "-PB"], text=True).strip()
  archive = root / f"fpc-{VERSION}.source.tar.gz"
  if not archive.exists():
    partial = archive.with_suffix(".partial")
    with urllib.request.urlopen(URL, timeout=60) as response, partial.open("wb") as output:
      shutil.copyfileobj(response, output)
    partial.replace(archive)
  if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    parser.error(f"Source checksum mismatch: {archive}")
  source = root / "source"
  if not (source / f"fpc-{VERSION}" / "Makefile").exists():
    if not hasattr(tarfile, "data_filter"):
      parser.error("Python with tarfile.data_filter is required for safe extraction")
    source.mkdir(exist_ok=True)
    with tarfile.open(archive) as package:
      package.extractall(source, filter="data")
  patch = Path(__file__).with_name("fpc-bootstrap.patch")
  source_tree = source / f"fpc-{VERSION}"
  applied = subprocess.run(["git", "-C", str(source_tree), "apply", "--reverse", "--check", str(patch)],
                           capture_output=True).returncode == 0
  previous = root / "bootstrap-applied.patch"
  patch_changed = previous.exists() and previous.read_bytes() != patch.read_bytes()
  if not applied and previous.exists():
    subprocess.run(["git", "-C", str(source_tree), "apply", "--reverse", "--check", str(previous)], check=True)
    subprocess.run(["git", "-C", str(source_tree), "apply", "--reverse", str(previous)], check=True)
  if not applied:
    subprocess.run(["git", "-C", str(source_tree), "apply", "--check", str(patch)], check=True)
    subprocess.run(["git", "-C", str(source_tree), "apply", str(patch)], check=True)
  if patch_changed:
    subprocess.run(["make", "-C", str(source_tree), "distclean",
                    f"CPU_TARGET={cpu}", f"OS_TARGET={target_os}", f"FPC={compiler}"], check=True,
                   env={key: value for key, value in os.environ.items()
                        if key not in ("MAKEFLAGS", "MFLAGS")})
  previous.write_bytes(patch.read_bytes())
  prefix = root / "install"
  command = ["make", "-j" + str(args.jobs), "-C", str(source / f"fpc-{VERSION}"),
    f"CPU_TARGET={cpu}", f"OS_TARGET={target_os}", f"FPC={compiler}",
    f"BINUTILSPREFIX={binutils_prefix}", f"INSTALL_PREFIX={prefix}"]
  options = []
  system = platform.system()
  machine = platform.machine().lower()
  if system == "Darwin":
    sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    options.append(f"-XR{sdk}")
    if args.host_linker:
      linker = args.host_linker.absolute()
      if not linker.is_file():
        parser.error(f"Host linker not found: {linker}")
      deployment = subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip()
      wrapper_dir = root / "host-binutils"
      wrapper_dir.mkdir(exist_ok=True)
      wrapper = wrapper_dir / "ld"
      template = Path(__file__).resolve().parents[1] / "cmake/macos_fpc_link.py.in"
      text = template.read_text().replace("@Python3_EXECUTABLE@", sys.executable)
      text = text.replace("@INNO_DARWIN_LINKER@", str(linker))
      text = text.replace("@CMAKE_OSX_DEPLOYMENT_TARGET@", deployment)
      wrapper.write_text(text)
      wrapper.chmod(0o755)
      options.append(f"-FD{wrapper_dir}")
  if system == "Linux":
    patch_linux_startup(source / f"fpc-{VERSION}", machine)
  if args.arch == "x86" and machine in ("arm64", "aarch64"):
    # The ARM64 bootstrap compiler has no native 80-bit Extended type.
    # FPC's software x87 support supplies it for the i386 code generator.
    options.extend(("-dFPC_SOFT_FPUX80", f"-Fu{source / f'fpc-{VERSION}' / 'rtl' / 'inc'}"))
  if options:
    command.append("OPT=" + " ".join(options))
  environment = {key: value for key, value in os.environ.items()
                 if key not in ("MAKEFLAGS", "MFLAGS")}
  for target in ("crossall", "crossinstall"):
    subprocess.run([*command, target], check=True, env=environment)
  cross = prefix / "lib" / "fpc" / VERSION / compiler_name
  if not cross.is_file():
    parser.error(f"Cross compiler was not installed: {cross}")
  print(f"Native Windows cross compiler: {cross}")


if __name__ == "__main__":
  main()
