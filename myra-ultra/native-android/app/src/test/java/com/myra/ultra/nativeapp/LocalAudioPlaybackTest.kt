package com.myra.ultra.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAudioPlaybackTest {
    @Test fun acceptsAudioMimeTypesCaseInsensitively() {
        assertTrue(isSupportedLocalAudioMimeType("audio/mpeg"))
        assertTrue(isSupportedLocalAudioMimeType(" AUDIO/FLAC "))
    }

    @Test fun rejectsNonAudioAndMissingMimeTypes() {
        assertFalse(isSupportedLocalAudioMimeType("image/jpeg"))
        assertFalse(isSupportedLocalAudioMimeType("application/octet-stream"))
        assertFalse(isSupportedLocalAudioMimeType(null))
        assertFalse(isSupportedLocalAudioMimeType(""))
    }

    @Test fun onlyReadyPausedOrCompletedTracksCanStartOrResume() {
        assertTrue(LocalAudioPlaybackState.READY.canStartOrResume())
        assertTrue(LocalAudioPlaybackState.PAUSED.canStartOrResume())
        assertTrue(LocalAudioPlaybackState.COMPLETED.canStartOrResume())
        assertFalse(LocalAudioPlaybackState.EMPTY.canStartOrResume())
        assertFalse(LocalAudioPlaybackState.PREPARING.canStartOrResume())
        assertFalse(LocalAudioPlaybackState.PLAYING.canStartOrResume())
        assertFalse(LocalAudioPlaybackState.ERROR.canStartOrResume())
    }

    @Test fun pauseIsAvailableOnlyWhilePlaying() {
        assertTrue(LocalAudioPlaybackState.PLAYING.canPause())
        LocalAudioPlaybackState.entries.filterNot { it == LocalAudioPlaybackState.PLAYING }
            .forEach { assertFalse("$it must not offer pause", it.canPause()) }
    }

    @Test fun stopIsUnavailableOnlyWithoutASelectedTrack() {
        assertFalse(LocalAudioPlaybackState.EMPTY.canStop())
        LocalAudioPlaybackState.entries.filterNot { it == LocalAudioPlaybackState.EMPTY }
            .forEach { assertTrue("$it can be reset", it.canStop()) }
    }

    @Test fun seekingIsAvailableOnlyWhileTrackIsPreparedAndActiveOrPaused() {
        assertTrue(LocalAudioPlaybackState.PLAYING.canSeek())
        assertTrue(LocalAudioPlaybackState.PAUSED.canSeek())
        LocalAudioPlaybackState.entries.filterNot { it == LocalAudioPlaybackState.PLAYING || it == LocalAudioPlaybackState.PAUSED }
            .forEach { assertFalse("$it must not offer seek", it.canSeek()) }
    }

    @Test fun seekPositionIsClampedToTrackBounds() {
        assertTrue(clampLocalAudioPosition(-3L, 100L) == 0L)
        assertTrue(clampLocalAudioPosition(101L, 100L) == 100L)
        assertTrue(clampLocalAudioPosition(50L, 100L) == 50L)
        assertTrue(clampLocalAudioPosition(9L, -1L) == 0L)
    }

    @Test fun formatsElapsedTimeAsMinuteOrHourClock() {
        assertTrue(formatLocalAudioTime(0L) == "00:00")
        assertTrue(formatLocalAudioTime(65_000L) == "01:05")
        assertTrue(formatLocalAudioTime(3_661_000L) == "1:01:01")
        assertTrue(formatLocalAudioTime(-1L) == "00:00")
    }
}
