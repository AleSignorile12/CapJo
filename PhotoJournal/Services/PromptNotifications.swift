import Foundation
import UserNotifications

enum PromptNotifications {
    static func updatePendingPromptForToday(_ prompt: String) async {
        let center = UNUserNotificationCenter.current()
        let identifierPrefix = "photo-prompt-\(dayKey(Date()))"
        let requests = await center.pendingNotificationRequests()
        guard let existing = requests
            .filter({ $0.identifier == identifierPrefix || $0.identifier.hasPrefix(identifierPrefix + "-") })
            .sorted(by: {
                let firstDate = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? .distantFuture
                let secondDate = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? .distantFuture
                return firstDate < secondDate
            })
            .first,
              let trigger = existing.trigger else { return }

        let content = UNMutableNotificationContent()
        content.title = existing.content.title
        content.body = "Take a picture of “\(prompt)”"
        content.sound = existing.content.sound
        content.badge = existing.content.badge
        var userInfo = existing.content.userInfo
        userInfo["prompt"] = prompt
        userInfo["challengeID"] = "\(existing.identifier)-\(UUID().uuidString)"
        content.userInfo = userInfo
        content.categoryIdentifier = existing.content.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: existing.identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    static func cancelScheduledPrompts() {
        let center = UNUserNotificationCenter.current()
        Task {
            let requests = await center.pendingNotificationRequests()
            let identifiers = requests.map(\.identifier).filter {
                $0.hasPrefix("photo-prompt-") || $0.hasPrefix("photo-follow-up-")
            }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    static func scheduleWeek(
        categories: [PromptCategory],
        notificationsPerDay: Int = 1
    ) async -> String? {
        guard !categories.isEmpty else { return "Choose at least one interest first." }

        let center = UNUserNotificationCenter.current()
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            guard allowed else { return "Notifications are off. You can enable them in iPhone Settings." }
        } catch {
            return "Could not request notification permission: \(error.localizedDescription)"
        }

        let oldRequests = await center.pendingNotificationRequests()
        let oldIDs = oldRequests.map(\.identifier).filter { $0.hasPrefix("photo-prompt-") || $0.hasPrefix("photo-follow-up-") }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)

        let calendar = Calendar.current
        let now = Date()
        let allPrompts = categories.flatMap(\.prompts)
        let todayKey = Self.dayKey(now)
        let savedPrompt = UserDefaults.standard.string(forKey: "todayPrompt") ?? ""
        let savedPromptDate = UserDefaults.standard.string(forKey: "todayPromptDate") ?? ""
        var shouldSetTodayPrompt = savedPromptDate != todayKey || !allPrompts.contains(savedPrompt)

        let promptsPerDay = min(max(notificationsPerDay, 1), 5)

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: day)

            var randomMinutes = Set<Int>()
            while randomMinutes.count < promptsPerDay {
                randomMinutes.insert(Int.random(in: (9 * 60)..<(19 * 60)))
            }

            var promptsForDay = allPrompts.shuffled()
            var lastPromptDate: Date?
            for (index, minuteOfDay) in randomMinutes.sorted().enumerated() {
                let hour = minuteOfDay / 60
                let minute = minuteOfDay % 60
                guard let promptDate = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: dayStart
                ), promptDate > now else { continue }

                if promptsForDay.isEmpty {
                    promptsForDay = allPrompts.shuffled()
                }
                guard let prompt = promptsForDay.popLast() else { continue }

                if dayOffset == 0 && lastPromptDate == nil && shouldSetTodayPrompt {
                    UserDefaults.standard.set(prompt, forKey: "todayPrompt")
                    UserDefaults.standard.set(todayKey, forKey: "todayPromptDate")
                    shouldSetTodayPrompt = false
                }

                let promptContent = UNMutableNotificationContent()
                promptContent.title = "A moment for your journal"
                promptContent.body = "Take a picture of “\(prompt)”"
                promptContent.sound = .default
                let promptTrigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: promptDate),
                    repeats: false
                )
                let key = Self.dayKey(promptDate)
                let suffix = index == 0 ? "" : "-\(index + 1)"
                let identifier = "photo-prompt-\(key)\(suffix)"
                let challengeID = "\(identifier)-\(UUID().uuidString)"
                promptContent.userInfo = ["prompt": prompt, "challengeID": challengeID]
                let promptRequest = UNNotificationRequest(
                    identifier: identifier,
                    content: promptContent,
                    trigger: promptTrigger
                )
                try? await center.add(promptRequest)
                lastPromptDate = promptDate
            }

            // One gentle reminder may follow the last prompt. The daily total
            // remains at five or fewer, including the reminder.
            if promptsPerDay < 5,
               let lastPromptDate,
               let followUpDate = calendar.date(byAdding: .hour, value: 2, to: lastPromptDate) {
                let followUpContent = UNMutableNotificationContent()
                followUpContent.title = "A gentle reminder"
                followUpContent.body = "Don't forget to be mindful—take a picture!"
                followUpContent.sound = .default
                let followUpTrigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate),
                    repeats: false
                )
                let followUpRequest = UNNotificationRequest(
                    identifier: "photo-follow-up-\(Self.dayKey(followUpDate))",
                    content: followUpContent,
                    trigger: followUpTrigger
                )
                try? await center.add(followUpRequest)
            }
        }

        return nil
    }

    static func cancelFollowUp(for date: Date) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["photo-follow-up-\(dayKey(date))"]
        )
    }

    static func activateChallenge(from request: UNNotificationRequest) {
        guard request.identifier.hasPrefix("photo-prompt-") else { return }

        let bodyPrefix = "Take a picture of “"
        let promptFromBody: String? = {
            guard request.content.body.hasPrefix(bodyPrefix), request.content.body.last == "”" else { return nil }
            return String(request.content.body.dropFirst(bodyPrefix.count).dropLast())
        }()
        guard let prompt = (request.content.userInfo["prompt"] as? String) ?? promptFromBody,
              !prompt.isEmpty else { return }

        let challengeID = (request.content.userInfo["challengeID"] as? String) ?? request.identifier
        UserDefaults.standard.set(prompt, forKey: "activeChallengePrompt")
        UserDefaults.standard.set(challengeID, forKey: "activeChallengeID")
    }

    static func activateLatestDeliveredChallengeForToday() async {
        let center = UNUserNotificationCenter.current()
        let prefix = "photo-prompt-\(dayKey(Date()))"
        let delivered = await center.deliveredNotifications()
        guard let latest = delivered
            .filter({ $0.request.identifier == prefix || $0.request.identifier.hasPrefix(prefix + "-") })
            .max(by: { $0.date < $1.date }) else { return }
        activateChallenge(from: latest.request)
    }

    static func clearActiveChallenge() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "activeChallengePrompt")
        defaults.removeObject(forKey: "activeChallengeID")
        let center = UNUserNotificationCenter.current()
        let todayPrefix = "photo-prompt-\(dayKey(Date()))"
        Task {
            let delivered = await center.deliveredNotifications()
            let identifiers = delivered.map(\.request.identifier).filter {
                $0 == todayPrefix || $0.hasPrefix(todayPrefix + "-")
            }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

final class PhotoJournalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PhotoJournalNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        PromptNotifications.activateChallenge(from: notification.request)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        PromptNotifications.activateChallenge(from: response.notification.request)
        completionHandler()
    }
}
