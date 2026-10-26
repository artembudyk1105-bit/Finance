import Foundation
import SwiftUI

enum TxType: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? "Трата" : "Поступление" }
}

enum TxSource: String, Codable {
    case manual, voice, recurring, shortcut, demo
}

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: TxType
    var amount: Double
    var name: String
    var category: String
    /// День в формате yyyy-MM-dd
    var day: String
    var createdAt = Date()
    var isMandatory: Bool
    var source: TxSource = .manual

    var month: String { String(day.prefix(7)) }
    var signedAmount: Double { type == .income ? amount : -amount }
    var cat: Category { Category.byId(category) }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppSettings: Codable {
    var currency = "₽"
    var monthlyBudget: Double = 0
    var savingsTarget: Double = 20
    var categoryLimits: [String: Double] = [:]
    var mandatoryOverride: [String: Bool] = [:]
    var alerts = true
    var notifications = false
    var apiKey = ""
    var model = "claude-opus-5-5"
    var theme: AppTheme = .system
    var speechLocale = "ru-RU"

    init() {}

    // Новые поля в будущих версиях не должны ломать старые сохранения
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? d.currency
        monthlyBudget = try c.decodeIfPresent(Double.self, forKey: .monthlyBudget) ?? d.monthlyBudget
        savingsTarget = try c.decodeIfPresent(Double.self, forKey: .savingsTarget) ?? d.savingsTarget
        categoryLimits = try c.decodeIfPresent([String: Double].self, forKey: .categoryLimits) ?? d.categoryLimits
        mandatoryOverride = try c.decodeIfPresent([String: Bool].self, forKey: .mandatoryOverride) ?? d.mandatoryOverride
        alerts = try c.decodeIfPresent(Bool.self, forKey: .alerts) ?? d.alerts
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? d.notifications
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? d.apiKey
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? d.theme
        speechLocale = try c.decodeIfPresent(String.self, forKey: .speechLocale) ?? d.speechLocale
    }
}

struct RecurringPayment: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var type: TxType
    var category: String
    var dayOfMonth: Int
    /// Месяц (yyyy-MM), за который платёж уже проведён
    var lastMonth: String
}

struct Goal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var target: Double
    var saved: Double
    var icon: String
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var isUser: Bool
    var text: String
    var date = Date()
}

struct AppData: Codable {
    var transactions: [Transaction] = []
    var settings = AppSettings()
    var recurring: [RecurringPayment] = []
    var goals: [Goal] = []
    var chat: [ChatMessage] = []
    var alerted: Set<String> = []
    var lastOpenMonth = ""
    var closedMonths: Set<String> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactions = try c.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        recurring = try c.decodeIfPresent([RecurringPayment].self, forKey: .recurring) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        chat = try c.decodeIfPresent([ChatMessage].self, forKey: .chat) ?? []
        alerted = try c.decodeIfPresent(Set<String>.self, forKey: .alerted) ?? []
        lastOpenMonth = try c.decodeIfPresent(String.self, forKey: .lastOpenMonth) ?? ""
        closedMonths = try c.decodeIfPresent(Set<String>.self, forKey: .closedMonths) ?? []
    }
}

/// Итоги одного месяца
struct MonthSummary {
    let month: String
    var income = 0.0
    var expense = 0.0
    var mandatory = 0.0
    var optional = 0.0
    var byCat: [String: Double] = [:]
    var byIncCat: [String: Double] = [:]
    var byDay: [Int: Double] = [:]
    var list: [Transaction] = []
    var daysTotal = 30
    var daysPassed = 0
    var forecast = 0.0

    var count: Int { list.count }
    var balance: Double { income - expense }
    var saveRate: Double { income > 0 ? balance / income : 0 }
    var daysLeft: Int { daysTotal - daysPassed }
    var isCurrent: Bool { month == Day.currentMonth }

    var categoriesSorted: [String] { byCat.keys.sorted { byCat[$0, default: 0] > byCat[$1, default: 0] } }
    var incomeCategoriesSorted: [String] { byIncCat.keys.sorted { byIncCat[$0, default: 0] > byIncCat[$1, default: 0] } }
}
