import Foundation
import SwiftUI

@MainActor
final class DockStatusController {
    private let adapter: DockProgressAdapter
    private(set) var lastSuccessfulState: DockRenderState = .empty

    init(adapter: DockProgressAdapter) {
        self.adapter = adapter
    }

    func update(isAuthenticated: Bool, selectedSubscription: Subscription?, selectedDailyUsagePercent: Double?, alias: String?, hasError: Bool) {
        let clampedPercent = selectedDailyUsagePercent.map { min(max($0, 0), 100) }
        let state = DockRenderState(
            progress: clampedPercent.map { min(max($0 / 100, 0.001), 0.999) },
            displayPercent: clampedPercent,
            alias: alias?.isEmpty == false ? alias : nil,
            color: DockColorScale.color(for: clampedPercent ?? 0),
            isAuthenticated: isAuthenticated,
            hasSelection: selectedSubscription != nil,
            hasError: hasError
        )

        if !hasError {
            lastSuccessfulState = state
        }

        adapter.apply(hasError ? lastSuccessfulState : state)
    }

    func reset() {
        lastSuccessfulState = .empty
        adapter.reset()
    }
}
