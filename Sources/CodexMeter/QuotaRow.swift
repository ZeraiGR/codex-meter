import SwiftUI
import MeterCore

struct QuotaRow:View {
    var window:QuotaWindow
    var body:some View {
        TimelineView(.periodic(from:.now,by:60)) { context in
            QuotaRowContent(window:window,now:context.date)
        }
    }
}

struct QuotaRowContent:View {
    var window:QuotaWindow
    var now:Date
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            VStack(alignment:.leading,spacing:7) {
                HStack {
                    Text(window.label).font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(window.usedPercent))% потрачено · \(Int(window.remaining))% осталось")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).monospacedDigit()
                        .accessibilityIdentifier("quota-remaining-caption")
                }
                QuotaFillBar(remaining:window.remaining,tint:Format.color(window.remaining))
                    .accessibilityLabel("Остаток квоты")
                    .accessibilityValue("\(Int(window.remaining))%")
                    .accessibilityIdentifier("quota-remaining-bar")
            }
            if let elapsed=window.elapsedPercent(at:now) {
                let passed=Int(elapsed.rounded()),remaining=100-passed
                VStack(alignment:.leading,spacing:7) {
                    HStack {
                        Text(window.windowDurationMins==10080 ? "Время недели":"Время периода")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(passed)% прошло · \(remaining)% осталось")
                            .font(.caption).foregroundStyle(MeterTheme.secondary).monospacedDigit()
                            .accessibilityIdentifier("quota-time-caption")
                    }
                    QuotaFillBar(remaining:100-elapsed,tint:.blue)
                        .accessibilityLabel("Остаток времени")
                        .accessibilityValue("\(remaining)%")
                        .accessibilityIdentifier("quota-time-bar")
                }.help("Обе шкалы показывают остаток. Время считается от начала периода квоты до его восстановления, а не с понедельника.")
            } else if window.resetDate.map({$0<=now}) != true {
                Text("Прогресс времени недоступен")
                    .font(.caption2).foregroundStyle(MeterTheme.secondary)
                    .help("Для расчёта нужны длительность текущего периода и дата восстановления квоты.")
            }
            if let reset=window.resetDate,reset.timeIntervalSince1970.isFinite {
                HStack {
                    Image(systemName:"arrow.trianglehead.clockwise")
                    Text(reset>now ? "Восстановление через \(Format.time(reset.timeIntervalSince(now)))":"Период завершён · проверяем восстановление…")
                        .accessibilityIdentifier("quota-reset-message")
                    Spacer()
                    Text(reset.formatted(date:.abbreviated,time:.shortened))
                        .accessibilityIdentifier("quota-reset-date")
                }.font(.caption2).foregroundStyle(MeterTheme.secondary)
            }
        }
    }
}

private struct QuotaFillBar:View {
    let remaining:Double
    let tint:Color
    var body:some View {
        GeometryReader { geometry in
            ZStack(alignment:.leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width:geometry.size.width*remaining/100)
            }
        }.frame(height:7).accessibilityElement(children:.ignore)
    }
}
