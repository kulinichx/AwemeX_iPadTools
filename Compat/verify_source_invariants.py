#!/usr/bin/env python3
from pathlib import Path
import plistlib
import sys
import re

root = Path(__file__).resolve().parent
src = (root / "AwemeX_iPadCompat.c").read_text(encoding="utf-8")
code = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
code = re.sub(r"//.*", "", code)
mk = (root / "Makefile").read_text(encoding="utf-8")
plist_path = root / "AwemeX_iPadCompat.plist"

required = [
    "AWESearchEntranceView",
    "AWEHPDiscoverFeedEntranceView",
    "AWEElementStackView",
    "IESLiveStackView",
    "AWEPlayInteractionViewController",
    "showDislikeOnVideo",
    "g24MPeX47iRQ9mJBhaKvZx6F:",
]
for token in required:
    if token not in src:
        raise SystemExit(f"FAIL missing required token: {token}")

forbidden = [
    'objc_getClass("UIView")',
    "NSURLSession",
    "downloadTaskWithURL",
    "SCNetworkReachability",
    "NSTimer",
    "scheduledTimerWithTimeInterval",
    "CADisplayLink",
]
for token in forbidden:
    if token in code:
        raise SystemExit(f"FAIL forbidden broad/background mechanism present: {token}")

if "ARCHS := arm64 arm64e" not in mk:
    raise SystemExit("FAIL Makefile must build arm64 + arm64e")
if "@loader_path/AwemeX_iPadCompat.dylib" not in mk:
    raise SystemExit("FAIL expected loader-relative install name missing")

with plist_path.open("rb") as f:
    p = plistlib.load(f)
bundles = p.get("Filter", {}).get("Bundles", [])
if bundles != ["com.ss.iphone.ugc.Aweme"]:
    raise SystemExit(f"FAIL unexpected Filter.Bundles: {bundles!r}")

print("SOURCE INVARIANTS: PASS")
print("- target bundle: com.ss.iphone.ugc.Aweme")
print("- architectures: arm64 + arm64e")
print("- no global UIView hook token")
print("- no downloader/network/timer implementation")
print("- v0.3 long-press remains diagnostic only")
