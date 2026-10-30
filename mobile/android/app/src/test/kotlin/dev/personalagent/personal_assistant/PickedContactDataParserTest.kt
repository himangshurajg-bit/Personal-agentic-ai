package dev.personalagent.personal_assistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PickedContactDataParserTest {
    @Test fun trimsAndReturnsOnlyOneValidSelectedContact() {
        assertEquals(
            PickedContactData("Asha Rao", "+91 98765 43210"),
            PickedContactDataParser.parse(" Asha Rao ", " +91 98765 43210 "),
        )
    }

    @Test fun rejectsMissingOrOutOfBoundsValues() {
        assertNull(PickedContactDataParser.parse(null, "+1 555 0100"))
        assertNull(PickedContactDataParser.parse("Asha", null))
        assertNull(PickedContactDataParser.parse(" ", "+1 555 0100"))
        assertNull(PickedContactDataParser.parse("Asha", "12"))
        assertNull(PickedContactDataParser.parse("Asha", "abc"))
        assertNull(PickedContactDataParser.parse("Asha", "+1 555 0100\nOther"))
        assertNull(PickedContactDataParser.parse("A".repeat(121), "+1 555 0100"))
        assertNull(PickedContactDataParser.parse("Asha", "1".repeat(49)))
    }
}
