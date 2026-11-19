import Testing
@testable import MacMoshKit

@Test func versionHasThreeParts() {
    #expect(MacMoshInfo.version.split(separator: ".").count == 3)
}

@Test func identifiersMatchTheDesign() {
    #expect(MacMoshInfo.bundleID == "io.github.shariqh.macmosh")
    #expect(MacMoshInfo.agentLabel == "io.github.shariqh.macmosh.host")
}
