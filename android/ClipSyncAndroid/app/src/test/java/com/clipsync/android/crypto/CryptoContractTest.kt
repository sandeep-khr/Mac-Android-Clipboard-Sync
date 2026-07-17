package com.clipsync.android.crypto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.fail
import org.junit.Test
import java.util.Base64

/**
 * Proves the Android crypto reproduces the exact values the Mac (`ClipSyncCore`)
 * produces — the cross-platform contract. The known-answer vectors here are the
 * same literals pinned in the Swift tests; if these pass, the two platforms
 * interoperate.
 */
class CryptoContractTest {

    @Test
    fun sasKnownAnswerMatchesMac() {
        val keyA = ByteArray(32) { it.toByte() }             // 00 01 … 1f
        val keyB = ByteArray(32) { (255 - it).toByte() }     // ff fe … e0
        assertEquals("064987", SasCode.derive(keyA, keyB))
        // order-independent
        assertEquals(SasCode.derive(keyA, keyB), SasCode.derive(keyB, keyA))
    }

    @Test
    fun sessionKeyKnownAnswerMatchesMac() {
        val mac = DeviceKeypair.fromRawPrivateKey(ByteArray(32) { it.toByte() })          // 00 … 1f
        val phone = DeviceKeypair.fromRawPrivateKey(ByteArray(32) { (64 + it).toByte() }) // 40 … 5f
        val session = SessionCrypto(mac, phone.publicKeyRaw)
        assertEquals(
            "a0fe1886b3d80ff6abb9eb4540031af4e512c167c3c819fb97fcb576b2738a1a",
            session.keyHex,
        )
    }

    @Test
    fun bothPeersDeriveSameKeyAndRoundTrip() {
        val mac = DeviceKeypair.generate()
        val phone = DeviceKeypair.generate()
        val macSession = SessionCrypto(mac, phone.publicKeyRaw)
        val phoneSession = SessionCrypto(phone, mac.publicKeyRaw)
        assertEquals(macSession.keyHex, phoneSession.keyHex)

        val (nonce, ciphertext) = macSession.seal("hello 🌍 from the Mac — line1\nline2")
        assertEquals("hello 🌍 from the Mac — line1\nline2", phoneSession.open(nonce, ciphertext))
    }

    @Test
    fun freshNoncePerMessage() {
        val mac = DeviceKeypair.generate()
        val phone = DeviceKeypair.generate()
        val session = SessionCrypto(mac, phone.publicKeyRaw)
        val a = session.seal("same text")
        val b = session.seal("same text")
        assertNotEquals(a.first, b.first)
        assertNotEquals(a.second, b.second)
    }

    @Test
    fun tamperedCiphertextFails() {
        val mac = DeviceKeypair.generate()
        val phone = DeviceKeypair.generate()
        val macSession = SessionCrypto(mac, phone.publicKeyRaw)
        val phoneSession = SessionCrypto(phone, mac.publicKeyRaw)
        val (nonce, ciphertext) = macSession.seal("secret")
        val raw = Base64.getDecoder().decode(ciphertext)
        raw[0] = (raw[0].toInt() xor 0xFF).toByte()
        val tampered = Base64.getEncoder().encodeToString(raw)
        try {
            phoneSession.open(nonce, tampered)
            fail("expected AES-GCM tag verification to fail")
        } catch (_: Exception) {
            // expected
        }
    }
}
