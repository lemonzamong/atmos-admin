import SwiftUI

@main
struct atmos_adminApp: App {
    @UIApplicationDelegateAdaptor(AdminAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
