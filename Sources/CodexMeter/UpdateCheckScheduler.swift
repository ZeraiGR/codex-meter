import AppKit

/// Discovery cadence is independent of Sparkle's one-hour minimum scheduler.
/// The supplied action only probes; Sparkle still authenticates and installs updates.
@MainActor final class UpdateCheckScheduler {
    static let interval:TimeInterval=15*60
    private let interval:TimeInterval
    private let wakeDelay:TimeInterval
    private let center:NotificationCenter
    private let enabled:()->Bool
    private let busy:()->Bool
    private let check:()->Void
    private var timer:Timer?
    private var wakeTimer:Timer?
    private var observer:NSObjectProtocol?

    init(interval:TimeInterval=UpdateCheckScheduler.interval,wakeDelay:TimeInterval=5,
         center:NotificationCenter=NSWorkspace.shared.notificationCenter,
         enabled:@escaping()->Bool,busy:@escaping()->Bool,check:@escaping()->Void) {
        self.interval=interval;self.wakeDelay=wakeDelay;self.center=center
        self.enabled=enabled;self.busy=busy;self.check=check
    }
    func start() {
        guard observer == nil else{return}
        observer=center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.didWake() }
        }
        checkNow()
    }
    func checkNow() {
        wakeTimer?.invalidate();wakeTimer=nil
        restartTimer()
        checkIfAllowed()
    }
    private func restartTimer() {
        timer?.invalidate()
        let timer=Timer(timeInterval:interval,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {self?.checkIfAllowed()}
        }
        self.timer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func didWake() {
        guard observer != nil else{return}
        timer?.invalidate();timer=nil
        wakeTimer?.invalidate()
        let timer=Timer(timeInterval:wakeDelay,repeats:false) { [weak self] _ in
            MainActor.assumeIsolated {self?.checkNow()}
        }
        wakeTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func checkIfAllowed() {if enabled() && !busy() {check()}}
    func stop() {
        timer?.invalidate();timer=nil;wakeTimer?.invalidate();wakeTimer=nil
        if let observer {center.removeObserver(observer)}
        observer=nil
    }
    deinit {timer?.invalidate();wakeTimer?.invalidate();if let observer {center.removeObserver(observer)}}
}
