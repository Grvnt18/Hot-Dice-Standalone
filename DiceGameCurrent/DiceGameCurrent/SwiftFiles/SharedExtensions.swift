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
