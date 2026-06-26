import ARKit
import Combine
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import SceneKit
import SwiftUI
import UIKit

enum ScanStatus: Equatable {
    case ready
    case scanning
    case captured
    case uploading
    case uploaded
    case failed

    var title: String {
        switch self {
        case .ready: "준비"
        case .scanning: "스캔 중"
        case .captured: "검토 대기"
        case .uploading: "업로드 중"
        case .uploaded: "업로드 완료"
        case .failed: "확인 필요"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "viewfinder"
        case .scanning: "record.circle"
        case .captured: "checkmark.circle"
        case .uploading: "arrow.up.circle"
        case .uploaded: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle"
        }
    }
}

final class ScanController: NSObject, ObservableObject, ARSessionDelegate, CLLocationManagerDelegate {
    let session = ARSession()

    @Published private(set) var status: ScanStatus = .ready
    @Published private(set) var totalDistance = 0.0
    @Published private(set) var sampleCount = 0
    @Published private(set) var normalTrackingRatio = 0.0
    @Published private(set) var averageFeaturePointCount = 0.0
    @Published private(set) var currentFeaturePointCount = 0
    @Published private(set) var currentAmbientIntensity = 0.0
    @Published private(set) var scanStabilityScore = 0.0
    @Published private(set) var completedManifest: ScanManifestValue?
    @Published private(set) var keyframeCount = 0
    @Published private(set) var coverageSpanMeters = 0.0
    @Published private(set) var scanPath: [Vector3Value] = []
    @Published private(set) var spatialPreviewPoints: [Vector3Value] = []
    @Published private(set) var supportsMeshReconstruction = false
    @Published private(set) var meshAnchorCount = 0
    @Published private(set) var planeAnchorCount = 0
    @Published private(set) var meshVertexCount = 0
    @Published private(set) var currentMapHeadingDegrees = 0.0
    @Published private(set) var mapNorthDegrees = 0.0
    @Published private(set) var isRecordingPath = false
    @Published private(set) var rejectedFrameCount = 0
    @Published private(set) var trackingJumpCount = 0
    @Published private(set) var scanLatitude: Double?
    @Published private(set) var scanLongitude: Double?
    @Published private(set) var scanHorizontalAccuracyM: Double?
    @Published private(set) var message: String?
    @Published private(set) var processingProgress = 0.0
    @Published private(set) var reviewGraph: SceneGraphValue?
    @Published private(set) var digitalTwinManifest: DigitalTwinAssetManifestValue?
    @Published private(set) var digitalTwinPointCloudURL: URL?
    @Published private(set) var isDownloadingDigitalTwin = false
    @Published private(set) var bevMapManifest: BEVMapManifestValue?
    @Published private(set) var bevOccupancyImageURL: URL?
    @Published private(set) var isDownloadingBEVMap = false
    @Published private(set) var scanStatus: ScanStatusValue?
    @Published private(set) var mapValidation: MapValidationResultValue?
    @Published private(set) var draftMapRevision: Int?
    @Published private(set) var draftMapSaveState: String?
    @Published private(set) var uploadedBuildingID: UUID?
    @Published private(set) var uploadedSessionID: UUID?
    @Published private(set) var packageVersions: [PackageVersionInfoValue] = []
    @Published private(set) var serverJobs: [ProcessingJobValue] = []
    @Published private(set) var localDrafts: [LocalScanDraft] = []
    @Published private(set) var isRefreshingServerJobs = false
    @Published private(set) var systemStatus: AdminSystemStatusValue?
    @Published private(set) var pipelineReadiness: PipelineReadinessResponseValue?
    @Published private(set) var isRefreshingSystemStatus = false

    private var samples: [PoseSampleValue] = []
    private var startedAt: Date?
    private var floorName = ""
    private var previousPosition: SIMD3<Float>?
    private var previousSamplePosition: SIMD3<Float>?
    private var previousSampleRotation: simd_quatf?
    private var previousSampleTimestamp: TimeInterval?
    private var minPosition: SIMD3<Float>?
    private var maxPosition: SIMD3<Float>?
    private var lastSampleTime: TimeInterval = -.infinity
    private var stableTrackingStartTime: TimeInterval?
    private var observedFrameCount = 0
    private var normalTrackingCount = 0
    private var accumulatedFeaturePointCount = 0
    private var qualitySampleCount = 0
    private var capturedKeyframes: [CapturedKeyframe] = []
    private var currentSessionID = UUID()
    private var lastKeyframeTime: TimeInterval = -.infinity
    private var lastKeyframePosition: SIMD3<Float>?
    private var lastKeyframeRotation: simd_quatf?
    private var maxKeyframeCount = 240
    private var lastLocalAutosaveTime: TimeInterval = -.infinity
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var planeAnchors: [UUID: ARPlaneAnchor] = [:]
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let apiClient = AdminAPIClient()
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let locationManager = CLLocationManager()
    private var latestMagneticYawDegrees: Double?
    private var latestMagneticField: CMCalibratedMagneticField?
    private var latestPressureKpa: Double?
    private var latestRelativeAltitudeM: Double?
    private var hasCapturedNorthOffset = false
    private let fileManager = FileManager.default

    override init() {
        super.init()
        session.delegate = self
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        refreshLocalDrafts()
    }

    func startScan(floorName: String) {
        guard ARWorldTrackingConfiguration.isSupported else {
            status = .failed
            message = "이 기기에서는 공간 추적을 사용할 수 없습니다."
            return
        }
        self.floorName = floorName
        samples.removeAll(keepingCapacity: true)
        totalDistance = 0
        sampleCount = 0
        normalTrackingRatio = 0
        averageFeaturePointCount = 0
        currentFeaturePointCount = 0
        currentAmbientIntensity = 0
        scanStabilityScore = 0
        normalTrackingCount = 0
        accumulatedFeaturePointCount = 0
        qualitySampleCount = 0
        currentSessionID = UUID()
        capturedKeyframes.removeAll(keepingCapacity: true)
        keyframeCount = 0
        coverageSpanMeters = 0
        scanPath.removeAll(keepingCapacity: true)
        spatialPreviewPoints.removeAll(keepingCapacity: true)
        supportsMeshReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        meshAnchorCount = 0
        planeAnchorCount = 0
        meshVertexCount = 0
        meshAnchors.removeAll(keepingCapacity: true)
        planeAnchors.removeAll(keepingCapacity: true)
        currentMapHeadingDegrees = 0
        mapNorthDegrees = 0
        isRecordingPath = false
        rejectedFrameCount = 0
        trackingJumpCount = 0
        scanLatitude = nil
        scanLongitude = nil
        scanHorizontalAccuracyM = nil
        latestMagneticYawDegrees = nil
        latestMagneticField = nil
        latestPressureKpa = nil
        latestRelativeAltitudeM = nil
        hasCapturedNorthOffset = false
        lastKeyframeTime = -.infinity
        lastKeyframePosition = nil
        lastKeyframeRotation = nil
        lastLocalAutosaveTime = -.infinity
        maxKeyframeCount = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ? 180 : 320
        previousPosition = nil
        previousSamplePosition = nil
        previousSampleRotation = nil
        previousSampleTimestamp = nil
        minPosition = nil
        maxPosition = nil
        lastSampleTime = -.infinity
        stableTrackingStartTime = nil
        observedFrameCount = 0
        completedManifest = nil
        reviewGraph = nil
        digitalTwinManifest = nil
        digitalTwinPointCloudURL = nil
        bevMapManifest = nil
        bevOccupancyImageURL = nil
        scanStatus = nil
        mapValidation = nil
        message = "먼저 제자리에서 문, 표지판, 벽 모서리, 바닥 경계를 천천히 훑어 주세요."
        startedAt = Date()
        startMotionHeadingUpdates()
        startBarometerUpdates()
        startLocationUpdates()

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isAutoFocusEnabled = true
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        if supportsMeshReconstruction {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
        status = .scanning
    }

    func stopScan() {
        guard status == .scanning, let startedAt else { return }
        session.pause()
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingLocation()
        guard samples.count >= 2 else {
            status = .failed
            message = "자세 표본이 부족합니다. 카메라 권한과 추적 상태를 확인한 뒤 다시 스캔해 주세요."
            return
        }
        let finalizedSamples = finalizedPoseSamples()
        let finalizedDistance = pathDistance(finalizedSamples)
        let qualityFailures = scanCompletionFailures(samples: finalizedSamples, totalDistance: finalizedDistance)
        guard qualityFailures.isEmpty else {
            status = .failed
            message = qualityFailures.joined(separator: " ")
            completedManifest = nil
            return
        }
        completedManifest = ScanManifestValue(
            schemaVersion: 1,
            sessionId: currentSessionID,
            buildingId: UUID(),
            floorId: floorName,
            mapNorthDegrees: mapNorthDegrees,
            latitude: scanLatitude,
            longitude: scanLongitude,
            horizontalAccuracyM: scanHorizontalAccuracyM,
            startedAt: startedAt,
            endedAt: Date(),
            deviceModel: UIDevice.current.model,
            supportsSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            totalDistanceM: finalizedDistance,
            samples: finalizedSamples,
            keyframes: capturedKeyframes.map(\.metadata),
            spatialSamples: Array(spatialPreviewPoints.prefix(300)),
            meshAnchorCount: meshAnchorCount,
            planeAnchorCount: planeAnchorCount,
            meshVertexCount: meshVertexCount,
            datasetSchemaVersion: 1,
            capturePurpose: "indoor_navigation_physical_ai_dataset",
            privacyMode: "avoid_people_faces_documents",
            physicalAiCaptureEnabled: true,
            qualityProfile: "navigation_and_robot_learning",
            datasetRightsStatus: "facility_permission_required_before_resale",
            privacyReviewStatus: "pending_admin_review"
        )
        samples = finalizedSamples
        totalDistance = finalizedDistance
        sampleCount = finalizedSamples.count
        saveLocalDraftIfNeeded()
        refreshLocalDrafts()
        status = .captured
        message = "스캔 경로를 로컬에 저장했습니다. 서버가 3D 디지털트윈과 사용자용 2D 지도를 만든 뒤 검수할 수 있습니다."
    }

    func refreshLocalDrafts() {
        let root = scansRoot
        guard let urls = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            localDrafts = []
            return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        localDrafts = urls.compactMap { url in
            let manifestURL = url.appending(path: "manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(ScanManifestValue.self, from: data) else {
                return nil
            }
            return LocalScanDraft(
                id: manifest.sessionId,
                floorId: manifest.floorId,
                keyframeCount: manifest.keyframes.count,
                totalDistanceM: manifest.totalDistanceM,
                createdAt: manifest.endedAt
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @MainActor
    func restoreLocalDraft(_ draft: LocalScanDraft) {
        let directory = scanDirectory(for: draft.id)
        let manifestURL = directory.appending(path: "manifest.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(ScanManifestValue.self, from: data) else {
            status = .failed
            message = "저장된 스캔 명세를 불러오지 못했습니다."
            return
        }
        completedManifest = manifest
        currentSessionID = manifest.sessionId
        floorName = manifest.floorId
        totalDistance = manifest.totalDistanceM
        sampleCount = manifest.samples.count
        normalTrackingRatio = manifest.samples.isEmpty ? 0 : Double(manifest.samples.filter { $0.trackingState == "normal" }.count) / Double(manifest.samples.count)
        let featureCounts = manifest.samples.compactMap(\.featurePointCount)
        averageFeaturePointCount = featureCounts.isEmpty ? 0 : Double(featureCounts.reduce(0, +)) / Double(featureCounts.count)
        currentFeaturePointCount = featureCounts.last ?? 0
        currentAmbientIntensity = manifest.samples.compactMap(\.ambientIntensity).last ?? 0
        scanStabilityScore = manifest.samples.compactMap(\.trackingQuality).last ?? normalTrackingRatio
        keyframeCount = manifest.keyframes.count
        spatialPreviewPoints = manifest.spatialSamples ?? []
        meshAnchorCount = manifest.meshAnchorCount ?? 0
        planeAnchorCount = manifest.planeAnchorCount ?? 0
        meshVertexCount = manifest.meshVertexCount ?? 0
        scanLatitude = manifest.latitude
        scanLongitude = manifest.longitude
        scanHorizontalAccuracyM = manifest.horizontalAccuracyM
        capturedKeyframes = manifest.keyframes.compactMap { metadata in
            let imageURL = directory.appending(path: metadata.filename)
            guard fileManager.fileExists(atPath: imageURL.path) else { return nil }
            let depthURL = directory.appending(path: "\(metadata.id).f32")
            return CapturedKeyframe(
                metadata: metadata,
                fileURL: imageURL,
                depthFileURL: fileManager.fileExists(atPath: depthURL.path) ? depthURL : nil
            )
        }
        status = .captured
        message = "저장된 스캔을 불러왔습니다. 건물 이름과 주소를 확인한 뒤 업로드하세요."
    }

    @MainActor
    func deleteLocalDraft(_ draft: LocalScanDraft) {
        try? fileManager.removeItem(at: scanDirectory(for: draft.id))
        if completedManifest?.sessionId == draft.id {
            completedManifest = nil
            capturedKeyframes.removeAll()
            keyframeCount = 0
            status = .ready
        }
        refreshLocalDrafts()
        message = "저장된 스캔을 삭제했습니다."
    }

    private func startLocationUpdates() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        if scanHorizontalAccuracyM == nil || location.horizontalAccuracy <= (scanHorizontalAccuracyM ?? .greatestFiniteMagnitude) {
            scanLatitude = location.coordinate.latitude
            scanLongitude = location.coordinate.longitude
            scanHorizontalAccuracyM = location.horizontalAccuracy
        }
    }

    @MainActor
    func upload(buildingName: String, address: String) async {
        guard let manifest = completedManifest else { return }
        status = .uploading
        message = "건물 초안과 스캔 명세를 올리고 있습니다."
        do {
            let result = try await apiClient.upload(
                buildingName: buildingName,
                address: address,
                manifest: manifest,
                keyframes: capturedKeyframes
            )
            uploadedBuildingID = result.buildingId
            uploadedSessionID = result.sessionId
            message = "핵심 화면 업로드를 마쳤습니다. 인공지능 처리를 기다리고 있습니다."
            try await waitForProcessing(jobID: result.receipt.processingJobId)
            deleteUploadedLocalDraft(sessionID: manifest.sessionId)
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    @MainActor
    func refreshServerJobs() async {
        isRefreshingServerJobs = true
        defer { isRefreshingServerJobs = false }
        do {
            serverJobs = try await apiClient.processingJobs()
            if serverJobs.isEmpty {
                message = "서버에 복구할 처리 작업이 없습니다."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    func refreshSystemStatus() async {
        isRefreshingSystemStatus = true
        defer { isRefreshingSystemStatus = false }
        do {
            systemStatus = try await apiClient.systemStatus()
            pipelineReadiness = try await apiClient.pipelineReadiness()
        } catch {
            systemStatus = nil
            pipelineReadiness = nil
            message = error.localizedDescription
        }
    }

    @MainActor
    func resumeServerJob(_ job: ProcessingJobValue) async {
        uploadedBuildingID = job.buildingId
        uploadedSessionID = job.scanSessionId
        processingProgress = job.progress
        status = .uploading
        message = job.message
        do {
            switch job.status {
            case "review_required":
                reviewGraph = try await apiClient.sceneGraph(buildingID: job.buildingId, sessionID: job.scanSessionId)
                try await loadDigitalTwinAsset(buildingID: job.buildingId, sessionID: job.scanSessionId)
                try await loadBEVMapAsset(buildingID: job.buildingId, sessionID: job.scanSessionId)
                packageVersions = try await apiClient.packageVersions(buildingID: job.buildingId)
                status = .uploaded
                message = "검수 대기 작업을 불러왔습니다. 공간 노드와 연결을 확인한 뒤 게시하세요."
            case "failed":
                status = .failed
                message = job.message
            default:
                if let graph = try? await apiClient.sceneGraph(buildingID: job.buildingId, sessionID: job.scanSessionId) {
                    reviewGraph = graph
                    try await loadDigitalTwinAsset(buildingID: job.buildingId, sessionID: job.scanSessionId)
                    try await loadBEVMapAsset(buildingID: job.buildingId, sessionID: job.scanSessionId)
                    packageVersions = try await apiClient.packageVersions(buildingID: job.buildingId)
                    status = .uploaded
                    message = "기존 공간 검수 데이터를 불러왔습니다. 목적지 이름을 수정한 뒤 다시 게시하세요."
                } else {
                    try await waitForProcessing(jobID: job.id)
                }
            }
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    @MainActor
    private func waitForProcessing(jobID: UUID) async throws {
        for _ in 0..<180 {
            let job = try await apiClient.processingJob(id: jobID)
            processingProgress = job.progress
            message = job.message
            switch job.status {
            case "review_required":
                if let uploadedBuildingID, let uploadedSessionID {
                    reviewGraph = try await apiClient.sceneGraph(buildingID: uploadedBuildingID, sessionID: uploadedSessionID)
                    try await loadDigitalTwinAsset(buildingID: uploadedBuildingID, sessionID: uploadedSessionID)
                    try await loadBEVMapAsset(buildingID: uploadedBuildingID, sessionID: uploadedSessionID)
                }
                status = .uploaded
                return
            case "failed":
                throw APIError.processingFailed(job.message)
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw APIError.processingFailed("서버 처리가 예상보다 오래 걸립니다. 작업 상태는 서버에 보존되어 있습니다.")
    }

    @MainActor
    func publishReviewedScan() async {
        guard let uploadedBuildingID, let uploadedSessionID else { return }
        status = .uploading
        message = "게시 전 지도 품질과 경로 그래프를 검증하고 있습니다."
        do {
            try await saveReviewedDraft(comment: "manual_review_confirmed: publish_requested")
            let validation = try await apiClient.validateSpace(sessionID: uploadedSessionID)
            mapValidation = validation
            guard validation.publishable else {
                let blockers = validation.issues.filter { $0.severity == "blocking" }.map(\.message).joined(separator: " / ")
                throw APIError.processingFailed(blockers.isEmpty ? "게시 전 검증에 실패했습니다." : blockers)
            }
            message = validation.issues.isEmpty
                ? "검증을 통과했습니다. 사용자 앱용 지도 패키지를 게시하고 있습니다."
                : "경고가 있지만 게시 가능한 상태입니다. 사용자 앱용 지도 패키지를 게시하고 있습니다."
            let receipt = try await apiClient.publishSpace(sessionID: uploadedSessionID)
            packageVersions = try await apiClient.packageVersions(buildingID: uploadedBuildingID)
            status = .uploaded
            message = "지도 \(receipt.version)판을 게시했습니다. 노드 \(receipt.nodeCount)개, 연결 \(receipt.edgeCount)개가 사용자 앱에 배포됩니다."
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    @MainActor
    func saveAndValidateReviewedDraft() async {
        guard let uploadedSessionID else { return }
        status = .uploading
        message = "검수한 2D 지도 초안을 서버에 저장하고 있습니다."
        do {
            try await saveReviewedDraft(comment: "manual_review_confirmed: admin_saved_and_validated")
            let validation = try await apiClient.validateSpace(sessionID: uploadedSessionID)
            mapValidation = validation
            status = .uploaded
            if validation.publishable {
                message = "검수 초안이 저장됐고 게시 가능한 상태입니다."
            } else {
                let blockers = validation.issues.filter { $0.severity == "blocking" }.map(\.message).joined(separator: " / ")
                message = blockers.isEmpty ? "검수 초안은 저장됐지만 경고를 확인해야 합니다." : blockers
            }
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    @MainActor
    private func persistReviewedDraftAfterEdit() async {
        do {
            try await saveReviewedDraft(comment: "manual_review_confirmed: admin_edit_autosave")
            if let uploadedSessionID {
                mapValidation = try? await apiClient.validateSpace(sessionID: uploadedSessionID)
            }
        } catch {
            draftMapSaveState = "초안 저장 실패"
            message = error.localizedDescription
        }
    }

    @MainActor
    private func saveReviewedDraft(comment: String) async throws {
        guard let uploadedSessionID else { return }
        guard let graph = reviewGraph, let draftRoute = makeDraftRouteGraph(from: graph) else {
            throw APIError.processingFailed("저장할 검수 경로가 없습니다. 경로 노드가 2개 이상 필요합니다.")
        }
        draftMapSaveState = "저장 중"
        let draft = try await apiClient.saveDraftMap(
            sessionID: uploadedSessionID,
            routeGraph: draftRoute,
            comment: comment
        )
        draftMapRevision = draft.revision
        draftMapSaveState = "\(draft.revision)판 저장됨"
    }

    private func makeDraftRouteGraph(from graph: SceneGraphValue) -> DraftRouteGraphValue? {
        let routeNodes = graph.nodes
            .filter { $0.id.hasPrefix("trajectory:") && $0.reviewStatus != "rejected" }
            .sorted { lhs, rhs in trajectoryIndex(lhs.id) < trajectoryIndex(rhs.id) }
        guard routeNodes.count >= 2 else { return nil }

        var draftNodes = routeNodes.enumerated().map { index, node in
            let fallbackKind = index == 0 ? "entrance" : (index == routeNodes.count - 1 ? "waypoint" : "waypoint")
            let kind = normalizedDraftNodeKind(node, fallback: fallbackKind)
            return DraftRouteGraphNodeValue(
                id: "review_wp_\(index + 1)",
                floorId: normalizedFloorId(node.floorId),
                kind: kind,
                x: Double(node.geometry.center.x),
                y: Double(node.geometry.center.z),
                label: displayLabel(for: node, fallback: index == 0 ? "출발 지점" : "검수 경로 \(index + 1)"),
                accessible: isAccessible(node),
                verticalConnectorGroupId: verticalConnectorGroupId(for: node, kind: kind)
            )
        }
        let indexBySourceID = Dictionary(uniqueKeysWithValues: routeNodes.enumerated().map { ($0.element.id, $0.offset) })
        var draftEdges: [DraftRouteGraphEdgeValue] = []
        let approvedPathRelations = graph.relations.filter {
            $0.predicate == "scan_path_connected"
            && $0.reviewStatus != "rejected"
            && $0.attributes["accessible"] != "false"
        }
        if approvedPathRelations.isEmpty {
            for index in 0..<(draftNodes.count - 1) {
                draftEdges.append(makeDraftRouteEdge(source: draftNodes[index], target: draftNodes[index + 1]))
            }
        } else {
            for relation in approvedPathRelations {
                guard let sourceIndex = indexBySourceID[relation.sourceId],
                      let targetIndex = indexBySourceID[relation.targetId],
                      sourceIndex != targetIndex else { continue }
                draftEdges.append(makeDraftRouteEdge(source: draftNodes[sourceIndex], target: draftNodes[targetIndex]))
            }
        }

        var sourceNodeToDraftId = Dictionary(uniqueKeysWithValues: routeNodes.enumerated().map { ($0.element.id, draftNodes[$0.offset].id) })
        let semanticNodes = graph.nodes
            .filter { shouldIncludeInPublishedDraft($0) }
            .sorted { lhs, rhs in
                let lhsPriority = draftSemanticPriority(lhs)
                let rhsPriority = draftSemanticPriority(rhs)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.id < rhs.id
            }

        var usedNodeIds = Set(draftNodes.map(\.id))
        for (index, node) in semanticNodes.enumerated() {
            let kind = normalizedDraftNodeKind(node, fallback: "room")
            let nodeId = uniqueDraftNodeId(prefix: "review_\(kind)", sourceId: node.id, index: index + 1, used: &usedNodeIds)
            let floorId = normalizedFloorId(node.floorId)
            let draftNode = DraftRouteGraphNodeValue(
                id: nodeId,
                floorId: floorId,
                kind: kind,
                x: Double(node.geometry.center.x),
                y: Double(node.geometry.center.z),
                label: displayLabel(for: node, fallback: "\(kind) \(index + 1)"),
                accessible: isAccessible(node),
                verticalConnectorGroupId: verticalConnectorGroupId(for: node, kind: kind)
            )
            draftNodes.append(draftNode)
            sourceNodeToDraftId[node.id] = draftNode.id

            if let nearest = nearestRouteNode(to: draftNode, in: draftNodes.prefix(routeNodes.count)) {
                draftEdges.append(makeDraftRouteEdge(source: nearest, target: draftNode))
            }
        }

        let sourceDraftNodes = Dictionary(uniqueKeysWithValues: draftNodes.map { ($0.id, $0) })
        for relation in graph.relations where relation.reviewStatus == "approved" && relation.attributes["accessible"] != "false" {
            guard let sourceId = sourceNodeToDraftId[relation.sourceId],
                  let targetId = sourceNodeToDraftId[relation.targetId],
                  sourceId != targetId,
                  let source = sourceDraftNodes[sourceId],
                  let target = sourceDraftNodes[targetId],
                  !draftEdges.contains(where: { ($0.source == sourceId && $0.target == targetId) || ($0.source == targetId && $0.target == sourceId) }) else {
                continue
            }
            draftEdges.append(makeDraftRouteEdge(source: source, target: target))
        }

        guard !draftEdges.isEmpty else { return nil }
        return DraftRouteGraphValue(nodes: draftNodes, edges: draftEdges)
    }

    private func makeDraftRouteEdge(source: DraftRouteGraphNodeValue, target: DraftRouteGraphNodeValue) -> DraftRouteGraphEdgeValue {
        let dx = source.x - target.x
        let dy = source.y - target.y
        let distance = max((dx * dx + dy * dy).squareRoot(), 0.1)
        let kind: String
        if source.floorId == target.floorId {
            kind = source.kind == "door" || target.kind == "door" ? "door" : "corridor"
        } else if source.kind == "stairs" || target.kind == "stairs" {
            kind = "stairs"
        } else {
            kind = "elevator"
        }
        return DraftRouteGraphEdgeValue(
            source: source.id,
            target: target.id,
            distanceM: distance,
            bidirectional: true,
            accessible: source.accessible && target.accessible,
            kind: kind
        )
    }

    private func shouldIncludeInPublishedDraft(_ node: SceneGraphNodeValue) -> Bool {
        guard !node.id.hasPrefix("trajectory:"),
              !["floor", "space_sample"].contains(node.kind),
              node.reviewStatus == "approved",
              isAccessible(node),
              node.attributes["hazard"] != "true",
              node.attributes["restricted"] != "true" else {
            return false
        }
        let kind = normalizedDraftNodeKind(node, fallback: "")
        if ["room", "door", "stairs", "elevator"].contains(kind) { return true }
        if node.attributes["destination_candidate"] == "true" { return true }
        if node.attributes["candidate_role"] == "portal" { return true }
        if node.attributes["candidate_role"] == "vertical_connector" { return true }
        return false
    }

    private func draftSemanticPriority(_ node: SceneGraphNodeValue) -> Int {
        let kind = normalizedDraftNodeKind(node, fallback: "")
        if kind == "elevator" || kind == "stairs" { return 0 }
        if kind == "door" { return 1 }
        if node.attributes["destination_candidate"] == "true" { return 2 }
        if kind == "room" { return 3 }
        return 4
    }

    private func normalizedDraftNodeKind(_ node: SceneGraphNodeValue, fallback: String) -> String {
        let text = [
            node.attributes["node_type"],
            node.attributes["suggested_kind"],
            node.attributes["candidate_role"],
            node.kind,
            node.labels.first,
            node.attributes["display_label"],
            node.attributes["raw_label"]
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("elevator") || text.contains("엘리베이터") || text.contains("승강기") { return "elevator" }
        if text.contains("stair") || text.contains("계단") { return "stairs" }
        if text.contains("door") || text.contains("문") || text.contains("출입") || node.attributes["candidate_role"] == "portal" { return "door" }
        if text.contains("room") || text.contains("restroom") || text.contains("reception") || text.contains("desk") || text.contains("실") || text.contains("방") || text.contains("호") { return "room" }
        if ["entrance", "waypoint"].contains(fallback) { return fallback }
        if node.attributes["destination_candidate"] == "true" { return "room" }
        return fallback.isEmpty ? "room" : fallback
    }

    private func displayLabel(for node: SceneGraphNodeValue, fallback: String) -> String {
        let candidates = [
            node.attributes["display_label"],
            node.attributes["room_label"],
            node.attributes["destination_label"],
            node.attributes["object_label"],
            node.attributes["object_class"],
            node.labels.first,
            node.attributes["raw_label"],
            node.attributes["node_type"],
            node.attributes["suggested_kind"]
        ]
        for candidate in candidates {
            let cleaned = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleaned.isEmpty,
               !cleaned.hasPrefix("trajectory:"),
               cleaned != "unknown",
               cleaned != "object" {
                return cleaned
            }
        }
        return fallback
    }

    private func normalizedFloorId(_ value: String?) -> String {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? (floorName.isEmpty ? "1층" : floorName) : cleaned
    }

    private func isAccessible(_ node: SceneGraphNodeValue) -> Bool {
        node.attributes["accessible"] != "false"
            && node.attributes["restricted"] != "true"
            && node.attributes["hazard"] != "true"
    }

    private func verticalConnectorGroupId(for node: SceneGraphNodeValue, kind: String) -> String? {
        guard kind == "elevator" || kind == "stairs" else { return nil }
        let candidates = [
            node.attributes["vertical_connector_group_id"],
            node.attributes["connector_group_id"],
            displayLabel(for: node, fallback: kind)
        ]
        for candidate in candidates {
            let normalized = normalizeConnectorGroup(candidate, kind: kind)
            if normalized != nil { return normalized }
        }
        return nil
    }

    private func normalizeConnectorGroup(_ value: String?, kind: String) -> String? {
        let cleaned = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "엘리베이터", with: "elevator")
            .replacingOccurrences(of: "승강기", with: "elevator")
            .replacingOccurrences(of: "계단", with: "stairs")
            .replacingOccurrences(of: #"[^a-z0-9가-힣]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard let cleaned, !cleaned.isEmpty else { return nil }
        return cleaned.hasPrefix(kind) ? cleaned : "\(kind)-\(cleaned)"
    }

    private func nearestRouteNode(to node: DraftRouteGraphNodeValue, in routeNodes: ArraySlice<DraftRouteGraphNodeValue>) -> DraftRouteGraphNodeValue? {
        let sameFloor = routeNodes.filter { $0.floorId == node.floorId }
        let candidates = sameFloor.isEmpty ? Array(routeNodes) : sameFloor
        return candidates.min { lhs, rhs in
            squaredDistance(lhs, node) < squaredDistance(rhs, node)
        }
    }

    private func squaredDistance(_ lhs: DraftRouteGraphNodeValue, _ rhs: DraftRouteGraphNodeValue) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private func uniqueDraftNodeId(prefix: String, sourceId: String, index: Int, used: inout Set<String>) -> String {
        let slug = sourceId
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9가-힣]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = "\(prefix)_\(slug.isEmpty ? "\(index)" : slug)"
        var candidate = base
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    private func trajectoryIndex(_ id: String) -> Int {
        Int(id.split(separator: ":").last ?? "") ?? 0
    }

    @MainActor
    func approveRecommendedCandidates(publishAfterApproval: Bool = false) async {
        guard let uploadedBuildingID, let uploadedSessionID, var graph = reviewGraph else { return }
        status = .uploading
        message = "AI 추천 후보를 승인하고 있습니다."
        do {
            for relation in graph.relations where relation.predicate == "scan_path_connected" && relation.reviewStatus != "rejected" {
                graph = try await apiClient.updateSceneRelation(
                    buildingID: uploadedBuildingID,
                    sessionID: uploadedSessionID,
                    relation: relation,
                    reviewStatus: "approved"
                )
            }

            for node in graph.nodes {
                if node.id.hasPrefix("trajectory:"), node.reviewStatus != "rejected" {
                    graph = try await apiClient.updateSceneNode(
                        buildingID: uploadedBuildingID,
                        sessionID: uploadedSessionID,
                        nodeID: node.id,
                        patch: SceneNodeReviewPatch(
                            reviewStatus: "approved",
                            labels: node.labels.isEmpty ? ["스캔 경로"] : node.labels,
                            kind: node.kind,
                            floorId: node.floorId,
                            center: nil,
                            accessible: true,
                            restricted: false,
                            hazard: false
                        )
                    )
                    continue
                }

                guard isSafeAutoApprovalCandidate(node), node.reviewStatus != "rejected" else {
                    continue
                }
                let label = node.attributes["display_label"] ?? node.labels.first ?? node.id
                let kind = node.attributes["suggested_kind"] ?? node.kind
                graph = try await apiClient.updateSceneNode(
                    buildingID: uploadedBuildingID,
                    sessionID: uploadedSessionID,
                    nodeID: node.id,
                    patch: SceneNodeReviewPatch(
                        reviewStatus: "approved",
                        labels: [label],
                        kind: kind,
                        floorId: node.floorId,
                        center: nil,
                        accessible: node.attributes["accessible"] != "false",
                        restricted: false,
                        hazard: node.attributes["hazard"] == "true"
                    )
                )
            }

            reviewGraph = graph
            try await saveReviewedDraft(comment: "manual_review_confirmed: recommended_candidates_saved")
            status = .uploaded
            message = "AI 추천 후보와 2D 지도 초안을 저장했습니다. 필요한 목적지 이름만 수정한 뒤 게시하세요."
            if publishAfterApproval {
                await publishReviewedScan()
            }
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    private func isSafeAutoApprovalCandidate(_ node: SceneGraphNodeValue) -> Bool {
        guard node.attributes["auto_review"] == "recommended" else { return false }
        if node.attributes["needs_admin_review"] == "true" || node.attributes["needs_human_review"] == "true" {
            return false
        }
        if node.attributes["quality_warnings"] != nil { return false }
        if node.attributes["hazard"] == "true" || node.attributes["restricted"] == "true" { return false }
        let nodeType = node.attributes["node_type"] ?? node.attributes["suggested_kind"] ?? node.kind
        if ["elevator", "stairs", "escalator", "exit"].contains(nodeType) { return false }
        let vlmConfidence = Double(node.attributes["vlm_confidence"] ?? "1") ?? 0
        return node.semanticConfidence >= 0.82 && vlmConfidence >= 0.82
    }

    @MainActor
    func refreshDigitalTwinAsset() async {
        guard let uploadedBuildingID, let uploadedSessionID else { return }
        do {
            try await loadDigitalTwinAsset(buildingID: uploadedBuildingID, sessionID: uploadedSessionID)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func loadDigitalTwinAsset(buildingID: UUID, sessionID: UUID) async throws {
        let manifest = try await apiClient.digitalTwin(buildingID: buildingID, sessionID: sessionID)
        digitalTwinManifest = manifest
        guard manifest.isCompleted else {
            digitalTwinPointCloudURL = nil
            if manifest.status == "failed" {
                message = manifest.errorMessage ?? "디지털트윈 생성에 실패했습니다."
            }
            return
        }
        let cachedURL = digitalTwinCacheURL(for: manifest)
        if fileManager.fileExists(atPath: cachedURL.path),
           let size = try? cachedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size == manifest.fileSizeBytes {
            digitalTwinPointCloudURL = cachedURL
            return
        }
        isDownloadingDigitalTwin = true
        defer { isDownloadingDigitalTwin = false }
        message = "서버에서 실제 binary point cloud를 내려받고 있습니다."
        let temporaryURL = try await apiClient.downloadDigitalTwinPointCloud(manifest)
        try fileManager.createDirectory(at: digitalTwinCacheRoot, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: cachedURL.path) {
            try fileManager.removeItem(at: cachedURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: cachedURL)
        digitalTwinPointCloudURL = cachedURL
        message = "디지털트윈 point cloud \(manifest.pointCount)점을 불러왔습니다."
    }

    func refreshBEVMapAsset() async {
        guard let uploadedBuildingID, let uploadedSessionID else { return }
        do {
            try await loadBEVMapAsset(buildingID: uploadedBuildingID, sessionID: uploadedSessionID)
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadBEVMapAsset(buildingID: UUID, sessionID: UUID) async throws {
        scanStatus = try? await apiClient.scanStatus(sessionID: sessionID)
        let manifest = try await apiClient.bevMap(buildingID: buildingID, sessionID: sessionID)
        bevMapManifest = manifest
        guard manifest.isCompleted else {
            bevOccupancyImageURL = nil
            if manifest.status == "failed" {
                message = manifest.errorMessage ?? "BEV 맵 생성에 실패했습니다."
            } else if manifest.status == "needs_rescan" {
                message = manifest.errorMessage ?? "2D 지도 품질이 낮아 재스캔이 필요합니다."
            }
            return
        }
        let cachedURL = bevMapCacheURL(for: manifest)
        if fileManager.fileExists(atPath: cachedURL.path) {
            bevOccupancyImageURL = cachedURL
            return
        }
        isDownloadingBEVMap = true
        defer { isDownloadingBEVMap = false }
        message = "서버에서 2D 버드아이뷰 맵을 내려받고 있습니다."
        let temporaryURL = try await apiClient.downloadBEVOccupancy(manifest)
        try fileManager.createDirectory(at: bevMapCacheRoot, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: cachedURL.path) {
            try fileManager.removeItem(at: cachedURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: cachedURL)
        bevOccupancyImageURL = cachedURL
        message = manifest.isFallback
            ? "2D 지도는 fallback으로 생성되었습니다. 벽, 문, 경로를 검수한 뒤 게시하세요."
            : "2D BEV 맵 \(manifest.width)x\(manifest.height)을 불러왔습니다."
    }

    private var digitalTwinCacheRoot: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "AtmosDigitalTwins", directoryHint: .isDirectory)
    }

    private func digitalTwinCacheURL(for manifest: DigitalTwinAssetManifestValue) -> URL {
        digitalTwinCacheRoot.appending(path: "\(manifest.assetId.uuidString).ply")
    }

    private var bevMapCacheRoot: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "AtmosBEVMaps", directoryHint: .isDirectory)
    }

    private func bevMapCacheURL(for manifest: BEVMapManifestValue) -> URL {
        bevMapCacheRoot.appending(path: "\(manifest.mapId.uuidString)-occupancy.png")
    }

    @MainActor
    func refreshPackageVersions() async {
        guard let uploadedBuildingID else { return }
        do {
            packageVersions = try await apiClient.packageVersions(buildingID: uploadedBuildingID)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    func rollbackPackage(to version: Int) async {
        guard let uploadedBuildingID else { return }
        status = .uploading
        message = "\(version)판으로 롤백하고 있습니다."
        do {
            let receipt = try await apiClient.rollbackPackage(buildingID: uploadedBuildingID, version: version)
            packageVersions = try await apiClient.packageVersions(buildingID: uploadedBuildingID)
            status = .uploaded
            message = "\(receipt.version)판을 다시 활성화했습니다."
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    @MainActor
    func unpublishPackage() async {
        guard let uploadedBuildingID else { return }
        status = .uploading
        message = "현재 게시 지도를 내리고 있습니다."
        do {
            try await apiClient.unpublishPackage(buildingID: uploadedBuildingID)
            packageVersions = []
            status = .uploaded
            message = "사용자 앱 배포에서 현재 지도를 내렸습니다. 이력은 서버에 보존됩니다."
        } catch {
            status = .failed
            message = error.localizedDescription
        }
    }

    @MainActor
    func updateReviewNode(
        nodeID: String,
        reviewStatus: String? = nil,
        labels: [String]? = nil,
        kind: String? = nil,
        floorID: String? = nil,
        center: Vector3Value? = nil,
        accessible: Bool? = nil,
        restricted: Bool? = nil,
        hazard: Bool? = nil
    ) async {
        guard let uploadedBuildingID, let uploadedSessionID else { return }
        do {
            reviewGraph = try await apiClient.updateSceneNode(
                buildingID: uploadedBuildingID,
                sessionID: uploadedSessionID,
                nodeID: nodeID,
                patch: SceneNodeReviewPatch(
                    reviewStatus: reviewStatus,
                    labels: labels,
                    kind: kind,
                    floorId: floorID,
                    center: center,
                    accessible: accessible,
                    restricted: restricted,
                    hazard: hazard
                )
            )
            await persistReviewedDraftAfterEdit()
            message = "검수 변경 사항과 2D 지도 초안을 저장했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    func updateReviewRelation(_ relation: SceneGraphRelationValue, reviewStatus: String) async {
        guard let uploadedBuildingID, let uploadedSessionID else { return }
        do {
            reviewGraph = try await apiClient.updateSceneRelation(
                buildingID: uploadedBuildingID,
                sessionID: uploadedSessionID,
                relation: relation,
                reviewStatus: reviewStatus
            )
            await persistReviewedDraftAfterEdit()
            message = "관계 검수 변경 사항과 2D 지도 초안을 저장했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    func updateReviewRelationAccessibility(_ relation: SceneGraphRelationValue, accessible: Bool) async {
        guard let uploadedBuildingID, let uploadedSessionID else { return }
        do {
            reviewGraph = try await apiClient.updateSceneRelationAccessibility(
                buildingID: uploadedBuildingID,
                sessionID: uploadedSessionID,
                relation: relation,
                reviewStatus: relation.reviewStatus,
                accessible: accessible
            )
            await persistReviewedDraftAfterEdit()
            message = "연결 접근성과 2D 지도 초안을 저장했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard status == .scanning, frame.timestamp - lastSampleTime >= 0.2 else { return }
        lastSampleTime = frame.timestamp

        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        updateHeadingCalibration(from: transform)
        let quaternion = simd_quatf(transform)
        let intrinsics = frame.camera.intrinsics
        let featurePointCount = frame.rawFeaturePoints?.points.count ?? 0
        let ambientIntensity = frame.lightEstimate?.ambientIntensity ?? 0
        let motionSpeed = instantaneousSpeed(position: position, timestamp: frame.timestamp)
        let angularSpeed = instantaneousAngularSpeed(rotation: quaternion, timestamp: frame.timestamp)
        let trackingState: String
        switch frame.camera.trackingState {
        case .normal:
            trackingState = "normal"
        case .limited:
            trackingState = "limited"
        case .notAvailable:
            trackingState = "not_available"
        }
        observedFrameCount += 1
        if trackingState == "normal" {
            normalTrackingCount += 1
        }
        let trackingQuality = sampleQuality(
            trackingState: trackingState,
            featurePointCount: featurePointCount,
            ambientIntensity: ambientIntensity,
            motionSpeed: motionSpeed,
            angularSpeed: angularSpeed
        )
        currentFeaturePointCount = featurePointCount
        currentAmbientIntensity = ambientIntensity
        scanStabilityScore = trackingQuality
        accumulatedFeaturePointCount += featurePointCount
        qualitySampleCount += 1
        averageFeaturePointCount = qualitySampleCount == 0 ? 0 : Double(accumulatedFeaturePointCount) / Double(qualitySampleCount)
        normalTrackingRatio = Double(normalTrackingCount) / Double(max(observedFrameCount, 1))
        updateFeaturePointPreviewIfNeeded(frame: frame)

        if !isRecordingPath {
            if shouldStartRecording(
                trackingState: trackingState,
                featurePointCount: featurePointCount,
                trackingQuality: trackingQuality,
                motionSpeed: motionSpeed,
                angularSpeed: angularSpeed
            ) {
                if stableTrackingStartTime == nil {
                    stableTrackingStartTime = frame.timestamp
                }
                let stableDuration = frame.timestamp - (stableTrackingStartTime ?? frame.timestamp)
                if stableDuration >= 1.1 {
                    isRecordingPath = true
                    previousPosition = position
                    previousSamplePosition = position
                    previousSampleRotation = quaternion
                    previousSampleTimestamp = frame.timestamp
                    message = "초기 기준점이 잡혔습니다. 이제 복도 중심을 따라 천천히 이동하며 벽과 바닥을 함께 훑어 주세요."
                    captureKeyframeIfNeeded(frame: frame, position: position, trackingState: trackingState, trackingQuality: trackingQuality)
                } else {
                    message = "초기 기준점 잡는 중입니다. 휴대폰을 천천히 들고 문, 표지판, 모서리, 바닥 경계를 비춰 주세요."
                    previousSamplePosition = position
                    previousSampleRotation = quaternion
                    previousSampleTimestamp = frame.timestamp
                }
            } else {
                stableTrackingStartTime = nil
                rejectedFrameCount += 1
                message = "아직 기준점이 불안정합니다. 흰 벽보다 문, 표지판, 모서리, 바닥 경계를 비춰 주세요."
                previousSamplePosition = position
                previousSampleRotation = quaternion
                previousSampleTimestamp = frame.timestamp
            }
            return
        }

        if isPoseJump(
            trackingState: trackingState,
            trackingQuality: trackingQuality,
            motionSpeed: motionSpeed,
            angularSpeed: angularSpeed
        ) {
            rejectedFrameCount += 1
            trackingJumpCount += 1
            previousPosition = nil
            message = "위치가 순간적으로 튀었습니다. 잠시 멈추고 같은 방향을 다시 비춰 주세요."
            previousSamplePosition = position
            previousSampleRotation = quaternion
            previousSampleTimestamp = frame.timestamp
            return
        }

        let isReliableForMap = isReliablePoseSample(
            trackingState: trackingState,
            featurePointCount: featurePointCount,
            ambientIntensity: ambientIntensity,
            motionSpeed: motionSpeed,
            angularSpeed: angularSpeed,
            trackingQuality: trackingQuality
        )
        guard isReliableForMap else {
            rejectedFrameCount += 1
            previousPosition = nil
            if samples.count > 10 {
                message = qualityMessage(
                    trackingState: trackingState,
                    featurePointCount: featurePointCount,
                    ambientIntensity: ambientIntensity,
                    motionSpeed: motionSpeed,
                    angularSpeed: angularSpeed,
                    quality: trackingQuality
                )
            }
            previousSamplePosition = position
            previousSampleRotation = quaternion
            previousSampleTimestamp = frame.timestamp
            return
        }

        if let previousPosition {
            let horizontalDistance = hypot(Double(position.x - previousPosition.x), Double(position.z - previousPosition.z))
            if horizontalDistance < 1.2 {
                totalDistance += horizontalDistance
            }
        }
        self.previousPosition = position
        updateCoverage(with: position)
        appendScanPath(position)

        samples.append(
            PoseSampleValue(
                timestamp: frame.timestamp,
                translation: Vector3Value(x: position.x, y: position.y, z: position.z),
                rotation: QuaternionValue(
                    x: quaternion.imag.x,
                    y: quaternion.imag.y,
                    z: quaternion.imag.z,
                    w: quaternion.real
                ),
                trackingState: trackingState,
                intrinsics: CameraIntrinsicsValue(
                    fx: intrinsics.columns.0.x,
                    fy: intrinsics.columns.1.y,
                    cx: intrinsics.columns.2.x,
                    cy: intrinsics.columns.2.y,
                    imageWidth: Int(frame.camera.imageResolution.width),
                    imageHeight: Int(frame.camera.imageResolution.height)
                ),
                featurePointCount: featurePointCount,
                ambientIntensity: ambientIntensity,
                motionSpeedMps: motionSpeed,
                angularSpeedDps: angularSpeed,
                trackingQuality: trackingQuality,
                magneticFieldX: latestMagneticField?.field.x,
                magneticFieldY: latestMagneticField?.field.y,
                magneticFieldZ: latestMagneticField?.field.z,
                magneticFieldAccuracy: latestMagneticField.map { Int($0.accuracy.rawValue) },
                pressureKpa: latestPressureKpa,
                relativeAltitudeM: latestRelativeAltitudeM
            )
        )
        sampleCount = samples.count
        if samples.count > 10 {
            message = qualityMessage(
                trackingState: trackingState,
                featurePointCount: featurePointCount,
                ambientIntensity: ambientIntensity,
                motionSpeed: motionSpeed,
                angularSpeed: angularSpeed,
                quality: trackingQuality
            )
        }
        previousSamplePosition = position
        previousSampleRotation = quaternion
        previousSampleTimestamp = frame.timestamp
        captureKeyframeIfNeeded(frame: frame, position: position, trackingState: trackingState, trackingQuality: trackingQuality)
        autosaveLocalScanIfNeeded(frameTimestamp: frame.timestamp)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updateSpatialAnchors(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateSpatialAnchors(anchors)
    }

    private func updateSpatialAnchors(_ anchors: [ARAnchor]) {
        guard status == .scanning else { return }
        var changed = false
        for anchor in anchors {
            if let mesh = anchor as? ARMeshAnchor {
                meshAnchors[mesh.identifier] = mesh
                changed = true
            } else if let plane = anchor as? ARPlaneAnchor {
                planeAnchors[plane.identifier] = plane
                changed = true
            }
        }
        guard changed else { return }
        rebuildSpatialPreview()
    }

    private func rebuildSpatialPreview() {
        meshAnchorCount = meshAnchors.count
        planeAnchorCount = planeAnchors.count
        meshVertexCount = meshAnchors.values.reduce(0) { $0 + $1.geometry.vertices.count }

        var points: [Vector3Value] = []
        for anchor in meshAnchors.values.prefix(16) {
            let vertices = anchor.geometry.vertices
            let step = max(vertices.count / 28, 1)
            var index = 0
            while index < vertices.count && points.count < 240 {
                let local = vertices.vertex(at: index)
                let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                points.append(Vector3Value(x: world.x, y: world.y, z: world.z))
                index += step
            }
        }

        for anchor in planeAnchors.values.prefix(20) {
            let center = anchor.transform * SIMD4<Float>(anchor.center.x, anchor.center.y, anchor.center.z, 1)
            points.append(Vector3Value(x: center.x, y: center.y, z: center.z))
        }

        if !points.isEmpty {
            spatialPreviewPoints = points
        }
    }

    private func updateFeaturePointPreviewIfNeeded(frame: ARFrame) {
        guard meshAnchors.isEmpty, let featurePoints = frame.rawFeaturePoints?.points, !featurePoints.isEmpty else { return }
        let step = max(featurePoints.count / 90, 1)
        var points: [Vector3Value] = []
        var index = 0
        while index < featurePoints.count && points.count < 120 {
            let point = featurePoints[index]
            points.append(Vector3Value(x: point.x, y: point.y, z: point.z))
            index += step
        }
        if !points.isEmpty {
            spatialPreviewPoints = points
        }
    }

    private func instantaneousSpeed(position: SIMD3<Float>, timestamp: TimeInterval) -> Double {
        guard let previousSamplePosition, let previousSampleTimestamp else { return 0 }
        let dt = max(timestamp - previousSampleTimestamp, 0.001)
        let distance = hypot(Double(position.x - previousSamplePosition.x), Double(position.z - previousSamplePosition.z))
        return distance / dt
    }

    private func instantaneousAngularSpeed(rotation: simd_quatf, timestamp: TimeInterval) -> Double {
        guard let previousSampleRotation, let previousSampleTimestamp else { return 0 }
        let dt = max(timestamp - previousSampleTimestamp, 0.001)
        let dot = min(1.0, max(-1.0, Double(simd_dot(previousSampleRotation.vector, rotation.vector))))
        let angle = 2.0 * acos(abs(dot))
        return (angle * 180.0 / .pi) / dt
    }

    private func sampleQuality(
        trackingState: String,
        featurePointCount: Int,
        ambientIntensity: Double,
        motionSpeed: Double,
        angularSpeed: Double
    ) -> Double {
        let trackingScore = trackingState == "normal" ? 1.0 : trackingState == "limited" ? 0.35 : 0.0
        let featureScore = min(Double(featurePointCount) / 140.0, 1.0)
        let lightScore = ambientIntensity <= 0 ? 0.75 : min(max(ambientIntensity / 180.0, 0.0), 1.0)
        let speedScore = motionSpeed <= 0.05 ? 0.9 : max(0.0, min(1.0, (1.4 - motionSpeed) / 1.1))
        let turnScore = angularSpeed <= 10 ? 0.95 : max(0.0, min(1.0, (150.0 - angularSpeed) / 120.0))
        return max(0.0, min(
            1.0,
            trackingScore * 0.38
                + featureScore * 0.24
                + lightScore * 0.13
                + speedScore * 0.15
                + turnScore * 0.10
        ))
    }

    private func qualityMessage(
        trackingState: String,
        featurePointCount: Int,
        ambientIntensity: Double,
        motionSpeed: Double,
        angularSpeed: Double,
        quality: Double
    ) -> String {
        if trackingState != "normal" {
            return "추적이 불안정합니다. 잠시 멈추고 벽, 문, 표지판을 천천히 비춰 주세요."
        }
        if featurePointCount < 70 {
            return "특징점이 부족합니다. 흰 벽보다 문, 안내판, 모서리, 가구가 보이게 비춰 주세요."
        }
        if ambientIntensity > 0, ambientIntensity < 80 {
            return "조도가 낮습니다. 화면을 더 밝은 방향으로 돌리거나 천천히 이동해 주세요."
        }
        if motionSpeed > 1.4 {
            return "이동이 빠릅니다. 지도를 정확히 만들려면 천천히 걸어 주세요."
        }
        if angularSpeed > 150 {
            return "회전이 빠릅니다. 휴대폰을 급하게 돌리지 말고 천천히 훑어 주세요."
        }
        if quality < 0.62 {
            return "스캔 품질이 낮습니다. 천천히 움직이고 특징이 많은 곳을 비춰 주세요."
        }
        return "좋습니다. 벽면과 통로 방향을 따라 천천히 계속 이동해 주세요."
    }

    private func shouldStartRecording(
        trackingState: String,
        featurePointCount: Int,
        trackingQuality: Double,
        motionSpeed: Double,
        angularSpeed: Double
    ) -> Bool {
        trackingState == "normal"
            && trackingQuality >= 0.72
            && featurePointCount >= 95
            && motionSpeed <= 0.55
            && angularSpeed <= 90
    }

    private func isReliablePoseSample(
        trackingState: String,
        featurePointCount: Int,
        ambientIntensity: Double,
        motionSpeed: Double,
        angularSpeed: Double,
        trackingQuality: Double
    ) -> Bool {
        if trackingState != "normal" { return false }
        if trackingQuality < 0.62 { return false }
        if featurePointCount < 60 { return false }
        if ambientIntensity > 0, ambientIntensity < 45 { return false }
        if motionSpeed > 1.55 { return false }
        if angularSpeed > 165 { return false }
        return true
    }

    private func isPoseJump(
        trackingState: String,
        trackingQuality: Double,
        motionSpeed: Double,
        angularSpeed: Double
    ) -> Bool {
        if trackingState != "normal" { return true }
        if motionSpeed > 2.15 { return true }
        if angularSpeed > 250 { return true }
        if trackingQuality < 0.42 { return true }
        return false
    }

    private func scanCompletionFailures(samples: [PoseSampleValue], totalDistance: Double) -> [String] {
        var failures: [String] = []
        if samples.count < 24 {
            failures.append("정확한 삼차원 지도를 만들 표본이 부족합니다. 시작점을 다시 잡고 10초 이상 천천히 스캔해 주세요.")
        }
        let requiredKeyframes = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ? 48 : 96
        if capturedKeyframes.count < requiredKeyframes {
            failures.append("삼차원 재구성용 화면이 부족합니다. 방 둘레를 따라 벽, 바닥, 문, 표지판, 코너를 여러 각도에서 더 오래 훑어 주세요.")
        }
        if spatialPreviewPoints.count < 80 {
            failures.append("공간 구조점이 부족합니다. 바닥만 찍지 말고 벽과 바닥이 함께 보이게 천천히 훑어 주세요.")
        }
        if normalTrackingRatio < 0.82 {
            failures.append("추적이 자주 불안정했습니다. 흰 벽보다 특징이 많은 벽면을 보며 다시 스캔해 주세요.")
        }
        if averageFeaturePointCount < 90 {
            failures.append("특징점이 부족합니다. 안내판, 문틀, 모서리, 가구가 보이게 다시 스캔해 주세요.")
        }
        if trackingJumpCount > max(2, samples.count / 18) {
            failures.append("스캔 중 위치 점프가 많았습니다. 급회전 없이 천천히 다시 스캔해 주세요.")
        }
        if totalDistance < 12.0 {
            failures.append("이동 거리가 너무 짧습니다. 방 둘레와 주요 통로를 따라 12미터 이상 이동한 뒤 끝내 주세요.")
        }
        return failures
    }

    private func finalizedPoseSamples() -> [PoseSampleValue] {
        var filtered: [PoseSampleValue] = []
        var previous: PoseSampleValue?
        for sample in samples {
            guard sample.trackingState == "normal",
                  (sample.trackingQuality ?? 1) >= 0.58,
                  (sample.featurePointCount ?? 999) >= 55,
                  (sample.motionSpeedMps ?? 0) <= 1.8,
                  (sample.angularSpeedDps ?? 0) <= 190 else {
                continue
            }
            if let previous {
                let dt = max(sample.timestamp - previous.timestamp, 0.001)
                let distance = horizontalDistance(sample.translation, previous.translation)
                let speed = distance / dt
                if distance < 0.025 { continue }
                if distance > 1.25 || speed > 2.05 { continue }
            }
            filtered.append(sample)
            previous = sample
        }
        guard filtered.count >= 3 else { return filtered }
        return smoothedPoseSamples(filtered)
    }

    private func smoothedPoseSamples(_ input: [PoseSampleValue]) -> [PoseSampleValue] {
        guard input.count >= 3 else { return input }
        return input.enumerated().map { index, sample in
            guard index > 0, index < input.count - 1 else { return sample }
            let previous = input[index - 1].translation
            let current = sample.translation
            let next = input[index + 1].translation
            if horizontalDistance(previous, current) > 1.2 || horizontalDistance(current, next) > 1.2 {
                return sample
            }
            let smoothed = Vector3Value(
                x: previous.x * 0.20 + current.x * 0.60 + next.x * 0.20,
                y: current.y,
                z: previous.z * 0.20 + current.z * 0.60 + next.z * 0.20
            )
            return PoseSampleValue(
                timestamp: sample.timestamp,
                translation: smoothed,
                rotation: sample.rotation,
                trackingState: sample.trackingState,
                intrinsics: sample.intrinsics,
                featurePointCount: sample.featurePointCount,
                ambientIntensity: sample.ambientIntensity,
                motionSpeedMps: sample.motionSpeedMps,
                angularSpeedDps: sample.angularSpeedDps,
                trackingQuality: sample.trackingQuality,
                magneticFieldX: sample.magneticFieldX,
                magneticFieldY: sample.magneticFieldY,
                magneticFieldZ: sample.magneticFieldZ,
                magneticFieldAccuracy: sample.magneticFieldAccuracy,
                pressureKpa: sample.pressureKpa,
                relativeAltitudeM: sample.relativeAltitudeM
            )
        }
    }

    private func pathDistance(_ input: [PoseSampleValue]) -> Double {
        guard input.count >= 2 else { return 0 }
        var distance = 0.0
        var previous = input[0].translation
        for sample in input.dropFirst() {
            let step = horizontalDistance(sample.translation, previous)
            if step < 1.25 {
                distance += step
            }
            previous = sample.translation
        }
        return distance
    }

    private func horizontalDistance(_ lhs: Vector3Value, _ rhs: Vector3Value) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dz = Double(lhs.z - rhs.z)
        return sqrt(dx * dx + dz * dz)
    }

    private func updateCoverage(with position: SIMD3<Float>) {
        if let minPosition, let maxPosition {
            self.minPosition = SIMD3<Float>(
                min(minPosition.x, position.x),
                min(minPosition.y, position.y),
                min(minPosition.z, position.z)
            )
            self.maxPosition = SIMD3<Float>(
                max(maxPosition.x, position.x),
                max(maxPosition.y, position.y),
                max(maxPosition.z, position.z)
            )
        } else {
            minPosition = position
            maxPosition = position
        }
        guard let minPosition = self.minPosition, let maxPosition = self.maxPosition else {
            coverageSpanMeters = 0
            return
        }
        let dx = Double(maxPosition.x - minPosition.x)
        let dz = Double(maxPosition.z - minPosition.z)
        coverageSpanMeters = sqrt(dx * dx + dz * dz)
    }

    private func appendScanPath(_ position: SIMD3<Float>) {
        let point = Vector3Value(x: position.x, y: position.y, z: position.z)
        if let last = scanPath.last {
            let dx = Double(point.x - last.x)
            let dz = Double(point.z - last.z)
            if sqrt(dx * dx + dz * dz) < 0.18 {
                return
            }
        }
        scanPath.append(point)
        if scanPath.count > 180 {
            scanPath.removeFirst(scanPath.count - 180)
        }
    }

    private func startMotionHeadingUpdates() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 20
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] sample, _ in
            guard let self, let sample else { return }
            let yaw = sample.attitude.yaw
            self.latestMagneticYawDegrees = self.normalized360(-(yaw * 180 / .pi))
            self.latestMagneticField = sample.magneticField
        }
    }

    private func startBarometerUpdates() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.latestPressureKpa = data.pressure.doubleValue
            self.latestRelativeAltitudeM = data.relativeAltitude.doubleValue
        }
    }

    private func updateHeadingCalibration(from transform: simd_float4x4) {
        let forwardX = -Double(transform.columns.2.x)
        let forwardZ = -Double(transform.columns.2.z)
        let mapHeading = normalized360(atan2(forwardX, forwardZ) * 180 / .pi)
        currentMapHeadingDegrees = mapHeading
        guard !hasCapturedNorthOffset, let latestMagneticYawDegrees else { return }
        mapNorthDegrees = normalized360(latestMagneticYawDegrees - mapHeading)
        hasCapturedNorthOffset = true
    }

    private func normalized360(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    private func captureKeyframeIfNeeded(
        frame: ARFrame,
        position: SIMD3<Float>,
        trackingState: String,
        trackingQuality: Double
    ) {
        guard capturedKeyframes.count < maxKeyframeCount else { return }
        let supportsDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let minInterval = supportsDepth ? 0.45 : 0.20
        let minDistance: Float = supportsDepth ? 0.22 : 0.08
        let minRotationDegrees = supportsDepth ? 8.0 : 5.0
        let minQuality = supportsDepth ? 0.58 : 0.52
        guard trackingState == "normal", trackingQuality >= minQuality, frame.timestamp - lastKeyframeTime >= minInterval else { return }
        let rotation = simd_quatf(frame.camera.transform)
        var displacement = Double.infinity
        var rotationDelta = Double.infinity
        var selectionReason = "initial_anchor"
        if let lastKeyframePosition, let lastKeyframeRotation {
            displacement = Double(simd_distance(lastKeyframePosition, position))
            rotationDelta = angularDistanceDegrees(lastKeyframeRotation, rotation)
            let movedEnough = displacement >= Double(minDistance)
            let rotatedEnough = rotationDelta >= minRotationDegrees
            if !movedEnough && !rotatedEnough { return }
            if movedEnough && rotatedEnough {
                selectionReason = "parallax_and_view_angle"
            } else if movedEnough {
                selectionReason = "parallax_distance"
            } else {
                selectionReason = "view_angle_change"
            }
        }
        let featureScore = min(Double(frame.rawFeaturePoints?.points.count ?? 0) / 180.0, 1.0)
        let selectionScore = min(1.0, max(0.0, trackingQuality * 0.62 + featureScore * 0.25 + min((displacement.isFinite ? displacement : Double(minDistance)) / Double(minDistance), 1.0) * 0.13))

        let source = CIImage(cvPixelBuffer: frame.capturedImage)
        let targetMaxDimension: CGFloat = supportsDepth ? 1920 : 1600
        let scale = min(1, targetMaxDimension / max(source.extent.width, source.extent.height))
        let image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let data = imageContext.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: supportsDepth ? 0.86 : 0.82]
        ) else { return }

        let frameID = "frame_\(capturedKeyframes.count + 1)"
        let directory = scanDirectory(for: currentSessionID)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appending(path: "\(frameID).jpg")
            try data.write(to: fileURL, options: .atomic)
            let depth = saveDepth(frame.sceneDepth?.depthMap, frameID: frameID, directory: directory)
            let metadata = KeyframeMetadataValue(
                id: frameID,
                timestamp: frame.timestamp,
                poseSampleTimestamp: samples.last?.timestamp ?? frame.timestamp,
                filename: "\(frameID).jpg",
                contentType: "image/jpeg",
                byteCount: data.count,
                depthWidth: depth?.width,
                depthHeight: depth?.height,
                depthByteCount: depth?.byteCount,
                selectionReason: selectionReason,
                selectionScore: selectionScore,
                displacementM: displacement.isFinite ? displacement : nil,
                rotationDeltaDegrees: rotationDelta.isFinite ? rotationDelta : nil
            )
            capturedKeyframes.append(CapturedKeyframe(metadata: metadata, fileURL: fileURL, depthFileURL: depth?.url))
            keyframeCount = capturedKeyframes.count
            lastKeyframeTime = frame.timestamp
            lastKeyframePosition = position
            lastKeyframeRotation = rotation
        } catch {
            message = "핵심 프레임을 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func angularDistanceDegrees(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Double {
        let dot = min(1.0, max(-1.0, Double(simd_dot(lhs.vector, rhs.vector))))
        return 2.0 * acos(abs(dot)) * 180.0 / .pi
    }

    private var scansRoot: URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appending(path: "atmos-admin-scans")
    }

    private func scanDirectory(for sessionID: UUID) -> URL {
        scansRoot.appending(path: sessionID.uuidString)
    }

    private func saveLocalDraftIfNeeded() {
        guard let completedManifest else { return }
        do {
            try writeLocalScanManifest(completedManifest)
        } catch {
            message = "스캔 명세를 로컬에 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func autosaveLocalScanIfNeeded(frameTimestamp: TimeInterval) {
        guard frameTimestamp - lastLocalAutosaveTime >= 2.0,
              let manifest = localAutosaveManifestSnapshot() else {
            return
        }
        lastLocalAutosaveTime = frameTimestamp
        do {
            try writeLocalScanManifest(manifest)
            refreshLocalDrafts()
        } catch {
            message = "스캔 자동 저장 실패: \(error.localizedDescription)"
        }
    }

    private func localAutosaveManifestSnapshot() -> ScanManifestValue? {
        guard let startedAt, samples.count >= 2, !capturedKeyframes.isEmpty else { return nil }
        return ScanManifestValue(
            schemaVersion: 1,
            sessionId: currentSessionID,
            buildingId: completedManifest?.buildingId ?? UUID(),
            floorId: floorName,
            mapNorthDegrees: mapNorthDegrees,
            latitude: scanLatitude,
            longitude: scanLongitude,
            horizontalAccuracyM: scanHorizontalAccuracyM,
            startedAt: startedAt,
            endedAt: Date(),
            deviceModel: UIDevice.current.model,
            supportsSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            totalDistanceM: totalDistance,
            samples: samples,
            keyframes: capturedKeyframes.map(\.metadata),
            spatialSamples: Array(spatialPreviewPoints.prefix(300)),
            meshAnchorCount: meshAnchorCount,
            planeAnchorCount: planeAnchorCount,
            meshVertexCount: meshVertexCount,
            datasetSchemaVersion: 1,
            capturePurpose: "indoor_navigation_physical_ai_dataset",
            privacyMode: "avoid_people_faces_documents",
            physicalAiCaptureEnabled: true,
            qualityProfile: "navigation_and_robot_learning",
            datasetRightsStatus: "facility_permission_required_before_resale",
            privacyReviewStatus: "autosaved_before_upload"
        )
    }

    private func writeLocalScanManifest(_ manifest: ScanManifestValue) throws {
        let directory = scanDirectory(for: manifest.sessionId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appending(path: "manifest.json"), options: .atomic)
    }

    private func deleteUploadedLocalDraft(sessionID: UUID) {
        try? fileManager.removeItem(at: scanDirectory(for: sessionID))
        refreshLocalDrafts()
    }

    private func saveDepth(
        _ pixelBuffer: CVPixelBuffer?,
        frameID: String,
        directory: URL
    ) -> (url: URL, width: Int, height: Int, byteCount: Int)? {
        guard let pixelBuffer, CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var packed = Data(count: width * height * MemoryLayout<Float32>.size)
        packed.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.baseAddress else { return }
            for row in 0..<height {
                memcpy(destinationBase.advanced(by: row * width * 4), base.advanced(by: row * sourceStride), width * 4)
            }
        }
        let url = directory.appending(path: "\(frameID).f32")
        do {
            try packed.write(to: url, options: .atomic)
            return (url, width, height, packed.count)
        } catch { return nil }
    }
}

private extension ARGeometrySource {
    func vertex(at index: Int) -> SIMD3<Float> {
        precondition(format == .float3, "Expected float3 mesh vertices")
        let pointer = buffer.contents().advanced(by: offset + index * stride)
        return pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }
}

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var controller: ScanController

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = controller.session
        view.automaticallyUpdatesLighting = true
        view.debugOptions = [.showFeaturePoints]
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.debugOptions = controller.status == .scanning ? [.showFeaturePoints] : []
    }
}
