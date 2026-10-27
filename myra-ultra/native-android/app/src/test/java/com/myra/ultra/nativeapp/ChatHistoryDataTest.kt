package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class ChatHistoryDataTest {
    @Test fun emptyHistorySerializesAsAnEmptyPersistedArray() {
        assertEquals("[]", ChatHistoryData.encode(emptyList()))
        assertEquals(emptyList<Pair<Boolean, String>>(), ChatHistoryData.decode(ChatHistoryData.encode(emptyList())))
    }

    @Test fun historyRoundTripsAndRetainsOnlyLastHundredMessages() {
        val input = (0..ChatHistoryData.MAX_MESSAGES).map { (it % 2 == 0) to "m$it" }
        val decoded = ChatHistoryData.decode(ChatHistoryData.encode(input))
        assertEquals(ChatHistoryData.MAX_MESSAGES, decoded.size)
        assertEquals(input.takeLast(ChatHistoryData.MAX_MESSAGES), decoded)
    }

    @Test fun decodeRejectsMalformedHistoryAndBoundsEachMessage() {
        assertEquals(emptyList<Pair<Boolean, String>>(), ChatHistoryData.decode("{broken"))
        val tooLong = "x".repeat(ChatHistoryData.MAX_MESSAGE_CHARS + 3)
        val decoded = ChatHistoryData.decode(ChatHistoryData.encode(listOf(false to tooLong)))
        assertEquals(ChatHistoryData.MAX_MESSAGE_CHARS, decoded.single().second.length)
    }
}
