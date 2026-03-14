import DockProgress
import Foundation
import SwiftUI

@MainActor
final class DockProgressAdapter {
    enum Mode {
        case customView
        case customCanvas
        case circle
    }

    private(set) var mode: Mode = .customView
    private var state: DockRenderState = .empty

    func apply(_ state: DockRenderState) {
        self.state = state

        guard let progress = state.progress, progress > 0, progress < 1, state.hasSelection else {
            reset()
            return
        }

        switch mode {
        case .customView:
            DockProgress.style = .customView { [state] progress in
                DockOverlayView(
                    progress: progress,
                    displayPercent: state.displayPercent,
                    alias: state.alias,
                    color: state.color,
                    hasError: state.hasError
                )
            }
        case .customCanvas:
            DockProgress.style = .customCanvas { [state] context, size, progress in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 18)
                let path = Path(ellipseIn: rect)
                context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 10)
                context.stroke(path.trimmedPath(from: 0, to: progress), with: .color(state.color), style: .init(lineWidth: 10, lineCap: .round))
            }
        case .circle:
            DockProgress.style = .circle(radius: 46, color: state.color)
        }

        DockProgress.progress = progress
    }

    func reset() {
        DockProgress.resetProgress()
    }

    func useFallbackMode() {
        mode = mode == .customView ? .customCanvas : .circle
        apply(state)
    }
}
