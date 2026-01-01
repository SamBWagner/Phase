import Foundation

struct DotNetVersion {
    let major: Int
    let latest: String
    let label: String
    let isSupported: Bool
    let longTermSupport: Bool
    
    init(major: Int, latest: String, label: String, supported: Bool = true, longTermSupport: Bool = false) {
        self.major = major
        self.latest = latest
        self.label = label
        self.isSupported = supported
        self.longTermSupport = longTermSupport
    }
}

struct DotNetVersionCatalog {
    private static let fallbackCurrent = DotNetVersion(
        major: 10,
        latest: "10.0.101",
        label: "Current",
        longTermSupport: true
    )
    
    private static let fallbackPrevious = DotNetVersion(
        major: 9,
        latest: "9.0.308",
        label: "Previous"
    )
    
    private static let fallbackLTS = DotNetVersion(
        major: 8,
        latest: "8.0.416",
        label: "LTS",
        longTermSupport: true
    )
    
    static let fallbackVersions = [fallbackCurrent, fallbackPrevious, fallbackLTS]
    
    private(set) static var tracked: [DotNetVersion] = fallbackVersions
    
    static func update(with versions: [DotNetVersion]) {
        tracked = versions
    }
    
    static func resetToFallback() {
        tracked = fallbackVersions
    }
    
    static func isTracked(majorVersion: Int) -> Bool {
        tracked.contains { $0.major == majorVersion }
    }
    
    static func getExpectedVersion(for majorVersion: Int) -> DotNetVersion? {
        tracked.first { $0.major == majorVersion }
    }
}
