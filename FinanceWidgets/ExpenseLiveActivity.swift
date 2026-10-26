import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FinanceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ExpenseLiveActivity()
    }
}

/// Результат записи в настоящем Dynamic Island и на экране блокировки
struct ExpenseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExpenseActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Text(context.state.icon).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.subtitle).font(.subheadline)
                        .foregroundStyle(context.state.isWarning ? Color.orange : Color.secondary).lineLimit(1)
                }
                Spacer()
                Text(context.state.amount).font(.title3.bold().monospacedDigit())
                    .foregroundStyle(context.state.isIncome ? Color.green : Color.primary)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.icon).font(.system(size: 30)).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.amount).font(.title3.bold().monospacedDigit())
                        .foregroundStyle(context.state.isIncome ? Color.green : Color.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.subtitle).font(.caption)
                            .foregroundStyle(context.state.isWarning ? Color.orange : Color.white.opacity(0.6)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text(context.state.icon)
            } compactTrailing: {
                Text(context.state.amount).font(.caption.bold().monospacedDigit())
                    .foregroundStyle(context.state.isWarning ? Color.orange : (context.state.isIncome ? Color.green : Color.white))
            } minimal: {
                Text(context.state.icon)
            }
            .keylineTint(context.state.isWarning ? Color.orange : Color.green)
        }
    }
}
