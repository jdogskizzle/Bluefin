#!/usr/bin/env python3
"""Bumps the build number, archives, uploads to App Store Connect, and clears the per-build
export-compliance gate — the exact manual sequence every TestFlight release of this app has
needed so far, now in one command. Run via `make testflight` (which handles the venv) rather
than directly.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT = REPO_ROOT / "Bluefin.xcodeproj"
SCHEME = "Bluefin"
INFO_PLIST = REPO_ROOT / "Bluefin" / "Info.plist"
EXPORT_OPTIONS_PLIST = Path(__file__).resolve().parent / "ExportOptions.plist"
ARCHIVE_PATH = REPO_ROOT / "build" / "Bluefin.xcarchive"
EXPORT_PATH = REPO_ROOT / "build" / "export"

KEY_ID = os.environ.get("ASC_KEY_ID", "6PMU983555")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "a358147c-094f-40a2-b81d-0728d2b2ae4f")
APP_ID = os.environ.get("ASC_APP_ID", "6808844655")
KEY_PATH = Path(os.environ.get(
    "ASC_KEY_PATH",
    str(Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"),
))

POLL_INTERVAL_SECONDS = 20
POLL_TIMEOUT_SECONDS = 20 * 60


def run(cmd: list[str]) -> None:
    print(f"$ {' '.join(cmd)}")
    subprocess.run(cmd, check=True, cwd=REPO_ROOT)


def bump_build_number() -> str:
    current = subprocess.check_output(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", str(INFO_PLIST)]
    ).decode().strip()
    new_version = str(int(current) + 1)
    subprocess.check_call(
        ["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleVersion {new_version}", str(INFO_PLIST)]
    )
    print(f"Bumped CFBundleVersion: {current} -> {new_version}")
    return new_version


def archive() -> None:
    if ARCHIVE_PATH.exists():
        subprocess.run(["rm", "-rf", str(ARCHIVE_PATH)], check=True)
    run([
        "xcodebuild", "archive",
        "-project", str(PROJECT),
        "-scheme", SCHEME,
        "-configuration", "Release",
        "-archivePath", str(ARCHIVE_PATH),
        "-destination", "generic/platform=iOS",
        "-allowProvisioningUpdates",
    ])


def export_and_upload() -> None:
    if EXPORT_PATH.exists():
        subprocess.run(["rm", "-rf", str(EXPORT_PATH)], check=True)
    run([
        "xcodebuild", "-exportArchive",
        "-archivePath", str(ARCHIVE_PATH),
        "-exportPath", str(EXPORT_PATH),
        "-exportOptionsPlist", str(EXPORT_OPTIONS_PLIST),
        "-authenticationKeyPath", str(KEY_PATH),
        "-authenticationKeyID", KEY_ID,
        "-authenticationKeyIssuerID", ISSUER_ID,
    ])


def make_token() -> str:
    # A fresh short-lived token per request rather than one reused across the whole poll loop —
    # polling can run for several minutes, longer than it's worth trusting a single token for.
    private_key = KEY_PATH.read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"},
    )


def asc_get(path: str, token: str) -> dict:
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com{path}",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def asc_patch(path: str, token: str, body: dict) -> int:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com{path}",
        data=data, method="PATCH",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        print(e.read().decode(), file=sys.stderr)
        return e.code


def find_build(version: str, token: str) -> dict | None:
    body = asc_get(
        f"/v1/builds?filter[app]={APP_ID}&filter[version]={version}"
        f"&sort=-uploadedDate&limit=5&include=buildBetaDetail",
        token,
    )
    included_by_id = {inc["id"]: inc for inc in body.get("included", [])}
    for b in body.get("data", []):
        attrs = b.get("attributes", {})
        if attrs.get("version") != version:
            continue
        # `relationships.buildBetaDetail.data` can be JSON `null` (not just absent) in the first
        # moments after upload, before the beta-detail record is linked — `or {}` covers that,
        # where a plain `.get(..., {})` wouldn't (the key is present, just null).
        rel = (b.get("relationships", {}).get("buildBetaDetail", {}).get("data") or {})
        detail = included_by_id.get(rel.get("id"), {}).get("attributes", {})
        return {
            "id": b["id"],
            "processingState": attrs.get("processingState"),
            "internalBuildState": detail.get("internalBuildState"),
        }
    return None


def wait_for_processing(version: str) -> dict:
    print(f"Waiting for App Store Connect to finish processing build {version}...")
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        try:
            build = find_build(version, make_token())
        except urllib.error.URLError as e:
            print(f"  (transient error polling: {e}, retrying)")
            build = None
        if build and build["processingState"] == "VALID":
            print(f"  build {build['id']} is VALID (internal state: {build['internalBuildState']})")
            return build
        if build and build["processingState"] == "INVALID":
            raise RuntimeError(f"Build {version} was rejected by App Store Connect (INVALID).")
        print(f"  still processing ({build['processingState'] if build else 'not visible yet'})...")
        time.sleep(POLL_INTERVAL_SECONDS)
    raise TimeoutError(f"Build {version} did not finish processing within {POLL_TIMEOUT_SECONDS}s.")


def clear_export_compliance(build_id: str) -> None:
    status = asc_patch(
        f"/v1/builds/{build_id}", make_token(),
        {"data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}},
    )
    if status != 200:
        raise RuntimeError(f"Failed to clear export compliance for build {build_id} (status {status}).")
    print(f"Cleared export compliance for build {build_id}.")


def main() -> None:
    if not KEY_PATH.exists():
        sys.exit(f"App Store Connect API key not found at {KEY_PATH}. Set ASC_KEY_PATH / ASC_KEY_ID.")

    version = bump_build_number()
    archive()
    export_and_upload()
    build = wait_for_processing(version)
    if build["internalBuildState"] == "MISSING_EXPORT_COMPLIANCE":
        clear_export_compliance(build["id"])
    else:
        print(f"Build {version} internal state is already {build['internalBuildState']}; nothing to clear.")
    print(f"\nDone - build {version} is ready on TestFlight.")


if __name__ == "__main__":
    main()
