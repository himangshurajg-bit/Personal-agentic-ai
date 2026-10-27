package com.myra.ultra.nativeapp

/** Daily/monthly summaries derived only from the app's existing on-device records. */
internal data class DashboardPersonalSummary(
    val waterTodayMl: Long,
    val waterTargetMl: Int?,
    val habitsCompletedToday: Int,
    val habitsTotal: Int,
    val expensesThisMonthMinor: Long,
) {
    companion object {
        fun summarize(
            waterRows: Iterable<String>,
            waterTargetMl: Int,
            habitRows: Iterable<String>,
            expenseRows: Iterable<String>,
            today: String,
            yearMonth: String,
        ): DashboardPersonalSummary {
            val water = waterRows.mapNotNull(WaterLog::decode)
            val habits = habitRows.mapNotNull(HabitTracker::decode)
            val expenses = expenseRows.mapNotNull(ExpenseData::decode)
            return DashboardPersonalSummary(
                waterTodayMl = WaterLog.totalForDate(water, today),
                waterTargetMl = waterTargetMl.takeIf { it in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS },
                habitsCompletedToday = habits.count { today in it.completedDates },
                habitsTotal = habits.size,
                expensesThisMonthMinor = ExpenseData.monthTotal(expenses, yearMonth),
            )
        }
    }
}
