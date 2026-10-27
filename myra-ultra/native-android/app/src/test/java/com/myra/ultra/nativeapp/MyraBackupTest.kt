package com.myra.ultra.nativeapp

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MyraBackupTest {
    private fun sample() = MyraBackup(
        records = mapOf(
            "tasks" to listOf(encodeTask(MyraTask("task-1", "Study", false))),
            "expenses" to listOf(ExpenseData.encode(MyraExpense("expense-1", 250, "Food", "tea", "2026-10-23"))),
            "water" to listOf(WaterLog.encode(WaterEntry("water-1", "2026-10-23", 500))),
            "habits" to listOf(HabitTracker.encode(MyraHabit("habit-1", "Read", setOf("2026-10-23")))),
            "journal" to listOf(JournalData.encode(MyraJournalEntry("journal-1", "2026-10-23", "A note"))),
        ),
        chatMessagesJson = JSONArray().put(JSONObject().put("user", true).put("text", "hello")).toString(),
        name = "Himangshu",
        language = "English",
        dailyWaterTargetMl = 2_000,
    )

    @Test fun encodeDecodeRoundTripsEveryWhitelistedLocalCategory() {
        val source = sample()
        val decoded = MyraBackupFormat.decode(MyraBackupFormat.encode(source))
        assertEquals(source.records, decoded.records)
        assertEquals(source.name, decoded.name)
        assertEquals(source.language, decoded.language)
        assertEquals(source.dailyWaterTargetMl, decoded.dailyWaterTargetMl)
        assertEquals(source.chatMessagesJson, decoded.chatMessagesJson)
        assertEquals(1, decoded.counts()["tasks"])
        assertEquals(1, decoded.counts()["chat"])
    }

    @Test fun serializedBackupHasVersionAndNoCredentialOrTransientFields() {
        val text = MyraBackupFormat.encode(sample())
        val root = JSONObject(text)
        assertEquals(1, root.getInt("schemaVersion"))
        assertEquals("myra-ultra-local-backup", root.getString("format"))
        listOf("apiKey", "gemini", "ciphertext", "token", "download", "cpu", "memory", "timer", "workManager").forEach {
            assertFalse("unexpected secret/transient field $it", text.contains(it, ignoreCase = true))
        }
        assertEquals(setOf("collections", "chatMessages", "settings"), root.getJSONObject("data").keySet())
        assertEquals(2_000, root.getJSONObject("data").getJSONObject("settings").getInt("dailyWaterTargetMl"))
    }


    @Test fun unsetWaterTargetStaysAbsentInNewBackup() {
        val noTarget = sample().copy(dailyWaterTargetMl = null)
        val text = MyraBackupFormat.encode(noTarget)
        assertFalse(JSONObject(text).getJSONObject("data").getJSONObject("settings").has("dailyWaterTargetMl"))
        assertNull(MyraBackupFormat.decode(text).dailyWaterTargetMl)
    }

    @Test fun oldBackupsWithoutOptionalWaterTargetRemainReadableAndBadTargetsAreRejected() {
        val root = JSONObject(MyraBackupFormat.encode(sample()))
        val settings = root.getJSONObject("data").getJSONObject("settings")
        settings.remove("dailyWaterTargetMl")
        assertNull(MyraBackupFormat.decode(root.toString()).dailyWaterTargetMl)
        settings.put("dailyWaterTargetMl", 249)
        assertRejected(root.toString())
        settings.put("dailyWaterTargetMl", 2_000.5)
        assertRejected(root.toString())
    }

    @Test fun unsupportedVersionUnknownFieldsAndMalformedJsonAreRejected() {
        val valid = JSONObject(MyraBackupFormat.encode(sample()))
        valid.put("schemaVersion", 2)
        assertRejected(valid.toString())
        val fractional = JSONObject(MyraBackupFormat.encode(sample())).put("schemaVersion", 1.5)
        assertRejected(fractional.toString())
        val extra = JSONObject(MyraBackupFormat.encode(sample())).put("apiKey", "secret")
        assertRejected(extra.toString())
        assertRejected("{broken")
    }

    @Test fun oversizedInputAndInvalidRecordsAreRejected() {
        assertRejected(" ".repeat(MyraBackupFormat.MAX_BYTES + 1))
        val invalid = sample().copy(records = sample().records + ("tasks" to listOf("broken|row")))
        assertNotNull(MyraBackupFormat.validate(invalid))
    }

    @Test fun injectedCredentialFieldsInsideBackupAreRejected() {
        val root = JSONObject(MyraBackupFormat.encode(sample()))
        root.getJSONObject("data").getJSONObject("settings").put("geminiApiKey", "secret")
        assertRejected(root.toString())
    }

    @Test fun invalidChatMessageIsRejected() {
        val bad = JSONObject(MyraBackupFormat.encode(sample()))
        bad.getJSONObject("data").put("chatMessages", JSONArray().put(JSONObject().put("user", "yes").put("text", "x")))
        assertRejected(bad.toString())
    }

    private fun assertRejected(text: String) {
        var rejected = false
        try { MyraBackupFormat.decode(text) } catch (_: Exception) { rejected = true }
        assertTrue("expected backup to be rejected", rejected)
    }
}
