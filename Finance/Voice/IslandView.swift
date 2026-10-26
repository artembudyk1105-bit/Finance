import SwiftUI

/// Остров поверх приложения: «вырастает» из настоящего Dynamic Island (размер как у плеера музыки)
struct IslandOverlay: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var speech: SpeechRecognizer
    let topInset: CGFloat
    let screenWidth: CGFloat

    private var hasIsland: Bool { topInset >= 51 }

    private var size: CGSize {
        switch router.island {
        case .hidden: return CGSize(width: 126, height: 37)
        case .listening: return CGSize(width: min(360, screenWidth - 20), height: 84)
        case .result: return CGSize(width: min(350, screenWidth - 24), height: 66)
        }
    }

    var body: some View {
        let s = size
        ZStack {
            RoundedRectangle(cornerRadius: s.height / 2, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(router.island == .hidden ? 0 : 0.3), radius: 18, y: 8)
            content
                .frame(width: s.width, height: s.height)
                .clipShape(RoundedRectangle(cornerRadius: s.height / 2, style: .continuous))
        }
        .frame(width: s.width, height: s.height)
        .opacity(router.island == .hidden ? 0 : 1)
        .scaleEffect(router.island == .hidden ? 0.92 : 1)
        .onTapGesture { if case .result = router.island { router.hideIsland() } }
        .padding(.top, hasIsland ? 11 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(router.island != .hidden)
        .animation(.spring(response: 0.48, dampingFraction: 0.72), value: router.island)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch router.island {
        case .hidden:
            Color.clear
        case .listening:
            ListeningContent()
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        case .result(let r):
            ResultContent(r: r)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }
}

private struct ListeningContent: View {
    @EnvironmentObject var speech: SpeechRecognizer
    @State private var started = Date()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.red.opacity(0.22)).frame(width: 40, height: 40)
                PulsingDot()
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Слушаю…").font(.caption).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        let sec = Int(ctx.date.timeIntervalSince(started))
                        Text(String(format: "%d:%02d", sec / 60, sec % 60)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                    }
                }
                LiveText(text: speech.transcript.isEmpty ? "Скажите: «кофе 250»" : speech.transcript, dim: speech.transcript.isEmpty)
            }
            Waveform(level: speech.level)
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .onAppear { started = Date() }
    }
}

/// Показывает конец фразы — то, что говорят прямо сейчас
private struct LiveText: View {
    let text: String
    let dim: Bool
    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(dim ? 0.55 : 1))
                .lineLimit(1)
                .fixedSize()
                .frame(width: geo.size.width, alignment: .trailing)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08)], startPoint: .leading, endPoint: .trailing))
                .animation(.easeOut(duration: 0.15), value: text)
        }
        .frame(height: 20)
    }
}

private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color.red).frame(width: 14, height: 14)
            .scaleEffect(on ? 0.7 : 1).opacity(on ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private struct Waveform: View {
    let level: Float
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<16, id: \.self) { i in
                    let wave = abs(sin(t * 7 + Double(i) * 0.9) * cos(t * 3.1 + Double(i) * 0.4))
                    let v = (0.16 + Double(level)) * (0.45 + 0.55 * wave)
                    Capsule().fill(Color.red).frame(width: 3, height: max(4, min(30, v * 30)))
                }
            }
            .frame(height: 30)
        }
    }
}

private struct ResultContent: View {
    let r: IslandState.Result
    var body: some View {
        HStack(spacing: 12) {
            Text(r.icon).font(.system(size: 19))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(r.subtitle).font(.caption)
                    .foregroundStyle(r.kind == .ok ? Color.white.opacity(0.55) : (r.kind == .warn ? Color.orange : Color.red))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !r.amount.isEmpty {
                Text(r.amount).font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(r.isIncome ? Color.green : .white).lineLimit(1).fixedSize()
            }
            ZStack {
                Circle().fill(r.kind == .ok ? Color.green : Color.orange).frame(width: 26, height: 26)
                Image(systemName: r.kind == .ok ? "checkmark" : "exclamationmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.black)
            }
            .transition(.scale)
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
    }
}
