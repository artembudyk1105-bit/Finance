import SwiftUI

enum AppTab: Hashable { case home, history, stats, assistant, more }

/// Состояние «острова» поверх интерфейса
enum IslandState: Equatable {
    case hidden
    case listening
    case result(Result)

    struct Result: Equatable {
        enum Kind: Equatable { case ok, warn, error }
        var icon: String
        var title: String
        var subtitle: String
        var amount: String = ""
        var isIncome = false
        var kind: Kind = .ok
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Навигация, остров, тосты и голосовой сценарий
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab: AppTab = .home
    @Published var island: IslandState = .hidden
    @Published var toast: Toast?
    @Published var pendingVoice = false
    @Published var openBudget = false

    private var islandToken = UUID()
    private var toastToken = UUID()

    func showResult(_ r: IslandState.Result, seconds: Double = 2.8) {
        island = .result(r)
        let token = UUID()
        islandToken = token
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if self.islandToken == token { self.island = .hidden }
        }
    }

    func hideIsland() { islandToken = UUID(); island = .hidden }

    func showToast(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let t = Toast(text: text, actionTitle: actionTitle, action: action)
        toast = t
        let token = UUID()
        toastToken = token
        Task {
            try? await Task.sleep(nanoseconds: actionTitle == nil ? 2_200_000_000 : 5_000_000_000)
            if self.toastToken == token { self.toast = nil }
        }
    }

    /// Общая реакция на добавленные записи: остров, вибрация, предупреждение, «Отменить»
    func announce(_ added: [Transaction], store: Store) {
        guard let first = added.first else { return }
        let alert = Assistant.afterAdd(added, store: store)
        let sum = added.reduce(0) { $0 + $1.signedAmount }
        let title = added.count == 1 ? first.name : added.map(\.name).joined(separator: ", ")
        let mustText = first.type == .expense ? (first.isMandatory ? " · обязательная" : " · необязательная") : ""
        let subtitle = alert?.text ?? (added.count == 1 ? first.cat.name + mustText : "\(added.count) \(Fmt.plural(added.count, "запись", "записи", "записей"))")
        showResult(.init(icon: added.count == 1 ? first.cat.icon : "🧾", title: title, subtitle: subtitle,
                         amount: store.money(sum, sign: true), isIncome: sum >= 0, kind: alert == nil ? .ok : .warn),
                   seconds: alert == nil ? 2.8 : 4.2)
        if alert == nil {
            Haptics.success()
            let ids = added.map(\.id)
            showToast("Добавлено: \(added.count)", actionTitle: "Отменить") {
                for id in ids { store.remove(id) }
            }
        } else {
            Haptics.warning()
        }
    }
}
