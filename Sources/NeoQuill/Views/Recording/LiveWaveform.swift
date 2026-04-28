import SwiftUI
import Combine

// 80-Bar Waveform mit Sinus-Motion. Default 80h, hairline-Trennung oben/unten.

struct LiveWaveform: View {

    var barCount: Int = 80
    var height: CGFloat = 80

    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var bars: [Double] {
        (0..<barCount).map { i in
            let a = sin(Double(i + tick) * 0.32) * 0.5
                + cos(Double(i + tick) * 0.5 * 0.18) * 0.4
            return 0.18 + abs(a) * 0.7
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Neon.textSecondary)
                    .opacity(0.4 + bars[i] * 0.6)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, height * bars[i]))
            }
        }
        .frame(height: height)
        .padding(.horizontal, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
        .onReceive(timer) { _ in tick &+= 1 }
    }
}

// MiniBars: kompakte 14-Bar-Variante für FloatingPill.
struct MiniBars: View {

    var barCount: Int = 14
    var height: CGFloat = 16

    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 0.10, on: .main, in: .common).autoconnect()

    private func value(_ i: Int) -> Double {
        0.25 + abs(sin(Double(i + tick) * 0.6) * 0.7)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Neon.textSecondary)
                    .frame(width: 2, height: max(2, height * value(i)))
            }
        }
        .frame(height: height)
        .padding(.horizontal, 4)
        .onReceive(timer) { _ in tick &+= 1 }
    }
}
