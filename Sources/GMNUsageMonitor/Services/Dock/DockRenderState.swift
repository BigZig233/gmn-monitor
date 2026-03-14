import DockProgress
import Foundation
import SwiftUI

struct DockRenderState: Equatable, Sendable {
    var progress: Double?
    var displayPercent: Double?
    var alias: String?
    var color: Color
    var isAuthenticated: Bool
    var hasSelection: Bool
    var hasError: Bool

    static let empty = DockRenderState(
        progress: nil,
        displayPercent: nil,
        alias: nil,
        color: .clear,
        isAuthenticated: false,
        hasSelection: false,
        hasError: false
    )
}
