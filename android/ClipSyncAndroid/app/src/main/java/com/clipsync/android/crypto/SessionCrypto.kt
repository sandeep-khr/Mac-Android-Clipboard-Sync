package com.clipsync.android.crypto

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Per-connection authenticated encryption — the Android counterpart of the Mac
 * `SessionCrypto`. Derives the session key with HKDF-SHA256 over the X25519
 * shared secret, then seals/opens payloads with AES-256-GCM. The wire encoding
 * (empty salt, this info string, base64 nonce, base64 `ciphertext‖tag`) is the
 * cross-platform contract.
 */
class SessionCrypto(ourKeypair: DeviceKeypair, peerPublicKey: ByteArray) {

    private val key: ByteArray = Hkdf.derive(
        ikm = ourKeypair.sharedSecret(peerPublicKey),
        salt = ByteArray(0),
        info = "clipsync-session-v1".toByteArray(Charsets.UTF_8),
        length = 32,
    )

    /** Raw 32-byte session key as hex — for tests / diagnostics. */
    val keyHex: String get() = key.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    /** Encrypts UTF-8 text → base64 nonce and base64 `ciphertext‖tag`. */
    fun seal(text: String): Pair<String, String> {
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        val ciphertextAndTag = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(nonce) to
            Base64.getEncoder().encodeToString(ciphertextAndTag)
    }

    /** Decrypts a nonce / `ciphertext‖tag` pair back to text. Throws on tamper. */
    fun open(nonceB64: String, ciphertextB64: String): String {
        val nonce = Base64.getDecoder().decode(nonceB64)
        val ciphertextAndTag = Base64.getDecoder().decode(ciphertextB64)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        return String(cipher.doFinal(ciphertextAndTag), Charsets.UTF_8)
    }
}
