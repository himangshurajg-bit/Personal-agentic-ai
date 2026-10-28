# MYRA-derived haptic feedback

The available MYRA Android feature matrix describes a `vibrate_phone` action that is limited to an explicit, latest-turn vibration request and previews one fixed 80 ms pulse for approval. Its model routing, Android dialog and physical vibration remain device-untested in that source.

Personal AI adds a small manual counterpart in Skills & actions: the owner taps “Test haptic feedback” to request one short Android haptic pulse. It does not run from chat or the model, does not monitor device state, and does not claim a physical vibration occurred. The Android/Flutter platform may ignore haptics when unsupported or disabled. This is a deliberate user-started app feedback action, not a port of MYRA's model-call routing or its 80 ms vibration API. No new device permission or persistent setting is introduced.

The Flutter widget test verifies that the haptic request is made only after the explicit tap. Device-specific strength and vibration availability, including Redmi behavior, remain unverified.
