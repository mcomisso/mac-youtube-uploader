import Foundation

enum PrivacyStatus: String, CaseIterable, Codable, Identifiable {
    case `private`
    case unlisted
    case `public`

    var id: String { rawValue }

    var label: String {
        switch self {
        case .private: "Private"
        case .unlisted: "Unlisted"
        case .public: "Public"
        }
    }
}

enum KidsSafetySelection: String, CaseIterable, Codable, Identifiable {
    case notMadeForKids
    case madeForKids

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notMadeForKids: "No, it is not made for kids"
        case .madeForKids: "Yes, it is made for kids"
        }
    }

    var apiValue: Bool {
        self == .madeForKids
    }
}

struct YouTubeCategory: Identifiable, Hashable {
    let id: String
    let name: String

    static let defaults: [YouTubeCategory] = [
        .init(id: "22", name: "People & Blogs"),
        .init(id: "24", name: "Entertainment"),
        .init(id: "19", name: "Travel & Events"),
        .init(id: "27", name: "Education"),
        .init(id: "28", name: "Science & Technology"),
        .init(id: "26", name: "Howto & Style"),
        .init(id: "20", name: "Gaming"),
        .init(id: "10", name: "Music"),
        .init(id: "17", name: "Sports"),
        .init(id: "2", name: "Autos & Vehicles")
    ]

    static func name(for id: String) -> String {
        defaults.first(where: { $0.id == id })?.name ?? "People & Blogs"
    }
}

struct MetadataDefaults: Codable, Equatable {
    var privacy: PrivacyStatus = .private
    var titleTemplate: String = "{filename}"
    var descriptionTemplate: String = ""
    var tags: [String] = []
    var categoryID: String = "22"
    var kidsSafety: KidsSafetySelection = .notMadeForKids
    var allowEmbedding: Bool = true

    func uploadMetadata(for titleSeed: String) -> UploadMetadata {
        let title = titleTemplate
            .replacingOccurrences(of: "{filename}", with: titleSeed)
            .replacingOccurrences(of: "{date}", with: Self.dateFormatter.string(from: Date()))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return UploadMetadata(
            title: title.isEmpty ? titleSeed : title,
            description: descriptionTemplate,
            tags: tags,
            categoryID: categoryID,
            privacy: privacy,
            madeForKids: kidsSafety.apiValue,
            allowEmbedding: allowEmbedding
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct UploadMetadata: Codable, Equatable {
    var title: String
    var description: String
    var tags: [String]
    var categoryID: String
    var privacy: PrivacyStatus
    var madeForKids: Bool
    var allowEmbedding: Bool
}
