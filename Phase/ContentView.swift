import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State private var isScanning = false
    @State private var healthResults: [DotNetHealthResult] = []
    @State private var errorMessage: String?
    @State private var networkAvailable = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        scan()
                    } label: {
                        Label(isScanning ? "Scanning…" : "Scan for .NET", systemImage: isScanning ? "hourglass" : "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)

                    Button(role: .destructive) { healthResults.removeAll(); errorMessage = nil } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(isScanning || (healthResults.isEmpty && errorMessage == nil))
                }

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Error", systemImage: "exclamationmark.triangle").font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
                }

                if healthResults.isEmpty && errorMessage == nil {
                    ContentUnavailableView("No results yet", systemImage: "tray", description: Text("Tap 'Scan for .NET' to check your installation health."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            let trackedResults = healthResults.filter { $0.label != "Other" }
                            if !trackedResults.isEmpty {
                                ForEach(trackedResults) { result in
                                    HealthResultTile(result: result)
                                }
                            }
                            
                            let otherResults = healthResults.filter { $0.label == "Other" }
                            if !otherResults.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Other Installations")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                    
                    ForEach(otherResults) { result in
                        HealthResultTile(result: result)
                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .padding()
            .navigationTitle(".NET Version Health")
        }
    }
}

private extension ContentView {
    func buildScanTargets() -> [URL?] {
        let canonicalPath = "/usr/local/share/dotnet"
        let canonicalURL = URL(fileURLWithPath: canonicalPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()

        var scanTargets: [URL?] = [nil] // prefer automatic discovery first
        if FileManager.default.fileExists(atPath: canonicalURL.path) {
            scanTargets.append(canonicalURL)
        }

        var seenKeys: Set<String> = []
        return scanTargets.filter { url in
            let key = (url?.standardizedFileURL.resolvingSymlinksInPath().path) ?? "(automatic discovery)"
            if seenKeys.contains(key) { return false }
            seenKeys.insert(key)
            return true
        }
    }

    func describeAttempt(_ url: URL?) -> String {
        guard let url = url else { return "(automatic discovery)" }

        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resolvedURL.path) else { return "\(resolvedURL.path) (missing)" }

        let resourceValues = try? resolvedURL.resourceValues(forKeys: Set<URLResourceKey>([.isDirectoryKey]))
        let isDir = resourceValues?.isDirectory ?? false
        if isDir {
            let dotnetBinaryPath = resolvedURL.appendingPathComponent("dotnet").path
            let hasDotnetBinary = fileManager.fileExists(atPath: dotnetBinaryPath)
            return "\(resolvedURL.path) (dotnet: \(hasDotnetBinary ? "found" : "missing"))"
        } else {
            let isExec = fileManager.isExecutableFile(atPath: resolvedURL.path)
            return "\(resolvedURL.path) (executable: \(isExec ? "yes" : "no"))"
        }
    }

    func validateRoot(_ url: URL?) -> String? {
        guard let rootURL = url else { return nil }
        let expectedSubpaths = ["sdk", "host/fxr", "shared"]
        let missing = expectedSubpaths.filter { !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent($0).path) }
        return missing.isEmpty ? nil : "missing: \(missing.joined(separator: ", "))"
    }

    func scanOnce(with url: URL?) async throws -> [DotNetScanResult] {
        return try await DotNetScanner().scan(baseURL: url)
    }

    func performScanAttempt(targets: [URL?]) async -> (results: [DotNetScanResult], attempted: [String], error: String?) {
        var aggregated: [DotNetScanResult] = []
        var attemptedDescriptions: [String] = []

        do {
            for target in targets {
                var description = describeAttempt(target)
                if let note = validateRoot(target) {
                    description += " (\(note))"
                }
                attemptedDescriptions.append(description)

                let foundResults = try await scanOnce(with: target)
                aggregated.append(contentsOf: foundResults)
            }

            return (aggregated, attemptedDescriptions, nil)
        } catch {
            return ([], attemptedDescriptions, error.localizedDescription)
        }
    }

#if os(macOS)
    func requestAccessToCanonicalDotNetFolder() -> URL? {
        let canonicalURL = URL(fileURLWithPath: "/usr/local/share/dotnet", isDirectory: true)
        let panel = NSOpenPanel()
        panel.title = "Authorize access to .NET folder"
        panel.message = "Phase needs temporary access to /usr/local/share/dotnet to list installed SDKs, runtimes, and hosts."
        panel.prompt = "Authorize"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.directoryURL = canonicalURL
        panel.nameFieldStringValue = canonicalURL.lastPathComponent

        panel.showsHiddenFiles = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = true
        panel.validateVisibleColumns()

        if panel.runModal() == .OK {
            var selectedURL = panel.url
            // If the user confirmed the parent, coerce to the canonical child
            if selectedURL?.standardizedFileURL.path == canonicalURL.deletingLastPathComponent().standardizedFileURL.path {
                if FileManager.default.fileExists(atPath: canonicalURL.path) {
                    selectedURL = canonicalURL
                }
            }
            if let selectedURL, selectedURL.standardizedFileURL.path == canonicalURL.standardizedFileURL.path {
                return selectedURL
            } else {
                return nil
            }
        }
        return nil
    }
#endif

    func scan() {
        errorMessage = nil
        healthResults.removeAll()
        isScanning = true

        let initialTargets = buildScanTargets()

        Task {
            await fetchVersionCatalog()
            let firstPass = await performScanAttempt(targets: initialTargets)

            #if os(macOS)
            if firstPass.results.isEmpty {
                if let authorizedURL = requestAccessToCanonicalDotNetFolder() {
                    let secondPass = await performScanAttempt(targets: [authorizedURL])
                    await finalizeScan(scanPass: secondPass, allAttempts: firstPass.attempted + secondPass.attempted)
                    return
                }
            }
            #endif

            await finalizeScan(scanPass: firstPass, allAttempts: firstPass.attempted)
        }
    }
    
    func fetchVersionCatalog() async {
        do {
            let latestVersions = try await DotNetVersionService.shared.fetchLatestVersions()
            DotNetVersionCatalog.update(with: latestVersions)
            networkAvailable = true
        } catch {
            DotNetVersionCatalog.resetToFallback()
            networkAvailable = false
            print("Failed to fetch latest versions: \(error.localizedDescription)")
        }
    }
    
    func finalizeScan(scanPass: (results: [DotNetScanResult], attempted: [String], error: String?), allAttempts: [String]) async {
        await MainActor.run {
            let scanner = DotNetScanner()
            self.healthResults = scanner.analyzeHealth(from: scanPass.results)
            self.isScanning = false
            
            if !networkAvailable && !scanPass.results.isEmpty {
                self.errorMessage = "Network unavailable - showing installed versions only. Unable to check for updates."
            } else if scanPass.results.isEmpty {
                let attempts = allAttempts.joined(separator: ", ")
                let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "(nil PATH)"
                let errorPrefix = scanPass.error.map { "\($0)\n" } ?? ""
                self.errorMessage = "\(errorPrefix).NET installations not found. Tried: \(attempts)\nPATH=\(envPath)"
            }
        }
    }
}

struct HealthResultTile: View {
    let result: DotNetHealthResult
    
    var shouldShowBadge: Bool {
        result.label != "Other"
    }
    
    var statusIcon: String {
        switch result.status {
        case .healthy: "checkmark.circle.fill"
        case .outOfDate: "exclamationmark.triangle.fill"
        case .unsupported: "info.circle.fill"
        case .missing: "xmark.circle.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.displayName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if shouldShowBadge {
                        Text(result.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(result.badgeColor, in: Capsule())
                    }
                }
                
                Spacer()
            }
            
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(result.statusText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(result.status == .missing ? .secondary : result.status.color)
                }
                
                Spacer()
                
                Image(systemName: statusIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(result.status.color)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(result.status.backgroundColor)
                .shadow(color: result.status.color.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(result.status.color.opacity(0.3), lineWidth: 2)
        )
    }
}

#Preview {
    ContentView()
}

