#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK}"
BT="$SDK/build-tools/35.0.0"
BUILD=build
mkdir -p "$BUILD/classes" "$BUILD/dex"
javac -d "$BUILD/classes" app/src/main/java/dev/personalagent/LocalLogic.java tests/LocalLogicTest.java
java -cp "$BUILD/classes" LocalLogicTest
javac -source 8 -target 8 -classpath "$SDK/platforms/android-35/android.jar" -d "$BUILD/classes" app/src/main/java/dev/personalagent/*.java
"$BT/aapt2" compile --dir app/src/main/res -o "$BUILD/resources.zip"
"$BT/aapt2" link -o "$BUILD/unsigned.apk" --manifest app/src/main/AndroidManifest.xml -I "$SDK/platforms/android-35/android.jar" --version-code 1 --version-name 0.1.0-test "$BUILD/resources.zip"
jar cf "$BUILD/classes.jar" -C "$BUILD/classes" dev
"$BT/d8" --lib "$SDK/platforms/android-35/android.jar" --min-api 26 --output "$BUILD/dex" "$BUILD/classes.jar"
cp "$BUILD/unsigned.apk" "$BUILD/unaligned.apk"
(cd "$BUILD/dex" && zip -q -u ../unaligned.apk classes.dex)
"$BT/zipalign" -f 4 "$BUILD/unaligned.apk" "$BUILD/aligned.apk"
KEY="${AGENT_TEST_KEYSTORE:-$HOME/.android/personal-agent-test.keystore}"
mkdir -p "$(dirname "$KEY")"
if [[ ! -f "$KEY" ]]; then keytool -genkeypair -keystore "$KEY" -storepass android -keypass android -alias test -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=Personal Agent Local Test, O=Development, C=US'; chmod 600 "$KEY"; fi
"$BT/apksigner" sign --ks "$KEY" --ks-key-alias test --ks-pass pass:android --key-pass pass:android --out "$BUILD/personal-agentic-ai-0.1.0-android-test.apk" "$BUILD/aligned.apk"
"$BT/apksigner" verify --verbose "$BUILD/personal-agentic-ai-0.1.0-android-test.apk"
"$BT/aapt2" dump badging "$BUILD/personal-agentic-ai-0.1.0-android-test.apk"
