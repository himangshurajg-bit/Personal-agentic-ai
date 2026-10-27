package com.myra.ultra.nativeapp

import androidx.compose.animation.core.CubicBezierEasing
import kotlin.math.roundToInt

/** Source UI states from ui_html.py's setMode(): idle/listening/thinking/speaking. */
enum class SourceVoiceState { IDLE, LISTENING, THINKING, SPEAKING }

data class SourceVoicePresentation(
    val state: SourceVoiceState,
    val status: String,
    val ringColor: Long,
    val orbScale: Float,
    val ringPulses: Boolean,
    val breathes: Boolean,
)

/**
 * Maps the prototype's setMode() status classes to the native session's verified status events.
 * Unknown live states stay in the documented listening baseline; an inactive/error session is idle.
 */
internal fun sourceVoicePresentation(active: Boolean, detail: String = ""): SourceVoicePresentation {
    val text = detail.lowercase()
    val state = when {
        !active || "stopped" in text || "ended" in text -> SourceVoiceState.IDLE
        "speak" in text || "bol rahi" in text -> SourceVoiceState.SPEAKING
        "listening" in text || "sun rahi" in text -> SourceVoiceState.LISTENING
        else -> SourceVoiceState.THINKING
    }
    val status = when (state) {
        SourceVoiceState.IDLE -> "Orb dabao — MYRA hamesha sunegi"
        SourceVoiceState.LISTENING -> "Sun rahi hoon…"
        SourceVoiceState.THINKING -> when {
            "reconnect" in text || "resum" in text -> "Dobara jud rahi hoon…"
            "connect" in text || "token" in text -> "Jud rahi hoon…"
            else -> "Soch rahi hoon…"
        }
        SourceVoiceState.SPEAKING -> "Bol rahi hoon…"
    }
    return when (state) {
        SourceVoiceState.IDLE -> SourceVoicePresentation(state, status, 0xFFFF3B5C, 1f, false, false)
        SourceVoiceState.LISTENING -> SourceVoicePresentation(state, status, 0xFF38D996, 1f, true, false)
        SourceVoiceState.THINKING -> SourceVoicePresentation(state, status, 0xFFFF8A4C, 1f, false, true)
        SourceVoiceState.SPEAKING -> SourceVoicePresentation(state, status, 0xFF4CC9F0, 1f, true, false)
    }
}

internal object SourceVoiceLayout {
    const val compactHeroHeightDp = 158
    const val orbSizeDp = 84
    const val compactOrbSizeDp = 66
    const val orbScaleWhenChatting = 0.78f
    /** CSS `.orb:active` uses 0.95 scale and the default CSS `ease` curve over .2s. */
    const val orbPressScale = 0.95f
    const val orbPressTransitionMillis = 200
    val orbPressEasing = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f)
    /** CSS object-position percentages from ui_html.py, passed to object-fit:cover alignment. */
    const val sourceImageIdleObjectPositionPercent = 14f
    const val sourceImageChattingObjectPositionPercent = 20f
    const val heroHeightTransitionMillis = 450
    const val portraitPositionTransitionMillis = 450
    const val pulseDurationMillis = 1500
    const val breatheDurationMillis = 1200
    const val ringInsetDp = -8
    const val dockBottomDp = 8
    const val dockGapDp = 6
    const val idleMicStroke = 1.9f
    const val liveMicStroke = 2.4f
    const val idleGradientEndStop = 0.80f
    const val activeGradientEndStop = 1f
    const val gradientCenterX = 0.35f
    const val gradientCenterY = 0.28f
    const val gradientRadius = 0.97f
    const val playbackSampleRateHz = 24_000
    const val playbackBytesPerSample = 2
    const val playbackTailMillis = 20
}

internal fun sourceOrbScaleWhenPressed(pressed: Boolean): Float =
    if (pressed) SourceVoiceLayout.orbPressScale else 1f

/**
 * Mirrors ui_html.py's playT > currentTime + 0.02 speaking test for queued 24 kHz mono PCM.
 * AudioTrack playback timing is estimated from the samples queued; device output latency remains
 * runtime-dependent, just as the Web Audio schedule is clock-dependent in the prototype.
 */
internal class SourceVoicePlaybackTimeline(
    private val sampleRateHz: Int = SourceVoiceLayout.playbackSampleRateHz,
    private val bytesPerSample: Int = SourceVoiceLayout.playbackBytesPerSample,
    private val tailMillis: Long = SourceVoiceLayout.playbackTailMillis.toLong(),
) {
    private var queuedUntilNanos = 0L

    fun enqueue(nowNanos: Long, pcmBytes: Int): Long {
        require(sampleRateHz > 0 && bytesPerSample > 0)
        require(pcmBytes >= 0)
        val base = maxOf(nowNanos, queuedUntilNanos)
        val durationNanos = pcmBytes.toLong() * 1_000_000_000L / (sampleRateHz.toLong() * bytesPerSample)
        queuedUntilNanos = base + durationNanos
        return queuedUntilNanos
    }

    fun isSpeaking(nowNanos: Long): Boolean = queuedUntilNanos > nowNanos + tailMillis * 1_000_000L

    fun millisUntilQuiet(nowNanos: Long): Long {
        val remainingNanos = queuedUntilNanos - nowNanos - tailMillis * 1_000_000L
        return if (remainingNanos <= 0L) 0L else (remainingNanos + 999_999L) / 1_000_000L
    }

    fun clear() { queuedUntilNanos = 0L }
}

/** CSS clamp(250px, 42vh, 380px), mapped to the app viewport in dp. */
internal fun sourceHeroHeightDp(viewportHeightDp: Float, compact: Boolean = false): Float = when {
    viewportHeightDp <= 560f -> 120f
    compact -> SourceVoiceLayout.compactHeroHeightDp.toFloat()
    else -> (viewportHeightDp * 0.42f).coerceIn(250f, 380f)
}

/** CSS object-position percentages are applied to the leftover (possibly negative) space. */
internal fun sourceObjectPositionOffset(containerSize: Int, scaledContentSize: Int, percent: Float): Int =
    ((containerSize - scaledContentSize) * percent / 100f).roundToInt()

/** CSS values from ui_html.py's system-ui stack, expressed as Compose's Android system sans metrics. */
internal object SourceVoiceTypography {
    const val androidFamilyName = "sans-serif"
    const val cssFontStack = "ui-sans-serif, system-ui, -apple-system, \"Segoe UI\", Roboto, \"Noto Sans\", \"Noto Sans Devanagari\", sans-serif"
    const val brandSizeSp = 15f
    const val brandWeight = 800
    const val brandLetterSpacingSp = 2.7f // .18em at 15px
    const val chipSizeSp = 13f
    const val greetingSizeSp = 22f
    const val greetingWeight = 800
    const val statusSizeSp = 14f
}
