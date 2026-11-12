"""Exercise the native compiler and source-built installers in CI."""

import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile


PAYLOAD = b"source-built installer payload\n" * 128
PACKAGES = [f"{style}-{codec}" for style in ("light", "dark", "dynamic")
            for codec in ("lzma2", "zip", "bzip")]


def run(command, expected=0, input=None):
  result = subprocess.run([str(value) for value in command], input=input,
                          capture_output=True, timeout=120)
  if result.returncode != expected:
    raise RuntimeError(f"{command[0]} exited with {result.returncode}, expected {expected}\n"
                       f"{result.stdout.decode('utf-8', errors='replace')}\n"
                       f"{result.stderr.decode('utf-8', errors='replace')}")
  return result


def check_compiler(iscc, root):
  version = run([iscc, "--version"]).stdout.decode("utf-8").strip()
  if not version.startswith("7."):
    raise RuntimeError(f"Unexpected compiler version: {version}")
  script = root / "diagnostic-测.iss"
  message = '诊 "quoted" \\ path'
  script.write_text('#pragma warning "warning-probe"\n#error ' + message,
                    encoding="utf-8-sig")
  # Capture bytes directly. PowerShell Start-Process can decode redirected UTF-8
  # using the Windows console code page before writing its output files.
  result = run([iscc, "--messages-jsonl", "--quiet-progress", script], expected=2)
  messages = [json.loads(line) for line in result.stderr.decode("utf-8").splitlines()]
  if (result.stdout or len(messages) != 2 or
      messages[0].get("severity") != "warning" or
      "warning-probe" not in messages[0].get("message", "") or
      messages[1] != {"severity": "error", "line": 2,
                      "filename": str(script), "message": message + "."}):
    raise RuntimeError(f"Incorrect JSONL diagnostics: {result.stdout!r}, {messages!r}")
  result = run([iscc, "--quiet", "--preprocess", "--inline-start=<<",
                "--inline-end=>>", "-"], input=b'<<"stdin-probe">>\n')
  if result.stdout.strip() != b"stdin-probe":
    raise RuntimeError(f"Incorrect stdin preprocessing: {result.stdout!r}")
  print(f"ISCC {version}: Unicode JSONL diagnostics and stdin preprocessing passed")


def check_machine(path, arch):
  image = path.read_bytes()
  offset = struct.unpack_from("<I", image, 60)[0]
  expected = {"x86": 0x014c, "x64": 0x8664}[arch]
  if (image[:2] != b"MZ" or image[offset:offset + 4] != b"PE\0\0" or
      struct.unpack_from("<H", image, offset + 4)[0] != expected):
    raise RuntimeError(f"Incorrect Windows {arch} image: {path}")


def package(compiler, assets, arch, output, root):
  suffix = ".exe" if os.name == "nt" else ""
  iscc = compiler / "iscc" / ("iscc" + suffix)
  tool = compiler / "issigtool" / ("issigtool" + suffix)
  extension = {"x86": "e32", "x64": "e64"}[arch]
  for name in ("Setup", "SetupLdr", "SetupCustomStyle"):
    check_machine(assets / f"{name}.{extension}", arch)
  private_key = root / "build.isprivatekey"
  public_key = root / "build.ispublickey"
  try:
    run([tool, f"--key-file={private_key}", "generate-private-key"])
    run([tool, f"--key-file={private_key}", "export-public-key", public_key])
    inputs = sorted(path for path in assets.iterdir()
                    if path.suffix.lower() in (".e32", ".e64", ".dll"))
    run([tool, f"--key-file={private_key}", "sign", *inputs])
    run([tool, f"--key-file={public_key}", "verify", *inputs])
  finally:
    private_key.unlink(missing_ok=True)
  output.mkdir(parents=True, exist_ok=True)
  (output / "license.txt").write_bytes(
    (Path(__file__).resolve().parents[1] / "license.txt").read_bytes())
  (root / "payload.txt").write_bytes(PAYLOAD)
  script = root / "package-测.iss"
  for name in PACKAGES:
    style, codec = name.split("-")
    script.write_text(fr"""[Setup]
AppName=CI Native Compiler Probe
AppVersion=1.0
DefaultDirName={{autopf}}\CI Native Compiler Probe
SetupArchitecture={arch}
WizardStyle=modern {style}
Compression={codec}
PrivilegesRequired=lowest
[Files]
Source: "payload.txt"; DestDir: "{{app}}"
[Code]
function InitializeSetup: Boolean;
begin
  Log('CI InitializeSetup');
  Result := True;
end;
function InitializeUninstall: Boolean;
begin
  Log('CI InitializeUninstall');
  Result := True;
end;
""", encoding="utf-8-sig")
    run([iscc, f"--compiler-path={assets}", f"--build-public-key={public_key}",
         f"--output-dir={output}", f"--output-filename={name}", script])
    check_machine(output / f"{name}.exe", arch)
    print(f"Packaged Windows {arch}: {name}")


def install(directory, arch, root):
  if os.name != "nt":
    raise RuntimeError("Installation checks require Windows")
  for name in PACKAGES:
    installer = directory / f"{name}.exe"
    check_machine(installer, arch)
    destination = root / name
    install_log = root / f"{name}-install.log"
    uninstall_log = root / f"{name}-uninstall.log"
    flags = ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"]
    try:
      run([installer, *flags, f"/DIR={destination}", f"/LOG={install_log}"])
      payload = destination / "payload.txt"
      if payload.read_bytes() != PAYLOAD:
        raise RuntimeError(f"Incorrect installed payload: {name}")
      run([destination / "unins000.exe", *flags, f"/LOG={uninstall_log}"])
      if payload.exists():
        raise RuntimeError(f"Uninstall left the payload: {name}")
      for log, marker in ((install_log, b"CI InitializeSetup"),
                          (uninstall_log, b"CI InitializeUninstall")):
        if marker not in log.read_bytes():
          raise RuntimeError(f"Pascal Script callback missing from {log}")
    except Exception:
      for log in (install_log, uninstall_log):
        if log.exists():
          print(log.read_text(encoding="utf-8-sig", errors="replace"))
      raise
    print(f"Installed and uninstalled Windows {arch}: {name}")


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--compiler", type=Path)
  parser.add_argument("--assets", type=Path)
  parser.add_argument("--arch", choices=("x64", "x86"))
  parser.add_argument("--output", type=Path)
  parser.add_argument("--install", type=Path)
  args = parser.parse_args()
  if not args.compiler and not args.install:
    parser.error("Specify --compiler or --install")
  if args.assets and not (args.compiler and args.arch and args.output):
    parser.error("Packaging requires --compiler, --assets, --arch and --output")
  if args.install and not args.arch:
    parser.error("Installation requires --arch")
  with tempfile.TemporaryDirectory(prefix="inno-ci-") as temporary:
    root = Path(temporary).resolve()
    if args.compiler:
      compiler = args.compiler.resolve()
      suffix = ".exe" if os.name == "nt" else ""
      check_compiler(compiler / "iscc" / ("iscc" + suffix), root)
      if args.assets:
        package(compiler, args.assets.resolve(), args.arch, args.output.resolve(), root)
    if args.install:
      install(args.install.resolve(), args.arch, root)


if __name__ == "__main__":
  main()
