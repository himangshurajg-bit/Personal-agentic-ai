package com.myra.ultra.nativeapp

import android.content.Context
import android.net.Uri
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.SecureRandom
import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.toByteString
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/** Versioned, authenticated passphrase envelope for portable backups. */
internal object MyraEncryptedBackup {
    const val MAX_ENVELOPE_BYTES = 3 * 1024 * 1024
    const val MIN_PASSPHRASE_CHARS = 12
    const val MAX_PASSPHRASE_CHARS = 256
    private const val FORMAT = "myra-ultra-encrypted-backup"
    private const val VERSION = 1
    private const val KDF = "PBKDF2WithHmacSHA256"
    private const val ITERATIONS = 600_000
    private const val CIPHER = "AES-256-GCM"
    private const val KEY_BITS = 256
    private const val SALT_BYTES = 16
    private const val NONCE_BYTES = 12
    private const val TAG_BITS = 128
    private const val AAD = "MYRA-ULTRA-BACKUP\u0000$FORMAT\u0000$VERSION\u0000$KDF\u0000$ITERATIONS\u0000$CIPHER"
    private val random = SecureRandom()
    private val envelopeKeys = setOf("format", "envelopeVersion", "kdf", "iterations", "cipher", "salt", "nonce", "ciphertext")

    fun isEnvelope(text: String): Boolean = try {
        JSONObject(text).opt("format") == FORMAT
    } catch (_: Exception) { false }

    fun encrypt(backup: MyraBackup, passphrase: CharArray): String {
        try {
            require(passphrase.size in MIN_PASSPHRASE_CHARS..MAX_PASSPHRASE_CHARS) {
                "Use a passphrase between $MIN_PASSPHRASE_CHARS and $MAX_PASSPHRASE_CHARS characters."
            }
            val plain = MyraBackupFormat.encode(backup).toByteArray(Charsets.UTF_8)
            try {
                val salt = ByteArray(SALT_BYTES).also(random::nextBytes)
                val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
                val keyBytes = derive(passphrase, salt)
                try {
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(TAG_BITS, nonce))
                    cipher.updateAAD(AAD.toByteArray(Charsets.UTF_8))
                    val ciphertext = cipher.doFinal(plain)
                    val result = JSONObject()
                        .put("format", FORMAT)
                        .put("envelopeVersion", VERSION)
                        .put("kdf", KDF)
                        .put("iterations", ITERATIONS)
                        .put("cipher", CIPHER)
                        .put("salt", b64(salt))
                        .put("nonce", b64(nonce))
                        .put("ciphertext", b64(ciphertext))
                        .toString()
                    require(result.toByteArray(Charsets.UTF_8).size <= MAX_ENVELOPE_BYTES) { "Encrypted backup is too large." }
                    return result
                } finally { keyBytes.fill(0) }
            } finally { plain.fill(0) }
        } finally { passphrase.fill('\u0000') }
    }

    fun decrypt(envelopeText: String, passphrase: CharArray): MyraBackup {
        try {
        require(envelopeText.toByteArray(Charsets.UTF_8).size <= MAX_ENVELOPE_BYTES) { "Encrypted backup is larger than 3 MiB." }
        require(passphrase.size <= MAX_PASSPHRASE_CHARS) { "Passphrase is too long." }
        val envelope = try { JSONObject(envelopeText) } catch (_: Exception) {
            throw IllegalArgumentException("Encrypted backup could not be opened. Check the file and passphrase.")
        }
        try {
            require(envelope.keys().asSequence().toSet() == envelopeKeys)
            require(envelope.opt("format") == FORMAT)
            require(envelope.opt("envelopeVersion") == VERSION)
            require(envelope.opt("kdf") == KDF)
            require(envelope.opt("iterations") == ITERATIONS)
            require(envelope.opt("cipher") == CIPHER)
            val salt = decodeB64(envelope.getString("salt"))
            val nonce = decodeB64(envelope.getString("nonce"))
            val ciphertext = decodeB64(envelope.getString("ciphertext"))
            require(salt.size == SALT_BYTES && nonce.size == NONCE_BYTES)
            require(ciphertext.size in 17..(MyraBackupFormat.MAX_BYTES + 16))
            val keyBytes = derive(passphrase, salt)
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(TAG_BITS, nonce))
                cipher.updateAAD(AAD.toByteArray(Charsets.UTF_8))
                val plain = cipher.doFinal(ciphertext)
                try {
                    require(plain.size <= MyraBackupFormat.MAX_BYTES)
                    val text = Charsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(plain)).toString()
                    return MyraBackupFormat.decode(text)
                } finally { plain.fill(0) }
            } finally { keyBytes.fill(0) }
        } catch (_: Exception) {
            // Keep wrong-key, tampering, and envelope-format failures indistinguishable.
            throw IllegalArgumentException("Encrypted backup could not be opened. Check the file and passphrase.")
        }
        } finally { passphrase.fill('\u0000') }
    }

    private fun derive(passphrase: CharArray, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(passphrase, salt, ITERATIONS, KEY_BITS)
        return try {
            SecretKeyFactory.getInstance(KDF).generateSecret(spec).encoded
        } finally { spec.clearPassword() }
    }

    private fun b64(bytes: ByteArray): String = bytes.toByteString().base64()
    private fun decodeB64(value: String): ByteArray = try {
        require(value.length <= (MAX_ENVELOPE_BYTES * 4 / 3))
        value.decodeBase64()?.toByteArray() ?: throw IllegalArgumentException("Invalid base64")
    } catch (_: Exception) {
        throw IllegalArgumentException("Encrypted backup could not be opened. Check the file and passphrase.")
    }
}

internal fun readMyraBackupText(context: Context, uri: Uri): String {
    val output = ByteArrayOutputStream()
    context.contentResolver.openInputStream(uri)?.use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= MyraEncryptedBackup.MAX_ENVELOPE_BYTES) { "Backup is larger than 3 MiB." }
            output.write(buffer, 0, count)
        }
    } ?: throw IOException("Could not open this backup file.")
    return output.toString(Charsets.UTF_8.name())
}

internal fun writeMyraEncryptedBackup(context: Context, uri: Uri, backup: MyraBackup, passphrase: CharArray): Boolean = try {
    val bytes = MyraEncryptedBackup.encrypt(backup, passphrase).toByteArray(Charsets.UTF_8)
    context.contentResolver.openOutputStream(uri, "wt")?.use { stream -> stream.write(bytes); stream.flush() } != null
} catch (_: Exception) { false }
