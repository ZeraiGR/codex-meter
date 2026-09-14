import SwiftUI
import MeterCore

struct TaskQuotaView:View {
    let summary:TaskSummary
    private func number(_ value:Double)->String {value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier:"ru_RU")))}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label("Недельная квота",systemImage:"chart.pie").font(.callout.weight(.medium))
                Spacer()
                if let quota=summary.weeklyQuota {Text(quota.complete ? "По всей задаче":"Учтённая часть").font(.caption).foregroundStyle(MeterTheme.secondary)}
            }
            if let quota=summary.weeklyQuota {
                Text(quota.points<0.01 ? "< 0,01%":"≈ \(number(quota.points))%")
                    .font(.system(size:28,weight:.semibold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(quota.complete ? MeterTheme.accent:MeterTheme.warning).accessibilityIdentifier("task-weekly-quota")
                if quota.points<=100 {ProgressView(value:quota.points,total:100).tint(quota.complete ? MeterTheme.accent:MeterTheme.warning)}
                if quota.windowCount>1 || quota.points>100 {
                    Text("Суммарно за недельные периоды: \(quota.windowCount). 100% соответствует одной полной недельной квоте.")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("task-quota-periods")
                } else {Text("От одной недельной квоты Codex").font(.caption).foregroundStyle(MeterTheme.secondary)}
                if !quota.complete {
                    Text("Измерения покрывают \(number(quota.coverage*100))% токенов задачи. Полный расход неизвестен; показана только учтённая часть.")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("task-quota-partial")
                }
            } else {
                Text("Недостаточно измерений").font(.headline).accessibilityIdentifier("task-quota-unknown")
                Text("Нужны снимки недельной квоты во время работы. По числу токенов этот процент определить нельзя.")
                    .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
    }
}
