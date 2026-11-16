import SwiftUI

@main
struct MCMKonsignationApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Brand.navy)
        }
    }
}
