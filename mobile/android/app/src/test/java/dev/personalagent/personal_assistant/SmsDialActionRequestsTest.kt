package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SmsDialActionRequestsTest {
    @Test fun dialRequiresOneE164NumberWithoutReformatting() {
        assertEquals(PhoneDialRequest("+14155550123"), PhoneHandoffPolicy.parseDial("+14155550123"))
        listOf("4155550123", "+01234567", "+123456", "+1234567890123456", "+1 4155550123", null, 7)
            .forEach { assertNull(PhoneHandoffPolicy.parseDial(it)) }
    }

    @Test fun smsDraftPreservesExactTextAndRequiresRecipient() {
        assertEquals(
            SmsDraftRequest("+14155550123", "Line one\nLine two"),
            PhoneHandoffPolicy.parseSms("+14155550123", "Line one\nLine two"),
        )
        assertNull(PhoneHandoffPolicy.parseSms("+14155550123", "  "))
        assertNull(PhoneHandoffPolicy.parseSms("4155550123", "Hello"))
        assertNull(PhoneHandoffPolicy.parseSms("+14155550123", "x".repeat(1601)))
        assertNull(PhoneHandoffPolicy.parseSms("+14155550123", "bad\u0000text"))
    }
}
