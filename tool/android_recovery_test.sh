#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../android"
recovery_result=0
./gradlew :app:connectedDebugAndroidTest || recovery_result=$?
adb logcat -d > ../build/recovery-logcat.txt
exit "$recovery_result"
