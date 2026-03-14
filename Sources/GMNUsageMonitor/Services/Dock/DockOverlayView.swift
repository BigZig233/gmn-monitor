import SwiftUI

struct DockOverlayView: View {
    let progress: Double
    let displayPercent: Double?
    let alias: String?
    let color: Color
    let hasError: Bool

    private let ringSize: CGFloat = 84
    private let ringLineWidth: CGFloat = 11

    private var percentText: String {
        guard let displayPercent else { return "--%" }
        return displayPercent.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.985, blue: 0.99),
                            Color(red: 0.9, green: 0.92, blue: 0.95),
                            Color(red: 0.78, green: 0.81, blue: 0.87)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.35),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 4,
                                endRadius: 120
                            )
                        )
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.88),
                                    Color.white.opacity(0.2),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 54)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1.2)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        .blur(radius: 1)
                        .offset(y: 1)
                        .mask(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.clear, Color.black],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                .padding(8)

            Circle()
                .stroke(Color.black.opacity(0.14), lineWidth: ringLineWidth)
                .frame(width: ringSize, height: ringSize)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringSize, height: ringSize)

            Text(percentText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .shadow(color: .white.opacity(0.75), radius: 1)

            if let alias, !alias.isEmpty {
                Text(alias)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 12)
                    .shadow(color: .white.opacity(0.65), radius: 1)
                    .offset(y: 34)
            }

            if hasError {
                Circle()
                    .fill(Color.red)
                    .frame(width: 14, height: 14)
                    .offset(x: 34, y: 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .drawingGroup()
    }
}
