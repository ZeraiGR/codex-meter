import AppKit

@MainActor enum UpdateScheduleChecks {
    static func run()->Bool {
        var failures=0
        func check(_ condition:Bool,_ label:String) {print("\(condition ? "PASS":"FAIL") \(label)");if !condition {failures += 1}}
        func settle(_ seconds:TimeInterval) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
        func wait(_ condition:()->Bool) {
            let deadline=Date().addingTimeInterval(2)
            while !condition() && Date()<deadline {settle(0.01)}
        }
        let center=NotificationCenter()
        var enabled=true,busy=false,calls=0
        let schedule=UpdateCheckScheduler(interval:0.05,wakeDelay:0.02,center:center,
            enabled:{enabled},busy:{busy},check:{calls += 1})
        schedule.start()
        check(calls==1,"Update discovery checks immediately on launch")
        schedule.start()
        check(calls==1,"Repeated scheduler startup does not duplicate launch checks")
        wait {calls>=2}
        check(calls>=2,"Update discovery repeats using its own timer")
        enabled=false;let disabledCount=calls
        center.post(name:NSWorkspace.didWakeNotification,object:nil);settle(0.15)
        check(calls==disabledCount,"Disabled automatic checks suppress both timer and wake requests")
        enabled=true;busy=true;let busyCount=calls
        schedule.checkNow();center.post(name:NSWorkspace.didWakeNotification,object:nil);settle(0.15)
        check(calls==busyCount,"Active update session prevents overlapping discovery checks")
        busy=false;schedule.checkNow()
        check(calls==busyCount+1,"Enabling discovery can request a fresh check immediately")
        schedule.stop()
        let wakeCenter=NotificationCenter()
        let wake=UpdateCheckScheduler(interval:60,wakeDelay:0.02,center:wakeCenter,
            enabled:{true},busy:{false},check:{calls += 1})
        wake.start();let beforeWake=calls
        for _ in 0..<3 {wakeCenter.post(name:NSWorkspace.didWakeNotification,object:nil)}
        wait {calls>beforeWake};settle(0.05)
        check(calls==beforeWake+1,"Wake events coalesce into one check without waiting for the interval")
        wakeCenter.post(name:NSWorkspace.didWakeNotification,object:nil);settle(0.005)
        wake.stop();let stopped=calls;settle(0.1)
        check(calls==stopped,"Stopping discovery cancels pending wake checks and timers")
        return failures==0
    }
}
