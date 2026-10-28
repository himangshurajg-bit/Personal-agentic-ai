# MYRA local audio preview adaptation

MYRA's Android Files row in `myra-ultra/FEATURE_MATRIX.md` records a user-selected SAF audio URI with local Play/Pause/Stop, position, duration and seeking; playback is foreground-only, stops when the user leaves Files, and never uploads the audio. The related MYRA source is the Android Files picker/player implementation described in the matrix; this adaptation does not copy MYRA source or assets.

Personal Agentic AI adds a separate audio-only picker and local playback card to its existing Selected file screen. It uses Android's user-initiated picker through Flutter's `file_picker` and plays the selected local path with `just_audio`. Playback can be paused/searched/stopped while the screen is open, pauses when the app leaves the resumed state, and the player is disposed when the screen closes. The pre-existing document picker and its behavior are unchanged. The file is neither read into Gemini nor uploaded by this feature.

This is a scoped functional adaptation, not exact parity: only one track is selectable, there is no multi-file queue or previous/next navigation, no video preview, and no persistent library or background playback. Device-specific audio codec, lifecycle and seek behavior still need Android 16 and Redmi testing. The app's Android 16 CI remains the build/test gate where local Flutter tooling is unavailable.
