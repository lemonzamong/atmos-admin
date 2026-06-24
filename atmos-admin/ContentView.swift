import Combine
import Contacts
import CoreLocation
import SceneKit
import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = ScanController()
    @StateObject private var addressLocator = AdminAddressLocator()
    @State private var buildingName = ""
    @State private var address = ""
    @State private var floorName = "1층"
    @State private var showsSpaceInfoSheet = false
    @State private var showsUploadInfoSheet = false
    @State private var showsSavedScans = false
    @State private var showsReviewSheet = false
    @State private var showsPackageOperations = false
    @State private var showsFloorPicker = false
    @State private var reviewSearchText = ""
    @State private var showAdvancedReview = false

    var body: some View {
        NavigationStack {
            ZStack {
                AdminTheme.brandCanvasGradient.ignoresSafeArea()
                adminAmbientLayer
                if scanner.status == .scanning {
                    scanSessionView
                } else {
                    adminHome
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AdminTheme.violet)
        .sheet(isPresented: $showsSpaceInfoSheet) {
            spaceInfoSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsUploadInfoSheet) {
            uploadInfoSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsSavedScans) {
            savedScansSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsReviewSheet) {
            NavigationStack {
                ScrollView {
                    reviewCard
                        .padding(20)
                }
                .background(AdminTheme.brandCanvasGradient)
                .navigationTitle("검수")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsPackageOperations) {
            NavigationStack {
                ScrollView {
                    packageOperationsCard
                        .padding(20)
                }
                .background(AdminTheme.brandCanvasGradient)
                .navigationTitle("게시 관리")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await scanner.refreshServerJobs()
            await scanner.refreshSystemStatus()
        }
    }

    private var adminHome: some View {
        VStack(spacing: 0) {
            adminTopBar
            Spacer(minLength: 100)
            VStack(spacing: 14) {
                Text("무엇을 할까요?")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(AdminTheme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.70)
                Text("공간을 한 번 스캔하면 서버가 자동으로 지도를 만들고, 관리자는 검수만 합니다")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AdminTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 72)
            VStack(spacing: 14) {
                Button {
                    showsSpaceInfoSheet = true
                } label: {
                    Text("스캔 시작")
                }
                .buttonStyle(AdminPrimaryButtonStyle())

                if scanner.reviewGraph != nil {
                    Button {
                        showsReviewSheet = true
                    } label: {
                        Text("검수할 지도 열기")
                    }
                    .buttonStyle(AdminSecondaryButtonStyle())
                } else if scanner.completedManifest != nil {
                    Button {
                        showsUploadInfoSheet = true
                    } label: {
                        Text("방금 스캔한 공간 업로드")
                    }
                    .buttonStyle(AdminSecondaryButtonStyle())
                }

                HStack(spacing: 12) {
                    minimalHomeAction("작업", systemImage: "folder.fill") {
                        showsSavedScans = true
                    }
                    minimalHomeAction("게시", systemImage: "paperplane.fill") {
                        showsPackageOperations = true
                    }
                    .opacity(scanner.uploadedBuildingID == nil ? 0.45 : 1)
                    .disabled(scanner.uploadedBuildingID == nil)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
    }

    private var adminTopBar: some View {
        HStack {
            statusBadge
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var adminAmbientLayer: some View {
        ZStack {
            Circle()
                .fill(AdminTheme.violet.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 46)
                .offset(x: -140, y: -260)
            Circle()
                .fill(AdminTheme.route.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 54)
                .offset(x: 160, y: 260)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 240)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func minimalHomeAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.black))
                Text(title)
                    .font(.caption.weight(.black))
            }
            .foregroundStyle(AdminTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.70), lineWidth: 1))
            .shadow(color: AdminTheme.shadow(0.07), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var packageOperationsCard: some View {
        if scanner.uploadedBuildingID != nil {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("지도 패키지 운영", systemImage: "shippingbox.fill")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button {
                        Task { await scanner.refreshPackageVersions() }
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .font(.caption.weight(.bold))
                }
                if scanner.packageVersions.isEmpty {
                    Text("아직 게시된 패키지 이력이 없습니다. 검수 완료 후 게시하면 버전 이력이 여기에 표시됩니다.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    ForEach(scanner.packageVersions) { version in
                        PackageVersionRow(version: version) {
                            Task { await scanner.rollbackPackage(to: version.version) }
                        }
                    }
                    Button(role: .destructive) {
                        Task { await scanner.unpublishPackage() }
                    } label: {
                        Label("현재 게시 지도 내리기", systemImage: "tray.and.arrow.down.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
                Text("운영 원칙: 잘못 게시된 지도는 삭제하지 않고 게시 취소하거나 이전 안정판으로 롤백합니다. 사용자 앱은 활성 패키지만 내려받습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .adminSurface(radius: 28, shadowOpacity: 0.08)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Riav Admin")
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.82))
                    Text("공간을 스캔하고\n검수하세요")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .lineSpacing(2)
                        .foregroundStyle(.white)
                }
                Spacer()
                statusBadge
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            }
            Text("한 번 스캔한 뒤 서버가 자동으로 장면 그래프를 만들고, 관리자는 목적지와 층 이동만 검수합니다.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AdminTheme.heroGradient,
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 112, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 14, y: 18)
                .accessibilityHidden(true)
        }
        .shadow(color: AdminTheme.violet.opacity(0.25), radius: 24, x: 0, y: 14)
    }

    private var workflowStrip: some View {
        HStack(spacing: 8) {
            workflowStep("정보", symbol: "building.2.fill", active: scanner.status == .ready)
            workflowStep("스캔", symbol: "camera.viewfinder", active: scanner.status == .scanning)
            workflowStep("검수", symbol: "checklist.checked", active: scanner.reviewGraph != nil)
            workflowStep("게시", symbol: "paperplane.fill", active: !scanner.packageVersions.isEmpty)
        }
        .padding(10)
        .adminSurface(radius: 22, shadowOpacity: 0.05)
    }

    private func workflowStep(_ title: String, symbol: String, active: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.headline.weight(.black))
            Text(title)
                .font(.caption.weight(.black))
        }
        .foregroundStyle(active ? .white : AdminTheme.violet)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(active ? AdminTheme.violet : AdminTheme.softViolet, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var homeActions: some View {
        VStack(spacing: 16) {
            Button {
                showsSpaceInfoSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 38, weight: .black))
                            .frame(width: 68, height: 68)
                            .background(.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.title2.weight(.black))
                    }
                    Text("새 공간 스캔")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("건물 정보 입력 후 복도와 주요 시설을 천천히 비추세요. 서버가 자동으로 목적지 후보를 만듭니다.")
                        .font(.headline.weight(.semibold))
                        .lineSpacing(3)
                        .opacity(0.84)
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 198, alignment: .leading)
                .background(AdminTheme.heroGradient, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 118, weight: .black))
                        .foregroundStyle(.white.opacity(0.09))
                        .offset(x: 14, y: 22)
                        .accessibilityHidden(true)
                }
                .shadow(color: AdminTheme.violet.opacity(0.22), radius: 24, y: 14)
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                adminQuickAction(
                    title: "작업 관리",
                    subtitle: "검수 대기",
                    symbol: "folder.fill",
                    color: AdminTheme.violet
                ) {
                    showsSavedScans = true
                }
                adminQuickAction(
                    title: "게시 관리",
                    subtitle: "배포 이력",
                    symbol: "paperplane.fill",
                    color: AdminTheme.route
                ) {
                    showsPackageOperations = true
                }
            }
        }
    }

    private func adminQuickAction(title: String, subtitle: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2.weight(.black))
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(AdminTheme.ink)
                Text(subtitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AdminTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(18)
            .adminSurface(radius: 28, shadowOpacity: 0.07)
        }
        .buttonStyle(.plain)
    }

    private var scanSessionView: some View {
        GeometryReader { proxy in
            ZStack {
                AdminTheme.ink.ignoresSafeArea()
                ARCameraView(controller: scanner)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        statusBadge
                            .padding(.leading, 18)
                            .padding(.top, 18)
                    }
                    .overlay(alignment: .topTrailing) {
                        scanMiniOverlay
                            .padding(.trailing, 14)
                            .padding(.top, 18)
                    }
                    .overlay { scanOverlayGuide }
                VStack {
                    Spacer()
                    VStack(spacing: 14) {
                        Text(scanActionText)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 20)
                        Button(role: .destructive) {
                            scanner.stopScan()
                            if canUpload && scanner.completedManifest != nil {
                                showsUploadInfoSheet = true
                            }
                        } label: {
                            Text("스캔 끝내기")
                                .font(.title3.weight(.black))
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AdminTheme.danger)
                    }
                    .padding(18)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private var savedScansSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    cardHeader("작업 복구", symbol: "folder.fill", subtitle: "앱이 꺼졌거나 네트워크가 끊겼던 스캔 작업을 서버에서 다시 불러옵니다.")
                    Button {
                        Task { await scanner.refreshServerJobs() }
                    } label: {
                        Label(scanner.isRefreshingServerJobs ? "새로고침 중" : "서버 작업 새로고침", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AdminPrimaryButtonStyle())
                    .disabled(scanner.isRefreshingServerJobs)

                    if scanner.completedManifest != nil {
                        localPendingScanCard
                    }

                    if !scanner.localDrafts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("이 기기에 저장된 스캔")
                                .font(.headline.weight(.black))
                                .foregroundStyle(AdminTheme.ink)
                            ForEach(scanner.localDrafts) { draft in
                                LocalDraftRow(draft: draft) {
                                    scanner.restoreLocalDraft(draft)
                                } onDelete: {
                                    scanner.deleteLocalDraft(draft)
                                }
                            }
                        }
                    }

                    if scanner.serverJobs.isEmpty {
                        ContentUnavailableView(
                            "복구할 서버 작업이 없습니다",
                            systemImage: "tray",
                            description: Text("스캔을 업로드하면 처리 중·검수 대기 작업이 이곳에 표시됩니다.")
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("서버 작업")
                                .font(.headline.weight(.black))
                                .foregroundStyle(AdminTheme.ink)
                            ForEach(scanner.serverJobs) { job in
                                ServerJobRow(job: job) {
                                    showsSavedScans = false
                                    Task { await scanner.resumeServerJob(job) }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(AdminTheme.canvas)
            .navigationTitle("작업 복구")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var serverStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("운영 상태")
                        .font(.headline.weight(.black))
                        .foregroundStyle(AdminTheme.ink)
                    Text(scanner.systemStatus?.workerStateText ?? "상태를 아직 확인하지 않았습니다")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AdminTheme.mutedInk)
                }
                Spacer()
                if scanner.isRefreshingSystemStatus {
                    ProgressView()
                        .tint(AdminTheme.violet)
                } else {
                    Button {
                        Task { await scanner.refreshSystemStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline.weight(.black))
                            .frame(width: 42, height: 42)
                            .background(AdminTheme.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("운영 상태 새로고침")
                }
            }
            if let status = scanner.systemStatus {
                HStack(spacing: 8) {
                    statusMetric("서버", status.isHealthy ? "정상" : "확인", status.isHealthy ? AdminTheme.safe : AdminTheme.caution)
                    statusMetric("DGX", status.workerOnline ? "연결" : "대기", status.workerOnline ? AdminTheme.safe : AdminTheme.danger)
                    statusMetric("처리", "\(status.processingBacklogCount)", AdminTheme.violet)
                }
                HStack(spacing: 8) {
                    statusMetric("검수", "\(status.reviewRequiredCount)", AdminTheme.route)
                    statusMetric("게시", "\(status.publishedPackageCount)", AdminTheme.safe)
                    statusMetric("실패", "\(status.failedCount)", status.failedCount == 0 ? AdminTheme.safe : AdminTheme.danger)
                }
                VStack(alignment: .leading, spacing: 7) {
                    statusLine("VLM", status.vlmEnabled ? (status.vlmModel ?? "켜짐") : "꺼짐")
                    statusLine("VGGT", status.vggtDepthEnabled ? "깊이 추정 켜짐" : "깊이 추정 꺼짐")
                    if let workerLastSeenAt = status.workerLastSeenAt {
                        statusLine("마지막 DGX 접속", workerLastSeenAt.formatted(date: .omitted, time: .standard))
                    }
                    if let latest = status.latestJobs.first {
                        statusLine("최근 작업", "\(latest.status) · \(latest.message)")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            } else {
                Text("새로고침을 누르면 Lightsail API, DGX worker, VLM, VGGT, 작업 대기열 상태를 확인합니다.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.74), lineWidth: 1))
        .shadow(color: AdminTheme.shadow(0.06), radius: 14, y: 7)
    }

    private func statusMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(AdminTheme.ink)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var localPendingScanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("이 기기의 업로드 대기 스캔", systemImage: "iphone.gen3")
                .font(.headline.weight(.black))
                .foregroundStyle(AdminTheme.ink)
            Text(scanner.message ?? "스캔 상태를 확인하세요.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                showsUploadInfoSheet = true
            } label: {
                Label("건물 정보 확인 후 업로드", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(AdminPrimaryButtonStyle())
            .disabled(scanner.status == .uploading)
        }
        .padding(18)
        .adminSurface(radius: 22, shadowOpacity: 0.06)
    }

    private var uploadInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Text("이 정보로 올릴까요?")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(AdminTheme.ink)
                            .multilineTextAlignment(.center)
                        Text("사용자 앱에 표시될 건물 이름과 주소입니다")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AdminTheme.mutedInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 8)
                    formField("건물 이름", systemImage: "building.2.fill", text: $buildingName)
                        .textContentType(.organizationName)
                    addressFormField
                        .textContentType(.fullStreetAddress)
                    if let manifest = scanner.completedManifest {
                        Text("\(manifest.floorId) · 핵심 화면 \(scanner.keyframeCount)장 · 샘플 \(scanner.sampleCount)개")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(AdminTheme.mutedInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if !canUpload {
                        Text("건물 이름과 주소를 모두 입력해야 업로드할 수 있습니다.")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AdminTheme.danger)
                    }
                }
                .padding(.vertical, 28)
                .padding(20)
            }
            .background(AdminTheme.brandCanvasGradient)
            .navigationTitle("업로드")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    showsUploadInfoSheet = false
                    Task { await scanner.upload(buildingName: buildingName, address: address) }
                } label: {
                    Text("서버에 업로드")
                }
                .buttonStyle(AdminPrimaryButtonStyle())
                .disabled(!canUpload || scanner.status == .uploading || scanner.completedManifest == nil)
                .padding(20)
                .background(.white.opacity(0.72))
            }
        }
    }

    private var spaceInfoSheet: some View {
        NavigationStack {
            ScrollView {
                buildingForm
                    .padding(20)
            }
            .background(AdminTheme.brandCanvasGradient)
            .navigationTitle("스캔 준비")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    showsSpaceInfoSheet = false
                    scanner.startScan(floorName: floorName)
                } label: {
                    Text("스캔 시작")
                }
                .buttonStyle(AdminPrimaryButtonStyle())
                .disabled(!canStart)
                .padding(20)
                .background(.white.opacity(0.72))
            }
        }
        .sheet(isPresented: $showsFloorPicker) {
            floorPickerSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var buildingForm: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("어디를 스캔하나요?")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(AdminTheme.ink)
                    .multilineTextAlignment(.center)
                Text("건물 이름, 주소, 층만 입력하면 바로 스캔을 시작합니다")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AdminTheme.mutedInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 14)
            formField("건물 이름", systemImage: "building.2.fill", text: $buildingName)
                .textContentType(.organizationName)
            addressFormField
                .textContentType(.fullStreetAddress)
            floorPickerField
            Text("예: 서울대학교 301동 · 서울특별시 관악구 관악로 1 · 3층")
                .font(.caption.weight(.bold))
                .foregroundStyle(AdminTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 28)
    }

    private func formField(_ placeholder: String, systemImage: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: text)
                .font(.title3.weight(.black))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.74), lineWidth: 1)
        )
        .shadow(color: AdminTheme.shadow(0.06), radius: 12, y: 6)
    }

    private var addressFormField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                TextField("주소", text: $address, axis: .vertical)
                    .font(.title3.weight(.black))
                    .textFieldStyle(.plain)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2, reservesSpace: true)
                Button {
                    addressLocator.fillCurrentAddress { resolvedAddress in
                        address = resolvedAddress
                    }
                } label: {
                    ZStack {
                        if addressLocator.isLoading {
                            ProgressView()
                                .tint(AdminTheme.violet)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .background(AdminTheme.violet, in: Circle())
                    .shadow(color: AdminTheme.violet.opacity(0.20), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(addressLocator.isLoading)
                .accessibilityLabel("현재 위치로 주소 입력")
            }
            .padding(.leading, 18)
            .padding(.trailing, 9)
            .frame(minHeight: 86)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.74), lineWidth: 1)
            )
            .shadow(color: AdminTheme.shadow(0.06), radius: 12, y: 6)
            if let message = addressLocator.message {
                Text(message)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(addressLocator.isError ? AdminTheme.danger : AdminTheme.mutedInk)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var floorPickerField: some View {
        Button {
            showsFloorPicker = true
        } label: {
            HStack(spacing: 12) {
                Text(floorName.isEmpty ? "층 선택" : floorName)
                    .font(.title3.weight(.black))
                    .foregroundStyle(floorName.isEmpty ? AdminTheme.mutedInk : AdminTheme.ink)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.headline.weight(.black))
                    .foregroundStyle(AdminTheme.violet)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.74), lineWidth: 1)
            )
            .shadow(color: AdminTheme.shadow(0.06), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("층 선택")
        .accessibilityValue(floorName)
    }

    private var floorPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("층을 선택하세요")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(AdminTheme.ink)
                        Text("스캔할 실제 층을 한 번만 선택하면 됩니다")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AdminTheme.mutedInk)
                    }
                    floorSection(title: "지하층", options: Array(floorOptions.prefix(6)))
                    floorSection(title: "지상층", options: Array(floorOptions.dropFirst(6)))
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(AdminTheme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        showsFloorPicker = false
                    }
                    .font(.headline.weight(.black))
                }
            }
        }
    }

    private func floorSection(title: String, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(AdminTheme.ink)
                .padding(.horizontal, 2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                ForEach(options, id: \.self) { option in
                    floorTile(option)
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AdminTheme.stroke, lineWidth: 1)
        )
        .shadow(color: AdminTheme.shadow(0.08), radius: 18, y: 8)
    }

    private func floorTile(_ option: String) -> some View {
        let isSelected = option == floorName
        return Button {
            floorName = option
            showsFloorPicker = false
        } label: {
            HStack(spacing: 7) {
                Text(option)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.82)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .black))
                }
            }
            .foregroundStyle(isSelected ? .white : AdminTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                isSelected ? AdminTheme.violet : Color(red: 0.982, green: 0.984, blue: 0.992),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? AdminTheme.deepViolet.opacity(0.35) : AdminTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: isSelected ? AdminTheme.violet.opacity(0.22) : .clear, radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option) 선택")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func cardHeader(_ title: String, symbol: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AdminTheme.violet, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.black))
                    .foregroundStyle(AdminTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var scanCard: some View {
        scanCard(cameraHeight: scanner.status == .scanning ? 520 : 330)
    }

    private func scanCard(cameraHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            if scanner.status != .scanning {
                cardHeader("스캔 미리보기", symbol: "viewfinder", subtitle: "보행 가능한 경로와 주요 랜드마크를 화면에 담습니다.")
            }
            ARCameraView(controller: scanner)
                .frame(height: cameraHeight)
                .overlay(alignment: .topLeading) { statusBadge.padding(12) }
                .overlay(alignment: .topTrailing) { scanMiniOverlay.padding(12) }
                .overlay { scanOverlayGuide }
                .overlay(alignment: .bottom) { scanInstruction.padding(12) }
                .clipShape(RoundedRectangle(cornerRadius: scanner.status == .scanning ? 30 : 24, style: .continuous))
            if scanner.status != .scanning {
                HStack {
                    scanMetric("이동 거리", scanner.totalDistance.formatted(.number.precision(.fractionLength(1))) + "m", "figure.walk")
                    scanMetric("특징점", "\(scanner.currentFeaturePointCount)개", "sparkles")
                    scanMetric("커버리지", scanner.coverageSpanMeters.formatted(.number.precision(.fractionLength(1))) + "m", "arrow.left.and.right")
                }
            }
        }
        .padding(scanner.status == .scanning ? 8 : 16)
        .adminSurface(radius: 30, shadowOpacity: 0.08)
    }

    private var scanMiniOverlay: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("\(Int((qualityScore * 100).rounded()))점")
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(qualityColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.92), in: Capsule())
            MiniSpatialScanMap(
                path: scanner.scanPath,
                spatialPoints: scanner.spatialPreviewPoints,
                headingDegrees: scanner.currentMapHeadingDegrees,
                supportsMeshReconstruction: scanner.supportsMeshReconstruction,
                meshAnchorCount: scanner.meshAnchorCount,
                planeAnchorCount: scanner.planeAnchorCount,
                meshVertexCount: scanner.meshVertexCount
            )
            .frame(width: scanner.status == .scanning ? 178 : 148, height: scanner.status == .scanning ? 154 : 128)
        }
        .opacity(scanner.status == .scanning || !scanner.scanPath.isEmpty || !scanner.spatialPreviewPoints.isEmpty ? 1 : 0)
        .accessibilityLabel("현재 스캔 영역, 카메라 구조점 프리뷰, 품질 점수, 지도 방향")
    }

    private func scanMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.headline.weight(.black))
                .foregroundStyle(AdminTheme.violet)
            Text(value)
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(AdminTheme.ink)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(AdminTheme.softViolet.opacity(0.60), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var scanInstruction: some View {
        Text(scanner.status == .scanning ? scanActionText : "스캔 시작 전 카메라 권한을 확인하세요")
            .font(.headline).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private var scanOverlayGuide: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                .padding(28)
            VStack {
                HStack {
                    overlayChip("문·표지판")
                    Spacer()
                    overlayChip("벽면")
                }
                Spacer()
                HStack {
                    overlayChip("복도 중심")
                    Spacer()
                    overlayChip("엘리베이터·계단")
                }
            }
            .padding(38)
        }
        .allowsHitTesting(false)
        .opacity(scanner.status == .scanning ? 1 : 0)
    }

    @ViewBuilder private var qualityCard: some View {
        if scanner.status == .scanning {
            HStack(spacing: 14) {
                qualityScoreBadge
                VStack(alignment: .leading, spacing: 6) {
                    Text(qualitySummary)
                        .font(.headline.weight(.black))
                        .foregroundStyle(AdminTheme.ink)
                    Text(scanActionText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AdminTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .adminSurface(radius: 26, shadowOpacity: 0.07)
        } else {
            VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                qualityScoreBadge
                VStack(alignment: .leading, spacing: 7) {
                    Text("스캔 품질")
                        .font(.title2.weight(.black))
                    Text(qualitySummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            qualityRow("정상 추적 90% 이상", ok: scanner.normalTrackingRatio >= 0.9 || scanner.sampleCount == 0)
            qualityRow("평균 특징점 100개 이상", ok: scanner.averageFeaturePointCount >= 100 || scanner.sampleCount == 0)
            qualityRow("실시간 안정성 65점 이상", ok: scanner.scanStabilityScore >= 0.65 || scanner.sampleCount == 0)
            qualityRow("핵심 화면 20장 이상", ok: scanner.keyframeCount >= 20 || scanner.sampleCount == 0)
            qualityRow("이동 거리 8미터 이상", ok: scanner.totalDistance >= 8 || scanner.sampleCount == 0)
            qualityRow("스캔 커버리지 6미터 이상", ok: scanner.coverageSpanMeters >= 6 || scanner.sampleCount == 0)
            qualityRow("공간 구조점 40개 이상", ok: scanner.spatialPreviewPoints.count >= 40 || scanner.sampleCount == 0)
            qualityRow("학습 데이터셋 포즈·이미지·공간 샘플 확보", ok: scanner.keyframeCount >= 20 && scanner.spatialPreviewPoints.count >= 40 || scanner.sampleCount == 0)
            qualityRow("개인정보·문서 노출 최소화", ok: true)
            if !qualityIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("지금 더 해야 할 것").font(.headline)
                    ForEach(qualityIssues, id: \.self) { issue in
                        Label(issue, systemImage: "arrow.right.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AdminTheme.caution)
                    }
                }
                .padding(14)
                .background(AdminTheme.caution.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            }
            Text("서버는 자동으로 장면 그래프 초안을 만들지만, 문·계단·엘리베이터 같은 경로 요소는 관리자 승인 전 사용자 경로에 포함하지 않습니다.")
                .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(22)
            .adminSurface(radius: 28, shadowOpacity: 0.08)
        }
    }

    @ViewBuilder private var reviewCard: some View {
        if let graph = scanner.reviewGraph {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text("2D 게시 지도 검수")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(AdminTheme.ink)
                        .multilineTextAlignment(.center)
                    Text("서버가 만든 디지털트윈에서 사용자 앱용 2D 지도와 목적지 태그만 검수합니다")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AdminTheme.mutedInk)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    reviewStat("목적지", "\(semanticReviewNodes(in: graph).count)", AdminTheme.violet)
                    reviewStat("경로", "\(routeWaypointCount(in: graph))", AdminTheme.route)
                }
                ReviewMapOverview(graph: graph)
                    .frame(height: 300)
                aiReviewSummary(graph)
                PrePublishChecklist(graph: graph)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("후보 확인").font(.headline.weight(.black))
                        Spacer()
                        Text("\(reviewNodes(for: graph).count)개 표시")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    TextField("목적지 이름, 종류, 층으로 검색", text: $reviewSearchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                    if reviewNodes(for: graph).isEmpty {
                        ContentUnavailableView(
                            "검수할 목적지 후보가 없습니다",
                            systemImage: "sparkles",
                            description: Text("문, 표지판, 엘리베이터가 보이도록 다시 스캔하거나 경로만 게시할 수 있습니다.")
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(reviewNodes(for: graph)) { node in
                            ReviewNodeRow(node: node) { nodeID, status, labels, kind, floorID, center, accessible, restricted, hazard in
                                Task {
                                    await scanner.updateReviewNode(
                                        nodeID: nodeID,
                                        reviewStatus: status,
                                        labels: labels,
                                        kind: kind,
                                        floorID: floorID,
                                        center: center,
                                        accessible: accessible,
                                        restricted: restricted,
                                        hazard: hazard
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(AdminTheme.canvas.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                DisclosureGroup(isExpanded: $showAdvancedReview) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("좌표가 크게 틀어진 경우에만 사용하세요. 일반 검수에서는 이 영역을 건드리지 않아도 됩니다.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        EditableGraphMap(graph: graph) { node, center in
                            Task {
                                await scanner.updateReviewNode(
                                    nodeID: node.id,
                                    center: center
                                )
                            }
                        }
                        .frame(height: 280)
                        if !graph.relations.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("연결 관계")
                                    .font(.headline.weight(.black))
                                ForEach(graph.relations.prefix(24)) { relation in
                                    ReviewRelationRow(relation: relation) { status in
                                        Task { await scanner.updateReviewRelation(relation, reviewStatus: status) }
                                    } onAccessibility: { accessible in
                                        Task { await scanner.updateReviewRelationAccessibility(relation, accessible: accessible) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Label("고급 지도 보정", systemImage: "slider.horizontal.3")
                        .font(.headline.weight(.black))
                        .foregroundStyle(AdminTheme.ink)
                }
                .padding(14)
                .background(AdminTheme.canvas.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                VStack(spacing: 10) {
                    Button { Task { await scanner.publishReviewedScan() } } label: {
                        Text("현재 검수 상태로 게시")
                    }
                    .buttonStyle(AdminPrimaryButtonStyle())
                    Text("게시 후 사용자 앱에서 이 건물을 내려받을 수 있습니다. 확실하지 않은 후보는 먼저 거절하세요")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AdminTheme.mutedInk)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func aiReviewSummary(_ graph: SceneGraphValue) -> some View {
        let semanticNodes = semanticReviewNodes(in: graph)
        let destinations = semanticNodes.filter { $0.attributes["destination_candidate"] == "true" || $0.attributes["auto_review"] == "recommended" }
        let needsLabel = semanticNodes.filter { $0.attributes["needs_admin_review"] == "true" || $0.attributes["needs_human_label"] == "true" || $0.labels.first?.contains("표지판") == true }
        let verticals = semanticNodes.filter { ["elevator", "stairs", "escalator"].contains($0.attributes["node_type"] ?? $0.attributes["suggested_kind"] ?? $0.kind) }
        let hazards = semanticNodes.filter { $0.attributes["hazard"] == "true" }
        return VStack(alignment: .leading, spacing: 14) {
            Text("AI가 찾은 확인 항목")
                .font(.title3.weight(.black))
                .foregroundStyle(AdminTheme.ink)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    reviewStat("목적지", "\(destinations.count)", AdminTheme.safe)
                    reviewStat("이름 확인", "\(needsLabel.count)", AdminTheme.caution)
                }
                HStack(spacing: 8) {
                    reviewStat("층 이동", "\(verticals.count)", AdminTheme.violet)
                    reviewStat("주의", "\(hazards.count)", AdminTheme.danger)
                }
            }
            HStack(spacing: 10) {
                Button {
                    Task { await scanner.approveRecommendedCandidates() }
                } label: {
                    Label("추천만 적용", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(AdminSecondaryButtonStyle())
                Button {
                    Task { await scanner.approveRecommendedCandidates(publishAfterApproval: true) }
                } label: {
                    Label("추천 적용 후 게시", systemImage: "paperplane.fill")
                }
                .buttonStyle(AdminPrimaryButtonStyle())
            }
            Text("추천 적용은 스캔 경로와 신뢰도 높은 목적지를 승인합니다. 잘못 잡힌 방 이름이나 출입 제한 후보만 고친 뒤 게시하면 됩니다.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AdminTheme.mutedInk)
        }
        .padding(18)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.74), lineWidth: 1))
        .shadow(color: AdminTheme.shadow(0.06), radius: 14, y: 7)
    }

    private func reviewStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.black))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func routeWaypointCount(in graph: SceneGraphValue) -> Int {
        graph.nodes.filter { $0.id.hasPrefix("trajectory:") && $0.reviewStatus != "rejected" }.count
    }

    private func reviewNodes(for graph: SceneGraphValue) -> [SceneGraphNodeValue] {
        let nodes = semanticReviewNodes(in: graph)
        let query = reviewSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
        guard !query.isEmpty else { return nodes }
        return nodes.filter { node in
            let searchable = ([node.id, node.kind, node.floorId ?? ""] + node.labels)
                .joined(separator: " ")
                .lowercased()
                .filter { !$0.isWhitespace }
            return searchable.contains(query)
        }
    }

    private func semanticReviewNodes(in graph: SceneGraphValue) -> [SceneGraphNodeValue] {
        graph.nodes
            .filter { !$0.id.hasPrefix("trajectory:") && !["floor", "space_sample"].contains($0.kind) }
            .sorted { lhs, rhs in
                let lhsPriority = reviewPriority(lhs)
                let rhsPriority = reviewPriority(rhs)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.id < rhs.id
            }
    }

    private func reviewPriority(_ node: SceneGraphNodeValue) -> Int {
        if node.attributes["hazard"] == "true" { return 0 }
        if node.attributes["needs_admin_review"] == "true" || node.attributes["needs_human_label"] == "true" { return 1 }
        let nodeType = node.attributes["node_type"] ?? node.attributes["suggested_kind"] ?? node.kind
        if ["elevator", "stairs", "escalator"].contains(nodeType) { return 2 }
        if node.attributes["destination_candidate"] == "true" || node.attributes["auto_review"] == "recommended" { return 3 }
        return 4
    }

    private func qualityRow(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? AdminTheme.safe : AdminTheme.caution)
                .font(.headline.weight(.black))
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(AdminTheme.ink)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background((ok ? AdminTheme.safe : AdminTheme.caution).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var qualityScoreBadge: some View {
        ZStack {
            Circle().stroke(.black.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: qualityScore)
                .stroke(qualityColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((qualityScore * 100).rounded()))")
                    .font(.title3.monospacedDigit().weight(.black))
                Text("점")
                    .font(.caption2.weight(.bold))
            }
        }
        .frame(width: 76, height: 76)
        .accessibilityLabel("스캔 품질 점수 \(Int((qualityScore * 100).rounded()))점")
    }

    private var statusBadge: some View {
        Label(scanner.status.title, systemImage: scanner.status.symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(statusColor, in: Capsule())
    }

    private var statusColor: Color {
        switch scanner.status {
        case .ready, .captured: AdminTheme.violet
        case .scanning, .uploading: AdminTheme.caution
        case .uploaded: AdminTheme.safe
        case .failed: AdminTheme.danger
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("실행")
                    .font(.headline.weight(.black))
                Spacer()
                Text(scanner.status.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
            if scanner.status == .scanning {
                Button(role: .destructive) {
                    scanner.stopScan()
                    if canUpload && scanner.completedManifest != nil {
                        showsUploadInfoSheet = true
                    }
                } label: { Label("스캔 끝내기", systemImage: "stop.fill") }
                    .buttonStyle(AdminPrimaryButtonStyle())
            } else {
                Button { showsSpaceInfoSheet = true } label: { Label("스캔 시작", systemImage: "camera.viewfinder") }
                    .buttonStyle(AdminPrimaryButtonStyle())
            }
            if scanner.completedManifest != nil {
                Button { showsUploadInfoSheet = true } label: {
                    Label("건물 정보 확인 후 업로드", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.status == .uploading)
            }
            if let message = scanner.message {
                Text(message).font(.footnote).foregroundStyle(scanner.status == .failed ? AdminTheme.danger : .secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if scanner.status == .uploading {
                ProgressView(value: scanner.processingProgress)
                    .tint(AdminTheme.violet)
                    .accessibilityLabel("서버 처리 진행률")
                    .accessibilityValue(scanner.processingProgress.formatted(.percent.precision(.fractionLength(0))))
            }
        }
        .padding(18)
        .adminSurface(radius: 26, shadowOpacity: 0.07)
    }

    private var canStart: Bool {
        !buildingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !floorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canUpload: Bool {
        !buildingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var floorOptions: [String] {
        let basements = (1...6).reversed().map { "B\($0)층" }
        let aboveGround = (1...30).map { "\($0)층" }
        return Array(basements) + aboveGround
    }

    private var qualityScore: Double {
        if scanner.sampleCount == 0 {
            return scanner.isRecordingPath ? 0.16 : min(scanner.scanStabilityScore * 0.55, 0.42)
        }
        let tracking = min(scanner.normalTrackingRatio / 0.9, 1)
        let features = min(scanner.averageFeaturePointCount / 100, 1)
        let stability = min(scanner.scanStabilityScore / 0.65, 1)
        let keyframes = min(Double(scanner.keyframeCount) / 20, 1)
        let distance = min(scanner.totalDistance / 8, 1)
        let coverage = min(scanner.coverageSpanMeters / 6, 1)
        let spatial = min(Double(scanner.spatialPreviewPoints.count) / 80, 1)
        return max(0, min(1, tracking * 0.23 + features * 0.18 + stability * 0.16 + keyframes * 0.20 + distance * 0.09 + coverage * 0.08 + spatial * 0.06))
    }

    private var qualityColor: Color {
        if qualityScore >= 0.86 { return AdminTheme.safe }
        if qualityScore >= 0.58 { return AdminTheme.caution }
        return AdminTheme.danger
    }

    private var qualitySummary: String {
        if scanner.sampleCount == 0 {
            return scanner.isRecordingPath ? "경로 기록을 시작했습니다." : "초기 기준점을 잡는 중입니다."
        }
        if qualityScore >= 0.86 { return "게시 전 검수로 넘어갈 수 있는 수준입니다." }
        if qualityScore >= 0.58 { return "사용 가능하지만 핵심 화면이나 추적 안정성이 더 필요합니다." }
        return "후처리 실패 가능성이 큽니다. 천천히 다시 훑어 주세요."
    }

    private var qualityIssues: [String] {
        guard scanner.sampleCount > 0 else { return [] }
        var issues: [String] = []
        if scanner.normalTrackingRatio < 0.9 {
            issues.append("휴대폰을 천천히 움직이고 어두운 벽이나 바닥만 비추지 마세요.")
        }
        if scanner.averageFeaturePointCount < 100 {
            issues.append("흰 벽보다 문, 표지판, 모서리, 가구처럼 특징이 많은 곳을 비춰 주세요.")
        }
        if scanner.scanStabilityScore < 0.65 {
            issues.append("급하게 걷거나 회전하지 말고 휴대폰을 천천히 훑어 주세요.")
        }
        if scanner.keyframeCount < 20 {
            issues.append("VGGT가 구조를 잡을 수 있게 문, 표지판, 벽면, 바닥 경계를 여러 각도에서 더 오래 훑어 주세요.")
        }
        if scanner.spatialPreviewPoints.count < 40 {
            issues.append("서버 재구성에 필요한 특징점이 부족합니다. 바닥과 벽이 함께 보이게 천천히 스캔해 주세요.")
        }
        if scanner.totalDistance < 8 {
            issues.append("복도 중심선을 따라 최소 \(Int(ceil(8 - scanner.totalDistance)))미터 더 걸어 주세요.")
        }
        if scanner.coverageSpanMeters < 6 {
            issues.append("한 지점 주변만 비추지 말고 시작점과 끝점이 충분히 벌어지도록 이동해 주세요.")
        }
        return issues
    }

    private var scanActionText: String {
        if !scanner.isRecordingPath {
            return "제자리에서 문·표지판·모서리를 비춰 기준점을 잡아 주세요"
        }
        if scanner.trackingJumpCount > 0 && scanner.scanStabilityScore < 0.70 {
            return "위치가 흔들렸습니다. 잠시 멈추고 같은 벽면을 다시 비춰 주세요"
        }
        if scanner.normalTrackingRatio < 0.75 && scanner.sampleCount > 10 {
            return "추적이 불안정합니다. 속도를 줄이고 특징이 많은 벽면을 비춰 주세요"
        }
        if scanner.averageFeaturePointCount < 100 && scanner.sampleCount > 10 {
            return "흰 벽보다 문·표지판·모서리가 보이게 비춰 주세요"
        }
        if scanner.scanStabilityScore < 0.65 && scanner.sampleCount > 10 {
            return "너무 빠릅니다. 천천히 걷고 휴대폰 회전을 줄여 주세요"
        }
        if scanner.spatialPreviewPoints.count < 40 && scanner.sampleCount > 6 {
            return "바닥과 벽을 함께 비춰 서버 재구성용 특징점을 더 모아 주세요"
        }
        if scanner.keyframeCount < 20 {
            return "VGGT용 핵심 화면을 모으는 중입니다. 벽·바닥·문을 천천히 훑어 주세요"
        }
        if scanner.totalDistance < 8 {
            return "복도 중심선을 따라 조금 더 이동해 주세요"
        }
        if scanner.coverageSpanMeters < 6 {
            return "시작점과 끝점이 충분히 벌어지도록 복도 방향으로 더 이동해 주세요"
        }
        return "품질이 좋습니다. 누락 구역만 한 번 더 비춰 주세요"
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 5) { Text(value).font(.title3.weight(.black)); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }

    private func overlayChip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.48), in: Capsule())
    }
}

private final class AdminAddressLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLoading = false
    @Published var message: String?
    @Published var isError = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var completion: ((String) -> Void)?
    private var bestLocation: CLLocation?
    private var timeoutTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var geocodeAttempt = 0
    private var isGeocoding = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func fillCurrentAddress(_ completion: @escaping (String) -> Void) {
        guard CLLocationManager.locationServicesEnabled() else {
            update(message: "위치 서비스가 꺼져 있습니다.", isError: true, loading: false)
            return
        }
        self.completion = completion
        bestLocation = nil
        geocodeAttempt = 0
        isGeocoding = false
        timeoutTask?.cancel()
        retryTask?.cancel()
        geocoder.cancelGeocode()
        update(message: "현재 위치를 확인하고 있습니다.", isError: false, loading: true)
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            scheduleGeocodeTimeout()
        case .denied, .restricted:
            update(message: "설정에서 위치 권한을 허용하면 현재 주소를 자동 입력할 수 있습니다.", isError: true, loading: false)
        @unknown default:
            update(message: "위치 권한 상태를 확인할 수 없습니다.", isError: true, loading: false)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            scheduleGeocodeTimeout()
        case .denied, .restricted:
            update(message: "설정에서 위치 권한을 허용하면 현재 주소를 자동 입력할 수 있습니다.", isError: true, loading: false)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            update(message: "현재 위치를 찾지 못했습니다.", isError: true, loading: false)
            return
        }
        if location.horizontalAccuracy >= 0,
           bestLocation == nil || location.horizontalAccuracy < (bestLocation?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
            bestLocation = location
        }
        if !isGeocoding, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 25 {
            geocode(location)
        }
    }

    private func scheduleGeocodeTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                guard let self, self.isLoading, !self.isGeocoding else { return }
                if let bestLocation = self.bestLocation {
                    self.geocode(bestLocation)
                } else {
                    self.manager.requestLocation()
                    self.scheduleGeocodeTimeout()
                }
            }
        }
    }

    private func geocode(_ location: CLLocation) {
        guard !isGeocoding else { return }
        isGeocoding = true
        geocodeAttempt += 1
        timeoutTask?.cancel()
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ko_KR")) { [weak self] placemarks, error in
            guard let self else { return }
            self.isGeocoding = false
            if let error {
                self.update(message: "건물번호가 있는 주소를 다시 찾는 중입니다. \(error.localizedDescription)", isError: false, loading: true)
                self.scheduleRetry()
                return
            }
            guard let placemark = placemarks?.first, let address = self.addressText(from: placemark) else {
                self.update(message: "현재 위치 주소를 다시 확인하고 있습니다.", isError: false, loading: true)
                self.scheduleRetry()
                return
            }
            guard self.containsStreetNumber(address) else {
                self.update(message: "건물번호가 포함된 주소를 찾는 중입니다. \(self.geocodeAttempt)회 시도", isError: false, loading: true)
                self.scheduleRetry()
                return
            }
            DispatchQueue.main.async {
                self.manager.stopUpdatingLocation()
                self.timeoutTask?.cancel()
                self.retryTask?.cancel()
                self.completion?(address)
                self.completion = nil
                self.isLoading = false
                self.isError = false
                self.message = "건물번호가 포함된 현재 주소를 입력했습니다."
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        update(message: "현재 위치 확인 실패: \(error.localizedDescription)", isError: true, loading: false)
    }

    private func addressText(from placemark: CLPlacemark) -> String? {
        if let postalAddress = placemark.postalAddress {
            let formatted = CNPostalAddressFormatter
                .string(from: postalAddress, style: .mailingAddress)
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { line in
                    !line.isEmpty
                    && line != postalAddress.country
                    && line != postalAddress.postalCode
                    && !line.allSatisfy(\.isNumber)
                }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty, containsStreetNumber(formatted) || placemark.subThoroughfare != nil {
                return formatted
            }
        }

        var parts: [String] = []
        appendUnique(placemark.administrativeArea, to: &parts)
        appendUnique(placemark.locality, to: &parts)
        appendUnique(placemark.subLocality, to: &parts)
        appendUnique(placemark.thoroughfare, to: &parts)
        appendUnique(placemark.subThoroughfare, to: &parts)
        if placemark.subThoroughfare == nil {
            appendAddressNameIfUseful(placemark.name, to: &parts)
        }
        if parts.isEmpty {
            appendAddressNameIfUseful(placemark.name, to: &parts)
        }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                guard let self, self.isLoading, self.completion != nil, !self.isGeocoding else { return }
                if let bestLocation = self.bestLocation {
                    self.manager.startUpdatingLocation()
                    self.geocode(bestLocation)
                } else {
                    self.manager.requestLocation()
                    self.scheduleGeocodeTimeout()
                }
            }
        }
    }

    private func appendUnique(_ value: String?, to parts: inout [String]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        guard !parts.contains(value) else { return }
        parts.append(value)
    }

    private func appendAddressNameIfUseful(_ value: String?, to parts: inout [String]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        guard containsStreetNumber(value) || parts.isEmpty else { return }
        appendUnique(value, to: &parts)
    }

    private func containsStreetNumber(_ value: String) -> Bool {
        value.range(of: #"\d+(-\d+)?"#, options: .regularExpression) != nil
    }

    private func update(message: String, isError: Bool, loading: Bool) {
        DispatchQueue.main.async {
            self.message = message
            self.isError = isError
            self.isLoading = loading
            if isError {
                self.completion = nil
                self.manager.stopUpdatingLocation()
                self.timeoutTask?.cancel()
                self.retryTask?.cancel()
                self.isGeocoding = false
                self.geocoder.cancelGeocode()
            }
        }
    }
}

private struct ReviewMapOverview: View {
    let graph: SceneGraphValue

    private var visibleNodes: [SceneGraphNodeValue] {
        graph.nodes.filter { !["floor", "space_sample"].contains($0.kind) && $0.reviewStatus != "rejected" }
    }

    private var routeNodes: [SceneGraphNodeValue] {
        graph.nodes
            .filter { $0.id.hasPrefix("trajectory:") && $0.reviewStatus != "rejected" }
            .sorted { lhs, rhs in
                trajectoryIndex(lhs.id) < trajectoryIndex(rhs.id)
            }
    }

    private var destinationNodes: [SceneGraphNodeValue] {
        graph.nodes
            .filter { !$0.id.hasPrefix("trajectory:") && !["floor", "space_sample"].contains($0.kind) && $0.reviewStatus != "rejected" }
            .sorted { lhs, rhs in
                if nodePriority(lhs) != nodePriority(rhs) { return nodePriority(lhs) < nodePriority(rhs) }
                return lhs.id < rhs.id
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("생성된 지도 미리보기", systemImage: "map.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(AdminTheme.ink)
                Spacer()
                Text("경로 \(routeNodes.count)개 · 후보 \(destinationNodes.count)개")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AdminTheme.mutedInk)
            }
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.96), AdminTheme.softViolet.opacity(0.46)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    grid(in: proxy.size)
                        .stroke(AdminTheme.stroke.opacity(0.58), lineWidth: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if routeNodes.count >= 2 {
                        Path { path in
                            path.move(to: point(for: routeNodes[0], in: proxy.size))
                            for node in routeNodes.dropFirst() {
                                path.addLine(to: point(for: node, in: proxy.size))
                            }
                        }
                        .stroke(AdminTheme.violet, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(routeNodes) { node in
                        Circle()
                            .fill(AdminTheme.violet)
                            .frame(width: node.id == routeNodes.first?.id || node.id == routeNodes.last?.id ? 17 : 11)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .position(point(for: node, in: proxy.size))
                            .accessibilityHidden(true)
                    }
                    ForEach(destinationNodes.prefix(18)) { node in
                        MapCandidateMarker(node: node)
                            .position(point(for: node, in: proxy.size))
                    }
                    if routeNodes.count < 2 {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2.weight(.black))
                            Text("스캔 경로가 부족합니다")
                                .font(.headline.weight(.black))
                            Text("복도 중심으로 조금 더 이동하며 다시 스캔하세요")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(AdminTheme.caution)
                    }
                    VStack {
                        HStack {
                            Spacer()
                            Text("북")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(AdminTheme.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.92), in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            HStack(spacing: 8) {
                legend("경로", color: AdminTheme.violet)
                legend("목적지", color: AdminTheme.safe)
                legend("확인", color: AdminTheme.caution)
                legend("주의", color: AdminTheme.danger)
            }
            .font(.caption.weight(.bold))
        }
        .padding(16)
        .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.78), lineWidth: 1))
        .shadow(color: AdminTheme.shadow(0.07), radius: 16, y: 8)
    }

    private func grid(in size: CGSize) -> Path {
        Path { path in
            for ratio in [0.25, 0.5, 0.75] {
                let x = size.width * ratio
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * ratio
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    private func point(for node: SceneGraphNodeValue, in size: CGSize) -> CGPoint {
        let nodes = visibleNodes.isEmpty ? [node] : visibleNodes
        let xs = nodes.map { Double($0.geometry.center.x) }
        let zs = nodes.map { Double($0.geometry.center.z) }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
        let padding = 30.0
        return CGPoint(
            x: padding + (Double(node.geometry.center.x) - minX) / max(maxX - minX, 1) * (size.width - padding * 2),
            y: size.height - padding - (Double(node.geometry.center.z) - minZ) / max(maxZ - minZ, 1) * (size.height - padding * 2)
        )
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(AdminTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }

    private func trajectoryIndex(_ id: String) -> Int {
        Int(id.split(separator: ":").last ?? "") ?? 0
    }

    private func nodePriority(_ node: SceneGraphNodeValue) -> Int {
        if node.attributes["hazard"] == "true" { return 0 }
        if node.attributes["needs_admin_review"] == "true" || node.attributes["needs_human_label"] == "true" { return 1 }
        if node.attributes["destination_candidate"] == "true" || node.attributes["auto_review"] == "recommended" { return 2 }
        return 3
    }
}

private struct MapCandidateMarker: View {
    let node: SceneGraphNodeValue

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: color.opacity(0.28), radius: 7, y: 4)
            Text(node.labels.first ?? node.id)
                .font(.caption2.weight(.black))
                .foregroundStyle(AdminTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white.opacity(0.88), in: Capsule())
        }
        .frame(width: 92)
        .accessibilityLabel("\(node.labels.first ?? node.id) 후보")
    }

    private var color: Color {
        if node.attributes["hazard"] == "true" { return AdminTheme.danger }
        if node.attributes["needs_admin_review"] == "true" || node.attributes["needs_human_label"] == "true" { return AdminTheme.caution }
        if node.attributes["destination_candidate"] == "true" || node.attributes["auto_review"] == "recommended" { return AdminTheme.safe }
        return AdminTheme.route
    }

    private var symbol: String {
        let type = node.attributes["node_type"] ?? node.attributes["suggested_kind"] ?? node.kind
        switch type {
        case "elevator": return "arrow.up.arrow.down"
        case "stairs", "escalator": return "stairs"
        case "door": return "door.left.hand.open"
        case "room": return "mappin.and.ellipse"
        default: return node.attributes["hazard"] == "true" ? "exclamationmark" : "sparkle"
        }
    }
}

private struct EditableGraphMap: View {
    let graph: SceneGraphValue
    let onMove: (_ node: SceneGraphNodeValue, _ center: Vector3Value) -> Void
    @State private var selectedNodeID: String?
    @State private var dragPreview: [String: Vector3Value] = [:]

    private var editableNodes: [SceneGraphNodeValue] {
        graph.nodes.filter { !["floor", "space_sample"].contains($0.kind) && $0.reviewStatus != "rejected" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("지도 편집", systemImage: "map.fill")
                    .font(.headline)
                Spacer()
                Text("점을 끌어서 이동하거나 버튼으로 미세 보정")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AdminTheme.canvas, AdminTheme.softViolet.opacity(0.40)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    grid(in: proxy.size)
                        .stroke(AdminTheme.stroke.opacity(0.55), lineWidth: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    ForEach(graph.relations) { relation in
                        if let source = editableNodes.first(where: { $0.id == relation.sourceId }),
                           let target = editableNodes.first(where: { $0.id == relation.targetId }),
                           relation.reviewStatus != "rejected" {
                            Path { path in
                                path.move(to: point(for: source, in: proxy.size))
                                path.addLine(to: point(for: target, in: proxy.size))
                            }
                            .stroke(relation.attributes["accessible"] == "false" ? AdminTheme.danger.opacity(0.55) : AdminTheme.violet.opacity(0.55), lineWidth: 4)
                        }
                    }
                    ForEach(editableNodes) { node in
                        let selected = selectedNodeID == node.id
                        Button {
                            selectedNodeID = node.id
                        } label: {
                            Circle()
                                .fill(nodeColor(node))
                                .frame(width: selected ? 24 : 17, height: selected ? 24 : 17)
                                .overlay(Circle().stroke(.white, lineWidth: selected ? 4 : 2))
                                .shadow(radius: selected ? 5 : 1)
                        }
                        .position(point(for: previewNode(node), in: proxy.size))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    selectedNodeID = node.id
                                    dragPreview[node.id] = center(from: value.location, original: node, in: proxy.size)
                                }
                                .onEnded { value in
                                    let center = center(from: value.location, original: node, in: proxy.size)
                                    dragPreview[node.id] = nil
                                    onMove(node, center)
                                }
                        )
                        .accessibilityLabel("\(node.labels.first ?? node.id) 지도 위치")
                    }
                }
            }
            if let node = editableNodes.first(where: { $0.id == selectedNodeID }) {
                HStack(spacing: 8) {
                    Text(node.labels.first ?? node.id)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    Button("위") { move(node, dx: 0, dz: 0.5) }
                    Button("아래") { move(node, dx: 0, dz: -0.5) }
                    Button("왼쪽") { move(node, dx: -0.5, dz: 0) }
                    Button("오른쪽") { move(node, dx: 0.5, dz: 0) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminTheme.stroke.opacity(0.70), lineWidth: 1)
        )
    }

    private func grid(in size: CGSize) -> Path {
        Path { path in
            for ratio in [0.25, 0.5, 0.75] {
                let x = size.width * ratio
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * ratio
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
    }

    private func move(_ node: SceneGraphNodeValue, dx: Float, dz: Float) {
        onMove(
            node,
            Vector3Value(
                x: node.geometry.center.x + dx,
                y: node.geometry.center.y,
                z: node.geometry.center.z + dz
            )
        )
    }

    private func previewNode(_ node: SceneGraphNodeValue) -> SceneGraphNodeValue {
        guard let center = dragPreview[node.id] else { return node }
        let geometry = SceneNodeGeometryValue(center: center, covarianceDiagonal: node.geometry.covarianceDiagonal)
        return SceneGraphNodeValue(
            id: node.id,
            kind: node.kind,
            floorId: node.floorId,
            geometry: geometry,
            labels: node.labels,
            semanticConfidence: node.semanticConfidence,
            reviewStatus: node.reviewStatus,
            attributes: node.attributes
        )
    }

    private func nodeColor(_ node: SceneGraphNodeValue) -> Color {
        if node.attributes["hazard"] == "true" { return AdminTheme.danger }
        if node.attributes["accessible"] == "false" || node.attributes["restricted"] == "true" { return AdminTheme.caution }
        if node.kind == "object" { return AdminTheme.safe }
        return AdminTheme.violet
    }

    private func point(for node: SceneGraphNodeValue, in size: CGSize) -> CGPoint {
        let nodes = editableNodes.isEmpty ? [node] : editableNodes
        let xs = nodes.map { Double($0.geometry.center.x) }
        let zs = nodes.map { Double($0.geometry.center.z) }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
        let padding = 28.0
        return CGPoint(
            x: padding + (Double(node.geometry.center.x) - minX) / max(maxX - minX, 1) * (size.width - padding * 2),
            y: size.height - padding - (Double(node.geometry.center.z) - minZ) / max(maxZ - minZ, 1) * (size.height - padding * 2)
        )
    }

    private func center(from point: CGPoint, original node: SceneGraphNodeValue, in size: CGSize) -> Vector3Value {
        let nodes = editableNodes.isEmpty ? [node] : editableNodes
        let xs = nodes.map { Double($0.geometry.center.x) }
        let zs = nodes.map { Double($0.geometry.center.z) }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
        let padding = 28.0
        let normalizedX = min(max((point.x - padding) / max(size.width - padding * 2, 1), 0), 1)
        let normalizedZ = min(max((size.height - padding - point.y) / max(size.height - padding * 2, 1), 0), 1)
        return Vector3Value(
            x: Float(minX + normalizedX * max(maxX - minX, 1)),
            y: node.geometry.center.y,
            z: Float(minZ + normalizedZ * max(maxZ - minZ, 1))
        )
    }
}

private struct MiniSpatialScanMap: View {
    let path: [Vector3Value]
    let spatialPoints: [Vector3Value]
    let headingDegrees: Double
    let supportsMeshReconstruction: Bool
    let meshAnchorCount: Int
    let planeAnchorCount: Int
    let meshVertexCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.965, green: 0.972, blue: 0.990).opacity(0.96))
            MiniSpatialSceneView(
                path: path,
                spatialPoints: spatialPoints,
                headingDegrees: headingDegrees,
                hasMesh: meshAnchorCount > 0
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.70), lineWidth: 1)
            )
            .opacity(path.isEmpty && spatialPoints.isEmpty ? 0.16 : 1)

            if path.isEmpty && spatialPoints.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.black))
                    Text("특징점 스캔")
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(AdminTheme.violet)
            }

            VStack {
                HStack {
                    Text(primaryStatusText)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(meshAnchorCount > 0 ? AdminTheme.safe : AdminTheme.violet)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.90), in: Capsule())
                    Spacer()
                    Text("스캔")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(AdminTheme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.90), in: Capsule())
                }
                Spacer()
            }
            .padding(7)
            VStack {
                Spacer()
                HStack {
                    Label("\(planeAnchorCount)", systemImage: "square.split.diagonal.2x2")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(AdminTheme.mutedInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.88), in: Capsule())
                    Spacer()
                    if meshAnchorCount == 0 && !spatialPoints.isEmpty {
                        Text(supportsMeshReconstruction ? "표면 보조" : "후처리용")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(supportsMeshReconstruction ? AdminTheme.caution : AdminTheme.violet)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.88), in: Capsule())
                    }
                }
            }
            .padding(7)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
    }

    private var primaryStatusText: String {
        if meshAnchorCount > 0 {
            return "보조 \(compactCount(meshVertexCount))"
        }
        if supportsMeshReconstruction {
            return "구조점 \(spatialPoints.count)"
        }
        return "카메라 \(spatialPoints.count)"
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 1000 {
            return "\(value / 1000)k"
        }
        return "\(value)"
    }
}

private struct MiniSpatialSceneView: UIViewRepresentable {
    let path: [Vector3Value]
    let spatialPoints: [Vector3Value]
    let headingDegrees: Double
    let hasMesh: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let scene = makeScene()
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: "mini-camera", recursively: false)
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let reference = Array((path + spatialPoints).suffix(360))
        let bounds = SpatialBounds(points: reference)
        let root = SCNNode()
        scene.rootNode.addChildNode(root)

        addLights(to: scene)
        addGrid(to: root, bounds: bounds)
        addSpatialPoints(to: root, bounds: bounds)
        addPath(to: root, bounds: bounds)
        addCurrentPose(to: root, bounds: bounds)
        addCamera(to: scene, bounds: bounds)

        return scene
    }

    private func addLights(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 820
        key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)
    }

    private func addCamera(to scene: SCNScene, bounds: SpatialBounds) {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = max(Double(bounds.radius) * 2.45, 2.4)
        camera.name = "mini-camera"
        camera.position = SCNVector3(0, max(bounds.radius * 1.25, 2.2), max(bounds.radius * 1.85, 3.0))
        camera.eulerAngles = SCNVector3(-Float.pi * 0.34, 0, 0)
        scene.rootNode.addChildNode(camera)
    }

    private func addGrid(to root: SCNNode, bounds: SpatialBounds) {
        let extent = max(bounds.radius, 1.2)
        let floorY = bounds.floorY - 0.02
        let material = lineMaterial(UIColor(white: 1.0, alpha: 0.45))
        let steps = 4
        for index in -steps...steps {
            let offset = Float(index) * extent / Float(steps)
            root.addChildNode(lineNode(
                from: SCNVector3(-extent, floorY, offset),
                to: SCNVector3(extent, floorY, offset),
                material: material
            ))
            root.addChildNode(lineNode(
                from: SCNVector3(offset, floorY, -extent),
                to: SCNVector3(offset, floorY, extent),
                material: material
            ))
        }
    }

    private func addSpatialPoints(to root: SCNNode, bounds: SpatialBounds) {
        let points = Array(spatialPoints.prefix(hasMesh ? 260 : 140))
        guard !points.isEmpty else { return }
        let radius: CGFloat = hasMesh ? 0.025 : 0.018
        for point in points {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 8
            sphere.firstMaterial = pointMaterial(for: point, hasMesh: hasMesh)
            let node = SCNNode(geometry: sphere)
            node.position = bounds.scenePoint(point)
            root.addChildNode(node)
        }
    }

    private func addPath(to root: SCNNode, bounds: SpatialBounds) {
        guard path.count >= 2 else { return }
        let material = lineMaterial(UIColor(red: 0.42, green: 0.32, blue: 1.0, alpha: 1.0))
        let points = path.map { bounds.scenePoint($0) }
        for pair in zip(points, points.dropFirst()) {
            root.addChildNode(lineNode(from: pair.0, to: pair.1, material: material))
        }
    }

    private func addCurrentPose(to root: SCNNode, bounds: SpatialBounds) {
        guard let current = path.last else { return }
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.28)
        cone.firstMaterial = material(UIColor(red: 0.42, green: 0.32, blue: 1.0, alpha: 1.0), emission: 0.18)
        let node = SCNNode(geometry: cone)
        node.position = bounds.scenePoint(current) + SCNVector3(0, 0.10, 0)
        node.eulerAngles = SCNVector3(Float.pi / 2, Float(-headingDegrees * .pi / 180), 0)
        root.addChildNode(node)
    }

    private func lineNode(from: SCNVector3, to: SCNVector3, material: SCNMaterial) -> SCNNode {
        let source = SCNGeometrySource(vertices: [from, to])
        let indices: [Int32] = [0, 1]
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: MemoryLayout<Int32>.size)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func pointMaterial(for point: Vector3Value, hasMesh: Bool) -> SCNMaterial {
        if !hasMesh {
            return material(UIColor(red: 0.47, green: 0.40, blue: 0.96, alpha: 0.70), emission: 0.08)
        }
        if point.y < -0.22 {
            return material(UIColor(red: 0.05, green: 0.55, blue: 0.95, alpha: 0.82), emission: 0.10)
        }
        if point.y > 0.85 {
            return material(UIColor(red: 1.0, green: 0.56, blue: 0.12, alpha: 0.86), emission: 0.10)
        }
        return material(UIColor(red: 0.06, green: 0.70, blue: 0.43, alpha: 0.82), emission: 0.10)
    }

    private func lineMaterial(_ color: UIColor) -> SCNMaterial {
        material(color, emission: 0.05)
    }

    private func material(_ color: UIColor, emission: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(emission)
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }
}

private struct SpatialBounds {
    let centerX: Float
    let centerY: Float
    let centerZ: Float
    let radius: Float
    let floorY: Float

    init(points: [Vector3Value]) {
        guard !points.isEmpty else {
            centerX = 0
            centerY = 0
            centerZ = 0
            radius = 1.4
            floorY = -0.04
            return
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let zs = points.map(\.z)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
        centerX = (minX + maxX) / 2
        centerY = (minY + maxY) / 2
        centerZ = (minZ + maxZ) / 2
        radius = max(max(maxX - minX, maxZ - minZ), maxY - minY) / 2 + 0.55
        floorY = minY - centerY
    }

    func scenePoint(_ point: Vector3Value) -> SCNVector3 {
        SCNVector3(point.x - centerX, point.y - centerY, point.z - centerZ)
    }
}

private func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}

private struct PrePublishChecklist: View {
    let graph: SceneGraphValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("게시 전 최종 확인", systemImage: isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(isReady ? AdminTheme.safe : AdminTheme.caution)
            checklistRow("보행 경로 노드 2개 이상", ok: routeNodes.count >= 2)
            checklistRow("차단되지 않은 경로 연결 1개 이상", ok: publishablePathRelations >= 1)
            checklistRow("계단·엘리베이터 층 정보 입력", ok: floorTransitionNodesReady)
            checklistRow("위험·출입 제한 후보 확인", ok: hazardAndRestrictedReviewed)
            if !blockingMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(blockingMessages, id: \.self) { message in
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AdminTheme.caution)
                    }
                }
                .padding(10)
                .background(AdminTheme.caution.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminTheme.stroke.opacity(0.70), lineWidth: 1)
        )
    }

    private var routeNodes: [SceneGraphNodeValue] {
        graph.nodes.filter { $0.id.hasPrefix("trajectory:") && $0.reviewStatus != "rejected" }
    }

    private var publishablePathRelations: Int {
        graph.relations.filter { $0.predicate == "scan_path_connected" && $0.reviewStatus != "rejected" && $0.attributes["accessible"] != "false" }.count
    }

    private var floorTransitionNodesReady: Bool {
        graph.nodes
            .filter { ["stairs", "elevator"].contains($0.kind) && $0.reviewStatus != "rejected" }
            .allSatisfy { !($0.floorId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var hazardAndRestrictedReviewed: Bool {
        graph.nodes
            .filter { $0.attributes["hazard"] == "true" || $0.attributes["restricted"] == "true" }
            .allSatisfy { $0.reviewStatus != "candidate" }
    }

    private var isReady: Bool {
        routeNodes.count >= 2 && publishablePathRelations >= 1 && floorTransitionNodesReady && hazardAndRestrictedReviewed
    }

    private var blockingMessages: [String] {
        var messages: [String] = []
        if routeNodes.count < 2 {
            messages.append("경로 노드가 부족합니다. 복도 중심 경로를 더 승인하세요.")
        }
        if publishablePathRelations < 1 {
            messages.append("사용 가능한 경로 연결이 없습니다. 연결 관계를 확인하세요.")
        }
        if !floorTransitionNodesReady {
            messages.append("계단·엘리베이터 노드의 층 이름을 입력하세요.")
        }
        if !hazardAndRestrictedReviewed {
            messages.append("위험 구역 또는 출입 제한 후보를 승인/거절로 확정하세요.")
        }
        return messages
    }

    private func checklistRow(_ title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(ok ? AdminTheme.safe : AdminTheme.caution)
    }
}

private struct ReviewRelationRow: View {
    let relation: SceneGraphRelationValue
    let onSave: (_ status: String) -> Void
    let onAccessibility: (_ accessible: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(predicateTitle)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminTheme.violet, in: Capsule())
                Text(statusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(relation.confidence.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(relation.sourceId) → \(relation.targetId)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AdminTheme.ink)
            HStack(spacing: 8) {
                Button("승인") { onSave("approved") }
                    .buttonStyle(.borderedProminent)
                    .tint(AdminTheme.safe)
                Button("거절") { onSave("rejected") }
                    .buttonStyle(.bordered)
                    .tint(AdminTheme.danger)
                Button("후보") { onSave("candidate") }
                    .buttonStyle(.bordered)
            }
            Toggle("접근 가능한 연결", isOn: Binding(
                get: { relation.attributes["accessible"] != "false" },
                set: { onAccessibility($0) }
            ))
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var predicateTitle: String {
        switch relation.predicate {
        case "scan_path_connected": "경로 연결"
        default: relation.predicate
        }
    }

    private var statusTitle: String {
        switch relation.reviewStatus {
        case "approved": "승인됨"
        case "rejected": "거절됨"
        default: "검수 전"
        }
    }

    private var statusColor: Color {
        switch relation.reviewStatus {
        case "approved": AdminTheme.safe
        case "rejected": AdminTheme.danger
        default: AdminTheme.caution
        }
    }
}

private struct PackageVersionRow: View {
    let version: PackageVersionInfoValue
    let onRollback: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(version.version)판")
                        .font(.headline.weight(.black))
                    Text(statusTitle)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }
                Text("노드 \(version.nodeCount)개 · 연결 \(version.edgeCount)개")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let sourceScan = version.sourceScan {
                    Text("스캔 \(sourceScan.prefix(8))")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("롤백") { onRollback() }
                .font(.caption.weight(.black))
                .buttonStyle(.borderedProminent)
                .tint(AdminTheme.violet)
                .disabled(version.status == "active")
        }
        .padding(14)
        .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var statusTitle: String {
        switch version.status {
        case "active": "활성"
        case "unpublished": "게시 중지"
        default: "보관"
        }
    }

    private var statusColor: Color {
        switch version.status {
        case "active": AdminTheme.safe
        case "unpublished": AdminTheme.caution
        default: AdminTheme.violet
        }
    }
}

private struct ServerJobRow: View {
    let job: ProcessingJobValue
    let onResume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.title2.weight(.black))
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline.weight(.black))
                        .foregroundStyle(AdminTheme.ink)
                    Text(job.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("스캔 \(job.scanSessionId.uuidString.prefix(8)) · 프레임 \(job.receivedKeyframes)/\(job.expectedKeyframes)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            ProgressView(value: job.progress)
                .tint(statusColor)
                .accessibilityLabel("처리 진행률 \(Int((job.progress * 100).rounded()))퍼센트")
            Button {
                onResume()
            } label: {
                Label(actionTitle, systemImage: actionSymbol)
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(statusColor)
        }
        .padding(16)
        .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusTitle). \(job.message). 진행률 \(Int((job.progress * 100).rounded()))퍼센트.")
    }

    private var statusTitle: String {
        switch job.status {
        case "review_required": "검수 대기"
        case "processing": "인공지능 처리 중"
        case "queued": "처리 대기"
        case "waiting_for_assets": "업로드 대기"
        case "failed": "처리 실패"
        default: "작업 상태 확인"
        }
    }

    private var statusSymbol: String {
        switch job.status {
        case "review_required": "checkmark.seal.fill"
        case "processing": "brain.head.profile"
        case "queued", "waiting_for_assets": "clock.fill"
        case "failed": "exclamationmark.triangle.fill"
        default: "doc.text.magnifyingglass"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case "review_required": AdminTheme.safe
        case "failed": AdminTheme.danger
        case "processing": AdminTheme.violet
        default: AdminTheme.caution
        }
    }

    private var actionTitle: String {
        switch job.status {
        case "review_required": "검수 이어하기"
        case "failed": "실패 내용 보기"
        default: "상태 이어보기"
        }
    }

    private var actionSymbol: String {
        switch job.status {
        case "review_required": "checklist.checked"
        case "failed": "exclamationmark.triangle"
        default: "arrow.clockwise"
        }
    }
}

private struct LocalDraftRow: View {
    let draft: LocalScanDraft
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(AdminTheme.violet)
                    .frame(width: 40, height: 40)
                    .background(AdminTheme.softViolet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(draft.floorId) 스캔")
                        .font(.headline.weight(.black))
                        .foregroundStyle(AdminTheme.ink)
                    Text("핵심 화면 \(draft.keyframeCount)장 · 이동 \(draft.totalDistanceM.formatted(.number.precision(.fractionLength(1))))m")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("세션 \(draft.id.uuidString.prefix(8))")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    onRestore()
                } label: {
                    Label("불러오기", systemImage: "arrow.down.doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AdminTheme.violet)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("삭제", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.black))
        }
        .padding(16)
        .adminSurface(radius: 22, shadowOpacity: 0.06)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(draft.floorId) 저장 스캔. 핵심 화면 \(draft.keyframeCount)장. 불러오거나 삭제할 수 있습니다.")
    }
}

private struct ReviewNodeRow: View {
    let node: SceneGraphNodeValue
    let onSave: (_ nodeID: String, _ status: String?, _ labels: [String]?, _ kind: String?, _ floorID: String?, _ center: Vector3Value?, _ accessible: Bool?, _ restricted: Bool?, _ hazard: Bool?) -> Void
    @State private var labelText: String
    @State private var kindText: String
    @State private var floorText: String

    init(
        node: SceneGraphNodeValue,
        onSave: @escaping (_ nodeID: String, _ status: String?, _ labels: [String]?, _ kind: String?, _ floorID: String?, _ center: Vector3Value?, _ accessible: Bool?, _ restricted: Bool?, _ hazard: Bool?) -> Void
    ) {
        self.node = node
        self.onSave = onSave
        _labelText = State(initialValue: node.attributes["display_label"] ?? node.labels.first ?? node.id)
        _kindText = State(initialValue: node.attributes["suggested_kind"] ?? node.kind)
        _floorText = State(initialValue: node.floorId ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(kindTitle)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(kindColor, in: Capsule())
                if node.attributes["destination_candidate"] == "true" {
                    chip("목적지", color: AdminTheme.safe)
                }
                if verticalCandidate {
                    chip("층 이동", color: AdminTheme.violet)
                }
                if node.attributes["needs_admin_review"] == "true" || node.attributes["needs_human_label"] == "true" {
                    chip("확인 필요", color: AdminTheme.caution)
                }
                if node.attributes["hazard"] == "true" {
                    chip("주의", color: AdminTheme.danger)
                }
                Text(statusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(node.semanticConfidence.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            TextField("사용자에게 보일 이름", text: $labelText)
                .textFieldStyle(.roundedBorder)
                .font(.headline.weight(.bold))
                .submitLabel(.done)
                .onSubmit { saveLabel() }
            if !metadataSummary.isEmpty {
                Text(metadataSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let warningText {
                Label(warningText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AdminTheme.caution)
            }
            HStack(spacing: 8) {
                Button("이름 저장") {
                    saveLabel()
                }
                .buttonStyle(.bordered)
                Button("목적지로 저장") {
                    onSave(node.id, "approved", cleanedLabels, destinationKind, cleanedFloor, nil, true, false, false)
                }
                .buttonStyle(.borderedProminent)
                .tint(AdminTheme.violet)
            }
            .font(.headline.weight(.black))
            HStack(spacing: 8) {
                Picker("종류", selection: $kindText) {
                    Text("경로").tag("scan_waypoint")
                    Text("문").tag("door")
                    Text("방").tag("room")
                    Text("계단").tag("stairs")
                    Text("엘리베이터").tag("elevator")
                    Text("객체").tag("object")
                }
                .pickerStyle(.menu)
                TextField("층", text: $floorText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 90)
                Button("속성 저장") {
                    onSave(node.id, nil, cleanedLabels, kindText, cleanedFloor, nil, nil, nil, nil)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.bold))
            HStack(spacing: 8) {
                Button("승인") { onSave(node.id, "approved", cleanedLabels, kindText, cleanedFloor, nil, nil, nil, nil) }
                    .buttonStyle(.borderedProminent)
                    .tint(AdminTheme.safe)
                Button("거절") { onSave(node.id, "rejected", cleanedLabels, kindText, cleanedFloor, nil, nil, nil, nil) }
                    .buttonStyle(.bordered)
                    .tint(AdminTheme.danger)
                Button("후보") { onSave(node.id, "candidate", cleanedLabels, kindText, cleanedFloor, nil, nil, nil, nil) }
                    .buttonStyle(.bordered)
                Spacer()
                Text(positionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("접근 가능", isOn: Binding(
                    get: { node.attributes["accessible"] != "false" },
                    set: { onSave(node.id, nil, nil, nil, nil, nil, $0, nil, nil) }
                ))
                Toggle("직원 전용·출입 제한", isOn: Binding(
                    get: { node.attributes["restricted"] == "true" },
                    set: { onSave(node.id, nil, nil, nil, nil, nil, nil, $0, nil) }
                ))
                Toggle("위험 구역", isOn: Binding(
                    get: { node.attributes["hazard"] == "true" },
                    set: { onSave(node.id, nil, nil, nil, nil, nil, nil, nil, $0) }
                ))
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .adminSurface(radius: 20, shadowOpacity: 0.05)
    }

    private var cleanedLabels: [String] {
        let value = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? [node.id] : [value]
    }

    private var cleanedFloor: String? {
        let value = floorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var destinationKind: String {
        kindText == "scan_waypoint" ? "room" : kindText
    }

    private func saveLabel() {
        onSave(node.id, nil, cleanedLabels, kindText, cleanedFloor, nil, nil, nil, nil)
    }

    private var kindTitle: String {
        switch node.attributes["node_type"] ?? node.attributes["suggested_kind"] ?? node.kind {
        case "scan_waypoint": "경로"
        case "room_sign": "표지판"
        case "room": "목적지"
        case "door": "문"
        case "stairs": "계단"
        case "elevator": "엘리베이터"
        case "escalator": "에스컬레이터"
        case "restroom": "화장실"
        case "reception": "접수"
        case "information_desk": "안내"
        case "obstacle": "장애물"
        case "object": "객체"
        default: node.attributes["node_type"] ?? node.kind
        }
    }

    private var statusTitle: String {
        switch node.reviewStatus {
        case "approved": "승인됨"
        case "rejected": "거절됨"
        default: "검수 전"
        }
    }

    private var statusColor: Color {
        switch node.reviewStatus {
        case "approved": AdminTheme.safe
        case "rejected": AdminTheme.danger
        default: AdminTheme.caution
        }
    }

    private var kindColor: Color {
        if node.attributes["hazard"] == "true" { return AdminTheme.danger }
        if verticalCandidate { return AdminTheme.violet }
        if node.attributes["destination_candidate"] == "true" { return AdminTheme.safe }
        return node.kind == "scan_waypoint" ? AdminTheme.violet : AdminTheme.caution
    }

    private var positionText: String {
        "x \(node.geometry.center.x.formatted(.number.precision(.fractionLength(1)))) · z \(node.geometry.center.z.formatted(.number.precision(.fractionLength(1))))"
    }

    private var verticalCandidate: Bool {
        let type = node.attributes["node_type"] ?? node.attributes["suggested_kind"] ?? node.kind
        return ["elevator", "stairs", "escalator"].contains(type)
    }

    private var metadataSummary: String {
        var parts: [String] = []
        if let confidence = node.attributes["vlm_confidence"] {
            parts.append("AI 확신도 \(confidence)")
        }
        if let roomNumber = node.attributes["room_number"] {
            parts.append("방 번호 \(roomNumber)")
        }
        if let raw = node.attributes["raw_label"] {
            parts.append("검출 \(raw)")
        }
        return parts.joined(separator: " · ")
    }

    private var warningText: String? {
        guard let warnings = node.attributes["quality_warnings"], !warnings.isEmpty else { return nil }
        if warnings.contains("destination_name_required") { return "목적지 이름 확인 필요" }
        if warnings.contains("high_position_uncertainty") { return "위치 불확실성이 큼" }
        if warnings.contains("low_semantic_confidence") { return "AI 인식 확신도가 낮음" }
        return warnings
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.black))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

#Preview { ContentView() }
