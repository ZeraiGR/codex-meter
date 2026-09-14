import SwiftUI

@MainActor enum UISmokeChecks {
    static func run() -> Bool {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        NSApp.accessibilitySetValue(true,forAttribute:NSAccessibility.Attribute(rawValue:"AXEnhancedUserInterface"))
        let navigation = WindowNavigation()
        let rect = NSRect(x: -10000, y: -10000, width: 420, height: 550)
        let panel = NSPanel(contentRect: rect, styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        let dashboard = NSWindow(contentRect: rect, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; dashboard.isReleasedWhenClosed = false
        defer { panel.orderOut(nil); dashboard.orderOut(nil) }
        func settle(until ready: (() -> Bool)? = nil) {
            let deadline = Date().addingTimeInterval(ready == nil ? 0.3 : 3)
            while Date() < deadline {
                let slice = min(deadline, Date().addingTimeInterval(0.02))
                RunLoop.main.run(until: slice)
                if let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
                NSApp.updateWindows()
                if ready?() == true { return }
            }
        }
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition {
                failures += 1
                print("panelVisible=\(panel.isVisible) dashboardVisible=\(dashboard.isVisible) key=\(dashboard.isKeyWindow) minimized=\(dashboard.isMiniaturized) active=\(NSApp.isActive)")
            }
        }
        navigation.attach(panel, as: .popover)
        panel.makeKeyAndOrderFront(nil)
        navigation.showDashboard {
            // First opening: SwiftUI attaches its window after openWindow returns.
            DispatchQueue.main.async { navigation.attach(dashboard, as: .dashboard) }
        }
        settle(until: { !panel.isVisible && dashboard.isVisible && dashboard.isKeyWindow })
        check(!panel.isVisible && dashboard.isVisible && dashboard.isKeyWindow, "First navigation closes panel and focuses dashboard")
        panel.makeKeyAndOrderFront(nil)
        navigation.showDashboard {}
        settle(until: { !panel.isVisible && dashboard.isVisible && dashboard.isKeyWindow })
        check(!panel.isVisible && dashboard.isVisible && dashboard.isKeyWindow, "Existing dashboard comes forward on repeated navigation")
        dashboard.miniaturize(nil); settle(until: { dashboard.isMiniaturized })
        guard dashboard.isMiniaturized else {check(false,"Dashboard reaches minimized state before restoration");return false}
        panel.makeKeyAndOrderFront(nil)
        navigation.showDashboard {}; settle(until: { !dashboard.isMiniaturized && !panel.isVisible && dashboard.isKeyWindow })
        check(!dashboard.isMiniaturized && !panel.isVisible && dashboard.isKeyWindow, "Minimized dashboard is restored")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let message = "Не удалось обновить квоту.\n\naccount/rateLimits/read · код -32603\nПодробности ответа сервера"
        Clipboard.copy(message, to: pasteboard)
        check(pasteboard.string(forType: .string) == message, "Copy keeps full multiline error without changing user clipboard")
        let browserPassed=BrowserUIChecks.run()
        let headingPassed=HeadingUIChecks.run()
        let assignmentPassed=AssignmentUIChecks.run()
        let costPassed=CostUIChecks.run()
        let chooserPassed=TaskChooserUIChecks.run()
        let quotaTimePassed=QuotaTimeUIChecks.run()
        let paymentDraftPassed=PaymentDraftUIChecks.run()
        let connectionPassed=ConnectionUIChecks.run()
        let taskListPassed=TaskListUIChecks.run()
        let updateSchedulePassed=UpdateScheduleChecks.run()
        return browserPassed && headingPassed && assignmentPassed && costPassed && chooserPassed && quotaTimePassed && paymentDraftPassed && connectionPassed && taskListPassed && updateSchedulePassed && failures == 0
    }
}
