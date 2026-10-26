import SwiftUI

struct AssistantView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var input = ""
    @State private var thinking = false
    @State private var showBudget = false
    @FocusState private var focused: Bool

    private let quick = ["Сколько осталось?", "Что убрать?", "Прогноз", "Итоги месяца", "Итоги прошлого месяца", "Подписки", "Совет"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Assistant.insights(store: store)) { i in insightCard(i) }

                        Text("ЧАТ").font(.footnote).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quick, id: \.self) { q in
                                    Button(q) { Haptics.tap(); ask(q) }
                                        .font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                                }
                            }
                        }
                        .disabled(thinking)

                        if store.data.chat.isEmpty {
                            bubble("Привет! Я слежу за вашими тратами и подскажу, где можно сэкономить. Спросите что-нибудь или нажмите подсказку выше.\n\n💡 " + Assistant.tipOfDay, isUser: false)
                        }
                        ForEach(store.data.chat) { m in bubble(m.text, isUser: m.isUser).id(m.id) }
                        if thinking { TypingBubble().id("typing") }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.data.chat.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color(.systemGroupedBackground))
                .onChange(of: store.data.chat.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: thinking) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Ассистент")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.data.chat.removeAll() } label: { Image(systemName: "trash") }
                        .disabled(store.data.chat.isEmpty)
                }
            }
            .sheet(isPresented: $showBudget) { NavigationStack { BudgetView() } }
        }
    }

    private func insightCard(_ i: Assistant.Insight) -> some View {
        let palette: [Color] = [.red, .orange, .blue, .green]
        let color = palette[i.level.rawValue]
        return HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(i.title).font(.subheadline.weight(.semibold))
                Text(i.text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let action = i.action {
                    Button(i.actionTitle + " →") {
                        switch action {
                        case .budget: showBudget = true
                        case .cuts:
                            store.data.chat.append(ChatMessage(isUser: true, text: "Что можно убрать?"))
                            store.data.chat.append(ChatMessage(isUser: false, text: Assistant.cuts(store: store)))
                        }
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bubble(_ text: String, isUser: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 50) }
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(isUser ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: isUser ? 20 : 6,
                                                       bottomTrailingRadius: isUser ? 6 : 20, topTrailingRadius: 20, style: .continuous))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .transition(.scale(scale: 0.7, anchor: isUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
            if !isUser { Spacer(minLength: 50) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Спросите о своих финансах…", text: $input)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 14).frame(height: 38)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Color.accentColor, in: Circle())
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        ask(q)
    }

    private func ask(_ q: String) {
        guard !thinking else { return }
        store.data.chat.append(ChatMessage(isUser: true, text: q))
        thinking = true
        Task {
            let n = Parser.normalize(q)
            let answer: String
            if n.contains("итог") && n.contains("прошл") {
                answer = Assistant.monthReport(Day.addMonths(Day.currentMonth, -1), store: store)
            } else {
                answer = await Assistant.answer(q, store: store)
            }
            thinking = false
            store.data.chat.append(ChatMessage(isUser: false, text: answer))
            if store.data.chat.count > 200 { store.data.chat.removeFirst(store.data.chat.count - 200) }
        }
    }
}

private struct TypingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .offset(y: sin(phase + Double(i) * 0.8) * 3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { phase = .pi * 2 } }
    }
}
