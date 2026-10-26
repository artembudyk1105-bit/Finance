import UIKit
import UserNotifications
import ActivityKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func press() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

enum Notifier {
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Каждое 1-е число в 10:00 — напоминание подвести итоги
    static func scheduleMonthly() {
        let c = UNMutableNotificationContent()
        c.title = "Итоги месяца готовы"
        c.body = "Откройте приложение — ассистент подвёл итоги прошлого месяца."
        var dc = DateComponents()
        dc.day = 1
        dc.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "monthly", content: c, trigger: trigger))
    }

    static func cancelMonthly() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["monthly"])
    }
}

/// Показ результата в настоящем Dynamic Island (когда запись добавлена из «Команд»/Siri/кнопки действия)
@MainActor
enum LiveActivityManager {
    static func show(_ added: [Transaction], alert: Assistant.Alert?, store: Store) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let first = added.first else { return }
        let sum = added.reduce(0) { $0 + $1.signedAmount }
        let title = added.count == 1 ? first.name : added.map(\.name).joined(separator: ", ")
        let subtitle = alert?.text ?? (added.count == 1 ? first.cat.name : "\(added.count) \(Fmt.plural(added.count, "запись", "записи", "записей"))")
        let state = ExpenseActivityAttributes.ContentState(
            icon: added.count == 1 ? first.cat.icon : "🧾", title: title, subtitle: subtitle,
            amount: store.money(sum, sign: true), isIncome: sum >= 0, isWarning: alert != nil)
        do {
            let activity = try Activity.request(attributes: ExpenseActivityAttributes(startedAt: Date()),
                                                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)),
                                                pushType: nil)
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            await activity.end(nil, dismissalPolicy: .immediate)
        } catch {
            // Live Activities выключены или недоступны — результат всё равно виден в диалоге «Команд»
        }
    }
}
