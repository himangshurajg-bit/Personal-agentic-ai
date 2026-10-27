package com.myra.ultra.nativeapp

import java.io.IOException
import java.util.Locale
import org.json.JSONObject

internal enum class GeminiCameraFacing(val argument: String, val label: String) {
    BACK("back", "rear camera"),
    FRONT("front", "front camera");

    companion object {
        fun fromArgument(value: String): GeminiCameraFacing? = values().firstOrNull { it.argument == value }
    }
}

/** Narrow, reviewed Android replacement for the prototype's explicit take_photo request. */
internal data class GeminiTakePhotoRequest(
    val facing: GeminiCameraFacing = GeminiCameraFacing.BACK,
    val intentAction: String = GeminiTakePhotoPolicy.ACTION_IMAGE_CAPTURE,
)

internal object GeminiTakePhotoPolicy {
    const val TOOL = "take_photo"
    const val ACTION_IMAGE_CAPTURE = "android.media.action.IMAGE_CAPTURE"
    const val EXTRA_CAMERA_FACING = "android.intent.extras.CAMERA_FACING"
    // Integer values match Camera.CameraInfo constants without requiring the deprecated camera API.
    const val CAMERA_FACING_BACK = 0
    const val CAMERA_FACING_FRONT = 1

    fun request(args: JSONObject): GeminiTakePhotoRequest {
        if (args.length() > 1 || (args.length() == 1 && !args.has("facing"))) {
            throw IOException("Gemini requested unexpected camera arguments; no camera was opened.")
        }
        val facing = if (!args.has("facing")) GeminiCameraFacing.BACK else {
            val value = args.opt("facing") as? String
                ?: throw IOException("Gemini requested an invalid camera; no camera was opened.")
            GeminiCameraFacing.fromArgument(value)
                ?: throw IOException("Gemini requested an unsupported camera; no camera was opened.")
        }
        return GeminiTakePhotoRequest(facing)
    }

    /** Require a direct photo request; a non-default lens must be stated in that same message. */
    fun hasExplicitIntent(userText: String, request: GeminiTakePhotoRequest): Boolean {
        val text = userText.lowercase(Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|not)\\b.{0,32}\\b(?:take|capture|snap)\\b").containsMatchIn(text)) return false
        if (Regex("\\b(?:if|when|whenever|later|tomorrow|schedule|remind|after|before)\\b").containsMatchIn(text)) return false
        if (Regex("\\b(?:how|what|why|tell me|explain|teach me)\\b").containsMatchIn(text)) return false
        val photo = "(?:a\\s+)?(?:photo|picture|selfie)"
        val directPhoto = Regex("\\b(?:take|capture|snap)\\s+$photo\\b|\\b(?:take|capture|snap)\\b[^.!?;]{0,24}\\b$photo\\b").containsMatchIn(text)
        if (!directPhoto) return false

        val mentionsFacingCamera = Regex(
            "\\b(?:front|rear|back)(?:-facing)?\\b.{0,24}\\bcameras?\\b|\\bcameras?\\b.{0,24}\\b(?:front|rear|back)(?:-facing)?\\b"
        ).containsMatchIn(text)
        val asksFront = Regex("\\bselfie\\b").containsMatchIn(text) ||
            (mentionsFacingCamera && Regex("\\bfront(?:-facing)?\\b").containsMatchIn(text))
        val asksBack = mentionsFacingCamera && Regex("\\b(?:rear|back)(?:-facing)?\\b").containsMatchIn(text)
        if (asksFront && asksBack) return false
        return when (request.facing) {
            GeminiCameraFacing.FRONT -> asksFront
            GeminiCameraFacing.BACK -> !asksFront
        }
    }
}
