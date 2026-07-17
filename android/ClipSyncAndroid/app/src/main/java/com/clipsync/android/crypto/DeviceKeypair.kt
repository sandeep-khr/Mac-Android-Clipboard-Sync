package com.clipsync.android.crypto

import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import java.security.SecureRandom
import java.util.Base64

/**
 * This device's long-term X25519 identity keypair — the Android counterpart of
 * the Mac `DeviceKeypair`. Uses BouncyCastle so the raw 32-byte key format and
 * the X25519 agreement match CryptoKit byte-for-byte (see the crypto contract in
 * docs/superpowers/specs/2026-07-17-phase4a-mac-crypto-design.md).
 */
class DeviceKeypair private constructor(private val privateKey: X25519PrivateKeyParameters) {

    companion object {
        fun generate(): DeviceKeypair =
            DeviceKeypair(X25519PrivateKeyParameters(SecureRandom()))

        fun fromRawPrivateKey(raw: ByteArray): DeviceKeypair {
            require(raw.size == 32) { "X25519 private key must be 32 bytes" }
            return DeviceKeypair(X25519PrivateKeyParameters(raw, 0))
        }
    }

    /** 32-byte raw private key — persist this (Keystore); never send it. */
    val privateKeyRaw: ByteArray get() = privateKey.encoded

    /** 32-byte raw public key — safe to share; travels in `hello`. */
    val publicKeyRaw: ByteArray get() = privateKey.generatePublicKey().encoded

    /** Base64 of the public key, the exact form carried on the wire. */
    val publicKeyBase64: String get() = Base64.getEncoder().encodeToString(publicKeyRaw)

    /** X25519 agreement with a peer's raw 32-byte public key. */
    fun sharedSecret(peerPublicKey: ByteArray): ByteArray {
        require(peerPublicKey.size == 32) { "X25519 public key must be 32 bytes" }
        val agreement = X25519Agreement()
        agreement.init(privateKey)
        val secret = ByteArray(agreement.agreementSize)
        agreement.calculateAgreement(X25519PublicKeyParameters(peerPublicKey, 0), secret, 0)
        return secret
    }
}
