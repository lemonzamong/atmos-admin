import Foundation

struct AdminAPIClient {
    var baseURL: URL { AdminServerConfiguration.baseURL }
    private var session: URLSession { Self.uploadSession }

    private static let uploadSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func upload(
        buildingName: String,
        address: String,
        manifest: ScanManifestValue,
        keyframes: [CapturedKeyframe]
    ) async throws -> UploadedScanResult {
        let normalizedName = buildingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !normalizedAddress.isEmpty else {
            throw APIError.invalidBuildingInfo
        }
        let building: BuildingRecord = try await request(
            path: "/v1/buildings",
            method: "POST",
            body: BuildingCreate(
                name: normalizedName,
                address: normalizedAddress,
                latitude: manifest.latitude?.validLatitude,
                longitude: manifest.longitude?.validLongitude,
                horizontalAccuracyM: manifest.horizontalAccuracyM?.validHorizontalAccuracy
            ),
            retryCount: 0
        )
        var serverManifest = manifest
        serverManifest.buildingId = building.id
        let receipt: ScanReceipt = try await request(
            path: "/v1/buildings/\(building.id.uuidString)/scans",
            method: "POST",
            headers: ["X-Atmos-Device-Id": PushNotificationManager.shared.deviceID],
            body: serverManifest,
            retryCount: 2
        )
        for keyframe in keyframes {
            try await uploadKeyframe(
                buildingID: building.id,
                sessionID: serverManifest.sessionId,
                keyframe: keyframe
            )
            if let depthURL = keyframe.depthFileURL {
                try await uploadDepth(
                    buildingID: building.id,
                    sessionID: serverManifest.sessionId,
                    frameID: keyframe.metadata.id,
                    fileURL: depthURL
                )
            }
        }
        return UploadedScanResult(buildingId: building.id, sessionId: serverManifest.sessionId, receipt: receipt)
    }

    func registerPushToken(_ registration: PushTokenRegistrationValue) async throws {
        let _: PushTokenRegistrationResponse = try await request(
            path: "/v1/admin/devices/push-token",
            method: "POST",
            body: registration
        )
    }

    func systemStatus() async throws -> AdminSystemStatusValue {
        let request = URLRequest(url: baseURL.appending(path: "/v1/admin/system-status"))
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AdminSystemStatusValue.self, from: data)
    }

    private func uploadDepth(buildingID: UUID, sessionID: UUID, frameID: String, fileURL: URL) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/depth/\(frameID)"))
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        configureNetworkStabilityHeaders(&request)
        let (data, response) = try await performUpload(request, fromFile: fileURL, retryCount: 2)
        try validate(response: response, data: data)
    }

    func processingJob(id: UUID) async throws -> ProcessingJobValue {
        let request = URLRequest(url: baseURL.appending(path: "/v1/processing-jobs/\(id.uuidString)"))
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProcessingJobValue.self, from: data)
    }

    func processingJobs(status: String? = nil) async throws -> [ProcessingJobValue] {
        var components = URLComponents(url: baseURL.appending(path: "/v1/processing-jobs"), resolvingAgainstBaseURL: false)!
        if let status {
            components.queryItems = [URLQueryItem(name: "status", value: status)]
        }
        let request = URLRequest(url: components.url!)
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ProcessingJobValue].self, from: data)
    }

    func sceneGraph(buildingID: UUID, sessionID: UUID) async throws -> SceneGraphValue {
        let request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/scene-graph"))
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SceneGraphValue.self, from: data)
    }

    func publish(buildingID: UUID, sessionID: UUID) async throws -> PublishReceiptValue {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/publish"))
        request.httpMethod = "POST"
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PublishReceiptValue.self, from: data)
    }

    func packageVersions(buildingID: UUID) async throws -> [PackageVersionInfoValue] {
        let request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/package/versions"))
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PackageVersionInfoValue].self, from: data)
    }

    func rollbackPackage(buildingID: UUID, version: Int) async throws -> PublishReceiptValue {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/package/rollback/\(version)"))
        request.httpMethod = "POST"
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PublishReceiptValue.self, from: data)
    }

    func unpublishPackage(buildingID: UUID) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/package"))
        request.httpMethod = "DELETE"
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
    }

    func updateSceneNode(
        buildingID: UUID,
        sessionID: UUID,
        nodeID: String,
        patch: SceneNodeReviewPatch
    ) async throws -> SceneGraphValue {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/scene-graph/nodes/\(nodeID)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(patch)
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SceneGraphValue.self, from: data)
    }

    func updateSceneRelation(
        buildingID: UUID,
        sessionID: UUID,
        relation: SceneGraphRelationValue,
        reviewStatus: String
    ) async throws -> SceneGraphValue {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/scene-graph/relations"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            SceneRelationReviewPatch(
                sourceId: relation.sourceId,
                targetId: relation.targetId,
                predicate: relation.predicate,
                reviewStatus: reviewStatus,
                accessible: nil
            )
        )
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SceneGraphValue.self, from: data)
    }

    func updateSceneRelationAccessibility(
        buildingID: UUID,
        sessionID: UUID,
        relation: SceneGraphRelationValue,
        reviewStatus: String,
        accessible: Bool
    ) async throws -> SceneGraphValue {
        var request = URLRequest(url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/scene-graph/relations"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            SceneRelationReviewPatch(
                sourceId: relation.sourceId,
                targetId: relation.targetId,
                predicate: relation.predicate,
                reviewStatus: reviewStatus,
                accessible: accessible
            )
        )
        let (data, response) = try await performData(request, retryCount: 2)
        try validate(response: response, data: data)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SceneGraphValue.self, from: data)
    }

    private func uploadKeyframe(
        buildingID: UUID,
        sessionID: UUID,
        keyframe: CapturedKeyframe
    ) async throws {
        var request = URLRequest(
            url: baseURL.appending(path: "/v1/buildings/\(buildingID.uuidString)/scans/\(sessionID.uuidString)/keyframes/\(keyframe.metadata.id)")
        )
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let data = try Data(contentsOf: keyframe.fileURL)
        configureNetworkStabilityHeaders(&request)
        let (responseData, response) = try await performUpload(request, from: data, retryCount: 2)
        try validate(response: response, data: responseData)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        headers: [String: String] = [:],
        body: Body,
        retryCount: Int = 1
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configureNetworkStabilityHeaders(&request)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performData(request, retryCount: retryCount)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }

    private func configureNetworkStabilityHeaders(_ request: inout URLRequest) {
        request.timeoutInterval = 120
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("AtmosAdmin/scan-upload", forHTTPHeaderField: "User-Agent")
    }

    private func performData(_ request: URLRequest, retryCount: Int) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                var configuredRequest = request
                configureNetworkStabilityHeaders(&configuredRequest)
                return try await session.data(for: configuredRequest)
            } catch {
                guard attempt < retryCount, error.isTransientNetworkError else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(350_000_000 * attempt))
            }
        }
    }

    private func performUpload(_ request: URLRequest, from data: Data, retryCount: Int) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                var configuredRequest = request
                configureNetworkStabilityHeaders(&configuredRequest)
                return try await session.upload(for: configuredRequest, from: data)
            } catch {
                guard attempt < retryCount, error.isTransientNetworkError else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(500_000_000 * attempt))
            }
        }
    }

    private func performUpload(_ request: URLRequest, fromFile fileURL: URL, retryCount: Int) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                var configuredRequest = request
                configureNetworkStabilityHeaders(&configuredRequest)
                return try await session.upload(for: configuredRequest, fromFile: fileURL)
            } catch {
                guard attempt < retryCount, error.isTransientNetworkError else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(500_000_000 * attempt))
            }
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let detail = ServerErrorPayload.decodeMessage(from: data)
            throw APIError.serverMessage(statusCode: http.statusCode, detail: detail)
        }
    }
}

enum AdminServerConfiguration {
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ATMOS_API_BASE_URL") as? String,
           let url = URL(string: value), !value.isEmpty { return url }
        return URL(string: "https://riav.duckdns.org")!
    }

    static var baseURLString: String {
        defaultBaseURLString
    }

    static var defaultBaseURLString: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ATMOS_API_BASE_URL") as? String,
           !value.isEmpty {
            return value
        }
        return "https://riav.duckdns.org"
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case serverMessage(statusCode: Int, detail: String?)
    case processingFailed(String)
    case invalidBuildingInfo

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "서버가 요청을 처리하지 못했습니다. 네트워크 상태와 운영 서버 상태를 확인해 주세요."
        case .serverMessage(let statusCode, let detail):
            if let detail, !detail.isEmpty {
                "서버 오류 \(statusCode): \(detail)"
            } else {
                "서버 오류 \(statusCode): 요청을 처리하지 못했습니다."
            }
        case .processingFailed(let message): message
        case .invalidBuildingInfo:
            "건물 이름과 주소를 먼저 입력해 주세요."
        }
    }
}

private enum ServerErrorPayload: Decodable {
    case message(String)
    case validation([ValidationErrorPayload])
    case unknown

    private enum CodingKeys: String, CodingKey {
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let message = try? container.decode(String.self, forKey: .detail) {
            self = .message(message)
            return
        }
        if let errors = try? container.decode([ValidationErrorPayload].self, forKey: .detail) {
            self = .validation(errors)
            return
        }
        self = .unknown
    }

    static func decodeMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data) {
            switch payload {
            case .message(let message):
                return message
            case .validation(let errors):
                return errors.map(\.displayMessage).joined(separator: " / ")
            case .unknown:
                break
            }
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct ValidationErrorPayload: Decodable {
    let loc: [Location]
    let msg: String
    let type: String?

    var displayMessage: String {
        let location = loc.map(\.description).joined(separator: ".")
        if location.isEmpty {
            return msg
        }
        return "\(location): \(msg)"
    }

    enum Location: Decodable, CustomStringConvertible {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                self = .int(try container.decode(Int.self))
            }
        }

        var description: String {
            switch self {
            case .string(let value): value
            case .int(let value): String(value)
            }
        }
    }
}

private extension Double {
    var validLatitude: Double? {
        guard isFinite, (-90.0...90.0).contains(self) else { return nil }
        return self
    }

    var validLongitude: Double? {
        guard isFinite, (-180.0...180.0).contains(self) else { return nil }
        return self
    }

    var validHorizontalAccuracy: Double? {
        guard isFinite, self >= 0 else { return nil }
        return self
    }
}

private extension Error {
    var isTransientNetworkError: Bool {
        guard let urlError = self as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable,
             .backgroundSessionWasDisconnected:
            return true
        default:
            return false
        }
    }
}
