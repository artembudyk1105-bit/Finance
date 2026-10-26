import Foundation

/// Свободный диалог с Claude. Для Swift нет официального SDK Anthropic, поэтому — прямой HTTP-запрос к Messages API.
@MainActor
enum ClaudeClient {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let system = """
    Ты — финансовый ассистент в приложении учёта трат. Отвечай по-русски, коротко (до 120 слов), дружелюбно и конкретно, \
    с цифрами из данных пользователя. Помогай с финансовой грамотностью: бюджет, подушка безопасности, сокращение необязательных трат, цели. \
    Не давай советов по покупке конкретных ценных бумаг. Без markdown-заголовков и таблиц; можно короткие списки с «•». \
    Данные пользователя (JSON) приходят в сообщении — опирайся только на них.
    """

    static func context(_ store: Store) -> String {
        let m = Day.currentMonth
        var months: [[String: Any]] = []
        for i in stride(from: 5, through: 0, by: -1) {
            let s = store.summary(Day.addMonths(m, -i))
            guard s.count > 0 else { continue }
            var byCat: [String: Int] = [:]
            for (c, v) in s.byCat { byCat[Category.byId(c).name] = Int(v) }
            months.append(["month": s.month, "income": Int(s.income), "expenses": Int(s.expense),
                           "mandatory": Int(s.mandatory), "optional": Int(s.optional), "byCategory": byCat] as [String: Any])
        }
        let cur = store.summary(m)
        let last = cur.list.prefix(40).map { [$0.day, $0.type == .income ? "+" : "-", $0.amount, $0.name, $0.cat.name, $0.isMandatory ? "обяз" : "необяз"] as [Any] }
        let limits = Dictionary(store.settings.categoryLimits.map { (Category.byId($0.key).name, Int($0.value)) }, uniquingKeysWith: { a, _ in a })
        let dict: [String: Any] = [
            "today": Day.today, "currency": store.settings.currency, "monthlyBudget": store.budget, "categoryLimits": limits,
            "currentMonth": ["daysPassed": cur.daysPassed, "daysLeft": cur.daysLeft, "forecast": Int(cur.forecast), "lastTransactions": last] as [String: Any],
            "months": months,
            "goals": store.data.goals.map { ["name": $0.name, "target": $0.target, "saved": $0.saved] as [String: Any] },
            "recurring": store.data.recurring.map { ["name": $0.name, "amount": $0.amount, "day": $0.dayOfMonth] as [String: Any] }
        ]
        let raw = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return String(data: raw, encoding: .utf8) ?? "{}"
    }

    static func ask(_ question: String, store: Store) async throws -> String {
        // История: последние сообщения, чередование user/assistant, начиная с user
        var msgs: [[String: String]] = []
        for m in store.data.chat.suffix(10) {
            let role = m.isUser ? "user" : "assistant"
            if msgs.isEmpty && role != "user" { continue }
            if let last = msgs.last, last["role"] == role {
                msgs[msgs.count - 1]["content"] = (last["content"] ?? "") + "\n" + m.text
            } else {
                msgs.append(["role": role, "content": m.text])
            }
        }
        let content = "Мои данные: \(context(store))\n\nВопрос: \(question)"
        if let last = msgs.last, last["role"] == "user" {
            msgs[msgs.count - 1]["content"] = (last["content"] ?? "") + "\n" + content
        } else {
            msgs.append(["role": "user", "content": content])
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(store.settings.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": store.settings.model,
            "max_tokens": 4000,
            "system": system,
            "messages": msgs,
            "output_config": ["effort": "low"] as [String: Any],
            "fallbacks": "default"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw APIError(message: msg)
        }
        if json["stop_reason"] as? String == "refusal" { return "Не могу ответить на этот вопрос. Попробуйте переформулировать." }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "…" : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
