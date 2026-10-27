package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TextUtilityTest {
    @Test fun base64RoundTripsUnicodeUtf8() {
        val input = "MYRA · नमस्ते · 🌱"
        val encoded = TextUtility.transform(TextUtilityOperation.BASE64_ENCODE, input)
        assertEquals(input, TextUtility.transform(TextUtilityOperation.BASE64_DECODE, encoded))
    }

    @Test fun rejectsMalformedBase64AndNonUtf8DecodedBytes() {
        assertRejected { TextUtility.transform(TextUtilityOperation.BASE64_DECODE, "%%%not-base64%%") }
        assertRejected { TextUtility.transform(TextUtilityOperation.BASE64_DECODE, "//4=") }
    }

    @Test fun urlFormEncodingRoundTripsUnicodeSpacesAndPlusSigns() {
        val input = "Guwahati + MYRA / नमस्ते"
        val encoded = TextUtility.transform(TextUtilityOperation.URL_ENCODE, input)
        assertTrue(encoded.contains("+"))
        assertEquals(input, TextUtility.transform(TextUtilityOperation.URL_DECODE, encoded))
    }

    @Test fun rejectsMalformedPercentEscape() {
        assertRejected { TextUtility.transform(TextUtilityOperation.URL_DECODE, "%Q0") }
    }

    @Test fun formatsAndMinifiesJsonObjectsAndArrays() {
        val pretty = TextUtility.transform(TextUtilityOperation.JSON_PRETTY, "{\"name\":\"MYRA\",\"items\":[1,2]}")
        assertTrue(pretty.contains("\n  \"name\""))
        assertEquals("{\"name\":\"MYRA\",\"items\":[1,2]}", TextUtility.transform(TextUtilityOperation.JSON_MINIFY, pretty))
        assertEquals("[1,{\"ok\":true}]", TextUtility.transform(TextUtilityOperation.JSON_MINIFY, "[ 1, { \"ok\" : true } ]"))
    }

    @Test fun rejectsMalformedScalarAndDeepJson() {
        assertRejected { TextUtility.transform(TextUtilityOperation.JSON_PRETTY, "{bad}") }
        assertRejected { TextUtility.transform(TextUtilityOperation.JSON_PRETTY, "true") }
        val tooDeep = "{".repeat(34) + "\"x\":1" + "}".repeat(34)
        assertRejected { TextUtility.transform(TextUtilityOperation.JSON_PRETTY, tooDeep) }
    }

    @Test fun inputAndOutputHaveExplicitLimits() {
        assertRejected { TextUtility.transform(TextUtilityOperation.URL_ENCODE, "x".repeat(TextUtility.MAX_INPUT_CHARS + 1)) }
        assertRejected { TextUtility.transform(TextUtilityOperation.URL_ENCODE, "é".repeat(32_000)) }
    }

    private fun assertRejected(block: () -> Unit) {
        var rejected = false
        try { block() } catch (_: IllegalArgumentException) { rejected = true }
        assertTrue("expected invalid text to be rejected", rejected)
    }
}
