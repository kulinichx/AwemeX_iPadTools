# AwemeX iPadCompat v0.3 probe — GitHub Actions overlay

This overlay adds a separate GitHub Actions build for the current v0.3 diagnostic compatibility layer. It intentionally does **not** modify the repository's existing AlphaPro source, Makefile, package metadata, or existing workflows.

## Why separate first

The final design is still one AwemeX package where `AwemeX.dylib` weak-loads `AwemeX_iPadCompat.dylib`. Do not make that production binary patch yet. The first device test must keep the compatibility dylib as a separate TrollFools injection so a failure can be removed without touching the original AwemeX 2.6.2 binary.

## What v0.3 probe contains

- iPad search entrance compatibility
- iPad sidebar compatibility
- targeted right-stack scaling bridge into AwemeX's own `awe_applySafeScaling`
- a diagnostic one-finger long-press trigger on `AWEPlayInteractionViewController` that sends `showDislikeOnVideo`

It contains no independent downloader, network stack, timers, reachability monitor, global `UIView` layout hook, or AlphaPro preference UI.

## GitHub Actions output

The workflow builds arm64 + arm64e and uploads:

- `AwemeX_iPadCompat.dylib`
- `AwemeX_iPadCompat.plist`
- `AwemeX-iPadCompat-v0.3-probe.deb`
- `BUILD-RECEIPT.txt`

The DEB is for TrollFools test import. It is not the final merged AwemeX package.

## Device test configuration

Use only:

- `AwemeX.dylib` — ON
- `AwemeX_iPadCompat.dylib` — ON
- `AwemeX_AlphaPro.dylib` — OFF

Do not patch `AwemeX.dylib` with the weak-load command yet.

Test search/sidebar/right-side scaling first. Then on one normal feed video, perform one normal one-finger long press and report exactly what UI appears. If there is a crash, stop and provide the new `.ips`.
