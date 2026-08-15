import Testing
import Foundation
import Domain
import SyncCore

// MARK: - R3.4 bootstrap object name tests (moved from DomainTests)
//
// Per remediation roadmap 2026-08-15 R3.4 (A-1): `RemoteLayout.
// bootstrapObjectName` moved from Domain (which must stay Foundation-only)
// to SyncCore, where it uses `SecurityCore.SHA256DigestHash`. The behavior
// contract is unchanged — these tests previously lived in DomainTests and
// pin the exact same semantics.

@Suite struct RemoteLayoutBootstrapNameTests {

    // The bootstrap object name is a DETERMINISTIC function of the locator:
    // the create path uploads under it and the join path fetches under the
    // same name. Must not collide with the fixed manifest object name.

    @Test
    func bootstrapObjectNameIsDeterministic() {
        let locator = RemoteLayout.opaqueObjectName()
        let a = RemoteLayout.bootstrapObjectName(for: locator)
        let b = RemoteLayout.bootstrapObjectName(for: locator)
        #expect(a == b, "the bootstrap object name MUST be deterministic for a given locator")
    }

    @Test
    func bootstrapObjectNameIdenticalForCreateAndJoin() {
        // The object the create path uploads is exactly the object the join
        // path fetches — same locator, same derived name, both paths.
        let locator = RemoteLayout.opaqueObjectName()
        let createName = RemoteLayout.bootstrapObjectName(for: locator)
        let joinName = RemoteLayout.bootstrapObjectName(for: locator)
        #expect(createName == joinName)
        #expect(createName == RemoteLayout.bootstrapObjectName(for: locator))
    }

    @Test
    func bootstrapObjectNameDistinguishesLocators() {
        let l1 = RemoteLayout.opaqueObjectName()
        let l2 = RemoteLayout.opaqueObjectName()
        #expect(RemoteLayout.bootstrapObjectName(for: l1) != RemoteLayout.bootstrapObjectName(for: l2),
                "different locators MUST derive different bootstrap object names")
    }

    @Test
    func bootstrapObjectNameDoesNotCollideWithManifestName() {
        let locator = RemoteLayout.opaqueObjectName()
        let name = RemoteLayout.bootstrapObjectName(for: locator)
        #expect(name != "manifest", "the bootstrap object must not collide with the manifest object name")
    }

    @Test
    func bootstrapObjectNameIsOpaqueShaped() {
        let locator = RemoteLayout.opaqueObjectName()
        let name = RemoteLayout.bootstrapObjectName(for: locator)
        // Names reveal no semantic type (constitution VII).
        for banned in ["bootstrap", "note", "asset", "manifest", "vault"] {
            #expect(!name.contains(banned))
        }
        #expect(!name.isEmpty)
    }
}
