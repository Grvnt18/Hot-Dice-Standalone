import UIKit
import SceneKit
import SwiftUI
import simd

// Consolidated during a full-codebase review — UIColor(hex:) was
// independently defined, identically, in both DieMaterialFactory.swift
// and DieFaceLabels.swift; SCNVector3.simd was independently defined,
// identically, in both DiceRollController.swift and DieFaceLabels.swift.
// One shared copy of each here, used everywhere.

extension UIColor {
    convenience init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension SCNVector3 {
    var simd: simd_float3 {
        simd_float3(Float(x), Float(y), Float(z))
    }
}

extension UIColor {
    /// Multiplies brightness, working in HSB so hue and saturation are
    /// preserved — blending toward black in RGB would desaturate as it
    /// darkens and leave the colour looking muddy rather than shaded.
    func darkened(by fraction: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: b * (1 - fraction), alpha: a)
    }

    /// The counterpart to `darkened`, raising brightness toward full.
    ///
    /// Also in HSB, and for the same reason: blending toward white in RGB
    /// washes the hue out, so a lit cap would read as a grey disc rather
    /// than as a brighter version of the post it sits on.
    ///
    /// A fully-bright colour has no headroom left, so saturation gives way
    /// instead — which is what a lit surface does anyway.
    func lightened(by fraction: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        let headroom = 1 - b
        let raised = b + headroom * fraction
        let spent = max(0, fraction - headroom)
        return UIColor(hue: h,
                       saturation: s * (1 - spent),
                       brightness: min(1, raised),
                       alpha: a)
    }

    /// Standard (ITU-R BT.601) relative luminance, used to decide whether
    /// light or dark text/UI elements read better against this color.
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

// Was independently, privately defined in DiceGameShell.swift for the
// score bar's per-die cell colors — moved here (and made non-private) so
// AppTheme and SettingsView can share the exact same conversion instead of
// a second copy of the same eight lines.
extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}


// ---------------------------------------------------------------------
// One spelling of `onChange` for two toolchains — here rather than in a
// file of its own, for the reason given at the bottom of
// DiceSceneEnvironment.swift: neither project picks up a new file by
// itself, and a missing one fails as "no member 'onValueChange'" at
// twelve call sites.
//
// This file's whole job is shared extensions, so it is where a shared
// extension belongs anyway.
// ---------------------------------------------------------------------

// One spelling of `onChange` for two toolchains.
//
// This project builds in two places that disagree about which `onChange`
// exists. The iPad runs Swift Playgrounds against a current SDK, where
// `onChange(of:perform:)` is deprecated. The Mac is Monterey, so Xcode
// 14.2 and the iOS 16.2 SDK, where the replacement does not exist at
// all. Writing either one directly is wrong on one machine:
//
//   one parameter  ->  twelve deprecation warnings on the iPad
//   two parameters ->  twelve ERRORS on the Mac
//
// Twelve warnings is not a build failure, but it is twelve lines of
// yellow to scroll past every time the question is "is there a red one
// in here". That is a real cost on the machine the project is supposed
// to iterate on, so it is worth removing rather than tolerating.
//
// `if #available(iOS 17, *)` CANNOT do this, which is worth stating
// because it is the obvious reach. Availability is a runtime test: both
// branches must still type-check, so the two-parameter call has to
// exist in the SDK being compiled against. On Xcode 14.2 it does not,
// and the file fails to build.
//
// `#if swift(...)` is a compile-time test, and the branch not taken is
// never type-checked at all — so the Mac never sees the call it has no
// SDK for.
//
// THE JOIN IS APPROXIMATE, AND DELIBERATELY SO. `#if swift(>=5.9)` asks
// about the COMPILER; the API needs the iOS 17 SDK. Those are separate
// things. They move together on the two machines this project has —
// Xcode 14.2 is Swift 5.7 with the iOS 16 SDK, and any Playgrounds new
// enough to be Swift 5.9 carries iOS 17 or later — so the test is
// reliable here. A Swift 5.9 compiler pointed at an iOS 16 SDK would
// break it. That combination does not exist in this project, and if it
// ever does, this is the one place to fix.
//
// The one-parameter closure receives the NEW value, which is exactly
// what the second parameter of the two-parameter form is. Nothing in
// the tree reads the old value, so this is a rename rather than a
// rewrite, and both branches call `action` with the same thing.
extension View {

    /// Runs `action` with the new value whenever `value` changes.
    func onValueChange<V: Equatable>(
        of value: V,
        perform action: @escaping (V) -> Void
    ) -> some View {
        #if swift(>=5.9)
        return self.onChange(of: value) { _, newValue in action(newValue) }
        #else
        return self.onChange(of: value) { newValue in action(newValue) }
        #endif
    }
}
