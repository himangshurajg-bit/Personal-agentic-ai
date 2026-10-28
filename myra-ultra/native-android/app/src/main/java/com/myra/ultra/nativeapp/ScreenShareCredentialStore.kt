package com.myra.ultra.nativeapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Stores only the pairing-scoped sender token, encrypted with an Android Keystore key. */
object ScreenShareCredentialStore {
    private const val PREFS = "myra_screen_share_credentials"
    private const val KEY_ALIAS = "myra_screen_share_sender_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    fun save(context: Context, credentials: ScreenShareCredentials) {
        val normalized = credentials.copy(serviceUrl = ScreenShareProtocol.normalizeServiceUrl(credentials.serviceUrl))
        require(ScreenShareProtocol.isValidPairingId(normalized.pairingId))
        require(normalized.senderToken.length in 32..128)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(normalized.senderToken.toByteArray(Charsets.UTF_8))
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val saved = prefs.edit()
            .putString("service_url", normalized.serviceUrl)
            .putString("pairing_id", normalized.pairingId)
            .putString("token_iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("token_ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .commit()
        check(saved) { "MYRA couldn't save the paired receiver securely." }
    }

    fun read(context: Context): ScreenShareCredentials? {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val url = prefs.getString("service_url", null) ?: return null
        val id = prefs.getString("pairing_id", null) ?: return null
        val ivText = prefs.getString("token_iv", null) ?: return null
        val ciphertextText = prefs.getString("token_ciphertext", null) ?: return null
        return try {
            val normalizedUrl = ScreenShareProtocol.normalizeServiceUrl(url)
            if (!ScreenShareProtocol.isValidPairingId(id)) return null
            val iv = Base64.decode(ivText, Base64.NO_WRAP)
            val ciphertext = Base64.decode(ciphertextText, Base64.NO_WRAP)
            require(iv.size == 12 && ciphertext.size in 16..256)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            val token = cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
            if (token.length !in 32..128) return null
            ScreenShareCredentials(normalizedUrl, id, token)
        } catch (_: Exception) {
            null
        }
    }

    fun saveSessionId(context: Context, sessionId: String) {
        require(ScreenShareProtocol.isValidSessionId(sessionId))
        val saved = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString("last_session_id", sessionId).commit()
        check(saved) { "MYRA couldn't save the screen-share session reference." }
    }

    fun readSessionId(context: Context): String? {
        return context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("last_session_id", null)?.takeIf { ScreenShareProtocol.isValidSessionId(it) }
    }

    fun forget(context: Context) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }
}
