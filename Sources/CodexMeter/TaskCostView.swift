import SwiftUI
import MeterCore

struct TaskCostView:View {
    let summary:TaskSummary
    var exchangeRate:USDExchangeRate?=nil
    var exchangeRateIssue:String?=nil
    var updatingExchangeRate=false
    var refreshExchangeRate:(()->Void)?=nil
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if let total=summary.rubles {
                Text("Суммарная стоимость задачи").font(.callout.weight(.medium))
                Text("≈ "+Format.rub(total)).font(.title.weight(.semibold)).monospacedDigit().accessibilityIdentifier("task-cost-amount")
                dollarAmount(total,id:"task-cost-amount-usd")
                Text("Все запуски задачи: \(summary.runs.count) · оценка доли оплаты подписки").font(.caption).foregroundStyle(MeterTheme.secondary)
            } else if let measured=summary.measuredRubles {
                if let projected=summary.projectedRubles {
                    HStack(alignment:.top,spacing:20) {
                        costMetric("Учтено по измерениям",measured,id:"task-cost-amount")
                        costMetric("Приблизительный итог",projected,id:"task-cost-projection")
                    }
                    Text("Итог уже включает учтённую сумму. Он предполагает такой же средний расход у пропущенной части и может заметно отличаться от фактической стоимости.")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("task-cost-incomplete")
                } else {
                    Text("Учтённая стоимость задачи").font(.callout.weight(.medium))
                    Text("≈ "+Format.rub(measured)).font(.title.weight(.semibold)).monospacedDigit().accessibilityIdentifier("task-cost-amount")
                    dollarAmount(measured,id:"task-cost-amount-usd")
                    Text("Для приблизительного итога недостаточно данных о покрытии.").accessibilityIdentifier("task-cost-incomplete")
                        .font(.callout).fixedSize(horizontal:false,vertical:true)
                }
                if let coverage=summary.costCoverage {
                    ProgressView(value:coverage).tint(MeterTheme.warning)
                    Text("Рассчитано для \(coverage>0 && coverage<0.0001 ? "менее 0,01%":coverage.formatted(.percent.precision(.fractionLength(0...2)).locale(Locale(identifier:"ru_RU")))) токенов задачи")
                        .font(.caption).foregroundStyle(MeterTheme.secondary)
                }
                if summary.projectedRubles != nil {
                    Text("Приблизительный итог = учтённая сумма ÷ доля токенов с данными.")
                        .font(.caption2).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                }
            } else {
                Text("Суммарная стоимость задачи").font(.callout.weight(.medium))
                Text("Недостаточно данных").font(.title3.weight(.semibold))
                Text(summary.quotaPoints != nil ? "Добавьте оплату подписки за период выполнения задачи. Без неё нельзя перевести расход квоты в рубли.":"Нужны измерения изменения квоты и оплата за период работы. История токенов сама по себе не определяет цену задачи.")
                    .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if summary.rubles != nil || summary.measuredRubles != nil {
                VStack(alignment:.leading,spacing:4) {
                    if let rate=exchangeRate,rate.valid {
                        Text("ЦБ РФ на "+rate.effectiveDate.formatted(Date.FormatStyle(date:.numeric,time:.omitted,locale:Locale(identifier:"ru_RU"),timeZone:TimeZone(identifier:"Europe/Moscow")!))+": 1 USD = "+Format.rub(rate.rublesPerDollar))
                        if rate.isStale() || exchangeRateIssue != nil {
                            Text("Сохранённый курс · "+(exchangeRateIssue ?? "курс давно не обновлялся")).foregroundStyle(MeterTheme.warning)
                        }
                    } else {
                        Text(updatingExchangeRate ? "Загружаем курс USD…":"USD недоступен · нет курса ЦБ РФ")
                        if let exchangeRateIssue {Text(exchangeRateIssue).foregroundStyle(MeterTheme.warning)}
                    }
                    if let refreshExchangeRate {
                        Button(updatingExchangeRate ? "Обновляем курс…":"Обновить курс",action:refreshExchangeRate)
                            .buttonStyle(.link).disabled(updatingExchangeRate)
                    }
                }.font(.caption).foregroundStyle(MeterTheme.secondary)
                    .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("task-cost-exchange-rate")
            }
        }.frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
    }
    @ViewBuilder private func dollarAmount(_ rubles:Double,id:String)->some View {
        if let dollars=exchangeRate?.dollars(for:rubles) {
            Text("≈ "+Format.usd(dollars)).font(.callout.weight(.medium)).monospacedDigit()
                .foregroundStyle(MeterTheme.secondary).accessibilityIdentifier(id)
        }
    }
    private func costMetric(_ label:String,_ value:Double,id:String)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(label).font(.callout.weight(.medium)).fixedSize(horizontal:false,vertical:true)
            Text("≈ "+Format.rub(value)).font(.title2.weight(.semibold)).monospacedDigit()
                .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(id)
            dollarAmount(value,id:id+"-usd")
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

}
