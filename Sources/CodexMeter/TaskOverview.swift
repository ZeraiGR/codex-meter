import SwiftUI
import MeterCore

struct DetailsDisclosureStyle:DisclosureGroupStyle {
    func makeBody(configuration:Configuration)->some View {
        VStack(alignment:.leading,spacing:0) {
            Button {configuration.isExpanded.toggle()} label: {
                HStack(spacing:6) {
                    Image(systemName:configuration.isExpanded ? "chevron.down":"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MeterTheme.secondary).frame(width:12)
                    configuration.label
                    Spacer(minLength:0)
                }.frame(minHeight:28).contentShape(Rectangle()).textSelection(.disabled)
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "Развёрнуто":"Свёрнуто")
            if configuration.isExpanded {configuration.content}
        }
    }
}

struct TaskOverview:View {
    @EnvironmentObject var store:MeterStore
    let summary:TaskSummary
    @State private var expanded=false
    var body:some View {
        Card {
            HStack {Metric(label:"Токены",value:Format.tokens(summary.tokens.total));Metric(label:"Время выполнения",value:Format.time(summary.activeSeconds))}
            Divider()
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text(summary.rubles == nil ? "Учтённая стоимость":"Стоимость").font(.caption).foregroundStyle(MeterTheme.secondary)
                    Text((summary.rubles ?? summary.measuredRubles).map{ "≈ "+Format.rub($0) } ?? "Нет оценки").font(.headline)
                    if let dollars=store.exchangeRate?.dollars(for:summary.rubles ?? summary.measuredRubles) {
                        Text("≈ "+Format.usd(dollars)).font(.caption)
                        if store.exchangeRate?.isStale() == true || store.exchangeRateIssue != nil {Text("Сохранённый курс").font(.caption2).foregroundStyle(MeterTheme.warning)}
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:4) {
                    Text("Недельная квота").font(.caption).foregroundStyle(MeterTheme.secondary)
                    Text(summary.weeklyQuota.map{$0.points<0.01 ? "< 0,01%":"≈ "+$0.points.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier:"ru_RU")))+"%"} ?? "Нет измерений").font(.headline)
                    if let quota=summary.weeklyQuota,!quota.complete {Text("Измерена часть задачи").font(.caption).foregroundStyle(MeterTheme.warning)}
                    if let quota=summary.weeklyQuota,quota.windowCount>1 {Text("Недельных периодов: \(quota.windowCount)").font(.caption).foregroundStyle(MeterTheme.secondary)}
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            DisclosureGroup(isExpanded:$expanded) {
                VStack(alignment:.leading,spacing:16) {
                    TaskQuotaView(summary:summary)
                    Divider()
                    TaskCostView(summary:summary,exchangeRate:store.exchangeRate,exchangeRateIssue:store.exchangeRateIssue,updatingExchangeRate:store.updatingExchangeRate,refreshExchangeRate:{store.refreshExchangeRate()})
                    Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:8) {
                        row("Вход",Format.tokens(summary.tokens.input));row("Из него кэш",Format.tokens(summary.tokens.cached))
                        row("Выход",Format.tokens(summary.tokens.output));row("Из него reasoning",Format.tokens(summary.tokens.reasoning))
                        row("Полное время",Format.time(summary.wallSeconds))
                    }.font(.callout)
                    Text("Кэш входит во входные токены, reasoning — в выходные. Полное время включает паузы; время выполнения учитывает параллельную работу один раз.").font(.caption).foregroundStyle(MeterTheme.secondary)
                    Text(summary.quotaQuality).font(.caption).foregroundStyle(MeterTheme.secondary)
                }.padding(.top,12)
            } label:{Text("Детали расхода")}
                .accessibilityIdentifier("task-expense-details")
        }.disclosureGroupStyle(DetailsDisclosureStyle())
    }
    private func row(_ title:String,_ value:String)->some View {GridRow {Text(title).foregroundStyle(MeterTheme.secondary);Text(value).textSelection(.enabled)}}
}

struct TaskExecutionView:View {
    let runs:[RunRecord]
    private var profiles:[String] {
        Set(runs.flatMap {run in
            let configurations=run.execution?.configurations ?? []
            if configurations.isEmpty {return [(run.model.isEmpty ? "Модель не записана":run.model)+" · "+(run.effort.isEmpty ? "Рассуждение не записано":run.effort)]}
            return configurations.map{($0.model.isEmpty ? "Модель не записана":$0.model)+" · "+($0.effort.isEmpty ? "Рассуждение не записано":$0.effort)}
        }).sorted()
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Контекст выполнения").font(.headline)
            Text("Запусков: \(runs.count)").font(.caption).foregroundStyle(MeterTheme.secondary)
            ForEach(Array(profiles.prefix(3)),id:\.self) {Text($0).font(.callout).textSelection(.enabled)}
            if profiles.count>3 {Text("Ещё сочетаний модели и рассуждения: \(profiles.count-3)").font(.caption).foregroundStyle(MeterTheme.secondary)}
            DisclosureGroup("Параметры и инструменты запусков") {
                LazyVStack(alignment:.leading,spacing:18) {
                    ForEach(runs.sorted{$0.started<$1.started}) {run in
                        VStack(alignment:.leading,spacing:8) {
                            Text(run.started.formatted(date:.abbreviated,time:.shortened)+" · "+Format.tokens(run.tokens.total)+" токенов").font(.headline)
                            Text(run.title).font(.callout)
                            ExecutionContextView(run:run)
                        }
                        Divider()
                    }
                }.padding(.top,12)
            }.accessibilityIdentifier("task-execution-details")
        }.disclosureGroupStyle(DetailsDisclosureStyle())
    }
}

struct ExecutionContextView:View {
    let run:RunRecord
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            LabeledContent("Harness",value:run.execution?.harness.isEmpty == false ? run.execution!.harness:"Не записан")
            Text("Клиент и версия записаны при создании диалога. После возобновления версия клиента могла измениться.").font(.caption).foregroundStyle(MeterTheme.secondary)
            if let source=run.execution?.source {LabeledContent("Источник",value:source)}
            let configurations=run.execution?.configurations ?? []
            if configurations.isEmpty {
                LabeledContent("Модель",value:run.model.isEmpty ? "Не записана":run.model)
                LabeledContent("Рассуждение",value:run.effort.isEmpty ? "Не записано":run.effort)
            } else {
                ForEach(Array(configurations.enumerated()),id:\.offset) {_,config in
                    VStack(alignment:.leading,spacing:4) {
                        Text((config.model.isEmpty ? "Модель не записана":config.model)+" · "+(config.effort.isEmpty ? "Уровень рассуждения не записан":config.effort)).font(.callout.weight(.medium))
                        Text(Format.tokens(config.tokens.total)+" токенов при этих параметрах").font(.caption)
                        if let provider=config.provider {LabeledContent("Провайдер",value:provider)}
                        if let tier=config.serviceTier {LabeledContent("Service tier",value:tier)}
                        if let window=config.contextWindow {LabeledContent("Окно контекста",value:Format.tokens(Int64(window)))}
                    }
                }
            }
            Text("Имя модели записано как в журнале. Точная серверная версия за псевдонимом не раскрывается журналом.").font(.caption).foregroundStyle(MeterTheme.secondary)
            Divider()
            Text("MCP и инструменты").font(.callout.weight(.medium))
            Text("Доступные MCP: полный список в журнале не сохранён. Текущие настройки не описывают доступность в прошлом.").font(.caption).foregroundStyle(MeterTheme.secondary)
            let calls=run.execution?.calls ?? []
            if calls.isEmpty {Text("События выполнения инструментов не записаны. Это не подтверждает, что инструменты не использовались.").font(.caption)}
            else {
                let grouped=Dictionary(grouping:calls,by:{($0.server.map{$0+" / "} ?? "")+$0.name})
                ForEach(grouped.keys.sorted(),id:\.self) {name in
                    let values=grouped[name] ?? []
                    HStack(alignment:.top) {
                        Text(name).lineLimit(nil)
                        Spacer()
                        Text("\(values.count) выз.").monospacedDigit()
                    }.font(.caption)
                    let failed=values.filter{["failed","error","cancelled"].contains($0.status)}.count
                    if failed>0 {Text("Ошибок или отмен: \(failed)").font(.caption2).foregroundStyle(MeterTheme.warning)}
                }
                DisclosureGroup("События инструментов") {
                    LazyVStack(alignment:.leading,spacing:8) {
                        ForEach(calls) {call in
                            VStack(alignment:.leading,spacing:2) {
                                Text((call.server.map{$0+" / "} ?? "")+call.name).font(.caption.weight(.medium))
                                Text([call.completedAt.map{$0.formatted(date:.omitted,time:.standard)},call.status,call.duration.map{Format.time($0)}].compactMap{$0}.joined(separator:" · ")).font(.caption2).foregroundStyle(MeterTheme.secondary)
                            }
                        }
                    }.padding(.top,8)
                }
            }
            DisclosureGroup("Идентификаторы запуска") {
                VStack(alignment:.leading,spacing:4) {Text("Запуск: "+run.id);Text("Диалог: "+run.thread);if let parent=run.parentThread {Text("Родительский диалог: "+parent)};if let cwd=run.workingDirectory {Text("Проект: "+cwd)}}.font(.caption)
            }
        }.font(.caption).textSelection(.enabled).disclosureGroupStyle(DetailsDisclosureStyle()).accessibilityIdentifier("execution-context")
    }
}
