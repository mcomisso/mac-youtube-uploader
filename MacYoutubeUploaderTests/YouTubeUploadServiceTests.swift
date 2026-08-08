import XCTest
@testable import MacYoutubeUploader

final class YouTubeUploadServiceTests: XCTestCase {
    func testResumesUploadAfterRecoverableServerError() async throws {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=test")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<10))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, headers: ["Location": uploadURL.absoluteString]),
                .response(statusCode: 308, headers: ["Range": "bytes=0-5"])
            ],
            uploadResults: [
                .response(statusCode: 308, headers: ["Range": "bytes=0-3"]),
                .response(statusCode: 503),
                .response(statusCode: 201, body: #"{"id":"video123"}"#)
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 4,
            resumeRetryDelayNanoseconds: 0
        )

        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            onProgress: { _ in },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")
        XCTAssertEqual(
            transport.uploadRequests.map { $0.request.value(forHTTPHeaderField: "Content-Range") },
            ["bytes 0-3/10", "bytes 4-7/10", "bytes 6-9/10"]
        )
        XCTAssertEqual(transport.uploadRequests.map(\.data), [
            Data([0, 1, 2, 3]),
            Data([4, 5, 6, 7]),
            Data([6, 7, 8, 9])
        ])
        XCTAssertEqual(transport.dataRequests[1].httpMethod, "PUT")
        XCTAssertEqual(transport.dataRequests[1].value(forHTTPHeaderField: "Content-Range"), "bytes */10")
        XCTAssertFalse(transport.dataRequests.contains { $0.httpMethod == "DELETE" })
    }

    func testCancelsResumableSessionAfterPermanentFailure() async throws {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=failed")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<10))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, headers: ["Location": uploadURL.absoluteString]),
                .response(statusCode: 200)
            ],
            uploadResults: [
                .response(statusCode: 400, body: "bad request")
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        do {
            _ = try await service.upload(
                fileURL: fileURL,
                metadata: makeMetadata(),
                channel: makeChannel(),
                oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
                onProgress: { _ in },
                onCredentialsRefreshed: { _ in }
            )
            XCTFail("Expected upload to fail")
        } catch AppError.invalidHTTPStatus(let status, let body) {
            XCTAssertEqual(status, 400)
            XCTAssertEqual(body, "bad request")
        }

        XCTAssertEqual(transport.dataRequests.last?.httpMethod, "DELETE")
        XCTAssertEqual(transport.dataRequests.last?.url, uploadURL)
        XCTAssertEqual(transport.dataRequests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testAddsUploadedVideoToPlaylist() async throws {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=playlist")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<4))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, headers: ["Location": uploadURL.absoluteString]),
                .response(statusCode: 200, body: #"{"id":"playlist-item"}"#)
            ],
            uploadResults: [
                .response(statusCode: 201, body: #"{"id":"video123"}"#)
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            playlistID: "playlist123",
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            onProgress: { _ in },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")
        XCTAssertEqual(result.playlistID, "playlist123")
        XCTAssertTrue(result.wasAddedToPlaylist)
        XCTAssertNil(result.playlistErrorDescription)

        let playlistRequest = transport.dataRequests[1]
        XCTAssertEqual(playlistRequest.httpMethod, "POST")
        XCTAssertEqual(playlistRequest.url?.scheme, "https")
        XCTAssertEqual(playlistRequest.url?.host, "www.googleapis.com")
        XCTAssertEqual(playlistRequest.url?.path, "/youtube/v3/playlistItems")
        XCTAssertEqual(playlistRequest.url?.query, "part=snippet")
        XCTAssertEqual(playlistRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(playlistRequest.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=UTF-8")

        let body = try XCTUnwrap(playlistRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let snippet = try XCTUnwrap(json["snippet"] as? [String: Any])
        let resourceID = try XCTUnwrap(snippet["resourceId"] as? [String: Any])
        XCTAssertEqual(snippet["playlistId"] as? String, "playlist123")
        XCTAssertEqual(resourceID["kind"] as? String, "youtube#video")
        XCTAssertEqual(resourceID["videoId"] as? String, "video123")
    }

    func testFailsWhenResumeOffsetStopsAdvancing() async throws {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stalled")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, headers: ["Location": uploadURL.absoluteString]),
                .response(statusCode: 200)
            ],
            uploadResults: [
                .response(statusCode: 308, headers: ["Range": "bytes=0-1"]),
                .response(statusCode: 308, headers: ["Range": "bytes=0-1"]),
                .response(statusCode: 308, headers: ["Range": "bytes=0-1"])
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 4,
            maxResumeAttempts: 2,
            resumeRetryDelayNanoseconds: 0
        )

        do {
            _ = try await service.upload(
                fileURL: fileURL,
                metadata: makeMetadata(),
                channel: makeChannel(),
                oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
                onProgress: { _ in },
                onCredentialsRefreshed: { _ in }
            )
            XCTFail("Expected upload to fail after repeated resumes without progress")
        } catch AppError.server {
            // Expected: the upload gives up instead of looping forever.
        }

        XCTAssertEqual(transport.dataRequests.last?.httpMethod, "DELETE")
        XCTAssertEqual(transport.dataRequests.last?.url, uploadURL)
    }

    func testRestartsFromZeroWhenRangeHeaderIsUnusable() async throws {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=overflow")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<4))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, headers: ["Location": uploadURL.absoluteString])
            ],
            uploadResults: [
                .response(statusCode: 308, headers: ["Range": "bytes=0-\(Int64.max)"]),
                .response(statusCode: 201, body: #"{"id":"video123"}"#)
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            onProgress: { _ in },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")
        XCTAssertEqual(
            transport.uploadRequests.map { $0.request.value(forHTTPHeaderField: "Content-Range") },
            ["bytes 0-3/4", "bytes 0-3/4"]
        )
    }

    func testCompletesUploadWithPlaylistWarningWhenPlaylistInsertFails() async throws {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=playlist-warning")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<4))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, headers: ["Location": uploadURL.absoluteString]),
                .response(statusCode: 403, body: "missing playlist scope")
            ],
            uploadResults: [
                .response(statusCode: 201, body: #"{"id":"video123"}"#)
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            playlistID: "playlist123",
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            onProgress: { _ in },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")
        XCTAssertEqual(result.playlistID, "playlist123")
        XCTAssertFalse(result.wasAddedToPlaylist)
        XCTAssertEqual(result.playlistErrorDescription, "YouTube returned HTTP 403. missing playlist scope")
        XCTAssertFalse(transport.dataRequests.contains { $0.httpMethod == "DELETE" })
    }

    func testResumesFromStoredSessionAtServerReportedOffset() async throws {
        let storedSession = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stored")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<10))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 308, headers: ["Range": "bytes=0-5"])
            ],
            uploadResults: [
                .response(statusCode: 201, body: #"{"id":"video123"}"#)
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        var establishedSessions: [URL] = []
        var progressValues: [Double] = []
        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            resumeSessionURL: storedSession,
            onSessionEstablished: { establishedSessions.append($0) },
            onProgress: { progressValues.append($0) },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")

        // The only data request is the status probe against the stored
        // session; no new session was initiated.
        XCTAssertEqual(transport.dataRequests.count, 1)
        XCTAssertEqual(transport.dataRequests[0].url, storedSession)
        XCTAssertEqual(transport.dataRequests[0].httpMethod, "PUT")
        XCTAssertEqual(transport.dataRequests[0].value(forHTTPHeaderField: "Content-Range"), "bytes */10")
        XCTAssertTrue(establishedSessions.isEmpty)

        XCTAssertEqual(transport.uploadRequests.map(\.request.url), [storedSession])
        XCTAssertEqual(
            transport.uploadRequests.map { $0.request.value(forHTTPHeaderField: "Content-Range") },
            ["bytes 6-9/10"]
        )
        XCTAssertEqual(transport.uploadRequests.map(\.data), [Data([6, 7, 8, 9])])
        XCTAssertEqual(progressValues.first, 0.6)
    }

    func testStartsFreshSessionWhenStoredSessionIsDead() async throws {
        let storedSession = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=expired")!
        let freshSession = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=fresh")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<10))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 404, body: "session expired"),
                .response(statusCode: 200, headers: ["Location": freshSession.absoluteString])
            ],
            uploadResults: [
                .response(statusCode: 201, body: #"{"id":"video123"}"#)
            ]
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        var establishedSessions: [URL] = []
        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            resumeSessionURL: storedSession,
            onSessionEstablished: { establishedSessions.append($0) },
            onProgress: { _ in },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")
        XCTAssertEqual(establishedSessions, [freshSession])
        XCTAssertEqual(transport.dataRequests[0].url, storedSession)
        XCTAssertEqual(transport.dataRequests[1].httpMethod, "POST")
        XCTAssertEqual(transport.uploadRequests.map(\.request.url), [freshSession])
        XCTAssertEqual(
            transport.uploadRequests.map { $0.request.value(forHTTPHeaderField: "Content-Range") },
            ["bytes 0-9/10"]
        )
    }

    func testReturnsResultWithoutUploadingWhenStoredSessionAlreadyCompleted() async throws {
        let storedSession = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=done")!
        let fileURL = try makeTemporaryVideo(bytes: Array(0..<10))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transport = MockYouTubeUploadTransport(
            dataResults: [
                .response(statusCode: 200, body: #"{"id":"video123"}"#)
            ],
            uploadResults: []
        )
        let service = YouTubeUploadService(
            transport: transport,
            chunkSize: 32,
            resumeRetryDelayNanoseconds: 0
        )

        var progressValues: [Double] = []
        let result = try await service.upload(
            fileURL: fileURL,
            metadata: makeMetadata(),
            channel: makeChannel(),
            oauthConfig: OAuthClientConfig(clientID: "client", clientSecret: ""),
            resumeSessionURL: storedSession,
            onProgress: { progressValues.append($0) },
            onCredentialsRefreshed: { _ in }
        )

        XCTAssertEqual(result.videoID, "video123")
        XCTAssertTrue(transport.uploadRequests.isEmpty)
        XCTAssertEqual(transport.dataRequests.count, 1)
        XCTAssertEqual(progressValues, [1])
    }
}

private final class MockYouTubeUploadTransport: YouTubeUploadTransport {
    enum Result {
        case response(statusCode: Int, headers: [String: String] = [:], body: String = "")
        case failure(Error)
    }

    private var dataResults: [Result]
    private var uploadResults: [Result]
    private(set) var dataRequests: [URLRequest] = []
    private(set) var uploadRequests: [(request: URLRequest, data: Data)] = []

    init(dataResults: [Result], uploadResults: [Result]) {
        self.dataResults = dataResults
        self.uploadResults = uploadResults
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        dataRequests.append(request)
        return try resolve(dataResults.removeFirst(), request: request)
    }

    func upload(
        request: URLRequest,
        from data: Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        uploadRequests.append((request, data))
        onProgress(1)
        return try resolve(uploadResults.removeFirst(), request: request)
    }

    private func resolve(_ result: Result, request: URLRequest) throws -> (Data, URLResponse) {
        switch result {
        case .response(let statusCode, let headers, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        }
    }
}

private func makeTemporaryVideo(bytes: [UInt8]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")
    try Data(bytes).write(to: url)
    return url
}

private func makeMetadata() -> UploadMetadata {
    UploadMetadata(
        title: "Test video",
        description: "",
        tags: [],
        categoryID: "22",
        privacy: .private,
        madeForKids: false,
        allowEmbedding: true
    )
}

private func makeChannel() -> AuthorizedChannel {
    AuthorizedChannel(
        id: "channel",
        title: "Channel",
        handle: nil,
        thumbnailURL: nil,
        credentials: OAuthCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        )
    )
}
