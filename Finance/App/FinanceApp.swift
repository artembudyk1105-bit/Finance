import SwiftUI

@main
struct FinanceApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var router = Router.shared
    @StateObject private var speech = SpeechRecognizer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(speech)
                .preferredColorScheme(store.data.settings.theme.colorScheme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var speech: SpeechRecognizer
    @Environment(\.scenePhase) private var scenePhase

    @State private var showAdd = false
    @State private var showQuick = false
    @State private var pressing = false
    @State private var pressStart = Date()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TabView(selection: $router.tab) {
                    HomeView(showAdd: $showAdd).tag(AppTab.home)
                        .tabItem { Label("Обзор", systemImage: "house.fill") }
                    HistoryView().tag(AppTab.history)
                        .tabItem { Label("История", systemImage: "list.bullet") }
                    StatsView().tag(AppTab.stats)
                        .tabItem { Label("Статистика", systemImage: "chart.bar.fill") }
                    AssistantView().tag(AppTab.assistant)
                        .tabItem { Label("Ассистент", systemImage: "sparkles") }
                    MoreView().tag(AppTab.more)
                        .tabItem { Label("Ещё", systemImage: "ellipsis") }
                }
                .overlay(alignment: .bottom) {
                    if router.tab != .assistant {
                        micDock.padding(.bottom, 58)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottom) {
                    if let t = router.toast {
                        ToastView(toast: t) { router.toast = nil }
                            .padding(.bottom, 140)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: router.toast)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: router.tab)

                IslandOverlay(topInset: geo.safeAreaInsets.top, screenWidth: geo.size.width)
            }
        }
        .sheet(isPresented: $showAdd) { TransactionEditor(tx: nil) }
        .sheet(isPresented: $showQuick) { QuickInputView() }
        .onAppear {
            activate()
            // Приложение было закрыто и запущено кнопкой действия / Siri
            if router.pendingVoice { router.pendingVoice = false; startVoice(auto: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activate() }
            if phase == .background { store.save() }
        }
        .onChange(of: router.pendingVoice) { _, v in
            if v { router.pendingVoice = false; startVoice(auto: true) }
        }
    }

    // MARK: - Кнопки снизу

    private var micDock: some View {
        HStack(spacing: 16) {
            roundButton("plus") { showAdd = true }
            micButton
            roundButton("keyboard") { showQuick = true }
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var micButton: some View {
        let rec = speech.isRecording
        return ZStack {
            if rec {
                PulseHalo()
            }
            Circle()
                .fill(rec ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "FF5A4F"), Color(hex: "E0241A")], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LinearGradient(colors: [Color(hex: "2B2B2E"), .black], startPoint: .top, endPoint: .bottom)))
                .frame(width: 70, height: 70)
                .shadow(color: rec ? Color.red.opacity(0.45) : .black.opacity(0.3), radius: 14, y: 6)
            Image(systemName: "mic.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
        }
        .scaleEffect(rec ? 1.14 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: rec)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressing {
                        pressing = true
                        pressStart = Date()
                        startVoice(auto: false)
                    }
                }
                .onEnded { _ in
                    pressing = false
                    endVoice()
                }
        )
        .accessibilityLabel("Удерживайте и говорите")
    }

    // MARK: - Голос

    private func startVoice(auto: Bool) {
        Haptics.press()
        Task {
            guard await SpeechRecognizer.requestPermissions() else {
                router.showResult(.init(icon: "🔒", title: "Нет доступа к микрофону", subtitle: "Разрешите в Настройках iPhone", kind: .error), seconds: 3.5)
                return
            }
            // Кнопку уже отпустили, пока спрашивали разрешение
            if !auto && !pressing { return }
            speech.autoStopOnSilence = auto
            speech.onFinish = { text in handleVoice(text) }
            do {
                try speech.start(locale: store.settings.speechLocale)
                router.island = .listening
            } catch {
                router.showResult(.init(icon: "🎙️", title: "Голос недоступен", subtitle: error.localizedDescription, kind: .error), seconds: 3)
            }
        }
    }

    private func endVoice() {
        guard speech.isRecording else { return }
        if Date().timeIntervalSince(pressStart) < 0.35 {
            speech.cancel()
            router.showResult(.init(icon: "👆", title: "Удерживайте кнопку", subtitle: "и говорите: «кофе 250»"), seconds: 2)
            return
        }
        speech.stop()
    }

    private func handleVoice(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            router.showResult(.init(icon: "🤔", title: "Не расслышал", subtitle: "Удерживайте кнопку, пока говорите", kind: .error), seconds: 2.4)
            Haptics.error()
            return
        }
        let added = store.addFromText(t, source: .voice)
        if added.isEmpty {
            router.showResult(.init(icon: "❓", title: "«\(t)»", subtitle: "Не нашёл сумму — скажите, например, «кофе 250»", kind: .error), seconds: 3.6)
            Haptics.error()
        } else {
            router.announce(added, store: store)
        }
    }

    // MARK: - Запуск / возврат в приложение

    private func activate() {
        let auto = store.applyRecurring()
        if let prev = store.monthRollover() {
            router.showToast("Итоги: \(Day.monthName(prev, withYear: false)) готовы", actionTitle: "Открыть") { router.tab = .assistant }
        } else if !auto.isEmpty {
            router.showToast("Проведены регулярные платежи: " + auto.map(\.name).joined(separator: ", "))
        }
    }
}

private struct PulseHalo: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle().fill(Color.red.opacity(0.35))
                    .frame(width: 70, height: 70)
                    .scaleEffect(animate ? 1.9 : 1)
                    .opacity(animate ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(Double(i) * 0.7), value: animate)
            }
        }
        .onAppear { animate = true }
    }
}
