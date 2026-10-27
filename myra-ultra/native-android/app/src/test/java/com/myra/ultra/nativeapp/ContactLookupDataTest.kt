package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ContactLookupDataTest {
    @Test fun trimsValidSinglePickedContact() {
        assertEquals(PickedContact("Ada Lovelace", "+44 (20) 7946-0958"), ContactLookupData.parse(" Ada Lovelace ", " +44 (20) 7946-0958 "))
    }

    @Test fun acceptsCommonExtensionAndInternationalPunctuation() {
        assertEquals("+1 555 123 4567 ext 9", ContactLookupData.parse("Desk", "+1 555 123 4567 ext 9")?.phoneNumber)
        assertEquals("+33 1 42 68 53 00", ContactLookupData.parse("Paris", "+33 1 42 68 53 00")?.phoneNumber)
    }

    @Test fun rejectsMissingOversizedOrControlCharacterData() {
        assertNull(ContactLookupData.parse(null, "5551234"))
        assertNull(ContactLookupData.parse("", "5551234"))
        assertNull(ContactLookupData.parse("A".repeat(ContactLookupData.MAX_NAME_LENGTH + 1), "5551234"))
        assertNull(ContactLookupData.parse("Ada", "5\n551234"))
        assertNull(ContactLookupData.parse("Ada\u0000", "5551234"))
    }

    @Test fun rejectsValuesThatAreNotPhoneNumbers() {
        listOf("", "abc", "12", "5551234;DROP", "5551234\u202e").forEach {
            assertNull("$it", ContactLookupData.parse("Ada", it))
        }
    }
}
