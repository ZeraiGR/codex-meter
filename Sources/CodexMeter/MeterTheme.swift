import SwiftUI
import AppKit

enum MeterTheme {
    static func adaptive(_ name:String,light:UInt32,dark:UInt32)->Color {
        Color(nsColor:NSColor(name:NSColor.Name(name)) { appearance in
            let value=appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark:light
            return NSColor(srgbRed:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255,alpha:1)
        })
    }
    static let background=adaptive("meter.background",light:0xFFFFFF,dark:0x1C1C1E)
    static let surface=adaptive("meter.surface",light:0xF2F4F6,dark:0x29292C)
    static let secondary=adaptive("meter.secondary",light:0x515C67,dark:0xB4B9C2)
    static let accent=adaptive("meter.accent",light:0x006B60,dark:0x62D9C6)
    static let warning=adaptive("meter.warning",light:0x925000,dark:0xFFD080)
    static let danger=adaptive("meter.danger",light:0xB42332,dark:0xFF929C)
}

/// Disable keyboard actions as well as mouse input. An opaque progress card stays
/// readable in either appearance; the overlay intercepts clicks outside the card.
struct ActionProgress:ViewModifier {
    @EnvironmentObject var store:MeterStore
    func body(content:Content)->some View {
        content
            .disabled(store.isPerformingAction)
            .allowsHitTesting(!store.isPerformingAction)
            .overlay {
                if let title=store.activity {
                    ZStack {
                        MeterTheme.background.opacity(0.78).contentShape(Rectangle()).onTapGesture {}
                        VStack(spacing:12) {
                            ProgressView().controlSize(.regular)
                            Text(title).font(.headline).multilineTextAlignment(.center)
                            Text("Дождитесь завершения операции.").font(.callout).foregroundStyle(MeterTheme.secondary)
                        }.padding(24).frame(maxWidth:360)
                            .background(MeterTheme.background,in:RoundedRectangle(cornerRadius:16))
                            .overlay(RoundedRectangle(cornerRadius:16).stroke(Color.primary.opacity(0.15)))
                            .accessibilityElement(children:.combine).accessibilityIdentifier("action-progress")
                    }
                }
            }
            .interactiveDismissDisabled(store.isPerformingAction)
    }
}

extension View {
    func actionProgress()->some View {modifier(ActionProgress())}
}
