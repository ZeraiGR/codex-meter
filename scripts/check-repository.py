#!/usr/bin/env python3
"""Reject accidental private artifacts before publishing source."""
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
files=subprocess.check_output(["git","ls-files","-z"],cwd=ROOT).decode().split("\0")
bad=[]
for name in filter(None,files):
    p=ROOT/name
    if p.suffix in [".sqlite",".db",".key",".p12",".pem"] or name.startswith((".vendor/",".build/","dist/")):
        bad.append(name);continue
    if p.suffix.lower() in [".png",".jpg",".icns"]:continue
    text=p.read_text(errors="replace")
    patterns=[r"/"+r"Users/[^/\s]+/",r"https?://[^\s/]*\.ts\.net",r"-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----",r"gh[pousr]_[A-Za-z0-9]{30,}"]
    if any(re.search(pattern,text) for pattern in patterns):bad.append(name)
if bad:raise SystemExit("Private/generated material in repository: "+", ".join(bad))
print("PASS source privacy and artifact boundaries")
