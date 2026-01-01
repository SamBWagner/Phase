import Foundation

struct DotNetReleasesIndex: Codable {
    let releasesIndex: [DotNetRelease]
    
    enum CodingKeys: String, CodingKey {
        case releasesIndex = "releases-index"
    }
}

struct DotNetRelease: Codable {
    let channelVersion: String
    let latestRelease: String
    let latestSdk: String
    let latestRuntime: String
    let supportPhase: String
    let releaseType: String
    let eolDate: String?
    
    enum CodingKeys: String, CodingKey {
        case channelVersion = "channel-version"
        case latestRelease = "latest-release"
        case latestSdk = "latest-sdk"
        case latestRuntime = "latest-runtime"
        case supportPhase = "support-phase"
        case releaseType = "release-type"
        case eolDate = "eol-date"
    }
    
    var isSupported: Bool {
        supportPhase == "active"
    }
    
    var longTermSupport: Bool {
        releaseType == "lts"
    }
    
    var majorVersion: Int {
        let components = channelVersion.split(separator: ".")
        guard let first = components.first, let major = Int(first) else { return 0 }
        return major
    }
}

class DotNetVersionService {
    static let shared = DotNetVersionService()
    
    private let apiURL = "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
    
    private init() {}
    
    func fetchLatestVersions() async throws -> [DotNetVersion] {
        guard let url = URL(string: apiURL) else {
            throw VersionServiceError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VersionServiceError.networkError
        }
        
        let decoder = JSONDecoder()
        let releasesIndex = try decoder.decode(DotNetReleasesIndex.self, from: data)
        
        return determineVersionsToTrack(from: releasesIndex.releasesIndex)
    }
    
    private func determineVersionsToTrack(from releases: [DotNetRelease]) -> [DotNetVersion] {
        let dotnetReleases = releases
            .filter { isDotNetFramework($0) }
            .sorted { $0.majorVersion > $1.majorVersion }
        
        guard !dotnetReleases.isEmpty else { return [] }
        
        var trackedVersions: [DotNetVersion] = []
        
        addCurrentVersion(from: dotnetReleases, to: &trackedVersions)
        addPreviousVersion(from: dotnetReleases, to: &trackedVersions)
        addThirdVersion(from: dotnetReleases, to: &trackedVersions)
        
        return trackedVersions
    }
    
    private func isDotNetFramework(_ release: DotNetRelease) -> Bool {
        let firstComponent = release.channelVersion.split(separator: ".").first
        return firstComponent?.contains(".") == false
    }
    
    private func addCurrentVersion(from releases: [DotNetRelease], to trackedVersions: inout [DotNetVersion]) {
        guard let current = releases.first else { return }
        
        trackedVersions.append(DotNetVersion(
            major: current.majorVersion,
            latest: current.latestSdk,
            label: "Current",
            supported: current.isSupported,
            longTermSupport: current.longTermSupport
        ))
    }
    
    private func addPreviousVersion(from releases: [DotNetRelease], to trackedVersions: inout [DotNetVersion]) {
        guard releases.count > 1 else { return }
        
        let previous = releases[1]
        trackedVersions.append(DotNetVersion(
            major: previous.majorVersion,
            latest: previous.latestSdk,
            label: "Previous",
            supported: previous.isSupported,
            longTermSupport: previous.longTermSupport
        ))
    }
    
    private func addThirdVersion(from releases: [DotNetRelease], to trackedVersions: inout [DotNetVersion]) {
        guard releases.count > 2 else { return }
        
        let hasLongTermSupport = trackedVersions.contains { $0.longTermSupport }
        
        if hasLongTermSupport {
            addPreviousPreviousVersion(releases[2], to: &trackedVersions)
        } else {
            addLatestLongTermSupportVersion(from: releases, to: &trackedVersions)
        }
    }
    
    private func addPreviousPreviousVersion(_ release: DotNetRelease, to trackedVersions: inout [DotNetVersion]) {
        let label = release.isSupported ? "Previous" : "Unsupported"
        
        trackedVersions.append(DotNetVersion(
            major: release.majorVersion,
            latest: release.latestSdk,
            label: label,
            supported: release.isSupported,
            longTermSupport: release.longTermSupport
        ))
    }
    
    private func addLatestLongTermSupportVersion(from releases: [DotNetRelease], to trackedVersions: inout [DotNetVersion]) {
        guard let latestLTS = releases.first(where: { $0.longTermSupport && $0.isSupported }) else { return }
        
        trackedVersions.append(DotNetVersion(
            major: latestLTS.majorVersion,
            latest: latestLTS.latestSdk,
            label: "LTS",
            supported: latestLTS.isSupported,
            longTermSupport: latestLTS.longTermSupport
        ))
    }
}

enum VersionServiceError: Error, LocalizedError {
    case invalidURL
    case networkError
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .networkError: return "Network error - unable to fetch latest versions"
        case .parsingError: return "Failed to parse version data"
        }
    }
}
