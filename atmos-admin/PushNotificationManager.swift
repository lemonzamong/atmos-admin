import Combine
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AdminAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushNotificationManager.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.registerDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationManager.shared.lastStatus = "푸시 알림 등록 실패: \(error.localizedDescription)"
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        PushNotificationManager.shared.lastStatus = "처리 상태 알림을 받았습니다."
        completionHandler(.newData)
    }
}

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    @Published var isAuthorized = false
    @Published var lastStatus = "푸시 알림 준비 중"

    let deviceID: String
    private let apiClient = AdminAPIClient()

    override init() {
        if let saved = UserDefaults.standard.string(forKey: "atmosAdminDeviceID") {
            deviceID = saved
        } else {
            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: "atmosAdminDeviceID")
            deviceID = generated
        }
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await requestAuthorizationAndRegister() }
    }

    func registerDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "atmosAdminPushToken")
        Task { await sendTokenToServer(token) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    private func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            if granted {
                lastStatus = "푸시 알림 권한 허용됨"
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                if let savedToken = UserDefaults.standard.string(forKey: "atmosAdminPushToken") {
                    await sendTokenToServer(savedToken)
                }
            } else {
                lastStatus = "푸시 알림 권한이 꺼져 있습니다."
            }
        } catch {
            lastStatus = "푸시 알림 권한 요청 실패: \(error.localizedDescription)"
        }
    }

    private func sendTokenToServer(_ token: String) async {
        let bundleID = Bundle.main.bundleIdentifier ?? "atmos.atmos-admin"
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        do {
            try await apiClient.registerPushToken(
                PushTokenRegistrationValue(
                    deviceId: deviceID,
                    token: token,
                    platform: "ios",
                    appBundleId: bundleID,
                    environment: environment
                )
            )
            lastStatus = "푸시 알림 등록 완료"
        } catch {
            lastStatus = "푸시 알림 서버 등록 실패: \(error.localizedDescription)"
        }
    }
}
