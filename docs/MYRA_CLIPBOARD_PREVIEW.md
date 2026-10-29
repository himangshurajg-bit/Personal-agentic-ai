# MYRA clipboard preview port

## Source basis

The MYRA Android Tools screen in `myra-ultra/native-android/app/src/main/java/com/myra/ultra/nativeapp/MainActivity.kt` reads the clipboard only after the user taps `Read clipboard`. It inspects the first clipboard item’s text without coercing other clipboard formats, previews at most 4,000 characters, does not send or save the preview, and clears it when the app backgrounds or the Tools screen leaves composition. The shared preview limit and surrogate-safe truncation are in `ClipboardPreview.kt`.

## Personal Agentic AI adaptation

The Personal AI Files/Tools feature tabs now include a separate Clipboard preview. A tap calls an Android bridge that first checks the primary clip has `text/plain`, then reads only the first item's `text`; unsupported clipboard content is not coerced to text. The UI caps the displayed preview at 4,000 UTF-16 code units without splitting a surrogate pair, keeps it in screen state only, and clears it when the app leaves the foreground, the screen closes, or the user taps Clear. It does not send clipboard content to the assistant or persist it. This is a local preview only, not MYRA's Gemini clipboard-sharing action or approval flow.

## Verification and limits

The feature has Dart unit/widget coverage for tap-only reads, local display/clear and the length boundary, plus an Android unit test for the plain-text MIME gate. Android device clipboard behavior, non-Android platforms, OEM behavior and Redmi testing are not established by these source-level tests. Only the first plain-text item is shown; rich content, additional items and clipboard history are not handled.
