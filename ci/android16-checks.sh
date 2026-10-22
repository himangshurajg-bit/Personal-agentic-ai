#!/usr/bin/env bash
set -euo pipefail
repo_root="$PWD"
evidence_dir="$repo_root/evidence"
mkdir -p "$evidence_dir"
# Preserve device diagnostics before the emulator runner tears down a failed test.
logcat_pid=''
trap 'status=$?; trap - EXIT; if [[ -n "$logcat_pid" ]]; then kill "$logcat_pid" 2>/dev/null || true; wait "$logcat_pid" 2>/dev/null || true; fi; if ((status != 0)); then timeout 10s adb devices -l > "$evidence_dir/adb-state-on-failure.txt" 2>&1 || true; timeout 10s adb logcat -d -t 4000 > "$evidence_dir/logcat-on-failure.txt" 2>&1 || true; fi; exit "$status"' EXIT
adb shell getprop > evidence/device-properties.txt
adb logcat -c
adb logcat -v threadtime > evidence/logcat-live.txt 2>&1 &
logcat_pid=$!
adb shell getprop ro.build.version.sdk | grep '^36'
cd mobile
flutter build apk --debug --target-platform android-x64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant dev.personalagent.personal_assistant android.permission.POST_NOTIFICATIONS
set -o pipefail
flutter test --no-uninstall integration_test/android16_test.dart -d emulator-5554 --reporter expanded 2>&1 | tee ../evidence/android16-test.log
# flutter test otherwise uninstalls at teardown and erases the restart fixture.
adb shell pm path dev.personalagent.personal_assistant | tee ../evidence/installed-before-restart.txt | grep '^package:'
adb shell am force-stop dev.personalagent.personal_assistant
flutter test --no-uninstall integration_test/rehydrate_test.dart -d emulator-5554 --reporter expanded 2>&1 | tee ../evidence/android16-restart.log
adb shell am force-stop dev.personalagent.personal_assistant
adb shell am start -n dev.personalagent.personal_assistant/.MainActivity
sleep 3
adb exec-out screencap -p > ../evidence/android16-home.png
adb shell dumpsys package dev.personalagent.personal_assistant > ../evidence/package.txt
adb logcat -d > ../evidence/logcat.txt
