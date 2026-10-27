package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpenseDataTest {
    @Test fun parsesBoundedPositiveAmountsToMinorUnits() {
        assertEquals(1234L, ExpenseData.amountToMinorUnits(" 12.34 "))
        assertEquals(700L, ExpenseData.amountToMinorUnits("7"))
        assertNull(ExpenseData.amountToMinorUnits("0"))
        assertNull(ExpenseData.amountToMinorUnits("-1"))
        assertNull(ExpenseData.amountToMinorUnits("1.999"))
        assertNull(ExpenseData.amountToMinorUnits("NaN"))
        assertNull(ExpenseData.amountToMinorUnits("99999999999999"))
    }

    @Test fun validatesCalendarDatesAndRoundTripsEntries() {
        assertTrue(ExpenseData.isValidDate("2026-10-23"))
        assertTrue(!ExpenseData.isValidDate("2026-02-30"))
        assertTrue(!ExpenseData.isValidDate("2026-1-2"))
        val original = MyraExpense("id-1", 1234, "Food | drink", "tea ☕", "2026-10-23")
        assertEquals(original, ExpenseData.decode(ExpenseData.encode(original)))
        assertNull(ExpenseData.decode("broken|row"))
    }

    @Test fun sumsOnlyRequestedMonth() {
        val rows = listOf(
            MyraExpense("1", 100, "Food", "", "2026-10-01"),
            MyraExpense("2", 250, "Travel", "", "2026-10-31"),
            MyraExpense("3", 900, "Bills", "", "2026-11-01"),
        )
        assertEquals(350L, ExpenseData.monthTotal(rows, "2026-10"))
    }
}
