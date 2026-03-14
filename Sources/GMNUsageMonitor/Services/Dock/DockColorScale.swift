import SwiftUI

enum DockColorScale {
    static func color(for percent: Double) -> Color {
        let stops: [(Double, SIMD3<Double>)] = [
            (0, SIMD3(0.20, 0.78, 0.35)),
            (50, SIMD3(0.95, 0.80, 0.20)),
            (75, SIMD3(0.96, 0.55, 0.18)),
            (100, SIMD3(0.88, 0.22, 0.20))
        ]

        let clamped = min(max(percent, 0), 100)
        for index in 0..<(stops.count - 1) {
            let lhs = stops[index]
            let rhs = stops[index + 1]
            guard clamped >= lhs.0, clamped <= rhs.0 else { continue }
            let progress = (clamped - lhs.0) / (rhs.0 - lhs.0)
            let vector = lhs.1 + (rhs.1 - lhs.1) * progress
            return Color(red: vector.x, green: vector.y, blue: vector.z)
        }

        let fallback = stops.last!.1
        return Color(red: fallback.x, green: fallback.y, blue: fallback.z)
    }
}
