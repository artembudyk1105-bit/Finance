import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Binding var showAdd: Bool
    @State private var editing: Transaction?

    var body: some View {
        let s = store.summary(Day.currentMonth)
        NavigationStack {
            List {
                Section {
                    hero(s).plainRow()
                    tipCard.plainRow()
                    rings(s).plainRow()
                }
                Section {
                    if store.recent.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.recent) { tx in
                            TransactionRow(tx: tx, showDate: true)
                                .onTapGesture { editing = tx }
                                .swipeActions { deleteButton(tx) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Последние").font(.title3.bold()).foregroundStyle(.primary).textCase(nil)
                        Spacer()
                        Button("Все") { router.tab = .history }.textCase(nil)
                    }
                }
                Color.clear.frame(height: 70).plainRow()
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("Обзор")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(Day.todayTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) { CurrencyMenu() }
            }
            .sheet(item: $editing) { TransactionEditor(tx: $0) }
        }
    }

    // MARK: - Блоки

    private func hero(_ s: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Остаток в этом месяце").font(.subheadline).opacity(0.8)
            Text(store.money(s.balance))
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: s.balance))
                .minimumScaleFactor(0.6).lineLimit(1)
                .padding(.bottom, 10)
            HStack(spacing: 10) {
                heroPill("↓ Поступления", store.money(s.income))
                heroPill("↑ Траты", store.money(s.expense))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: "0A84FF"), Color(hex: "5E5CE6"), Color(hex: "BF5AF2")], startPoint: .topLeading, endPoint: .bottomTrailing)
                FloatingGlow()
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .animation(.snappy, value: s.balance)
    }

    private func heroPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).opacity(0.85)
            Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tipCard: some View {
        let h = Assistant.headline(store: store)
        let border: Color = h.level == .danger ? .red : (h.level == .warn ? .orange : .clear)
        return Button { router.tab = .assistant } label: {
            HStack(alignment: .top, spacing: 12) {
                AssistantAvatar()
                VStack(alignment: .leading, spacing: 3) {
                    Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(h.text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func rings(_ s: MonthSummary) -> some View {
        let B = store.budget
        let optMax = B > 0 ? B * 0.3 : s.income * 0.3
        let saveGoal = s.income * store.settings.savingsTarget / 100
        let data = [
            RingData(value: s.expense, max: B > 0 ? B : max(s.income, s.expense, 1), color: Color(hex: "FA114F"),
                     title: "Траты", valueText: store.money(s.expense), subtitle: B > 0 ? "из \(store.money(B))" : ""),
            RingData(value: s.optional, max: optMax > 0 ? optMax : max(s.expense, 1), color: Color(hex: "92E82A"),
                     title: "Необязательные", valueText: store.money(s.optional), subtitle: optMax > 0 ? "из \(store.money(optMax.rounded()))" : ""),
            RingData(value: max(s.balance, 0), max: max(saveGoal, 1), color: Color(hex: "1EEAEF"), overColor: Color(hex: "0A9DA1"),
                     title: "Сбережения", valueText: store.money(max(s.balance, 0)), subtitle: saveGoal > 0 ? "цель \(store.money(saveGoal.rounded()))" : "")
        ]
        return HStack(spacing: 18) {
            ActivityRings(rings: data).frame(width: 128, height: 128)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(data) { r in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Circle().fill(r.color).frame(width: 9, height: 9)
                            Text(r.title).font(.footnote).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(r.valueText).font(.headline.monospacedDigit())
                            Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🎙️").font(.system(size: 44))
            Text("Зажмите кнопку микрофона и скажите\n**«кофе 250 и такси 400»**").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Загрузить демо-данные") { store.seedDemo() }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func deleteButton(_ tx: Transaction) -> some View {
        Button(role: .destructive) {
            if let removed = store.remove(tx.id) {
                router.showToast("Удалено: \(removed.name)", actionTitle: "Отменить") { store.restore([removed]) }
            }
        } label: { Label("Удалить", systemImage: "trash") }
    }
}

struct CurrencyMenu: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Menu {
            Picker("Валюта", selection: $store.data.settings.currency) {
                ForEach(Store.currencies, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Text(store.settings.currency)
                .font(.headline)
                .frame(minWidth: 32, minHeight: 32)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .onChange(of: store.data.settings.currency) { _, _ in Haptics.tap() }
    }
}

struct AssistantAvatar: View {
    @State private var spin = false
    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(hex: "0A84FF"), Color(hex: "BF5AF2"), Color(hex: "FF375F"), Color(hex: "FF9F0A"), Color(hex: "30D158"), Color(hex: "0A84FF")], center: .center))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
            Circle().fill(Color(.secondarySystemGroupedBackground)).padding(4)
            Image(systemName: "sparkle").font(.system(size: 14, weight: .bold))
        }
        .frame(width: 36, height: 36)
        .onAppear { spin = true }
    }
}

struct FloatingGlow: View {
    @State private var move = false
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 110))
            .frame(width: 220, height: 220)
            .offset(x: move ? 60 : 120, y: move ? -40 : -90)
            .scaleEffect(move ? 1.15 : 1)
            .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: move)
            .onAppear { move = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
    }
}
