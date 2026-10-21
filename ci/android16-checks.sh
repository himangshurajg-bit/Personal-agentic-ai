#!/usr/bin/env bash
set -euo pipefail
mkdir -p evidence
adb shell getprop > evidence/device-properties.txt
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
