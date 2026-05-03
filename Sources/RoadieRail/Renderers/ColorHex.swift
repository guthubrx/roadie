import SwiftUI

// SPEC-019 — Helper Color(hex:) partagé entre renderers.
// Extrait de WindowStack.swift (SPEC-018 polish).
// Parsing hex "#RRGGBB" ou "#RRGGBBAA". Fallback gris neutre si malformé.
// Tolérant : accepte avec ou sans #, lowercase ou uppercase.

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16)
        else {
            self = Color(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >>  8) & 0xFF) / 255.0
            b = Double( value        & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >>  8) & 0xFF) / 255.0
            a = Double( value        & 0xFF) / 255.0
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
