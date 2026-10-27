package com.myra.ultra.nativeapp

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GeminiTakePhotoTest {
    @Test fun defaultsToRearCameraAndAcceptsOnlyBoundedLensChoice() {
        assertEquals(GeminiTakePhotoRequest(), GeminiTakePhotoPolicy.request(JSONObject()))
        assertEquals(GeminiCameraFacing.BACK, GeminiTakePhotoPolicy.request(JSONObject()).facing)
        assertEquals(GeminiCameraFacing.FRONT, GeminiTakePhotoPolicy.request(JSONObject().put("facing", "front")).facing)
        listOf(JSONObject().put("camera", 1), JSONObject().put("facing", "external"), JSONObject().put("facing", "front").put("other", true))
            .forEach { args ->
                try {
                    GeminiTakePhotoPolicy.request(args)
                    throw AssertionError("accepted unsupported camera args: $args")
                } catch (_: IOException) { }
            }

        val declarations = GeminiSafeTools.declaration().getJSONArray("functionDeclarations")
        val declaration = (0 until declarations.length()).map { declarations.getJSONObject(it) }
            .single { it.getString("name") == GeminiSafeTools.TAKE_PHOTO }
        assertTrue(declaration.getString("description").contains("may ignore the lens hint"))
        val facing = declaration.getJSONObject("parameters").getJSONObject("properties").getJSONObject("facing")
        assertEquals("back", facing.getJSONArray("enum").getString(0))
        assertEquals("front", facing.getJSONArray("enum").getString(1))
    }

    @Test fun lensChoiceMustMatchDirectLatestMessage() {
        listOf("Take a photo", "Please take photo", "Capture a picture", "Snap a photo of the cake")
            .forEach { assertTrue("rejected: $it", GeminiTakePhotoPolicy.hasExplicitIntent(it, GeminiTakePhotoRequest())) }
        listOf("Take a selfie", "Capture a front camera picture")
            .forEach { assertTrue("rejected front request: $it", GeminiTakePhotoPolicy.hasExplicitIntent(it, GeminiTakePhotoRequest(GeminiCameraFacing.FRONT))) }
        listOf("Take a photo", "Capture a picture")
            .forEach { assertFalse("accepted implicit front selection: $it", GeminiTakePhotoPolicy.hasExplicitIntent(it, GeminiTakePhotoRequest(GeminiCameraFacing.FRONT))) }
        listOf("Take a selfie", "Use front and rear cameras to take a photo", "Don't take a photo", "If I ask later, take a photo", "Take a photo tomorrow", "Tell me how to take a photo", "Take a screenshot")
            .forEach { assertFalse("accepted: $it", GeminiTakePhotoPolicy.hasExplicitIntent(it, GeminiTakePhotoRequest())) }
    }
}
