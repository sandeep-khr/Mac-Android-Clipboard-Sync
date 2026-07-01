import Testing
@testable import ClipSyncCore

@Suite("DeviceIdentity / Bonjour TXT record")
struct DeviceIdentityTests {

    @Test("the service type is the agreed Bonjour type")
    func serviceType() {
        #expect(ClipSyncProtocol.serviceType == "_clipsync._tcp")
    }

    @Test("the protocol version is 1")
    func protocolVersion() {
        #expect(ClipSyncProtocol.version == 1)
    }

    @Test("the TXT record carries device name, id, and protocol version")
    func txtRecordFields() {
        let identity = DeviceIdentity(id: "abc-123", name: "Sandeep's MacBook")
        let txt = identity.txtRecord()
        #expect(txt["device_name"] == "Sandeep's MacBook")
        #expect(txt["device_id"] == "abc-123")
        #expect(txt["protocol_version"] == "1")
    }

    @Test("the TXT record has exactly the three agreed keys")
    func txtRecordKeys() {
        let txt = DeviceIdentity(id: "x", name: "y").txtRecord()
        #expect(Set(txt.keys) == ["device_name", "device_id", "protocol_version"])
    }
}
