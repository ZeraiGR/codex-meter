import SwiftUI
import MeterCore

struct ConnectionCard:View {
    @EnvironmentObject var store:MeterStore
    @State private var advanced=false
    @State private var manual=false
    @State private var path=""
    @State private var issue:String?
    private var changed:Bool { (manual ? path.trimmingCharacters(in:.whitespacesAndNewlines):"") != store.codexPath }
    var body:some View {
        Card {
            Text("Данные из Codex").font(.headline)
            TimelineView(.periodic(from:.now,by:60)) { context in
                VStack(alignment:.leading,spacing:6) {
                    if store.updating {
                        Label("Обновляем данные…",systemImage:"arrow.clockwise").foregroundStyle(MeterTheme.secondary)
                    } else if store.connectionError != nil {
                        Label("Не удалось обновить данные",systemImage:"exclamationmark.circle").foregroundStyle(MeterTheme.warning)
                        Text(store.snapshot==nil ? "Данные ещё не получены. Подробности ошибки показаны вверху окна.":"Последние полученные значения сохранены. Обновление повторится автоматически; подробности ошибки показаны вверху окна.").font(.caption).foregroundStyle(MeterTheme.secondary)
                    } else if store.snapshot?.fresh(at:context.date)==true {
                        Label("Данные Codex актуальны",systemImage:"checkmark.circle.fill").foregroundStyle(MeterTheme.accent)
                    } else {
                        Label(store.snapshot==nil ? "Ожидаем данные Codex":"Данные требуют обновления",systemImage:"clock").foregroundStyle(MeterTheme.secondary)
                        Text("Откройте Codex и войдите в свой аккаунт, затем нажмите «Обновить данные».").font(.caption).foregroundStyle(MeterTheme.secondary)
                    }
                    if let snapshot=store.snapshot {
                        Text("Последнее успешное обновление: \(snapshot.fetchedAt.formatted(date:.abbreviated,time:.shortened))")
                            .font(.caption).foregroundStyle(MeterTheme.secondary)
                    }
                }.accessibilityElement(children:.contain)
            }
            if !store.codexPath.isEmpty {
                Text("Сохранён ручной выбор файла Codex. Изменить его можно в дополнительных настройках.")
                    .font(.callout).fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("connection-mode")
            }
            Text("Квота обновляется раз в минуту, история задач — каждые 15 секунд.")
                .font(.caption).foregroundStyle(MeterTheme.secondary)
            Button("Обновить данные") { store.refresh() }
                .disabled(store.updating).accessibilityIdentifier("connection-refresh")
            DisclosureGroup("Дополнительные настройки",isExpanded:$advanced) {
                VStack(alignment:.leading,spacing:12) {
                    Text("Ручной выбор нужен, если автоматический поиск не находит вашу установку Codex. Обычно менять здесь ничего не требуется.")
                        .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    Picker("Поиск Codex",selection:$manual) {
                        Text("Автоматически").tag(false)
                        Text("Выбрать вручную").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("connection-search-mode")
                    if manual {
                        Text("Исполняемый файл codex").font(.callout.weight(.medium))
                        HStack {
                            TextField("Например: /opt/homebrew/bin/codex",text:$path)
                                .textFieldStyle(.roundedBorder).accessibilityIdentifier("connection-path")
                            Button("Выбрать файл…") { chooseFile() }
                        }
                        Text("Выберите файл с именем codex, а не папку проекта. Приложение Codex.app можно раскрыть для выбора файла внутри.")
                            .font(.caption).foregroundStyle(MeterTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    if let issue {Text(issue).font(.caption).foregroundStyle(MeterTheme.danger).fixedSize(horizontal:false,vertical:true)}
                    Button("Применить способ поиска") {
                        do {
                            try store.saveCodexPath(manual ? path:"")
                            path=store.codexPath;issue=nil;store.refresh()
                        } catch { issue=error.localizedDescription }
                    }.disabled(!changed || store.updating || (manual && path.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("connection-apply")
                }.padding(.top,10)
            }.accessibilityIdentifier("connection-advanced")
        }
        .onAppear {path=store.codexPath;manual = !path.isEmpty}
        .onChange(of:path) {_,_ in issue=nil}
        .onChange(of:manual) {_,_ in issue=nil}
    }
    private func chooseFile() {
        let panel=NSOpenPanel()
        panel.title="Выберите исполняемый файл codex"
        panel.prompt="Выбрать"
        panel.canChooseFiles=true;panel.canChooseDirectories=false
        panel.allowsMultipleSelection=false;panel.treatsFilePackagesAsDirectories=true
        if !path.isEmpty { panel.directoryURL=URL(fileURLWithPath:path).deletingLastPathComponent() }
        if panel.runModal() == .OK,let url=panel.url {path=url.path}
    }
}
