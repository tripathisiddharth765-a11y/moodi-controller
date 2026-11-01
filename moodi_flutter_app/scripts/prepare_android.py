#!/usr/bin/env python3
"""Add the Android BLE permissions required by MOODI to a Flutter scaffold."""

from pathlib import Path
import re
import sys

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    sys.exit("Android manifest not found. Run 'flutter create --platforms=android .' first.")

content = manifest.read_text(encoding="utf-8")
permissions = '''    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />

    <!-- Android 12+ BLE permissions. The app does not use BLE to determine location. -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

    <!-- Legacy Bluetooth permissions for Android 11 and below. -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />

'''

if "android.permission.BLUETOOTH_SCAN" not in content:
    content = re.sub(r"(<manifest\b[^>]*>\s*)", r"\1" + permissions, content, count=1)

# Keep the launcher name friendly and consistent on the phone.
content, label_count = re.subn(
    r'(<application\b[\s\S]*?android:label=")[^"]*(")',
    r'\1MOODI Controller\2',
    content,
    count=1,
)
if label_count == 0:
    sys.exit("Could not find android:label in the generated application manifest.")

manifest.write_text(content, encoding="utf-8")
print("Android BLE permissions and MOODI app label configured.")
