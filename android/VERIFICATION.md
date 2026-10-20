# Android test-build verification

The native Android source is independent of the Python runtime and has no runtime dependencies or requested Android permissions.

- Built with JDK 17, Android SDK platform 35 and official build-tools 35.0.0 (`aapt2`, `d8`, `zipalign`, `apksigner`).
- 16 standalone Java calculator/plan-preview assertions passed, including arithmetic precedence, decimal values, invalid inputs, division by zero, depth/length bounds and unsupported preview steps.
- Manifest/package inspected using `aapt2 dump badging`: `dev.personalagent`, version `0.1.0-test`, minimum API 26, target API 35.
- `apksigner verify --verbose` passed with APK Signature Scheme v2/v3. Development-only key is stored outside this repository; private signing material is not released.
- Python regression suite after adding Android: 102 unit tests and nine integration loopback tests passed. Existing Python source/runtime remains separate.

Runtime/emulator observations and artifact digest will be recorded in the Android GitHub prerelease notes. No physical phone has been tested. A successful compilation/signature is not a physical-device compatibility guarantee. This is a test APK, not a production/Play Store release; it has no model, online chat, voice, social integrations, external sender or autonomous device controls. Approving a local draft never sends it.

An Android 35 x86_64 emulator was attempted with software emulation because `/dev/kvm` is unavailable. It did not complete normal boot. Package installation failed inside the emulator's system service (`PackageManagerInternal` was null); the app did not launch and no usable screenshot was captured. Therefore emulator installation, launch and UI interactions are **not verified**. This result does not establish a device-specific app failure or success. The emulator was stopped; no screenshots are fabricated.
