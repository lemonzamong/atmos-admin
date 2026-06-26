import Foundation

struct BuildingCreate: Encodable {
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracyM: Double?
}

struct BuildingRecord: Decodable {
    let id: UUID
    let name: String
    let address: String
    let version: Int?
    let status: String?
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracyM: Double?
}

struct Vector3Value: Codable {
    let x: Float
    let y: Float
    let z: Float
}

struct QuaternionValue: Codable {
    let x: Float
    let y: Float
    let z: Float
    let w: Float
}

struct CameraIntrinsicsValue: Codable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let imageWidth: Int
    let imageHeight: Int
}

struct PoseSampleValue: Codable {
    let timestamp: TimeInterval
    let translation: Vector3Value
    let rotation: QuaternionValue
    let trackingState: String
    let intrinsics: CameraIntrinsicsValue
    let featurePointCount: Int?
    let ambientIntensity: Double?
    let motionSpeedMps: Double?
    let angularSpeedDps: Double?
    let trackingQuality: Double?
    let magneticFieldX: Double?
    let magneticFieldY: Double?
    let magneticFieldZ: Double?
    let magneticFieldAccuracy: Int?
    let pressureKpa: Double?
    let relativeAltitudeM: Double?
}

struct KeyframeMetadataValue: Codable {
    let id: String
    let timestamp: TimeInterval
    let poseSampleTimestamp: TimeInterval
    let filename: String
    let contentType: String
    let byteCount: Int
    let depthWidth: Int?
    let depthHeight: Int?
    let depthByteCount: Int?
    let selectionReason: String?
    let selectionScore: Double?
    let displacementM: Double?
    let rotationDeltaDegrees: Double?
}

struct CapturedKeyframe {
    let metadata: KeyframeMetadataValue
    let fileURL: URL
    let depthFileURL: URL?
}

struct ScanManifestValue: Codable {
    let schemaVersion: Int
    let sessionId: UUID
    var buildingId: UUID
    let floorId: String
    let mapNorthDegrees: Double
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracyM: Double?
    let startedAt: Date
    let endedAt: Date
    let deviceModel: String
    let supportsSceneDepth: Bool
    let totalDistanceM: Double
    let samples: [PoseSampleValue]
    let keyframes: [KeyframeMetadataValue]
    let spatialSamples: [Vector3Value]?
    let meshAnchorCount: Int?
    let planeAnchorCount: Int?
    let meshVertexCount: Int?
    let datasetSchemaVersion: Int?
    let capturePurpose: String?
    let privacyMode: String?
    let physicalAiCaptureEnabled: Bool?
    let qualityProfile: String?
    let datasetRightsStatus: String?
    let privacyReviewStatus: String?
}

struct ScanReceipt: Decodable {
    let processingJobId: UUID
    let acceptedSamples: Int
    let normalTrackingRatio: Double
    let sceneGraphNodeCount: Int
    let status: String
}

struct ProcessingJobValue: Decodable, Identifiable {
    let id: UUID
    let buildingId: UUID
    let scanSessionId: UUID
    let status: String
    let stage: String
    let progress: Double
    let message: String
    let expectedKeyframes: Int
    let receivedKeyframes: Int
    let updatedAt: String?
}

struct ScanArtifactStateValue: Decodable {
    let status: String
    let sourceModel: String?
    let pipelineVersion: String?
    let url: String?
    let qualityScore: Double?
    let errorCode: String?
    let errorMessage: String?
}

struct ScanStatusValue: Decodable {
    let scanId: UUID
    let buildingId: UUID
    let stage: String
    let state: String
    let progress: Double
    let message: String
    let qualityWarnings: [String]
    let artifacts: [String: ScanArtifactStateValue]
    let rawScanVersion: Int
    let geometryVersion: Int
    let bevVersion: Int
    let sceneGraphVersion: Int
    let reviewRevision: Int
    let publishedMapVersion: Int?
}

struct UploadedScanResult {
    let buildingId: UUID
    let sessionId: UUID
    let receipt: ScanReceipt
}

struct PushTokenRegistrationValue: Encodable {
    let deviceId: String
    let token: String
    let platform: String
    let appBundleId: String
    let environment: String
}

struct PushTokenRegistrationResponse: Decodable {
    let deviceId: String
    let token: String
    let platform: String
    let appBundleId: String
    let environment: String
    let updatedAt: String?
}

struct LocalScanDraft: Identifiable {
    let id: UUID
    let floorId: String
    let keyframeCount: Int
    let totalDistanceM: Double
    let createdAt: Date
}

struct SceneGraphValue: Decodable {
    let nodes: [SceneGraphNodeValue]
    let relations: [SceneGraphRelationValue]
}

struct DigitalTwinBoundsValue: Decodable {
    let min: Vector3Value
    let max: Vector3Value
}

struct DigitalTwinAssetManifestValue: Decodable {
    let schemaVersion: Int
    let assetId: UUID
    let sessionId: UUID
    let buildingId: UUID
    let status: String
    let pointCloudUrl: String?
    let pointCloudFormat: String
    let pointCloudMimeType: String
    let fileSizeBytes: Int
    let pointCount: Int
    let bounds: DigitalTwinBoundsValue?
    let coordinateSystem: String
    let units: String
    let sourceModel: String
    let pipelineVersion: String
    let checksumSha256: String?
    let generatedAt: Date?
    let errorCode: String?
    let errorMessage: String?

    var isCompleted: Bool { status == "completed" && pointCloudUrl != nil && pointCount > 0 }
}

struct BEVBoundsValue: Decodable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double
}

struct BEVRouteNodeValue: Decodable, Identifiable {
    let id: String
    let floorId: String
    let x: Double
    let y: Double
    let gridX: Int
    let gridY: Int
    let kind: String
    let label: String
}

struct BEVRouteEdgeValue: Decodable, Identifiable {
    let source: String
    let target: String
    let distanceM: Double
    let accessible: Bool
    var id: String { "\(source)-\(target)" }
}

struct BEVMapManifestValue: Decodable {
    let schemaVersion: Int
    let mapId: UUID
    let sessionId: UUID
    let buildingId: UUID
    let status: String
    let sourceAssetId: UUID?
    let sourceModel: String
    let pipelineVersion: String
    let coordinateSystem: String
    let units: String
    let resolutionM: Double
    let width: Int
    let height: Int
    let originX: Double
    let originY: Double
    let bounds: BEVBoundsValue?
    let occupancyUrl: String?
    let previewUrl: String?
    let freeSpaceUrl: String?
    let floorplanUrl: String?
    let roomsUrl: String?
    let portalsUrl: String?
    let routeGraphUrl: String?
    let occupancyGridUrl: String?
    let confidenceGridUrl: String?
    let semanticGridUrl: String?
    let pointCount: Int
    let freeCellCount: Int
    let occupiedCellCount: Int
    let unknownCellCount: Int
    let routeNodes: [BEVRouteNodeValue]
    let routeEdges: [BEVRouteEdgeValue]
    let qualityScore: Double
    let qualityWarnings: [String]?
    let generatedAt: Date?
    let errorCode: String?
    let errorMessage: String?

    var isCompleted: Bool { ["completed", "completed_with_fallback"].contains(status) && occupancyUrl != nil && width > 0 && height > 0 }
    var isFallback: Bool { status == "completed_with_fallback" }
}

struct SceneGraphNodeValue: Decodable, Identifiable {
    let id: String
    let kind: String
    let floorId: String?
    let geometry: SceneNodeGeometryValue
    let labels: [String]
    let semanticConfidence: Double
    let reviewStatus: String
    let attributes: [String: String]
}

struct SceneNodeGeometryValue: Decodable {
    let center: Vector3Value
    let covarianceDiagonal: Vector3Value
}

struct SceneGraphRelationValue: Decodable, Identifiable {
    let sourceId: String
    let targetId: String
    let predicate: String
    let confidence: Double
    let reviewStatus: String
    let attributes: [String: String]
    var id: String { "\(sourceId)-\(predicate)-\(targetId)" }
}

struct SceneRelationReviewPatch: Encodable {
    let sourceId: String
    let targetId: String
    let predicate: String
    let reviewStatus: String
    let accessible: Bool?
}

struct SceneNodeReviewPatch: Encodable {
    let reviewStatus: String?
    let labels: [String]?
    let kind: String?
    let floorId: String?
    let center: Vector3Value?
    let accessible: Bool?
    let restricted: Bool?
    let hazard: Bool?
}

struct DraftRouteGraphNodeValue: Encodable {
    let id: String
    let floorId: String
    let kind: String
    let x: Double
    let y: Double
    let label: String
    let accessible: Bool
}

struct DraftRouteGraphEdgeValue: Encodable {
    let source: String
    let target: String
    let distanceM: Double
    let bidirectional: Bool
    let accessible: Bool
    let kind: String
}

struct DraftRouteGraphValue: Encodable {
    let nodes: [DraftRouteGraphNodeValue]
    let edges: [DraftRouteGraphEdgeValue]
}

struct DraftMapPatchValue: Encodable {
    let baseRevision: Int?
    let floorplan: String?
    let routeGraph: DraftRouteGraphValue?
    let sceneGraph: String?
    let comment: String?
}

struct DraftMapRecordValue: Decodable {
    let scanId: UUID
    let buildingId: UUID
    let revision: Int
    let comment: String?
}

struct PublishReceiptValue: Decodable {
    let version: Int
    let nodeCount: Int
    let edgeCount: Int
    let status: String
}

struct PackageVersionInfoValue: Decodable, Identifiable {
    let buildingId: UUID
    let version: Int
    let status: String
    let nodeCount: Int
    let edgeCount: Int
    let sourceScan: String?
    let integritySha256: String?
    let createdAt: Date?
    var id: Int { version }
}

struct AdminSystemStatusValue: Decodable {
    let status: String
    let generatedAt: Date?
    let dataRoot: String
    let buildingCount: Int
    let publishedPackageCount: Int
    let jobCounts: [String: Int]
    let latestJobs: [ProcessingJobValue]
    let processingBacklogCount: Int
    let reviewRequiredCount: Int
    let failedCount: Int
    let workerTokenConfigured: Bool
    let workerOnline: Bool
    let workerId: String?
    let workerLastSeenAt: Date?
    let workerStaleAfterS: Int
    let semanticProvider: String
    let vlmEnabled: Bool
    let vlmEndpoint: String?
    let vlmModel: String?
    let vggtDepthEnabled: Bool
    let publicBaseUrl: String?

    var isHealthy: Bool {
        status == "ok"
    }

    var workerStateText: String {
        guard workerTokenConfigured else { return "worker 토큰 없음" }
        return workerOnline ? "DGX 연결됨" : "DGX 대기 또는 중단"
    }
}

struct PipelineReadinessResponseValue: Decodable {
    let status: String
    let items: [PipelineReadinessItemValue]

    var isReady: Bool {
        status == "ok"
    }
}

struct PipelineReadinessItemValue: Decodable, Identifiable {
    let component: String
    let status: String
    let message: String
    let detail: [String: String]

    var id: String { component }
}

struct MapValidationIssueValue: Decodable, Identifiable {
    let code: String
    let severity: String
    let message: String
    let target: String?
    var id: String { "\(severity):\(code):\(target ?? "")" }
}

struct MapValidationResultValue: Decodable {
    let scanId: UUID
    let buildingId: UUID
    let publishable: Bool
    let issues: [MapValidationIssueValue]
}
