
from pathlib import Path
import re
import sys

manifest = Path("android/app/src/main/AndroidManifest.xml")

if not manifest.exists():
    sys.exit("Android manifest not found!")

content = manifest.read_text(encoding="utf-8")

permissions = """
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />

    <uses-permission
        android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />

    <uses-permission
        android:name="android.permission.BLUETOOTH_CONNECT" />

    <uses-permission
        android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" />

    <uses-permission
        android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" />

    <uses-permission
        android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30" />

    <uses-permission
        android:name="android.permission.ACCESS_COARSE_LOCATION"
        android:maxSdkVersion="28" />
"""

if "android.permission.BLUETOOTH_SCAN" not in content:
    content = re.sub(
        r"(<manifest\b[^>]*>\s*)",
        lambda match: match.group(1) + permissions,
        content,
        count=1
    )

content, count = re.subn(
    r'(<application\b[\s\S]*?android:label=")[^"]*(")',
    r'\1MOODI Controller\2',
    content,
    count=1
)

if count == 0:
    sys.exit("Could not update application name.")

manifest.write_text(content, encoding="utf-8")

print("MOODI Android permissions configured successfully!")
