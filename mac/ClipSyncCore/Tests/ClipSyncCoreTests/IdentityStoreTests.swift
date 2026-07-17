import Foundation
import Testing
@testable import ClipSyncCore

@Suite("PersistentIdentity & TrustedDeviceStore")
struct IdentityStoreTests {

    @Test("loadOrCreate is idempotent: same id + keypair on repeat calls")
    func idempotent() throws {
        let store = InMemoryKeyStore()
        let identity = PersistentIdentity(keyStore: store)
        let first = try identity.loadOrCreate()
        let second = try identity.loadOrCreate()
        #expect(first.deviceId == second.deviceId)
        #expect(first.keypair.publicKeyRaw == second.keypair.publicKeyRaw)
        #expect(first.keypair.privateKeyRaw == second.keypair.privateKeyRaw)
    }

    @Test("a separate store yields a distinct identity")
    func freshDiffers() throws {
        let a = try PersistentIdentity(keyStore: InMemoryKeyStore()).loadOrCreate()
        let b = try PersistentIdentity(keyStore: InMemoryKeyStore()).loadOrCreate()
        #expect(a.deviceId != b.deviceId)
        #expect(a.keypair.publicKeyRaw != b.keypair.publicKeyRaw)
    }

    @Test("trust / lookup / untrust round-trip")
    func trustRoundTrip() throws {
        let store = TrustedDeviceStore(keyStore: InMemoryKeyStore())
        let peerKey = DeviceKeypair().publicKeyRaw

        #expect(try store.isTrusted(deviceId: "phone-1") == false)

        try store.trust(deviceId: "phone-1", publicKey: peerKey)
        #expect(try store.isTrusted(deviceId: "phone-1") == true)
        #expect(try store.publicKey(forDeviceId: "phone-1") == peerKey)

        try store.untrust(deviceId: "phone-1")
        #expect(try store.isTrusted(deviceId: "phone-1") == false)
        #expect(try store.publicKey(forDeviceId: "phone-1") == nil)
    }
}
