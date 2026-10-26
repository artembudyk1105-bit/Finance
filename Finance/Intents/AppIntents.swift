import AppIntents
import Foundation

/// «Записать трату» — работает в фоне без открытия приложения; результат показывается в Dynamic Island
struct AddExpenseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Записать трату"
    static let description = IntentDescription("Добавляет трату или поступление по фразе, например «кофе 250» или «зарплата 85 тысяч».")
    static let openAppWhenRun = false

    @Parameter(title: "Фраза", requestValueDialog: "Что записать?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Записать \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        let added = store.addFromText(text, source: .shortcut)
        guard !added.isEmpty else {
            return .result(dialog: "Не нашёл сумму во фразе «\(text)». Скажите, например: кофе 250.")
        }
        let alert = Assistant.afterAdd(added, store: store)
        store.save()
        if let alert, store.settings.notifications { Notifier.post("Финансы", alert.text) }
        let sum = added.reduce(0) { $0 + $1.signedAmount }
        let names = added.map(\.name).joined(separator: ", ")
        let summary = "\(names): \(store.money(sum, sign: true))" + (alert.map { ". \($0.text)" } ?? "")
        await LiveActivityManager.show(added, alert: alert, store: store)
        return .result(dialog: "\(summary)")
    }
}

/// «Голосовая трата» — открывает приложение и сразу слушает (останавливается после паузы)
struct VoiceExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Голосовая трата"
    static let description = IntentDescription("Открывает «Финансы» и сразу начинает слушать трату.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.tab = .home
        Router.shared.pendingVoice = true
        return .result()
    }
}

/// «Сколько осталось» — короткий ответ ассистента голосом Siri
struct BudgetLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Сколько осталось"
    static let description = IntentDescription("Подсказывает, сколько можно потратить до конца месяца.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = Assistant.localAnswer("сколько осталось", store: Store.shared) ?? ""
        return .result(dialog: "\(answer)")
    }
}

struct FinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: VoiceExpenseIntent(),
                    phrases: ["Голосовая трата в \(.applicationName)", "Записать голосом в \(.applicationName)"],
                    shortTitle: "Голосовая трата", systemImageName: "mic.fill")
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Записать трату в \(.applicationName)", "Добавить трату в \(.applicationName)"],
                    shortTitle: "Записать трату", systemImageName: "plus.circle.fill")
        AppShortcut(intent: BudgetLeftIntent(),
                    phrases: ["Сколько осталось в \(.applicationName)", "Мой бюджет в \(.applicationName)"],
                    shortTitle: "Сколько осталось", systemImageName: "chart.pie.fill")
    }
}
