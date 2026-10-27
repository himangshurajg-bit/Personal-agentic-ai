package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DashboardPersonalSummaryTest {
    @Test fun summarizesOnlyRequestedDayAndMonthAndKeepsUserTargetOptional() {
        val waterToday = WaterLog.newEntry("2026-10-27", 350, "w1")!!
        val waterYesterday = WaterLog.newEntry("2026-10-26", 700, "w2")!!
        val read = HabitTracker.create("Read", "h1")!!.copy(completedDates = setOf("2026-10-27"))
        val walk = HabitTracker.create("Walk", "h2")!!
        val thisMonth = MyraExpense("e1", 1250, "Food", "Lunch", "2026-10-02")
        val lastMonth = MyraExpense("e2", 9999, "Other", "Old", "2026-09-30")

        val summary = DashboardPersonalSummary.summarize(
            waterRows = listOf(WaterLog.encode(waterToday), WaterLog.encode(waterYesterday), "bad-row"),
            waterTargetMl = 2000,
            habitRows = listOf(HabitTracker.encode(read), HabitTracker.encode(walk), "bad-row"),
            expenseRows = listOf(ExpenseData.encode(thisMonth), ExpenseData.encode(lastMonth), "bad-row"),
            today = "2026-10-27",
            yearMonth = "2026-10",
        )

        assertEquals(350L, summary.waterTodayMl)
        assertEquals(2000, summary.waterTargetMl)
        assertEquals(1, summary.habitsCompletedToday)
        assertEquals(2, summary.habitsTotal)
        assertEquals(1250L, summary.expensesThisMonthMinor)
    }

    @Test fun unsetOrInvalidTargetIsNotReplacedWithAnAssumption() {
        val noTarget = DashboardPersonalSummary.summarize(emptyList(), 0, emptyList(), emptyList(), "2026-10-27", "2026-10")
        val invalidTarget = DashboardPersonalSummary.summarize(emptyList(), 100, emptyList(), emptyList(), "2026-10-27", "2026-10")
        assertNull(noTarget.waterTargetMl)
        assertNull(invalidTarget.waterTargetMl)
        assertEquals(0L, noTarget.waterTodayMl)
    }
}
