package com.myra.ultra.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiLiveActionPolicyTest {
    @Test fun volumeNeedsDirectStreamAndOneExactPercentage() {
        val music = GeminiVolumeRequest(MyraVolumeStream.MUSIC, 50)
        assertTrue(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Set the music volume to 50%", music))
        assertTrue(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Please change my music volume to 50 percent.", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Set the volume to 50%", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Set music volume louder", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("The music is at 50% volume", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Set music volume to 50% or 60%", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Don't set music volume to 50%", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("If I ask later, set music volume to 50%", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Set music volume to 50 percent tomorrow", music))
        assertFalse(GeminiLiveActionPolicy.hasExplicitVolumeIntent("Set music volume to 40%", music))
    }


    @Test fun liveNavigationRequiresExactPlaceAndDirectNonDeferredDirectionsRequest() {
        val request = GeminiNavigateRequest("Guwahati Railway Station")
        assertTrue(GeminiSafeTools.hasExplicitNavigateIntent("Navigate to Guwahati Railway Station", request))
        assertTrue(GeminiSafeTools.hasExplicitNavigateIntent("Show directions to Guwahati Railway Station", request))
        assertFalse(GeminiSafeTools.hasExplicitNavigateIntent("Navigate to Guwahati", request))
        assertFalse(GeminiSafeTools.hasExplicitNavigateIntent("Don't navigate to Guwahati Railway Station", request))
        assertFalse(GeminiSafeTools.hasExplicitNavigateIntent("If I ask later, navigate to Guwahati Railway Station", request))
        assertTrue(GeminiSafeTools.hasExplicitNavigateIntent("What are directions to Guwahati Railway Station?", request))
    }

    @Test fun liveBrightnessRequiresExactDirectLevelAndRejectsDeferredRequests() {
        val request = GeminiBrightnessRequest(128)
        assertTrue(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Set screen brightness to 128", request))
        assertTrue(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Please change display brightness to 0", GeminiBrightnessRequest(0)))
        assertFalse(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Set screen brightness to 127", request))
        assertFalse(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Set screen brightness to 128 tomorrow", request))
        assertFalse(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("If needed later, set screen brightness to 128", request))
        assertFalse(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Don't set screen brightness to 128", request))
        assertFalse(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Set screen brightness to 128 or 200", request))
        assertFalse(GeminiLiveActionPolicy.hasExplicitBrightnessIntent("Set screen brightness to 50 percent", GeminiBrightnessRequest(50)))
    }

    @Test fun torchNeedsOneDirectNonnegatedDirection() {
        assertTrue(GeminiLiveActionPolicy.hasExplicitTorchIntent("Turn the flashlight on", true))
        assertTrue(GeminiLiveActionPolicy.hasExplicitTorchIntent("Switch torch off", false))
        assertFalse(GeminiLiveActionPolicy.hasExplicitTorchIntent("Don't turn flashlight on", true))
        assertFalse(GeminiLiveActionPolicy.hasExplicitTorchIntent("If needed later, turn torch on", true))
        assertFalse(GeminiLiveActionPolicy.hasExplicitTorchIntent("Turn flashlight on or off", true))
        assertFalse(GeminiLiveActionPolicy.hasExplicitTorchIntent("Turn flashlight on", false))
        assertFalse(GeminiLiveActionPolicy.hasExplicitTorchIntent("The flashlight is on", true))
    }

    @Test fun liveTimerRequiresExactDirectDurationAndRejectsDelayedOrAmbiguousRequests() {
        val request = GeminiTimerPolicy.request(org.json.JSONObject().put("seconds", 300))!!
        assertTrue(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes", request))
        assertTrue(GeminiTimerPolicy.hasExplicitIntent("Start a timer for 300 seconds", request))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes", GeminiTimerPolicy.request(org.json.JSONObject().put("seconds", 60))!!))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes or 10 minutes", request))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Don't set a timer for 5 minutes", request))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("Set a timer for 5 minutes tomorrow", request))
        assertFalse(GeminiTimerPolicy.hasExplicitIntent("What is a 5 minute timer?", request))
    }

    @Test fun liveAlarmRequiresOneExactDirectOneOff24HourTime() {
        val alarm = GeminiAlarmPolicy.request(org.json.JSONObject().put("hour", 7).put("minute", 30))!!
        assertTrue(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30", alarm))
        assertTrue(GeminiAlarmPolicy.hasExplicitIntent("Create an alarm at 07:30", alarm))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30", GeminiAlarmPolicy.request(org.json.JSONObject().put("hour", 8).put("minute", 0))!!))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 7:30", alarm))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30 or 08:00", alarm))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Don't set an alarm for 07:30", alarm))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set an alarm for 07:30 tomorrow", alarm))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("Set a daily alarm for 07:30", alarm))
        assertFalse(GeminiAlarmPolicy.hasExplicitIntent("What time is my 07:30 alarm?", alarm))
    }

}
