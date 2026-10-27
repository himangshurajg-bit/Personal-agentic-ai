package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiNavigateTest {
    @Test fun navigationRequiresOneBoundedPlaceAndDeclaresReviewedSearch() {
        val request = GeminiSafeTools.navigateRequest(JSONObject().put("place", "  Central Park "))
        assertEquals("Central Park", request.place)
        assertEquals(GeminiSafeTools.NAVIGATE_TO, GeminiSafeTools.validate(GeminiSafeTools.NAVIGATE_TO, JSONObject().put("place", "Central Park")))
        listOf(
            JSONObject(),
            JSONObject().put("place", " "),
            JSONObject().put("place", "x".repeat(MapsDestinationData.MAX_LENGTH + 1)),
            JSONObject().put("place", "Park\nGate"),
            JSONObject().put("place", "Central Park").put("extra", true),
            JSONObject().put("place", 12),
        ).forEach { args ->
            try { GeminiSafeTools.navigateRequest(args); throw AssertionError("accepted $args") }
            catch (_: IOException) { }
        }
        val declaration = (0 until GeminiSafeTools.declaration().getJSONArray("functionDeclarations").length())
            .map { GeminiSafeTools.declaration().getJSONArray("functionDeclarations").getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.NAVIGATE_TO }
        assertTrue(declaration.getString("description").contains("native approval"))
        assertTrue(declaration.getString("description").contains("does not start or verify navigation"))
        assertEquals(JSONArray().put("place").toString(), declaration.getJSONObject("parameters").getJSONArray("required").toString())
    }

    @Test fun exactDestinationAndDirectDirectionRequestAreRequired() {
        val request = GeminiNavigateRequest("Central Park")
        assertTrue(GeminiSafeTools.hasExplicitNavigateIntent("Please give me directions to Central Park", request))
        assertTrue(GeminiSafeTools.hasExplicitNavigateIntent("Navigate to CENTRAL PARK", request))
        assertTrue(GeminiSafeTools.hasExplicitNavigateIntent("Take me to Central Park", request))
        listOf(
            "What is near Central Park?",
            "Give directions to Times Square",
            "Don't navigate to Central Park",
            "If I go to Central Park tomorrow, remind me",
            "Maybe navigate to Central Park later",
        ).forEach { assertFalse("accepted: $it", GeminiSafeTools.hasExplicitNavigateIntent(it, request)) }
    }

    @Test fun mapsHandoffUsesEncodedGeoSearchAndDoesNotClaimNavigation() {
        val request = GeminiNavigateRequest("New York & 5th / Café")
        val intent = GeminiSafeTools.navigateIntent(request)
        assertEquals("android.intent.action.VIEW", intent.action)
        assertEquals("geo:0,0?q=New+York+%26+5th+%2F+Caf%C3%A9", intent.data)
        assertFalse(intent.data.contains("google.navigation:"))
    }
}
