package com.myra.ultra.nativeapp

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MyraEncryptedBackupTest {
    private fun sample() = MyraBackup(
        records = mapOf(
            "tasks" to listOf(encodeTask(MyraTask("task-1", "Study", false))),
            "expenses" to emptyList(), "water" to emptyList(), "habits" to emptyList(), "journal" to emptyList(),
        ),
        chatMessagesJson = JSONArray().put(JSONObject().put("user", true).put("text", "private chat text" )).toString(),
        name = "Private profile name",
        language = "English",
        dailyWaterTargetMl = 1_500,
    )

    @Test fun encryptedBackupRoundTripsAndUsesFreshRandomSaltAndNonce() {
        val exportPassphrase = "correct horse battery staple".toCharArray()
        val first = MyraEncryptedBackup.encrypt(sample(), exportPassphrase)
        assertTrue(exportPassphrase.all { it == '\u0000' })
        val second = MyraEncryptedBackup.encrypt(sample(), "correct horse battery staple".toCharArray())
        assertNotEquals(first, second)
        val importPassphrase = "correct horse battery staple".toCharArray()
        val decoded = MyraEncryptedBackup.decrypt(first, importPassphrase)
        assertTrue(importPassphrase.all { it == '\u0000' })
        assertEquals(sample().records, decoded.records)
        assertEquals(sample().name, decoded.name)
        assertEquals(sample().language, decoded.language)
        assertEquals(sample().dailyWaterTargetMl, decoded.dailyWaterTargetMl)
        assertEquals(sample().chatMessagesJson, decoded.chatMessagesJson)
    }

    @Test fun wrongPassphraseFailsWithoutReturningDecodedData() {
        val envelope = MyraEncryptedBackup.encrypt(sample(), "correct horse battery staple".toCharArray())
        val wrongPassphrase = "wrong passphrase".toCharArray()
        try {
            MyraEncryptedBackup.decrypt(envelope, wrongPassphrase)
            fail("wrong passphrase was accepted")
        } catch (error: IllegalArgumentException) {
            assertEquals("Encrypted backup could not be opened. Check the file and passphrase.", error.message)
            assertTrue(wrongPassphrase.all { it == '\u0000' })
        }
    }

    @Test fun ciphertextTamperingFailsAuthentication() {
        val envelope = JSONObject(MyraEncryptedBackup.encrypt(sample(), "correct horse battery staple".toCharArray()))
        val cipherText = envelope.getString("ciphertext")
        val replacement = if (cipherText[0] == 'A') "B" else "A"
        envelope.put("ciphertext", replacement + cipherText.substring(1))
        try {
            MyraEncryptedBackup.decrypt(envelope.toString(), "correct horse battery staple".toCharArray())
            fail("tampered ciphertext was accepted")
        } catch (error: IllegalArgumentException) {
            assertEquals("Encrypted backup could not be opened. Check the file and passphrase.", error.message)
        }
    }

    @Test fun oversizedEnvelopeAndUnsupportedEnvelopeMetadataFailClosed() {
        try {
            MyraEncryptedBackup.decrypt(" ".repeat(MyraEncryptedBackup.MAX_ENVELOPE_BYTES + 1), "correct horse battery staple".toCharArray())
            fail("oversized envelope was accepted")
        } catch (_: IllegalArgumentException) { }
        val valid = JSONObject(MyraEncryptedBackup.encrypt(sample(), "correct horse battery staple".toCharArray()))
        valid.put("envelopeVersion", 2)
        try {
            MyraEncryptedBackup.decrypt(valid.toString(), "correct horse battery staple".toCharArray())
            fail("unsupported envelope version was accepted")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun encryptedEnvelopeRejectsAdditionalFieldsAndTooShortExportPassphrase() {
        val envelope = JSONObject(MyraEncryptedBackup.encrypt(sample(), "correct horse battery staple".toCharArray()))
        envelope.put("apiKey", "not included")
        try {
            MyraEncryptedBackup.decrypt(envelope.toString(), "correct horse battery staple".toCharArray())
            fail("unexpected field was accepted")
        } catch (_: IllegalArgumentException) { }
        try {
            MyraEncryptedBackup.encrypt(sample(), "short".toCharArray())
            fail("short passphrase was accepted for export")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun encryptedEnvelopeDoesNotExposeChatOrProfileAndPlainSchemaRemainsReadable() {
        val encrypted = MyraEncryptedBackup.encrypt(sample(), "correct horse battery staple".toCharArray())
        assertTrue(MyraEncryptedBackup.isEnvelope(encrypted))
        listOf("private chat text", "Private profile name", "geminiApiKey", "downloadRecords", "timerState").forEach {
            assertFalse("plaintext/secret field leaked: $it", encrypted.contains(it, ignoreCase = true))
        }
        val legacy = MyraBackupFormat.decode(MyraBackupFormat.encode(sample()))
        assertEquals(sample().records, legacy.records)
        assertEquals(sample().chatMessagesJson, legacy.chatMessagesJson)
    }
}
