import SwiftUI

/// SPEC-026 — Badge "numéro de stage" rendu en arrière-plan de chaque cellule
/// du navrail. Position, taille et opacité paramétrables via le TOML
/// `[fx.rail].stage_numbers_*` (lus dans Config.swift, propagés au boot/reload
/// dans StageNumbersBadgeState.shared).
public struct StageNumberBadge: View {
    public let number: String
    public let colorHex: String

    @ObservedObject private var state = StageNumbersBadgeState.shared

    public init(number: String, colorHex: String = "#FFFFFF") {
        self.number = number
        self.colorHex = colorHex
    }

    public var body: some View {
        Text(number)
            .font(.system(size: CGFloat(state.fontSize), weight: .black, design: .rounded))
            .foregroundColor(Color(hex: colorHex).opacity(state.opacity))
            .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
            .offset(x: CGFloat(state.offsetX), y: CGFloat(state.offsetY))
            .allowsHitTesting(false)
            .fixedSize()
    }
}
