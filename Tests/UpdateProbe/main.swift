// Isolated integration-test app. Never bundled in the distributable application.
import AppKit
import Sparkle
import MeterCore

@MainActor final class Probe:NSObject,SPUUserDriver,NSApplicationDelegate {
    var updater:SPUUpdater!
    let root=Bundle.main.bundleURL.deletingLastPathComponent()
    func record(_ message:String) {try? message.write(to:root.appendingPathComponent("result.txt"),atomically:true,encoding:.utf8)}
    func applicationDidFinishLaunching(_ notification:Notification) {
        do {
            let db=try Database(directory:root.appendingPathComponent("data"))
            if Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String == "102" {
                guard try db.tasks().count==1,try db.payments().count==1,try db.runs().count==1,try db.value("test-marker")=="preserved" else{throw MeterError("Data lost")}
                let expected=try Data(contentsOf:root.appendingPathComponent("before.json"))
                let previous=try JSONSerialization.jsonObject(with:expected) as! [String:[[String:String]]]
                guard try snapshot(db)==previous else{throw MeterError("Persisted rows changed during update")}
                record("installed-and-relaunched-data-preserved");NSApp.terminate(nil);return
            }
            let task=WorkTask(id:"fixture-task",title:"Review API",kind:"code-review")
            try db.saveTask(task)
            try db.savePayment(Payment(amount:3000,start:Date(timeIntervalSince1970:1704067200),end:Date(timeIntervalSince1970:1706745600)))
            try db.saveRun(RunRecord(id:"fixture-run",thread:"fixture-thread",started:Date(),tokens:.init(input:1000,output:100),taskID:task.id))
            try db.bind(thread:"fixture-thread",turn:"fixture-run",task:task.id)
            try db.set("test-marker","preserved")
            try JSONSerialization.data(withJSONObject:snapshot(db),options:[.sortedKeys]).write(to:root.appendingPathComponent("before.json"))
            updater=SPUUpdater(hostBundle:.main,applicationBundle:.main,userDriver:self,delegate:nil)
            try updater.start()
            updater.checkForUpdates()
        } catch {record("error: \(error)");NSApp.terminate(nil)}
    }
    func snapshot(_ db:Database)throws->[String:[[String:String]]] {
        var data=[String:[[String:String]]]()
        for table in ["kv","tasks","turns","bindings","payments","observations"] {data[table]=try db.query("SELECT * FROM "+table+" ORDER BY 1")}
        return data
    }
    func show(_ request:SPUUpdatePermissionRequest,reply:@escaping(SUUpdatePermissionResponse)->Void) {reply(SUUpdatePermissionResponse(automaticUpdateChecks:false,sendSystemProfile:false))}
    func showUserInitiatedUpdateCheck(cancellation:@escaping()->Void) {}
    func showUpdateFound(with appcastItem:SUAppcastItem,state:SPUUserUpdateState,reply:@escaping(SPUUserUpdateChoice)->Void) {record("found-update");reply(.install)}
    func showUpdateReleaseNotes(with downloadData:SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error:Error) {}
    func showUpdateNotFoundWithError(_ error:Error,acknowledgement:@escaping()->Void) {record("no-update");acknowledgement();NSApp.terminate(nil)}
    func showUpdaterError(_ error:Error,acknowledgement:@escaping()->Void) {record("rejected: \((error as NSError).code)");acknowledgement();NSApp.terminate(nil)}
    func showDownloadInitiated(cancellation:@escaping()->Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ length:UInt64) {}
    func showDownloadDidReceiveData(ofLength length:UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress:Double) {}
    func showReady(toInstallAndRelaunch reply:@escaping(SPUUserUpdateChoice)->Void) {reply(.install)}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated:Bool,retryTerminatingApplication:@escaping()->Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched:Bool,acknowledgement:@escaping()->Void) {acknowledgement()}
    func dismissUpdateInstallation() {}
}

MainActor.assumeIsolated {
    let app=NSApplication.shared
    app.setActivationPolicy(.accessory)
    let probe=Probe()
    app.delegate=probe
    withExtendedLifetime(probe){app.run()}
}
