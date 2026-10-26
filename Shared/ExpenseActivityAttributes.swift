import ActivityKit
import Foundation

/// Общая модель Live Activity для приложения и расширения виджетов
struct ExpenseActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var icon: String
        var title: String
        var subtitle: String
        var amount: String
        var isIncome: Bool
        var isWarning: Bool
    }

    var startedAt: Date
}
