package com.myra.ultra.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalVideoPreviewTest {
    @Test fun acceptsVideoMimeTypesCaseInsensitively() {
        assertTrue(isSupportedLocalVideoMimeType("video/mp4"))
        assertTrue(isSupportedLocalVideoMimeType(" VIDEO/QUICKTIME "))
    }

    @Test fun rejectsNonVideoAndMissingMimeTypes() {
        assertFalse(isSupportedLocalVideoMimeType("audio/mpeg"))
        assertFalse(isSupportedLocalVideoMimeType("image/jpeg"))
        assertFalse(isSupportedLocalVideoMimeType("application/octet-stream"))
        assertFalse(isSupportedLocalVideoMimeType(null))
        assertFalse(isSupportedLocalVideoMimeType(""))
    }

    @Test fun onlyPreparedPausedOrCompletedVideoCanStart() {
        assertTrue(LocalVideoPreviewState.READY.canStartOrResume())
        assertTrue(LocalVideoPreviewState.PAUSED.canStartOrResume())
        assertTrue(LocalVideoPreviewState.COMPLETED.canStartOrResume())
        listOf(LocalVideoPreviewState.EMPTY, LocalVideoPreviewState.PREPARING, LocalVideoPreviewState.PLAYING, LocalVideoPreviewState.ERROR)
            .forEach { assertFalse("$it must not start", it.canStartOrResume()) }
    }

    @Test fun pauseIsOfferedOnlyDuringPlayback() {
        assertTrue(LocalVideoPreviewState.PLAYING.canPause())
        LocalVideoPreviewState.values().filterNot { it == LocalVideoPreviewState.PLAYING }
            .forEach { assertFalse("$it must not pause", it.canPause()) }
    }

    @Test fun stopRequiresAnActiveOrCompletedVideo() {
        assertTrue(LocalVideoPreviewState.PLAYING.canStop())
        assertTrue(LocalVideoPreviewState.PAUSED.canStop())
        assertTrue(LocalVideoPreviewState.COMPLETED.canStop())
        assertFalse(LocalVideoPreviewState.EMPTY.canStop())
        assertFalse(LocalVideoPreviewState.PREPARING.canStop())
        assertFalse(LocalVideoPreviewState.READY.canStop())
        assertFalse(LocalVideoPreviewState.ERROR.canStop())
    }

    @Test fun seekingIsAvailableOnlyWhilePlayingOrPaused() {
        assertTrue(LocalVideoPreviewState.PLAYING.canSeek())
        assertTrue(LocalVideoPreviewState.PAUSED.canSeek())
        LocalVideoPreviewState.values().filterNot { it == LocalVideoPreviewState.PLAYING || it == LocalVideoPreviewState.PAUSED }
            .forEach { assertFalse("$it must not seek", it.canSeek()) }
    }

    @Test fun videoPositionIsClampedToDurationAndHandlesInvalidDuration() {
        assertTrue(clampLocalVideoPosition(-50, 10_000) == 0L)
        assertTrue(clampLocalVideoPosition(4_200, 10_000) == 4_200L)
        assertTrue(clampLocalVideoPosition(12_000, 10_000) == 10_000L)
        assertTrue(clampLocalVideoPosition(500, -1) == 0L)
    }
}
