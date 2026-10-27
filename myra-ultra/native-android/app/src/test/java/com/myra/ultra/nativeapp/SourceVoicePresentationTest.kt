package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SourceVoicePresentationTest {
    @Test fun prototypeStatesMapToSourceTextAndColors() {
        val idle = sourceVoicePresentation(active = false)
        assertEquals(SourceVoiceState.IDLE, idle.state)
        assertEquals("Orb dabao — MYRA hamesha sunegi", idle.status)
        assertEquals(0xFFFF3B5CL, idle.ringColor)
        assertFalse(idle.ringPulses)

        val listening = sourceVoicePresentation(true, "Listening · tap Stop to end")
        assertEquals(SourceVoiceState.LISTENING, listening.state)
        assertEquals("Sun rahi hoon…", listening.status)
        assertEquals(0xFF38D996L, listening.ringColor)
        assertTrue(listening.ringPulses)

        val thinking = sourceVoicePresentation(true, "Thinking")
        assertEquals(SourceVoiceState.THINKING, thinking.state)
        assertEquals("Soch rahi hoon…", thinking.status)
        assertEquals(0xFFFF8A4CL, thinking.ringColor)
        assertTrue(thinking.breathes)
        assertFalse(thinking.ringPulses)

        val speaking = sourceVoicePresentation(true, "MYRA is speaking…")
        assertEquals(SourceVoiceState.SPEAKING, speaking.state)
        assertEquals("Bol rahi hoon…", speaking.status)
        assertEquals(0xFF4CC9F0L, speaking.ringColor)
        assertTrue(speaking.ringPulses)
    }

    @Test fun sourceVoiceStatesIgnoreCaseAndLocalizeNativeSessionCopy() {
        assertEquals(SourceVoiceState.LISTENING, sourceVoicePresentation(true, "Sun rahi hoon…").state)
        assertEquals(SourceVoiceState.SPEAKING, sourceVoicePresentation(true, "Speaking").state)
        assertEquals(SourceVoiceState.THINKING, sourceVoicePresentation(true, "Connecting to Gemini Live…").state)
        assertEquals("Jud rahi hoon…", sourceVoicePresentation(true, "Connecting to Gemini Live…").status)
        assertEquals("Jud rahi hoon…", sourceVoicePresentation(true, "Requesting a short-lived Gemini Live token…").status)
        assertEquals("Dobara jud rahi hoon…", sourceVoicePresentation(true, "Reconnecting to Gemini Live…").status)
        assertEquals("Dobara jud rahi hoon…", sourceVoicePresentation(true, "Resuming Gemini Live…").status)
        assertEquals(SourceVoiceState.IDLE, sourceVoicePresentation(false, "MYRA is speaking").state)
        assertEquals(SourceVoiceState.IDLE, sourceVoicePresentation(true, "Live voice stopped.").state)
        assertEquals(SourceVoiceState.IDLE, sourceVoicePresentation(true, "Live voice ended.").state)
    }

    @Test fun portraitHeroUsesSourceClampAndChatGeometry() {
        assertEquals(120f, sourceHeroHeightDp(540f), 0.001f)
        assertEquals(250f, sourceHeroHeightDp(570f), 0.001f)
        assertEquals(336f, sourceHeroHeightDp(800f), 0.001f)
        assertEquals(380f, sourceHeroHeightDp(1200f), 0.001f)
        assertEquals(158f, sourceHeroHeightDp(800f, compact = true), 0.001f)
        assertEquals(120f, sourceHeroHeightDp(540f, compact = true), 0.001f)
        assertEquals(158, SourceVoiceLayout.compactHeroHeightDp)
        assertEquals(84, SourceVoiceLayout.orbSizeDp)
        assertEquals(66, SourceVoiceLayout.compactOrbSizeDp)
        assertEquals(14f, SourceVoiceLayout.sourceImageIdleObjectPositionPercent, 0.001f)
        assertEquals(20f, SourceVoiceLayout.sourceImageChattingObjectPositionPercent, 0.001f)
        assertEquals(450, SourceVoiceLayout.heroHeightTransitionMillis)
        assertEquals(450, SourceVoiceLayout.portraitPositionTransitionMillis)
        assertEquals(0.78f, SourceVoiceLayout.orbScaleWhenChatting, 0.001f)
        assertEquals(0.95f, sourceOrbScaleWhenPressed(pressed = true), 0.001f)
        assertEquals(1f, sourceOrbScaleWhenPressed(pressed = false), 0.001f)
        assertEquals(200, SourceVoiceLayout.orbPressTransitionMillis)
        assertEquals(0.8024f, SourceVoiceLayout.orbPressEasing.transform(0.5f), 0.002f)
        assertEquals(1500, SourceVoiceLayout.pulseDurationMillis)
        assertEquals(1200, SourceVoiceLayout.breatheDurationMillis)
        assertEquals(-8, SourceVoiceLayout.ringInsetDp)
        assertEquals(8, SourceVoiceLayout.dockBottomDp)
        assertEquals(6, SourceVoiceLayout.dockGapDp)
        assertEquals(1.9f, SourceVoiceLayout.idleMicStroke, 0.001f)
        assertEquals(2.4f, SourceVoiceLayout.liveMicStroke, 0.001f)
        assertEquals(0.80f, SourceVoiceLayout.idleGradientEndStop, 0.001f)
        assertEquals(1f, SourceVoiceLayout.activeGradientEndStop, 0.001f)
        assertEquals(0.35f, SourceVoiceLayout.gradientCenterX, 0.001f)
        assertEquals(0.28f, SourceVoiceLayout.gradientCenterY, 0.001f)
        assertEquals(0.97f, SourceVoiceLayout.gradientRadius, 0.001f)
    }

    @Test fun sourcePortraitCropUsesCssObjectPositionAgainstNegativeCoverSpace() {
        // CSS object-position places 14%/20% of the overflow above the viewport after cover scaling.
        assertEquals(-42, sourceObjectPositionOffset(containerSize = 300, scaledContentSize = 600, percent = 14f))
        assertEquals(-60, sourceObjectPositionOffset(containerSize = 300, scaledContentSize = 600, percent = 20f))
        assertEquals(-150, sourceObjectPositionOffset(containerSize = 300, scaledContentSize = 600, percent = 50f))
        assertEquals(0, sourceObjectPositionOffset(containerSize = 600, scaledContentSize = 600, percent = 50f))
    }

    @Test fun sourceHeroTypographyMatchesAndroidSystemSansMapping() {
        assertEquals("sans-serif", SourceVoiceTypography.androidFamilyName)
        assertEquals("ui-sans-serif, system-ui, -apple-system, \"Segoe UI\", Roboto, \"Noto Sans\", \"Noto Sans Devanagari\", sans-serif", SourceVoiceTypography.cssFontStack)
        assertEquals(15f, SourceVoiceTypography.brandSizeSp, 0.001f)
        assertEquals(800, SourceVoiceTypography.brandWeight)
        assertEquals(2.7f, SourceVoiceTypography.brandLetterSpacingSp, 0.001f)
        assertEquals(22f, SourceVoiceTypography.greetingSizeSp, 0.001f)
        assertEquals(14f, SourceVoiceTypography.statusSizeSp, 0.001f)
    }

    @Test fun audioTimelineKeepsSpeakingUntilQueuedOutputPassesSourceTail() {
        val timeline = SourceVoicePlaybackTimeline()
        val now = 1_000_000_000L
        val oneSecondOfMonoPcm = 24_000 * 2
        val firstEnd = timeline.enqueue(now, oneSecondOfMonoPcm)
        assertEquals(2_000_000_000L, firstEnd)
        assertTrue(timeline.isSpeaking(now))
        assertEquals(980L, timeline.millisUntilQuiet(now))
        assertTrue(timeline.isSpeaking(1_979_000_000L))
        assertFalse(timeline.isSpeaking(1_980_000_000L))

        val appendedEnd = timeline.enqueue(1_100_000_000L, oneSecondOfMonoPcm / 2)
        assertEquals(2_500_000_000L, appendedEnd)
        assertEquals(1_380L, timeline.millisUntilQuiet(1_100_000_000L))
        timeline.clear()
        assertFalse(timeline.isSpeaking(now))
        assertEquals(0L, timeline.millisUntilQuiet(now))
    }

    @Test fun audioTimelineDoesNotTreatSubTailChunkAsSpeaking() {
        val timeline = SourceVoicePlaybackTimeline()
        timeline.enqueue(0L, 24_000 * 2 / 100)
        assertFalse(timeline.isSpeaking(0L))
        assertEquals(0L, timeline.millisUntilQuiet(0L))
    }
}
