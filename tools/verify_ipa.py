#!/usr/bin/env python3
"""Verify unsigned device IPA produced by cloud Xcode without external dependencies.

This is a packaging smoke test, not a substitute for iOS runtime testing.
"""
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def verify(path: Path) -> None:
    if not path.is_file():
        raise ValueError(f"IPA not found: {path}")
    with zipfile.ZipFile(path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise ValueError(f"Damaged IPA member: {bad_member}")
        members = set(archive.namelist())
        info_name = "Payload/ReFindOne.app/Info.plist"
        if info_name not in members:
            raise ValueError("Missing Payload/ReFindOne.app/Info.plist")
        info = plistlib.loads(archive.read(info_name))
        executable_name = info.get("CFBundleExecutable")
        bundle_id = info.get("CFBundleIdentifier")
        if not isinstance(executable_name, str) or not executable_name:
            raise ValueError("Missing CFBundleExecutable")
        if not isinstance(bundle_id, str) or not bundle_id:
            raise ValueError("Missing CFBundleIdentifier")
        executable_path = f"Payload/ReFindOne.app/{executable_name}"
        if executable_path not in members:
            raise ValueError(f"Missing executable: {executable_path}")
        binary = archive.read(executable_path)
        # Thin little-endian Mach-O 64-bit with ARM64 CPU type (0x0100000C).
        # This catches accidental simulator/x86 or source-only ZIPs.
        if len(binary) < 32 or binary[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("Executable is not a thin 64-bit Mach-O binary")
        cpu_type = struct.unpack_from("<I", binary, 4)[0]
        if cpu_type != 0x0100000C:
            raise ValueError(f"Not an ARM64 iPhoneOS binary (CPU=0x{cpu_type:08X})")
        print(f"PASS: {path.name} ({path.stat().st_size:,} bytes)")
        print(f"Bundle: {bundle_id} | Version: {info.get('CFBundleShortVersionString')}")
        print("Executable: ARM64 iOS Mach-O | Payload layout: OK")
        print("NOTE: Device and LiveContainer launch are not validated by this test.")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: python3 tools/verify_ipa.py <path-to-ipa>")
        verify(Path(sys.argv[1]))
    except (OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as err:
        sys.exit(f"FAIL: {err}")
