import SwiftUI
import UserNotifications

@main
struct PhotoJournalApp: App {
    @StateObject private var journal = JournalStore()

    init() {
        UNUserNotificationCenter.current().delegate = PhotoJournalNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(journal)
        }
    }
}
