#!/usr/bin/env python3
"""Fetch pinned upstream artifacts; never trust an unverified download/cache."""
import hashlib
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = "2.10.0"
ARTIFACTS = {
    "Sparkle-for-Swift-Package-Manager.zip": "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959",
    "Sparkle-2.10.0.tar.xz": "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c",
}

def main():
    vendor = ROOT / ".vendor"
    vendor.mkdir(exist_ok=True)
    for name, checksum in ARTIFACTS.items():
        archive = vendor / name
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
            with tempfile.TemporaryDirectory(dir=vendor) as temporary:
                downloaded = pathlib.Path(temporary) / name
                subprocess.run(["curl", "-fLsS", "--retry", "3", "--connect-timeout", "20", "--max-time", "300", f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/{name}", "-o", str(downloaded)], check=True)
                if hashlib.sha256(downloaded.read_bytes()).hexdigest() != checksum:
                    raise SystemExit("Sparkle artifact checksum mismatch")
                downloaded.replace(archive)
        # Re-extract from verified archives, rather than trusting a stale framework.
        if name.endswith(".zip"):
            subprocess.run(["ditto", "-xk", str(archive), str(vendor)], check=True)
        else:
            tools = vendor / "sparkle-tools"
            tools.mkdir(exist_ok=True)
            subprocess.run(["tar", "-xf", str(archive), "-C", str(tools)], check=True)

if __name__ == "__main__":
    main()
