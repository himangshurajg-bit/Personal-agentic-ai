package com.myra.ultra.nativeapp

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException

internal data class MyraBackup(
    val records: Map<String, List<String>>,
    val chatMessagesJson: String,
    val name: String,
    val language: String,
    val dailyWaterTargetMl: Int? = null,
) {
    fun counts(): Map<String, Int> = buildMap {
        records.forEach { (key, rows) -> put(key, rows.size) }
        put("chat", JSONArray(chatMessagesJson).length())
        put("settings", 1)
    }
}

internal object MyraBackupFormat {
    const val MAX_BYTES = 2 * 1024 * 1024
    private const val FORMAT = "myra-ultra-local-backup"
    private const val VERSION = 1
    private val collectionNames = setOf("tasks", "expenses", "water", "habits", "journal")
    private val limits = mapOf("tasks" to 10_000, "expenses" to 20_000, "water" to 20_000, "habits" to 2_000, "journal" to 2_000)

    private fun keys(value: JSONObject): Set<String> = value.keys().asSequence().toSet()

    fun validate(backup: MyraBackup): String? {
        if (backup.records.keys != collectionNames) return "The backup does not contain the supported local data categories."
        for ((category, rows) in backup.records) {
            if (rows.size > (limits[category] ?: 0)) return "Too many $category records."
            if (rows.toSet().size != rows.size) return "Duplicate $category records are not supported."
            val valid = when (category) {
                "tasks" -> rows.all { decodeTask(it) != null }
                "expenses" -> rows.all { ExpenseData.decode(it) != null }
                "water" -> rows.all { WaterLog.decode(it) != null }
                "habits" -> rows.all { HabitTracker.decode(it) != null }
                "journal" -> rows.all { JournalData.decode(it) != null }
                else -> false
            }
            if (!valid) return "A $category record is malformed or unsupported."
        }
        if (backup.name.length > 120 || backup.name.any(Char::isISOControl)) return "The saved name is invalid."
        if (backup.language !in setOf("English", "Hindi", "Assamese")) return "The saved language is unsupported."
        if (backup.dailyWaterTargetMl != null && backup.dailyWaterTargetMl !in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS) return "The saved water target is invalid."
        val chat = try { JSONArray(backup.chatMessagesJson) } catch (_: Exception) { return "Saved chat history is malformed." }
        if (chat.length() > 100) return "The backup has more than 100 chat messages."
        for (index in 0 until chat.length()) {
            val item = chat.optJSONObject(index) ?: return "A saved chat message is malformed."
            if (keys(item) != setOf("user", "text")) return "A saved chat message has unsupported fields."
            if (item.opt("user") !is Boolean) return "A saved chat message has an invalid speaker."
            val text = item.opt("text") as? String ?: return "A saved chat message has invalid text."
            if (text.isBlank() || text.length > 8_000) return "A saved chat message is empty or too long."
        }
        return null
    }

    fun encode(backup: MyraBackup): String {
        validate(backup)?.let { throw IllegalArgumentException(it) }
        val collections = JSONObject()
        collectionNames.forEach { category ->
            val array = JSONArray()
            backup.records.getValue(category).forEach(array::put)
            collections.put(category, array)
        }
        val settings = JSONObject().put("name", backup.name).put("language", backup.language)
        backup.dailyWaterTargetMl?.let { settings.put("dailyWaterTargetMl", it) }
        val data = JSONObject()
            .put("collections", collections)
            .put("chatMessages", JSONArray(backup.chatMessagesJson))
            .put("settings", settings)
        val text = JSONObject().put("format", FORMAT).put("schemaVersion", VERSION).put("data", data).toString()
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Backup exceeds 2 MiB." }
        return text
    }

    fun decode(text: String): MyraBackup {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Backup is larger than 2 MiB." }
        val root = JSONObject(text)
        require(keys(root) == setOf("format", "schemaVersion", "data")) { "Backup has unsupported fields." }
        require(root.opt("format") == FORMAT) { "This is not a MYRA Ultra backup." }
        require(root.opt("schemaVersion") is Number && (root.opt("schemaVersion") as Number).toDouble() == VERSION.toDouble()) { "This backup version is unsupported." }
        val data = root.optJSONObject("data") ?: throw IllegalArgumentException("Backup data is missing.")
        require(keys(data) == setOf("collections", "chatMessages", "settings")) { "Backup data has unsupported fields." }
        val collections = data.optJSONObject("collections") ?: throw IllegalArgumentException("Backup collections are missing.")
        require(keys(collections) == collectionNames) { "Backup collections are incomplete or unsupported." }
        val records = collectionNames.associateWith { category ->
            val rows = collections.optJSONArray(category) ?: throw IllegalArgumentException("The $category collection is malformed.")
            (0 until rows.length()).map { index -> rows.opt(index) as? String ?: throw IllegalArgumentException("A $category record is not text.") }
        }
        val chat = data.optJSONArray("chatMessages") ?: throw IllegalArgumentException("Chat history is malformed.")
        val settings = data.optJSONObject("settings") ?: throw IllegalArgumentException("Settings are malformed.")
        val settingKeys = keys(settings)
        require(settingKeys == setOf("name", "language") || settingKeys == setOf("name", "language", "dailyWaterTargetMl")) { "Settings contain unsupported fields." }
        val name = settings.opt("name") as? String ?: throw IllegalArgumentException("The saved name is malformed.")
        val language = settings.opt("language") as? String ?: throw IllegalArgumentException("The saved language is malformed.")
        val target = if (settings.has("dailyWaterTargetMl")) {
            val raw = settings.opt("dailyWaterTargetMl")
            require(raw is Number && raw.toDouble() == raw.toInt().toDouble()) { "The saved water target is malformed." }
            raw.toInt()
        } else null
        val backup = MyraBackup(records, chat.toString(), name, language, target)
        validate(backup)?.let { throw IllegalArgumentException(it) }
        return backup
    }
}

internal object MyraBackupStorage {
    private val recordPrefs = mapOf(
        "tasks" to "myra_native_tasks",
        "expenses" to "myra_native_expenses",
        "water" to "myra_native_water",
        "habits" to "myra_native_habits",
        "journal" to "myra_native_journal",
    )
    private val allPrefs = recordPrefs.values + listOf("myra_native_chat", "myra_native_settings")

    fun snapshot(context: Context): MyraBackup {
        val records = recordPrefs.mapValues { (_, prefsName) ->
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).getStringSet("items", emptySet()).orEmpty().toList()
        }
        val chatPrefs = context.getSharedPreferences("myra_native_chat", Context.MODE_PRIVATE)
        val settings = context.getSharedPreferences("myra_native_settings", Context.MODE_PRIVATE)
        val backup = MyraBackup(
            records = records,
            chatMessagesJson = chatPrefs.getString("messages", "[]") ?: "[]",
            name = settings.getString("name", "") ?: "",
            language = settings.getString("language", "English") ?: "English",
            dailyWaterTargetMl = context.getSharedPreferences("myra_native_water", Context.MODE_PRIVATE)
                .getInt("daily_target_ml", 0).takeIf { it in WaterTarget.MIN_MILLILITERS..WaterTarget.MAX_MILLILITERS },
        )
        MyraBackupFormat.validate(backup)?.let { throw IllegalStateException("Local data cannot be backed up: $it") }
        return backup
    }

    /** Called only after the UI's explicit confirmation. Rollback is best-effort if a commit fails. */
    fun restore(context: Context, backup: MyraBackup): Boolean {
        require(MyraBackupFormat.validate(backup) == null) { "Backup validation failed." }
        val prefs = allPrefs.associateWith { context.getSharedPreferences(it, Context.MODE_PRIVATE) }
        val oldValues = prefs.mapValues { (_, p) -> p.all.toMap() }
        val edits = mutableListOf<Pair<android.content.SharedPreferences, (android.content.SharedPreferences.Editor) -> Unit>>()
        recordPrefs.forEach { (collection, prefName) ->
            val values = backup.records.getValue(collection).toSet()
            edits += prefs.getValue(prefName) to { editor -> editor.putStringSet("items", values) }
        }
        edits += prefs.getValue("myra_native_chat") to { editor -> editor.putString("messages", backup.chatMessagesJson) }
        edits += prefs.getValue("myra_native_settings") to { editor -> editor.putString("name", backup.name).putString("language", backup.language) }
        edits += prefs.getValue("myra_native_water") to { editor ->
            if (backup.dailyWaterTargetMl == null) editor.remove("daily_target_ml")
            else editor.putInt("daily_target_ml", backup.dailyWaterTargetMl)
        }
        try {
            for ((target, applyValues) in edits) {
                val editor = target.edit()
                applyValues(editor)
                if (!editor.commit()) {
                    prefs.forEach { (name, p) -> restorePreferenceSnapshot(p, oldValues.getValue(name)) }
                    return false
                }
            }
            return true
        } catch (_: Exception) {
            prefs.forEach { (name, p) -> restorePreferenceSnapshot(p, oldValues.getValue(name)) }
            return false
        }
    }

    private fun restorePreferenceSnapshot(prefs: android.content.SharedPreferences, values: Map<String, *>) {
        val editor = prefs.edit().clear()
        values.forEach { (key, value) -> when (value) {
            is String -> editor.putString(key, value)
            is Boolean -> editor.putBoolean(key, value)
            is Int -> editor.putInt(key, value)
            is Long -> editor.putLong(key, value)
            is Float -> editor.putFloat(key, value)
            is Set<*> -> editor.putStringSet(key, value.filterIsInstance<String>().toSet())
        } }
        editor.commit()
    }
}

internal fun readMyraBackup(context: Context, uri: Uri): MyraBackup {
    val output = ByteArrayOutputStream()
    context.contentResolver.openInputStream(uri)?.use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= MyraBackupFormat.MAX_BYTES) { "Backup is larger than 2 MiB." }
            output.write(buffer, 0, count)
        }
    } ?: throw IOException("Could not open this backup file.")
    return MyraBackupFormat.decode(output.toString(Charsets.UTF_8.name()))
}

internal fun writeMyraBackup(context: Context, uri: Uri, backup: MyraBackup): Boolean = try {
    val bytes = MyraBackupFormat.encode(backup).toByteArray(Charsets.UTF_8)
    context.contentResolver.openOutputStream(uri, "wt")?.use { stream -> stream.write(bytes); stream.flush() } != null
} catch (_: Exception) { false }
