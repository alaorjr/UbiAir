import SwiftUI

struct AirConditionerIllustration: View {
    let isOn: Bool
    let target: String
    let reduceMotion: Bool
    @State private var airflowPhase = false

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.78, 270)
            let unitHeight: CGFloat = 58
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [Color.primary.opacity(0.11), Color.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 1))
                    HStack {
                        Circle().fill(isOn ? Color.green.opacity(0.8) : Color.secondary.opacity(0.35)).frame(width: 4, height: 4)
                        Spacer()
                        Text(target == "—" ? "--" : target.replacingOccurrences(of: " °", with: "°"))
                            .font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.primary.opacity(0.72))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.primary.opacity(0.07), in: Capsule())
                    }
                    .padding(.horizontal, 11).padding(.top, 8)
                    VStack(spacing: 4) {
                        Spacer(minLength: 28)
                        Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
                        HStack(spacing: 3) {
                            ForEach(0..<25, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.28)).frame(width: 2, height: 7)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.055), in: UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                }
                .frame(width: width, height: unitHeight)
                .shadow(color: .black.opacity(0.07), radius: 7, y: 3)

                ZStack {
                    ForEach(0..<7, id: \.self) { index in
                        let x = CGFloat(index - 3) * width / 8
                        Path { path in
                            path.move(to: CGPoint(x: proxy.size.width / 2 + x * 0.5, y: 1))
                            path.addQuadCurve(to: CGPoint(x: proxy.size.width / 2 + x, y: 42), control: CGPoint(x: proxy.size.width / 2 + x * 1.25, y: 19))
                        }
                        .stroke(LinearGradient(colors: [.blue.opacity(isOn ? 0.24 : 0), .blue.opacity(0)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .offset(y: airflowPhase && isOn && !reduceMotion ? 4 : 0)
                    }
                }
                .frame(height: 43)
                .animation(isOn && !reduceMotion ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : nil, value: airflowPhase)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { if isOn && !reduceMotion { airflowPhase = true } }
            .onChange(of: isOn) { _, value in airflowPhase = value && !reduceMotion }
            .onChange(of: reduceMotion) { _, value in airflowPhase = isOn && !value }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOn ? "Ilustração do ar-condicionado ligado" : "Ilustração do ar-condicionado desligado")
    }
}
