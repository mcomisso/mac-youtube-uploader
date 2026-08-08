import Foundation

/// Creates and resolves security-scoped bookmarks so user-selected video
/// files remain readable across relaunches under App Sandbox
/// (ENABLE_USER_SELECTED_FILES = readonly).
enum SecurityScopedBookmark {
    struct Resolution {
        var url: URL
        var didStartAccessing: Bool
        /// A replacement bookmark when the stored one was stale.
        var refreshedBookmark: Data?
    }

    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a stored bookmark and starts security-scoped access. Callers
    /// own the access and must balance it with
    /// `stopAccessingSecurityScopedResource()` when the file is no longer
    /// needed.
    static func resolveAndStartAccessing(_ bookmark: Data) -> Resolution? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        return Resolution(
            url: url,
            didStartAccessing: didStartAccessing,
            refreshedBookmark: isStale ? bookmarkData(for: url) : nil
        )
    }
}
