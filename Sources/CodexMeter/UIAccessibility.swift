import AppKit

/// SwiftUI accessibility children need not declare NSAccessibilityProtocol.
/// Read the selectors they actually expose, including virtual text elements.
@MainActor enum UIAccessibility {
    static func value(_ node:NSObject,_ key:String)->Any? {
        node.responds(to:NSSelectorFromString(key)) ? node.value(forKey:key):nil
    }
    static func nodes(_ object:Any)->[NSObject] {
        var visited=Set<ObjectIdentifier>()
        func walk(_ object:Any)->[NSObject] {
            guard let node=object as? NSObject,visited.insert(ObjectIdentifier(node)).inserted else{return []}
            // Native list row containers can be absent from accessibilityChildren.
            // Visit live subviews as well as SwiftUI's virtual accessibility elements.
            let views=(node as? NSView)?.subviews ?? []
            let children=(value(node,"accessibilityChildren") as? [Any]) ?? []
            return [node]+views.flatMap{walk($0)}+children.flatMap{walk($0)}
        }
        return walk(object)
    }
    static func find(_ root:Any,_ id:String)->NSObject? {
        nodes(root).first{value($0,"accessibilityIdentifier") as? String==id}
    }
    static func frame(_ node:NSObject)->NSRect {(value(node,"accessibilityFrame") as? NSValue)?.rectValue ?? .zero}
    static func enabled(_ node:NSObject?)->Bool {guard let node else{return false};return value(node,"isAccessibilityEnabled") as? Bool ?? false}
    static func capture(_ view:NSView,_ name:String) {
        guard let path=ProcessInfo.processInfo.environment["CODEX_METER_UI_ARTIFACTS"] else{return}
        let dir=URL(fileURLWithPath:path);try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        view.layoutSubtreeIfNeeded()
        if let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
            view.cacheDisplay(in:view.bounds,to:rep)
            try? rep.representation(using:.png,properties:[:])?.write(to:dir.appendingPathComponent(name+".png"))
        }
    }
    static func press(_ node:NSObject?) {guard let node else{return};_ = (node as AnyObject).accessibilityPerformPress?()}
}
