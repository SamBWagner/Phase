import Foundation

struct DotNetScanner {
    private let commonDotNetPaths = [
        "/usr/local/share/dotnet/dotnet",
        "/usr/local/bin/dotnet",
        "/opt/homebrew/bin/dotnet"
    ]
    
    private let fallbackInstallationPath = "/usr/local/share/dotnet"
    
    func scan(baseURL: URL?) async throws -> [DotNetScanResult] {
        guard let baseURL = baseURL else {
            return try await scanUsingDotNetCLI()
        }
        
        return try await scanDirectories(at: baseURL)
    }
    
    private func scanUsingDotNetCLI() async throws -> [DotNetScanResult] {
        guard let dotnetPath = findDotNetExecutable() else {
            return try await fallbackToDirectoryScan()
        }
        
        var results: [DotNetScanResult] = []
        
        if let sdkOutput = try? await runCommand(dotnetPath, arguments: ["--list-sdks"]) {
            results.append(contentsOf: parseSDKOutput(sdkOutput))
        }
        
        if let runtimeOutput = try? await runCommand(dotnetPath, arguments: ["--list-runtimes"]) {
            results.append(contentsOf: parseRuntimeOutput(runtimeOutput))
        }
        
        if let infoOutput = try? await runCommand(dotnetPath, arguments: ["--info"]) {
            results.append(contentsOf: parseHostFromInfo(infoOutput))
        }
        
        return results
    }
    
    private func findDotNetExecutable() -> String? {
        commonDotNetPaths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    private func fallbackToDirectoryScan() async throws -> [DotNetScanResult] {
        guard FileManager.default.fileExists(atPath: fallbackInstallationPath) else {
            return []
        }
        
        return try await scanDirectories(at: URL(fileURLWithPath: fallbackInstallationPath))
    }
    
    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }
    
    private func parseSDKOutput(_ output: String) -> [DotNetScanResult] {
        output.split(separator: "\n").compactMap { line in
            guard let version = line.split(separator: " ", maxSplits: 1).first else {
                return nil
            }
            return DotNetScanResult(version: String(version), kind: .sdk)
        }
    }
    
    private func parseRuntimeOutput(_ output: String) -> [DotNetScanResult] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { return nil }
            
            let product = String(parts[0])
            let version = String(parts[1])
            return DotNetScanResult(version: version, kind: .runtime, product: product)
        }
    }
    
    private func parseHostFromInfo(_ output: String) -> [DotNetScanResult] {
        let lines = output.split(separator: "\n")
        var inHostSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if isHostSectionHeader(trimmedLine) {
                inHostSection = true
                continue
            }
            
            if inHostSection && isVersionLine(trimmedLine) {
                return extractHostVersion(from: trimmedLine)
            }
            
            if inHostSection && isEndOfHostSection(trimmedLine) {
                break
            }
        }
        
        return []
    }
    
    private func isHostSectionHeader(_ line: String) -> Bool {
        line.starts(with: "Host:") || line.starts(with: "Host (useful for support)")
    }
    
    private func isVersionLine(_ line: String) -> Bool {
        line.starts(with: "Version:")
    }
    
    private func isEndOfHostSection(_ line: String) -> Bool {
        line.starts(with: ".NET") || line.starts(with: "Runtime Environment:")
    }
    
    private func extractHostVersion(from line: String) -> [DotNetScanResult] {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return [] }
        
        let version = parts[1].trimmingCharacters(in: .whitespaces)
        return [DotNetScanResult(version: version, kind: .host)]
    }
    
    private func scanDirectories(at baseURL: URL) async throws -> [DotNetScanResult] {
        var results: [DotNetScanResult] = []
        
        results.append(contentsOf: scanSDKDirectory(at: baseURL))
        results.append(contentsOf: scanHostDirectory(at: baseURL))
        results.append(contentsOf: scanRuntimeDirectory(at: baseURL))
        
        return results
    }
    
    private func scanSDKDirectory(at baseURL: URL) -> [DotNetScanResult] {
        let sdkURL = baseURL.appendingPathComponent("sdk")
        return scanVersionsInDirectory(at: sdkURL, kind: .sdk)
    }
    
    private func scanHostDirectory(at baseURL: URL) -> [DotNetScanResult] {
        let hostURL = baseURL.appendingPathComponent("host/fxr")
        return scanVersionsInDirectory(at: hostURL, kind: .host)
    }
    
    private func scanRuntimeDirectory(at baseURL: URL) -> [DotNetScanResult] {
        let sharedURL = baseURL.appendingPathComponent("shared")
        guard let runtimeProducts = try? FileManager.default.contentsOfDirectory(atPath: sharedURL.path) else {
            return []
        }
        
        return runtimeProducts
            .filter { !$0.starts(with: ".") }
            .flatMap { product in
                let productURL = sharedURL.appendingPathComponent(product)
                return scanVersionsInDirectory(at: productURL, kind: .runtime, product: product)
            }
    }
    
    private func scanVersionsInDirectory(at url: URL, kind: DotNetScanResult.Kind, product: String? = nil) -> [DotNetScanResult] {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return []
        }
        
        return versions
            .filter { !$0.starts(with: ".") }
            .map { DotNetScanResult(version: $0, kind: kind, product: product) }
    }
    
    func analyzeHealth(from scanResults: [DotNetScanResult]) -> [DotNetHealthResult] {
        let sdkVersions = scanResults.filter { $0.kind == .sdk }
        let versionsByMajor = Dictionary(grouping: sdkVersions) { extractMajorVersion(from: $0.version) }
        
        var healthResults: [DotNetHealthResult] = []
        
        for trackedVersion in DotNetVersionCatalog.tracked {
            let result = analyzeTrackedVersion(trackedVersion, installedVersions: versionsByMajor[trackedVersion.major] ?? [])
            healthResults.append(result)
        }
        
        let otherResults = analyzeOtherVersions(versionsByMajor: versionsByMajor)
        healthResults.append(contentsOf: otherResults)
        
        return healthResults
    }
    
    private func analyzeTrackedVersion(_ trackedVersion: DotNetVersion, installedVersions: [DotNetScanResult]) -> DotNetHealthResult {
        guard !installedVersions.isEmpty else {
            return createMissingResult(for: trackedVersion)
        }
        
        guard trackedVersion.isSupported else {
            return createUnsupportedResult(for: trackedVersion, installedVersions: installedVersions)
        }
        
        return createSupportedResult(for: trackedVersion, installedVersions: installedVersions)
    }
    
    private func createMissingResult(for trackedVersion: DotNetVersion) -> DotNetHealthResult {
        DotNetHealthResult(
            majorVersion: trackedVersion.major,
            label: trackedVersion.label,
            expectedVersion: trackedVersion.latest,
            installedVersion: nil,
            status: .missing
        )
    }
    
    private func createUnsupportedResult(for trackedVersion: DotNetVersion, installedVersions: [DotNetScanResult]) -> DotNetHealthResult {
        let highestInstalled = findHighestVersion(in: installedVersions)
        
        return DotNetHealthResult(
            majorVersion: trackedVersion.major,
            label: trackedVersion.label,
            expectedVersion: trackedVersion.latest,
            installedVersion: highestInstalled,
            status: .unsupported
        )
    }
    
    private func createSupportedResult(for trackedVersion: DotNetVersion, installedVersions: [DotNetScanResult]) -> DotNetHealthResult {
        let highestInstalled = findHighestVersion(in: installedVersions)
        let status = determineHealthStatus(installed: highestInstalled, expected: trackedVersion.latest)
        
        return DotNetHealthResult(
            majorVersion: trackedVersion.major,
            label: trackedVersion.label,
            expectedVersion: trackedVersion.latest,
            installedVersion: highestInstalled,
            status: status
        )
    }
    
    private func determineHealthStatus(installed: String, expected: String) -> HealthStatus {
        compareVersions(installed, expected) == .orderedAscending ? .outOfDate : .healthy
    }
    
    private func findHighestVersion(in installedVersions: [DotNetScanResult]) -> String {
        let sortedVersions = installedVersions
            .map { $0.version }
            .sorted { compareVersions($0, $1) == .orderedDescending }
        
        return sortedVersions.first ?? ""
    }
    
    private func analyzeOtherVersions(versionsByMajor: [Int: [DotNetScanResult]]) -> [DotNetHealthResult] {
        let otherMajorVersions = versionsByMajor.keys
            .filter { !DotNetVersionCatalog.isTracked(majorVersion: $0) }
            .sorted(by: >)
        
        return otherMajorVersions.map { majorVersion in
            let installedVersions = versionsByMajor[majorVersion] ?? []
            let highestInstalled = findHighestVersion(in: installedVersions)
            
            return DotNetHealthResult(
                majorVersion: majorVersion,
                label: "Other",
                expectedVersion: nil,
                installedVersion: highestInstalled,
                status: .healthy
            )
        }
    }
    
    private func extractMajorVersion(from versionString: String) -> Int {
        let components = versionString.split(separator: ".")
        guard let firstComponent = components.first, let major = Int(firstComponent) else {
            return 0
        }
        return major
    }
    
    private func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let components1 = version1.split(separator: ".").compactMap { Int($0) }
        let components2 = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(components1.count, components2.count)
        
        for index in 0..<maxLength {
            let part1 = index < components1.count ? components1[index] : 0
            let part2 = index < components2.count ? components2[index] : 0
            
            if part1 < part2 {
                return .orderedAscending
            } else if part1 > part2 {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
}
