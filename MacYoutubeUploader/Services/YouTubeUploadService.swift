import Foundation

struct YouTubeUploadResult {
    var videoID: String?
    var playlistID: String?
    var playlistErrorDescription: String?

    var wasAddedToPlaylist: Bool {
        playlistID != nil && playlistErrorDescription == nil
    }
}

struct YouTubeUploadService {
    private let oauth: YouTubeOAuthService
    private let transport: YouTubeUploadTransport
    private let chunkSize: Int64
    private let maxResumeAttempts: Int
    private let resumeRetryDelayNanoseconds: UInt64
    private let refreshCoordinator: OAuthTokenRefreshCoordinator

    init(
        oauth: YouTubeOAuthService = YouTubeOAuthService(),
        transport: YouTubeUploadTransport = URLSessionYouTubeUploadTransport(),
        chunkSize: Int64 = 32 * 1024 * 1024,
        maxResumeAttempts: Int = 5,
        resumeRetryDelayNanoseconds: UInt64 = 1_000_000_000,
        refreshCoordinator: OAuthTokenRefreshCoordinator = .shared
    ) {
        self.oauth = oauth
        self.transport = transport
        self.chunkSize = chunkSize
        self.maxResumeAttempts = maxResumeAttempts
        self.resumeRetryDelayNanoseconds = resumeRetryDelayNanoseconds
        self.refreshCoordinator = refreshCoordinator
    }

    func upload(
        fileURL: URL,
        metadata: UploadMetadata,
        channel: AuthorizedChannel,
        playlistID: String? = nil,
        oauthConfig: OAuthClientConfig,
        resumeSessionURL: URL? = nil,
        onSessionEstablished: @escaping (URL) -> Void = { _ in },
        onProgress: @escaping (Double) -> Void,
        onCredentialsRefreshed: @escaping (OAuthCredentials) -> Void
    ) async throws -> YouTubeUploadResult {
        let credentials = try await freshCredentials(
            channel.credentials,
            channelID: channel.id,
            config: oauthConfig,
            onCredentialsRefreshed: onCredentialsRefreshed
        )
        let fileSize = try uploadFileSize(fileURL)

        var resumedSession: (location: URL, offset: Int64)?
        if let resumeSessionURL {
            switch try await probeExistingSession(
                resumeSessionURL,
                accessToken: credentials.accessToken,
                fileSize: fileSize
            ) {
            case .alive(let offset):
                resumedSession = (resumeSessionURL, offset)
            case .alreadyComplete(let data, _):
                // Every byte reached YouTube before the interruption; only
                // the bookkeeping after the upload is left to do.
                onProgress(1)
                return try await finishCompletedUpload(
                    data: data,
                    channel: channel,
                    playlistID: playlistID,
                    oauthConfig: oauthConfig,
                    credentials: credentials,
                    onCredentialsRefreshed: onCredentialsRefreshed
                )
            case .dead:
                resumedSession = nil
            }
        }

        let uploadLocation: URL
        let startOffset: Int64
        if let resumedSession {
            (uploadLocation, startOffset) = resumedSession
        } else {
            uploadLocation = try await initiateResumableSession(
                fileURL: fileURL,
                metadata: metadata,
                accessToken: credentials.accessToken
            )
            startOffset = 0
            onSessionEstablished(uploadLocation)
        }

        do {
            let (data, response) = try await uploadFile(
                fileURL: fileURL,
                uploadLocation: uploadLocation,
                accessToken: credentials.accessToken,
                startingAt: startOffset,
                onProgress: onProgress
            )
            try YouTubeOAuthService.validate(response: response, data: data)

            return try await finishCompletedUpload(
                data: data,
                channel: channel,
                playlistID: playlistID,
                oauthConfig: oauthConfig,
                credentials: credentials,
                onCredentialsRefreshed: onCredentialsRefreshed
            )
        } catch {
            await cancelResumableSession(uploadLocation, accessToken: credentials.accessToken)
            throw error
        }
    }

    private enum SessionProbe {
        case alive(offset: Int64)
        case alreadyComplete(Data, URLResponse)
        case dead
    }

    /// Asks YouTube how much of a previously started session it still holds
    /// (`Content-Range: bytes */<size>`). Any non-cancellation failure means
    /// the session is unusable and the upload restarts from a fresh session.
    private func probeExistingSession(
        _ uploadLocation: URL,
        accessToken: String,
        fileSize: Int64
    ) async throws -> SessionProbe {
        do {
            switch try await checkUploadStatus(
                uploadLocation: uploadLocation,
                accessToken: accessToken,
                fileSize: fileSize
            ) {
            case .completed(let data, let response):
                return .alreadyComplete(data, response)
            case .resume(let offset):
                return .alive(offset: offset)
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            return .dead
        }
    }

    private func finishCompletedUpload(
        data: Data,
        channel: AuthorizedChannel,
        playlistID: String?,
        oauthConfig: OAuthClientConfig,
        credentials: OAuthCredentials,
        onCredentialsRefreshed: @escaping (OAuthCredentials) -> Void
    ) async throws -> YouTubeUploadResult {
        let result = try? JSONDecoder().decode(VideoInsertResponse.self, from: data)
        var credentials = credentials
        if playlistID != nil {
            do {
                credentials = try await freshCredentials(
                    credentials,
                    channelID: channel.id,
                    config: oauthConfig,
                    onCredentialsRefreshed: onCredentialsRefreshed
                )
            } catch {
                return YouTubeUploadResult(
                    videoID: result?.id,
                    playlistID: playlistID,
                    playlistErrorDescription: error.localizedDescription
                )
            }
        }

        return await resultForCompletedUpload(
            videoID: result?.id,
            playlistID: playlistID,
            accessToken: credentials.accessToken
        )
    }

    private func freshCredentials(
        _ credentials: OAuthCredentials,
        channelID: String,
        config: OAuthClientConfig,
        onCredentialsRefreshed: (OAuthCredentials) -> Void
    ) async throws -> OAuthCredentials {
        let refresh = try await refreshCoordinator.refreshIfNeeded(
            credentials,
            channelID: channelID,
            config: config,
            oauth: oauth
        )
        if refresh.wasRefreshed {
            onCredentialsRefreshed(refresh.credentials)
        }
        return refresh.credentials
    }

    private func resultForCompletedUpload(
        videoID: String?,
        playlistID: String?,
        accessToken: String
    ) async -> YouTubeUploadResult {
        guard let playlistID else {
            return YouTubeUploadResult(videoID: videoID, playlistID: nil, playlistErrorDescription: nil)
        }

        guard let videoID, !videoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return YouTubeUploadResult(
                videoID: videoID,
                playlistID: playlistID,
                playlistErrorDescription: "YouTube did not return a video ID to add to the playlist."
            )
        }

        do {
            try await addVideo(videoID: videoID, toPlaylistID: playlistID, accessToken: accessToken)
            return YouTubeUploadResult(videoID: videoID, playlistID: playlistID, playlistErrorDescription: nil)
        } catch {
            return YouTubeUploadResult(
                videoID: videoID,
                playlistID: playlistID,
                playlistErrorDescription: error.localizedDescription
            )
        }
    }

    private func addVideo(
        videoID: String,
        toPlaylistID playlistID: String,
        accessToken: String
    ) async throws {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PlaylistItemInsertRequest(playlistID: playlistID, videoID: videoID))

        let (data, response) = try await transport.data(for: request)
        try YouTubeOAuthService.validate(response: response, data: data)
    }

    private func initiateResumableSession(
        fileURL: URL,
        metadata: UploadMetadata,
        accessToken: String
    ) async throws -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "part", value: "snippet,status")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.addValue(fileURL.probableVideoMimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.addValue("\(fileURL.fileSize ?? 0)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONEncoder().encode(VideoInsertRequest(metadata: metadata))

        let (data, response) = try await transport.data(for: request)
        try YouTubeOAuthService.validate(response: response, data: data)

        guard let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location) else {
            throw AppError.missingUploadLocation
        }

        return url
    }

    private func uploadFile(
        fileURL: URL,
        uploadLocation: URL,
        accessToken: String,
        startingAt startOffset: Int64 = 0,
        onProgress: @escaping (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let fileSize = try uploadFileSize(fileURL)
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var offset = min(max(startOffset, 0), fileSize)
        var resumeAttempts = 0
        var stalledResumes = 0
        onProgress(progress(forBytesUploaded: offset, fileSize: fileSize))

        func advance(to nextOffset: Int64) throws {
            if nextOffset > offset {
                stalledResumes = 0
            } else {
                stalledResumes += 1
                guard stalledResumes < maxResumeAttempts else {
                    throw AppError.server("YouTube kept requesting a resume without accepting any new video bytes.")
                }
            }
            offset = nextOffset
            onProgress(progress(forBytesUploaded: offset, fileSize: fileSize))
        }

        while offset < fileSize {
            try Task.checkCancellation()
            let chunkData = try readChunk(
                from: fileHandle,
                offset: offset,
                length: min(chunkSize, fileSize - offset)
            )

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await uploadChunk(
                    chunkData,
                    offset: offset,
                    fileSize: fileSize,
                    fileURL: fileURL,
                    uploadLocation: uploadLocation,
                    accessToken: accessToken,
                    onProgress: onProgress
                )
            } catch {
                guard canResume(after: error) else {
                    throw error
                }

                switch try await recoverUpload(
                    uploadLocation: uploadLocation,
                    accessToken: accessToken,
                    fileSize: fileSize,
                    resumeAttempts: &resumeAttempts,
                    lastError: error
                ) {
                case .completed(let data, let response):
                    onProgress(1)
                    return (data, response)
                case .resume(let nextOffset):
                    try advance(to: nextOffset)
                }
                continue
            }

            switch try await handleUploadResponse(
                data: data,
                response: response,
                uploadLocation: uploadLocation,
                accessToken: accessToken,
                fileSize: fileSize,
                resumeAttempts: &resumeAttempts
            ) {
            case .completed(let data, let response):
                onProgress(1)
                return (data, response)
            case .resume(let nextOffset):
                try advance(to: nextOffset)
            }
        }

        switch try await checkUploadStatus(
            uploadLocation: uploadLocation,
            accessToken: accessToken,
            fileSize: fileSize
        ) {
        case .completed(let data, let response):
            onProgress(1)
            return (data, response)
        case .resume:
            throw AppError.server("YouTube did not complete the upload after receiving the video bytes.")
        }
    }

    private func uploadFileSize(_ fileURL: URL) throws -> Int64 {
        guard let fileSize = fileURL.fileSize, fileSize > 0 else {
            throw AppError.server("The selected video file is empty or its size could not be read.")
        }
        return fileSize
    }

    private func readChunk(from fileHandle: FileHandle, offset: Int64, length: Int64) throws -> Data {
        try fileHandle.seek(toOffset: UInt64(offset))
        guard let data = try fileHandle.read(upToCount: Int(length)), !data.isEmpty else {
            throw AppError.server("The selected video file could not be read.")
        }
        return data
    }

    private func uploadChunk(
        _ data: Data,
        offset: Int64,
        fileSize: Int64,
        fileURL: URL,
        uploadLocation: URL,
        accessToken: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let lastByte = offset + Int64(data.count) - 1
        var request = URLRequest(url: uploadLocation)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(fileURL.probableVideoMimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes \(offset)-\(lastByte)/\(fileSize)", forHTTPHeaderField: "Content-Range")

        return try await transport.upload(request: request, from: data) { chunkProgress in
            let uploadedBytes = Double(offset) + (Double(data.count) * chunkProgress)
            onProgress(min(1, uploadedBytes / Double(fileSize)))
        }
    }

    private func handleUploadResponse(
        data: Data,
        response: URLResponse,
        uploadLocation: URL,
        accessToken: String,
        fileSize: Int64,
        resumeAttempts: inout Int
    ) async throws -> UploadRecovery {
        guard let http = response as? HTTPURLResponse else {
            resumeAttempts = 0
            return .completed(data, response)
        }

        if (200..<300).contains(http.statusCode) {
            resumeAttempts = 0
            return .completed(data, response)
        }

        if http.statusCode == 308 {
            resumeAttempts = 0
            return .resume(nextUploadOffset(from: http, fileSize: fileSize))
        }

        guard isRecoverableHTTPStatus(http.statusCode) else {
            try YouTubeOAuthService.validate(response: response, data: data)
            return .completed(data, response)
        }

        return try await recoverUpload(
            uploadLocation: uploadLocation,
            accessToken: accessToken,
            fileSize: fileSize,
            resumeAttempts: &resumeAttempts,
            lastError: AppError.invalidHTTPStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        )
    }

    private func recoverUpload(
        uploadLocation: URL,
        accessToken: String,
        fileSize: Int64,
        resumeAttempts: inout Int,
        lastError: Error
    ) async throws -> UploadRecovery {
        var currentError = lastError

        while resumeAttempts < maxResumeAttempts {
            resumeAttempts += 1
            try await sleepBeforeResumeRetry(attempt: resumeAttempts)

            do {
                return try await checkUploadStatus(
                    uploadLocation: uploadLocation,
                    accessToken: accessToken,
                    fileSize: fileSize
                )
            } catch {
                currentError = error
                guard canResume(after: error) else {
                    throw error
                }
            }
        }

        throw currentError
    }

    private func checkUploadStatus(
        uploadLocation: URL,
        accessToken: String,
        fileSize: Int64
    ) async throws -> UploadRecovery {
        var request = URLRequest(url: uploadLocation)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes */\(fileSize)", forHTTPHeaderField: "Content-Range")

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .completed(data, response)
        }

        if http.statusCode == 308 {
            return .resume(nextUploadOffset(from: http, fileSize: fileSize))
        }

        try YouTubeOAuthService.validate(response: response, data: data)
        return .completed(data, response)
    }

    private func nextUploadOffset(from response: HTTPURLResponse, fileSize: Int64) -> Int64 {
        // A 308 without a Range header means YouTube has not persisted any
        // bytes yet, so the upload restarts from zero. An unparseable or
        // out-of-bounds end offset is treated the same way instead of being
        // trusted (endOffset + 1 must not overflow Int64.max).
        guard let range = response.value(forHTTPHeaderField: "Range"),
              let endText = range.split(separator: "-").last,
              let endOffset = Int64(endText),
              endOffset >= 0,
              endOffset < Int64.max else {
            return 0
        }

        return min(fileSize, endOffset + 1)
    }

    private func progress(forBytesUploaded bytesUploaded: Int64, fileSize: Int64) -> Double {
        min(1, max(0, Double(bytesUploaded) / Double(fileSize)))
    }

    private func canResume(after error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if (error as? URLError)?.code == .cancelled {
            return false
        }
        if case AppError.invalidHTTPStatus(let status, _) = error {
            return isRecoverableHTTPStatus(status)
        }
        return true
    }

    private func isRecoverableHTTPStatus(_ status: Int) -> Bool {
        [500, 502, 503, 504].contains(status)
    }

    private func sleepBeforeResumeRetry(attempt: Int) async throws {
        guard resumeRetryDelayNanoseconds > 0 else { return }
        let multiplier = UInt64(1 << min(max(attempt - 1, 0), 4))
        try await Task.sleep(nanoseconds: resumeRetryDelayNanoseconds * multiplier)
    }

    private func cancelResumableSession(_ uploadLocation: URL, accessToken: String) async {
        var request = URLRequest(url: uploadLocation)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        _ = try? await transport.data(for: request)
    }
}

private enum UploadRecovery {
    case completed(Data, URLResponse)
    case resume(Int64)
}

protocol YouTubeUploadTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

    func upload(
        request: URLRequest,
        from data: Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> (Data, URLResponse)
}

struct URLSessionYouTubeUploadTransport: YouTubeUploadTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    func upload(
        request: URLRequest,
        from data: Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        return try await delegate.upload(request: request, from: data)
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let onProgress: (Double) -> Void
    private var session: URLSession?
    private var task: URLSessionUploadTask?
    private var responseData = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func upload(request: URLRequest, from data: Data) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                configuration.allowsConstrainedNetworkAccess = true
                configuration.allowsExpensiveNetworkAccess = true
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.uploadTask(with: request, from: data)
                self.task = task
                task.resume()
            }
        } onCancel: {
            task?.cancel()
            session?.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        responseData.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            session.invalidateAndCancel()
            self.session = nil
            self.task = nil
            self.continuation = nil
        }

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        guard let response = task.response else {
            continuation?.resume(throwing: AppError.server("Upload completed without an HTTP response."))
            return
        }

        continuation?.resume(returning: (responseData, response))
    }
}

private struct VideoInsertRequest: Encodable {
    var snippet: Snippet
    var status: Status

    init(metadata: UploadMetadata) {
        self.snippet = Snippet(
            title: metadata.title,
            description: metadata.description,
            tags: metadata.tags,
            categoryId: metadata.categoryID
        )
        self.status = Status(
            privacyStatus: metadata.privacy.rawValue,
            embeddable: metadata.allowEmbedding,
            selfDeclaredMadeForKids: metadata.madeForKids
        )
    }

    struct Snippet: Encodable {
        var title: String
        var description: String
        var tags: [String]
        var categoryId: String
    }

    struct Status: Encodable {
        var privacyStatus: String
        var embeddable: Bool
        var selfDeclaredMadeForKids: Bool
    }
}

private struct VideoInsertResponse: Decodable {
    var id: String?
}

private struct PlaylistItemInsertRequest: Encodable {
    var snippet: Snippet

    init(playlistID: String, videoID: String) {
        self.snippet = Snippet(
            playlistId: playlistID,
            resourceId: ResourceID(kind: "youtube#video", videoId: videoID)
        )
    }

    struct Snippet: Encodable {
        var playlistId: String
        var resourceId: ResourceID
    }

    struct ResourceID: Encodable {
        var kind: String
        var videoId: String
    }
}
