import importlib.util
from pathlib import Path
import plistlib
import unittest
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("release",ROOT/"scripts/release.py")
release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)

class ReleaseTests(unittest.TestCase):
    def setUp(self):self.info=plistlib.loads((ROOT/"Info.plist").read_bytes())
    def test_bundle_must_match_checked_source(self):
        changed=dict(self.info,CFBundleVersion="99999")
        with self.assertRaises(ValueError):release.validate_info(changed,self.info)
    def test_application_identity_is_fixed(self):
        for key in ["CFBundleIdentifier","CFBundleExecutable"]:
            changed=dict(self.info,**{key:"wrong-app"})
            with self.assertRaises(ValueError):release.validate_info(changed,changed)
    def test_authentication_cannot_be_disabled(self):
        for flag in ["SURequireSignedFeed","SUVerifyUpdateBeforeExtraction"]:
            changed=dict(self.info,**{flag:False})
            with self.assertRaises(ValueError):release.validate_info(changed,changed)
    def test_feed_verification_cannot_expire(self):
        changed=dict(self.info,SUSignedFeedFailureExpirationInterval=1)
        with self.assertRaises(ValueError):release.validate_info(changed,changed)
    def test_unattended_installation_not_enabled(self):
        changed=dict(self.info,SUAutomaticallyUpdate=True)
        with self.assertRaises(ValueError):release.validate_info(changed,changed)
    def test_release_origin_is_fixed(self):
        changed=dict(self.info,SUFeedURL="https://example.com/appcast.xml")
        with self.assertRaises(ValueError):release.validate_info(changed,changed)
    def test_version_is_numeric_not_lexical(self):
        self.assertGreater(release.version("1.10.0"),release.version("1.9.9"))
        for v in ["v1.0.0","1.0.0-beta","../1.0.0","1.0"]:
            with self.assertRaises(ValueError):release.version(v)
    def test_build_must_be_monotonic_integer(self):
        for build in ["0","-1","1.0","x"]:
            changed=dict(self.info,CFBundleVersion=build)
            with self.assertRaises(ValueError):release.validate_info(changed,changed)
    def test_feed_encodes_release_notes_as_text(self):
        url=f"https://github.com/{release.REPO}/releases/download/v{self.info['CFBundleShortVersionString']}/app.zip"
        feed=ET.fromstring(release.appcast(self.info,url,1024,"A"*86+"==","<script>alert('x')</script> & notes"))
        self.assertIsNone(feed.find(".//script"))
        self.assertEqual(feed.find(".//description").text,"<script>alert('x')</script> & notes")
        self.assertEqual(feed.find(".//enclosure").get("length"),"1024")
        self.assertEqual(feed.find(f".//{{{release.NS}}}version").text,self.info["CFBundleVersion"])
    def test_mutable_or_insecure_download_is_rejected(self):
        for url in ["http://example.com/app.zip",f"https://github.com/{release.REPO}/releases/latest/download/app.zip"]:
            with self.assertRaises(ValueError):release.appcast(self.info,url,100,"A"*86+"==","")
    def test_missing_signature_or_empty_file_is_rejected(self):
        url=f"https://github.com/{release.REPO}/releases/download/v{self.info['CFBundleShortVersionString']}/app.zip"
        for size,signature in [(0,"A"*86+"=="),(20,""),(20,"bad")]:
            with self.assertRaises(ValueError):release.appcast(self.info,url,size,signature,"")

if __name__=="__main__":unittest.main()
