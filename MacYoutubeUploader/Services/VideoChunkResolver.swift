import Foundation

struct VideoChunkResolver {
    func resolve(urls inputURLs: [URL]) -> [ResolvedUploadGroup] {
        let urls = expandDirectories(inputURLs)
            .filter(\.isSupportedVideoFile)
            .uniqued()

        let candidates = urls.map(ChunkCandidate.init(url:))
        let grouped = Dictionary(grouping: candidates) { candidate in
            candidate.matchKey ?? "single-\(candidate.url.path)"
        }

        return grouped.values
            .flatMap(splitIntoUploads)
            .sorted { lhs, rhs in
                let leftDate = lhs.sourceURLs.first?.bestFileDate ?? .distantPast
                let rightDate = rhs.sourceURLs.first?.bestFileDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate < rightDate
                }
                return (lhs.sourceURLs.first?.path ?? "") < (rhs.sourceURLs.first?.path ?? "")
            }
    }

    private func expandDirectories(_ urls: [URL]) -> [URL] {
        var output: [URL] = []

        for url in urls {
            if url.isDirectory {
                let children = (FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )?.compactMap { $0 as? URL }) ?? []
                output.append(contentsOf: children)
            } else {
                output.append(url)
            }
        }

        return output
    }

    private func splitIntoUploads(_ candidates: [ChunkCandidate]) -> [ResolvedUploadGroup] {
        let sorted = candidates.sorted { lhs, rhs in
            if let leftSequence = lhs.sequence, let rightSequence = rhs.sequence, leftSequence != rightSequence {
                return leftSequence < rightSequence
            }
            if lhs.sortDate != rhs.sortDate {
                return lhs.sortDate < rhs.sortDate
            }
            return lhs.url.path < rhs.url.path
        }

        guard sorted.count > 1, sorted.first?.matchKey != nil else {
            return sorted.map { candidate in
                ResolvedUploadGroup(sourceURLs: [candidate.url], titleSeed: candidate.titleSeed)
            }
        }

        var uploads: [[ChunkCandidate]] = []
        var current: [ChunkCandidate] = []

        for candidate in sorted {
            guard let previous = current.last else {
                current = [candidate]
                continue
            }

            let sequenceContinues: Bool
            if let previousSequence = previous.sequence, let sequence = candidate.sequence {
                sequenceContinues = sequence == previousSequence + 1
            } else {
                sequenceContinues = true
            }

            if sequenceContinues && previous.shouldContinueUpload(with: candidate) {
                current.append(candidate)
            } else {
                uploads.append(current)
                current = [candidate]
            }
        }

        if !current.isEmpty {
            uploads.append(current)
        }

        return uploads.map { group in
            let urls = group.map(\.url)
            let title = group.first?.titleSeed ?? urls.first?.deletingPathExtension().lastPathComponent ?? "Upload"
            return ResolvedUploadGroup(sourceURLs: urls, titleSeed: title)
        }
    }
}

private struct ChunkCandidate {
    var url: URL
    var matchKey: String?
    var sequence: Int?
    var continuityDate: Date?
    var pattern: ChunkPattern
    var maximumChunkGap: TimeInterval
    var titleSeed: String

    init(url: URL) {
        self.url = url
        let fileDate = url.bestFileDate
        self.continuityDate = fileDate == .distantPast ? nil : fileDate
        self.pattern = .numbered
        self.maximumChunkGap = ChunkPattern.numbered.maximumChunkGap

        let stem = url.deletingPathExtension().lastPathComponent
        if let dji = Self.djiMatch(stem: stem) {
            self.matchKey = "dji-\(url.deletingLastPathComponent().path)-\(dji.suffix ?? "standard")"
            self.sequence = dji.sequence
            self.continuityDate = dji.captureDate ?? continuityDate
            self.pattern = .dji
            self.maximumChunkGap = ChunkPattern.dji.maximumChunkGap
            self.titleSeed = dji.titleSeed
            return
        }

        if let goPro = Self.goProMatch(stem: stem) {
            self.matchKey = "gopro-\(url.deletingLastPathComponent().path)-\(goPro.identityPrefix)-\(goPro.clip)"
            self.sequence = goPro.sequence
            self.pattern = .goPro
            self.maximumChunkGap = ChunkPattern.goPro.maximumChunkGap
            self.titleSeed = goPro.titleSeed
            return
        }

        if let numbered = Self.trailingNumberMatch(stem: stem) {
            self.matchKey = "numbered-\(url.deletingLastPathComponent().path)-\(numbered.base)"
            self.sequence = numbered.sequence
            self.pattern = .numbered
            self.titleSeed = numbered.base
            return
        }

        self.matchKey = nil
        self.sequence = nil
        self.pattern = .single
        self.maximumChunkGap = ChunkPattern.single.maximumChunkGap
        self.titleSeed = stem
    }

    var sortDate: Date {
        continuityDate ?? .distantPast
    }

    func shouldContinueUpload(with next: ChunkCandidate) -> Bool {
        if pattern == .goPro, next.pattern == .goPro {
            return true
        }

        if isTimeContinuous(with: next) {
            return true
        }

        return isLikelyIntermediateChunk && isWithinChunkBoundaryWindow(of: next)
    }

    private var isLikelyIntermediateChunk: Bool {
        guard let fileSize = url.fileSize else {
            return false
        }
        return fileSize >= pattern.minimumIntermediateChunkSize
    }

    private func isTimeContinuous(with next: ChunkCandidate) -> Bool {
        guard let currentDate = continuityDate,
              let nextDate = next.continuityDate else {
            return true
        }

        let allowedGap = min(maximumChunkGap, next.maximumChunkGap)
        return abs(nextDate.timeIntervalSince(currentDate)) <= allowedGap
    }

    private func isWithinChunkBoundaryWindow(of next: ChunkCandidate) -> Bool {
        guard let currentDate = continuityDate,
              let nextDate = next.continuityDate else {
            return true
        }

        return abs(nextDate.timeIntervalSince(currentDate)) <= pattern.maximumChunkBoundaryGap
    }

    private static func djiMatch(stem: String) -> (sequence: Int, suffix: String?, titleSeed: String, captureDate: Date?)? {
        let pattern = #"^DJI_(\d{14})_(\d{3,5})(?:_([A-Za-z]))?$"#
        guard let result = stem.firstMatch(pattern: pattern),
              result.count >= 3,
              let sequence = Int(result[2]) else {
            return nil
        }

        let timestamp = result[1]
        let suffix = result.count > 3 ? result[3] : nil
        let titleSeed = ["DJI_\(timestamp)", suffix].compactMap { $0 }.joined(separator: "_")
        return (sequence, suffix, titleSeed, djiCaptureDate(from: timestamp))
    }

    private static func djiCaptureDate(from timestamp: String) -> Date? {
        guard timestamp.count == 14 else { return nil }

        func value(start: Int, length: Int) -> Int? {
            let lowerBound = timestamp.index(timestamp.startIndex, offsetBy: start)
            let upperBound = timestamp.index(lowerBound, offsetBy: length)
            return Int(timestamp[lowerBound..<upperBound])
        }

        guard let year = value(start: 0, length: 4),
              let month = value(start: 4, length: 2),
              let day = value(start: 6, length: 2),
              let hour = value(start: 8, length: 2),
              let minute = value(start: 10, length: 2),
              let second = value(start: 12, length: 2) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }

    private static func goProMatch(stem: String) -> (identityPrefix: String, sequence: Int, clip: String, titleSeed: String)? {
        let pattern = #"^(.*?)(G[HXLMP])(\d{2})(\d{4})$"#
        guard let result = stem.firstMatch(pattern: pattern),
              result.count == 5,
              let sequence = Int(result[3]) else {
            return goProClassicMatch(stem: stem)
        }

        let identityPrefix = result[1] + result[2]
        let clip = result[4]
        return (identityPrefix, sequence, clip, "\(identityPrefix)\(clip)")
    }

    private static func goProClassicMatch(stem: String) -> (identityPrefix: String, sequence: Int, clip: String, titleSeed: String)? {
        let pattern = #"^(.*?)GOPR(\d{4})$"#
        guard let result = stem.firstMatch(pattern: pattern),
              result.count == 3 else {
            return nil
        }

        let customPrefix = result[1]
        let clip = result[2]
        return ("\(customPrefix)GP", 0, clip, "\(customPrefix)GOPR\(clip)")
    }

    private static func trailingNumberMatch(stem: String) -> (base: String, sequence: Int)? {
        let pattern = #"^(.+?)[_\-. ]?(\d{3,5})$"#
        guard let result = stem.firstMatch(pattern: pattern),
              result.count == 3,
              let sequence = Int(result[2]) else {
            return nil
        }

        let base = result[1].trimmingCharacters(in: CharacterSet(charactersIn: "_-. "))
        guard !base.isEmpty else { return nil }
        return (base, sequence)
    }
}

private enum ChunkPattern {
    case dji
    case goPro
    case numbered
    case single

    var maximumChunkGap: TimeInterval {
        switch self {
        case .dji:
            return 45 * 60
        case .numbered:
            return 30 * 60
        case .goPro:
            return .infinity
        case .single:
            return 0
        }
    }

    var maximumChunkBoundaryGap: TimeInterval {
        switch self {
        case .dji, .numbered:
            return 2 * 60 * 60
        case .goPro:
            return .infinity
        case .single:
            return 0
        }
    }

    var minimumIntermediateChunkSize: Int64 {
        switch self {
        case .dji, .numbered:
            return Int64(3.5 * 1024 * 1024 * 1024)
        case .goPro, .single:
            return Int64.max
        }
    }
}

private extension String {
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let swiftRange = Range(match.range(at: index), in: self) else {
                return nil
            }
            return String(self[swiftRange])
        }
    }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }
}
