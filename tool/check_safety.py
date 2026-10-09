"""Regression guard for source capabilities; not a substitute for native review."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import plistlib

root=Path(__file__).resolve().parents[1]
manifest=ET.parse(root/'android/app/src/main/AndroidManifest.xml')
permissions={e.attrib['{http://schemas.android.com/apk/res/android}name']
             for e in manifest.findall('uses-permission') if e.attrib.get('{http://schemas.android.com/tools}node') != 'remove'}
expected={'android.permission.READ_EXTERNAL_STORAGE','android.permission.READ_MEDIA_IMAGES',
          'android.permission.READ_MEDIA_VIDEO','android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
          'android.permission.READ_CONTACTS','android.permission.ACCESS_NETWORK_STATE'}
assert permissions==expected, f'Unexpected Android permission: {permissions ^ expected}'
kt=(root/'android/app/src/main/kotlin/app/clearsafe/clearsafe/MainActivity.kt').read_text(encoding='utf-8')
swift=(root/'ios/Runner/AppDelegate.swift').read_text(encoding='utf-8')
native=list((root/'android/app/src/main/kotlin').rglob('*.kt'))
for p in native:
    for pattern in [r'contentResolver\.(delete|update|insert|applyBatch)',r'openOutputStream',r'FileOutputStream',r'createDeleteRequest']:
        assert not re.search(pattern,p.read_text(encoding='utf-8')),f'{p}: {pattern}'
actions=(root/'android/app/src/main/kotlin/app/clearsafe/clearsafe/MediaActions.kt').read_text(encoding='utf-8')
assert 'createTrashRequest' in actions and '.commit()' in actions and 'MessageDigest' in actions
assert 'IS_TRASHED' in actions and 'DATE_EXPIRES' in actions
assert 'recoverable_actions' not in kt.split('clearsafe/read_only')[1]
for p in (root/'packages/safe_scanner/lib').rglob('*.dart'):
    assert 'MethodChannel' not in p.read_text() and 'TrashService' not in p.read_text()
for pattern in [r'performChanges',r'PHAssetChangeRequest',r'CNMutableContact',r'CNSaveRequest',r'store\.execute']:
    assert not re.search(pattern,swift),pattern
assert 'isNetworkAccessAllowed=false' in swift
with (root/'ios/Runner/Info.plist').open('rb') as f: plist=plistlib.load(f)
assert 'NSPhotoLibraryUsageDescription' in plist and 'NSContactsUsageDescription' in plist
assert 'NSPhotoLibraryAddUsageDescription' not in plist
with (root/'ios/Runner/PrivacyInfo.xcprivacy').open('rb') as f: privacy=plistlib.load(f)
reasons={e['NSPrivacyAccessedAPIType']:e['NSPrivacyAccessedAPITypeReasons'] for e in privacy['NSPrivacyAccessedAPITypes']}
assert reasons['NSPrivacyAccessedAPICategoryDiskSpace']==['E174.1']
assert '3B52.1' in reasons['NSPrivacyAccessedAPICategoryFileTimestamp']
assert privacy['NSPrivacyTracking'] is False
assert 'PrivacyInfo.xcprivacy in Resources' in (root/'ios/Runner.xcodeproj/project.pbxproj').read_text()
for p in (root/'lib').rglob('*.dart'):
    assert 'future_actions' not in p.read_text(encoding='utf-8'),str(p)
print('Safety guards passed: offline manifest, system-only trash, durable journal, isolated scanner, iOS read-only.')
