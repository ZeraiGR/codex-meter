#!/usr/bin/env python3
"""Publish a tested bundle as a draft, then expose its signed feed atomically.

Run only from the release workflow after every required quality job succeeds.
SPARKLE_PRIVATE_KEY is read from the environment and passed over stdin, never argv.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
REPO="ZeraiGR/codex-meter"
NS="http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle",NS)

def version(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+",value):raise ValueError("Version must be x.y.z")
    return tuple(map(int,value.split(".")))

def validate_info(info,source):
    required=["CFBundleIdentifier","CFBundleVersion","CFBundleShortVersionString","SUFeedURL","SUPublicEDKey","LSMinimumSystemVersion"]
    for key in required:
        if info.get(key)!=source.get(key):raise ValueError(f"Bundle and source disagree: {key}")
    if info.get("CFBundleIdentifier")!="local.codex-meter.app" or info.get("CFBundleExecutable")!="codex-meter":raise ValueError("Unexpected application identity")
    version(info["CFBundleShortVersionString"])
    if not re.fullmatch(r"[1-9]\d*",info["CFBundleVersion"]):raise ValueError("Build must be a positive integer")
    if info["SUFeedURL"]!=f"https://github.com/{REPO}/releases/latest/download/appcast.xml":raise ValueError("Unexpected update origin")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):raise ValueError("Update authentication must be enabled")
    if info.get("SUSignedFeedFailureExpirationInterval")!=0:raise ValueError("Signed feed verification must not expire")
    if info.get("SUAutomaticallyUpdate"):raise ValueError("Unattended installation is not enabled for this release channel")

def appcast(info,url,size,signature,notes):
    if not url.startswith(f"https://github.com/{REPO}/releases/download/v{info['CFBundleShortVersionString']}/"):
        raise ValueError("Archive must have an immutable release URL")
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==",signature):raise ValueError("Invalid Ed25519 signature")
    if size<=0:raise ValueError("Empty update")
    rss=ET.Element("rss",version="2.0")
    channel=ET.SubElement(rss,"channel")
    ET.SubElement(channel,"title").text="Codex Meter updates"
    ET.SubElement(channel,"link").text=f"https://github.com/{REPO}"
    item=ET.SubElement(channel,"item")
    ET.SubElement(item,"title").text="Codex Meter "+info["CFBundleShortVersionString"]
    ET.SubElement(item,f"{{{NS}}}version").text=info["CFBundleVersion"]
    ET.SubElement(item,f"{{{NS}}}shortVersionString").text=info["CFBundleShortVersionString"]
    ET.SubElement(item,f"{{{NS}}}minimumSystemVersion").text=info["LSMinimumSystemVersion"]
    ET.SubElement(item,"description",{f"{{{NS}}}descriptionFormat":"plain-text"}).text=notes
    ET.SubElement(item,"enclosure",{"url":url,"length":str(size),"type":"application/octet-stream",f"{{{NS}}}edSignature":signature})
    return ET.tostring(rss,encoding="utf-8",xml_declaration=True)

def run(*args,**kwargs):return subprocess.run([str(a) for a in args],check=True,**kwargs)
def output(*args):return subprocess.check_output([str(a) for a in args],text=True).strip()

def main():
    app=ROOT/"dist/Codex Meter.app"
    info=plistlib.loads((app/"Contents/Info.plist").read_bytes())
    validate_info(info,plistlib.loads((ROOT/"Info.plist").read_bytes()))
    run("codesign","--verify","--deep","--strict",app)
    archs=set(output("lipo","-archs",app/"Contents/MacOS/codex-meter").split())
    if archs!={"arm64","x86_64"}:raise SystemExit("Only universal builds may be published")
    key=os.environ.get("SPARKLE_PRIVATE_KEY","")
    if not key:raise SystemExit("SPARKLE_PRIVATE_KEY secret is not configured")
    public=run("swift",ROOT/"scripts/public-key.swift",input=key,text=True,capture_output=True).stdout.strip()
    if public != info["SUPublicEDKey"]:raise SystemExit("Signing key does not match the application public key")
    commit=os.environ.get("GITHUB_SHA")
    if not commit or not re.fullmatch(r"[0-9a-f]{40}",commit):raise SystemExit("Release requires an exact CI commit")
    tag="v"+info["CFBundleShortVersionString"]
    if os.environ.get("GITHUB_REF_TYPE")=="tag" and os.environ.get("GITHUB_REF_NAME")!=tag:raise SystemExit("Tag and bundle version disagree")
    existing=[r for page in json.loads(output("gh","api",f"repos/{REPO}/releases","--paginate","--slurp")) for r in page]
    if any(r["tag_name"]==tag for r in existing):raise SystemExit("Release tag already exists; use a new version")
    stable=[r for r in existing if not r["draft"] and not r["prerelease"]]
    for release in stable:
        if version(release["tag_name"].removeprefix("v"))>=version(info["CFBundleShortVersionString"]):raise SystemExit("Release version must increase")
    if stable:
        previous=output("gh","release","download","--repo",REPO,"--pattern","appcast.xml","--output","-")
        old=ET.fromstring(previous).find(f".//{{{NS}}}version")
        if old is None or int(old.text)>=int(info["CFBundleVersion"]):raise SystemExit("Release build must increase")
    notes_file=ROOT/"releases"/(tag+".md")
    notes=notes_file.read_text()
    if len(notes.strip())<40:raise SystemExit("Meaningful release notes are required")
    sign=ROOT/".vendor/sparkle-tools/bin/sign_update"
    with tempfile.TemporaryDirectory(prefix="meter-release-") as tmp:
        folder=Path(tmp);archive=folder/f"Codex-Meter-{info['CFBundleShortVersionString']}-universal.zip"
        run("ditto","-c","-k","--keepParent",app,archive)
        signature=run(sign,"--ed-key-file","-","-p",archive,input=key,text=True,capture_output=True).stdout.strip()
        feed=folder/"appcast.xml"
        feed.write_bytes(appcast(info,f"https://github.com/{REPO}/releases/download/{tag}/{archive.name}",archive.stat().st_size,signature,notes))
        run(sign,"--ed-key-file","-",feed,input=key,text=True,capture_output=True)
        run(sign,"--ed-key-file","-","--verify",archive,signature,input=key,text=True,capture_output=True)
        run(sign,"--ed-key-file","-","--verify",feed,input=key,text=True,capture_output=True)
        checksum=folder/"SHA256SUMS"
        checksum.write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in [archive,feed]))
        manifest=folder/"release.json"
        manifest.write_text(json.dumps({"version":info["CFBundleShortVersionString"],"build":info["CFBundleVersion"],"commit":commit,"architectures":sorted(archs),"appleNotarized":False,"archiveSHA256":hashlib.sha256(archive.read_bytes()).hexdigest()},indent=2)+"\n")
        run("gh","release","create",tag,"--repo",REPO,"--target",commit,"--draft","--title","Codex Meter "+info["CFBundleShortVersionString"],"--notes-file",notes_file)
        run("gh","release","upload",tag,archive,feed,checksum,manifest,"--repo",REPO)
        # No client can see the new /latest feed until every asset has been uploaded.
        run("gh","release","edit",tag,"--repo",REPO,"--draft=false","--latest")
        print("Published",tag,"from",commit)

if __name__=="__main__":main()
