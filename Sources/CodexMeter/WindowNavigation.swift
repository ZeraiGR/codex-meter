import SwiftUI

/// Keep the menu-bar panel out of the way when navigating to the main window.
@MainActor final class WindowNavigation {
    static let shared = WindowNavigation()
    enum Role { case popover, dashboard }
    private weak var popover: NSWindow?
    private weak var dashboard: NSWindow?
    private var awaitingDashboard = false

    func attach(_ window: NSWindow, as role: Role) {
        switch role {
        case .popover: popover = window
        case .dashboard:
            dashboard = window
            if awaitingDashboard { focusDashboard() }
        }
    }

    func dismissPopover() {popover?.orderOut(nil)}

    func showDashboard(open: () -> Void) {
        awaitingDashboard = true
        popover?.orderOut(nil)
        open()
        focusDashboard()
        // SwiftUI may finish restoring an existing window on the next run loop.
        DispatchQueue.main.async { [weak self] in self?.focusDashboard() }
    }

    private func focusDashboard() {
        guard let dashboard else { return }
        awaitingDashboard = false
        if dashboard.isMiniaturized { dashboard.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        dashboard.makeKeyAndOrderFront(nil)
    }
}

struct WindowReader: NSViewRepresentable {
    let role: WindowNavigation.Role
    func makeNSView(context: Context) -> Observer { Observer(role: role) }
    func updateNSView(_ nsView: Observer, context: Context) {}

    final class Observer: NSView {
        let role: WindowNavigation.Role
        init(role: WindowNavigation.Role) { self.role = role; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                DispatchQueue.main.async { [role] in WindowNavigation.shared.attach(window, as: role) }
            }
        }
    }
}

enum Clipboard {
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct ErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)?
    private var parts: [String] { message.components(separatedBy: "\n\n") }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(parts[0]).fixedSize(horizontal: false, vertical: true)
                if parts.count > 1 {
                    DisclosureGroup("Подробности") {
                        Text(parts.dropFirst().joined(separator: "\n\n"))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            Button { Clipboard.copy(message) } label: { Image(systemName: "doc.on.doc").frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Скопировать ошибку").accessibilityLabel("Скопировать ошибку")
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Скрыть ошибку")
            }
        }.font(.caption).foregroundStyle(.orange)
    }
}
