import SwiftUI

// MARK: - Карточка

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// Карточка внутри List без системного фона и отступов
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Строка операции

struct TransactionRow: View {
    @EnvironmentObject var store: Store
    let tx: Transaction
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            Text(tx.cat.icon).font(.system(size: 19))
                .frame(width: 38, height: 38)
                .background(tx.cat.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(showDate ? Day.label(tx.day) : tx.cat.name).lineLimit(1)
                    if tx.type == .expense { MandatoryTag(isMandatory: tx.isMandatory) }
                    if tx.source == .voice || tx.source == .shortcut { Image(systemName: "mic.fill").font(.caption2) }
                    if tx.source == .recurring { Image(systemName: "repeat").font(.caption2) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(store.money(tx.signedAmount, sign: true))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(tx.type == .income ? Color.green : Color.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct MandatoryTag: View {
    let isMandatory: Bool
    var body: some View {
        Text(isMandatory ? "обяз." : "необяз.")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((isMandatory ? Color.blue : Color.orange).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isMandatory ? Color.blue : Color.orange)
    }
}

// MARK: - Кольца как в Apple Watch

struct RingData: Identifiable {
    let id = UUID()
    var value: Double
    var max: Double
    var color: Color
    var overColor: Color = .red
    var title: String
    var valueText: String
    var subtitle: String
}

struct ActivityRings: View {
    let rings: [RingData]
    var lineWidth: CGFloat = 14
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { i, r in
                let inset = CGFloat(i) * (lineWidth + 3)
                let p = r.max > 0 ? r.value / r.max : 0
                ZStack {
                    Circle().stroke(r.color.opacity(0.2), lineWidth: lineWidth)
                    Circle().trim(from: 0, to: min(p, 1) * progress)
                        .stroke(r.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if p > 1 {
                        Circle().trim(from: 0, to: min(p - 1, 1) * progress)
                            .stroke(r.overColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                .padding(inset + lineWidth / 2)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.3)) { progress = 1 } }
    }
}

// MARK: - Переключатель месяца

struct MonthSwitcher: View {
    @Binding var month: String
    var yearMode = false

    var body: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 36, height: 36) }
            Spacer()
            Text(yearMode ? "\(Day.year(month)) год" : Day.monthName(month)).font(.headline).contentTransition(.numericText())
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 36, height: 36) }
                .disabled(yearMode ? Day.year(month) >= Day.year(Day.currentMonth) : month >= Day.currentMonth)
        }
    }

    private func step(_ d: Int) {
        Haptics.tap()
        withAnimation(.snappy) {
            var m = Day.addMonths(month, d * (yearMode ? 12 : 1))
            if m > Day.currentMonth { m = Day.currentMonth }
            month = m
        }
    }
}

// MARK: - Сетка категорий

struct CategoryGrid: View {
    let type: TxType
    @Binding var selected: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(type == .expense ? Category.expenses : Category.incomes) { c in
                Button {
                    Haptics.tap()
                    selected = c.id
                } label: {
                    VStack(spacing: 4) {
                        Text(c.icon).font(.system(size: 24))
                        Text(c.name).font(.system(size: 11)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected == c.id ? Color.accentColor : .clear, lineWidth: 2))
                    .foregroundStyle(selected == c.id ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Тост

struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text).lineLimit(2)
            if let title = toast.actionTitle {
                Button(title) {
                    Haptics.tap()
                    toast.action?()
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.cyan)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - Прогресс-полоска

struct ProgressBar: View {
    var value: Double
    var color: Color
    var limit: Double? = nil
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1) * (shown ? 1 : 0))
                if let limit, limit <= 1 {
                    Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 2, height: 12).offset(x: geo.size.width * limit - 1)
                }
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.easeOut(duration: 1)) { shown = true } }
    }
}
