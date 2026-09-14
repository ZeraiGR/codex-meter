#!/usr/bin/env python3
"""Exercise Sparkle's real download, signature verification, installer and relaunch.

Only temporary apps, temporary keys and synthetic SQLite records are used.
The production application, login keychain and user database are never opened.
"""
import functools
import http.server
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
NS="http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle",NS)

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        if self.path.endswith("/interrupted-download/update.zip"):
            self.send_response(200);self.send_header("Content-Length","1000000");self.end_headers()
            self.wfile.write(b"truncated");self.wfile.flush();self.close_connection=True
        else:super().do_GET()

def run(*args,**kw):
    return subprocess.run([str(a) for a in args],check=True,**kw)

def main():
    tools=ROOT/".vendor/sparkle-tools/bin"
    native="arm64" if os.uname().machine=="arm64" else "x86_64"
    probe=ROOT/".build"/native/(native+"-apple-macosx")/"release/update-probe"
    framework=ROOT/"dist/Codex Meter.app/Contents/Frameworks/Sparkle.framework"
    with tempfile.TemporaryDirectory(prefix="meter-update-e2e-") as temporary:
        root=Path(temporary)
        key=root/"signing.key"
        swift=["swift"]
        sdk=Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
        if sdk.exists():swift += ["-sdk",str(sdk)]
        run(*swift,ROOT/"scripts/test-key.swift",key)
        public=key.with_suffix(".key.pub").read_text()
        server=http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(QuietHandler,directory=str(root)))
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        base=f"http://127.0.0.1:{server.server_port}"
        try:
            for case in ["install","tampered-archive","tampered-feed","offline","same-version","downgrade","unsupported-os","wrong-key","interrupted-download"]:
                folder=root/case;folder.mkdir()
                signing_key=key
                if case=="wrong-key":
                    signing_key=folder/"wrong.key"
                    run(*swift,ROOT/"scripts/test-key.swift",signing_key)
                app=folder/"Update Probe.app"
                bundle_id="local.codex-meter.probe."+uuid.uuid4().hex
                def make_app(destination,version):
                    macos=destination/"Contents/MacOS";macos.mkdir(parents=True)
                    shutil.copy2(probe,macos/"update-probe")
                    run("ditto",framework,destination/"Contents/Frameworks/Sparkle.framework")
                    config=dict(CFBundleIdentifier=bundle_id,CFBundleName="Update Probe",CFBundleExecutable="update-probe",CFBundlePackageType="APPL",CFBundleVersion=version,CFBundleShortVersionString=version,LSMinimumSystemVersion="14.0",LSUIElement=True,SUFeedURL=f"{base}/{case}/appcast.xml",SUPublicEDKey=public,SUEnableAutomaticChecks=False,SUAllowsAutomaticUpdates=False,SUVerifyUpdateBeforeExtraction=True,SURequireSignedFeed=True,SUSignedFeedFailureExpirationInterval=0,NSAppTransportSecurity={"NSAllowsLocalNetworking":True,"NSAllowsArbitraryLoads":True})
                    (destination/"Contents/Info.plist").write_bytes(plistlib.dumps(config))
                    run("codesign","--force","--sign","-",destination,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                make_app(app,"101")
                payload=folder/"payload";payload.mkdir()
                target_version="101" if case=="same-version" else "100" if case=="downgrade" else "102"
                make_app(payload/app.name,target_version)
                archive=folder/"update.zip"
                run("ditto","-c","-k","--keepParent",payload/app.name,archive)
                signature=subprocess.check_output([str(tools/"sign_update"),"--ed-key-file",str(signing_key),"-p",str(archive)],text=True).strip()
                rss=ET.Element("rss",version="2.0");channel=ET.SubElement(rss,"channel");ET.SubElement(channel,"title").text="Test updates"
                item=ET.SubElement(channel,"item");ET.SubElement(item,"title").text="Test release"
                ET.SubElement(item,f"{{{NS}}}version").text=target_version
                ET.SubElement(item,f"{{{NS}}}shortVersionString").text=target_version
                ET.SubElement(item,f"{{{NS}}}minimumSystemVersion").text="99.0" if case=="unsupported-os" else "14.0"
                ET.SubElement(item,"enclosure",{"url":f"{base}/{case}/update.zip","length":str(archive.stat().st_size),"type":"application/octet-stream",f"{{{NS}}}edSignature":signature})
                feed=folder/"appcast.xml";ET.ElementTree(rss).write(feed,encoding="utf-8",xml_declaration=True)
                run(tools/"sign_update","--ed-key-file",signing_key,feed,stdout=subprocess.DEVNULL)
                if case=="tampered-archive":
                    with archive.open("ab") as out:out.write(b"corrupt")
                elif case=="tampered-feed":feed.write_text(feed.read_text().replace("Test release","Forged release"))
                elif case=="offline":feed.unlink()
                with (folder/"probe.log").open("w") as log:
                    process=subprocess.Popen([str(app/"Contents/MacOS/update-probe")],stdout=log,stderr=subprocess.STDOUT)
                    deadline=time.monotonic()+120
                    result=""
                    while time.monotonic()<deadline:
                        receipt=folder/"result.txt"
                        if receipt.exists():result=receipt.read_text()
                        if result.startswith(("installed-","rejected:","no-update","error:")):break
                        time.sleep(.2)
                    if process.poll() is None:
                        try:process.wait(timeout=5)
                        except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)
                version=plistlib.loads((app/"Contents/Info.plist").read_bytes())["CFBundleVersion"]
                expected="installed-and-relaunched-data-preserved" if case=="install" else "no-update" if case in ["same-version","downgrade","unsupported-os"] else "rejected:"
                if not result.startswith(expected) or version != ("102" if case=="install" else "101"):
                    print((folder/"probe.log").read_text()[-6000:])
                    raise AssertionError(f"{case}: result={result!r}, installed={version}")
                print("PASS UPDATE",case,flush=True)
        finally:server.shutdown();server.server_close()

if __name__=="__main__":main()
