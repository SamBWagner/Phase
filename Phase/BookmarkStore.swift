import Foundation

#if os(macOS)
import AppKit
#endif

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let bookmarkKey = "dotnetFolderBookmarkData"
    private var currentURL: URL?
    private var hasActiveAccess = false

    private init() {}

    func resolvedURL() -> URL? {
        if let currentURL { return currentURL }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: data,
                               options: [.withSecurityScope],
                               relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
            if isStale {
                try save(url: url)
            }
            currentURL = url
            return url
            #else
            return nil
            #endif
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    func save(url: URL) throws {
        #if os(macOS)
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        currentURL = url
        #else
        UserDefaults.standard.set(url.path, forKey: bookmarkKey)
        currentURL = url
        #endif
    }

    @discardableResult
    func startAccessing(url: URL) -> Bool? {
        #if os(macOS)
        guard !hasActiveAccess else { return true }
        let started = url.startAccessingSecurityScopedResource()
        hasActiveAccess = started
        return started
        #else
        return true
        #endif
    }

    func stopAccessing() {
        #if os(macOS)
        guard hasActiveAccess, let url = currentURL else { return }
        url.stopAccessingSecurityScopedResource()
        hasActiveAccess = false
        #endif
    }
}
