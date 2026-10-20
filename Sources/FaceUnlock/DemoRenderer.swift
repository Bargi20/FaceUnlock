import AppKit
import SwiftUI

/// Renders the README demo: the real Face ID panel and rings, frame by frame,
/// over a mock desktop. Run with
/// `FaceUnlock --render-demo <unlock|failure> <output folder>`;
/// Tools/make-demo.sh turns the PNG frames into GIFs.
@MainActor
enum DemoRenderer {
    enum Scenario: String { case unlock, failure }

    static let fps = 50.0

    /// Handles `--render-demo` and returns true if it did.
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-demo"), args.count > i + 2,
              let scenario = Scenario(rawValue: args[i + 1]) else { return false }
        let folder = URL(fileURLWithPath: args[i + 2], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let timeline = DemoTimeline(scenario: scenario)
        let count = Int(timeline.duration * fps)
        for frame in 0..<count {
            let renderer = ImageRenderer(content: DemoScene(time: Double(frame) / fps, timeline: timeline))
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            let url = folder.appendingPathComponent(String(format: "frame%04d.png", frame))
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        print("rendered \(count) frames to \(folder.path)")
        return true
    }
}

/// When each step happens, in seconds from the start of the clip. Matches the
/// app: spring open, scan, fixed brake, then the panel closes 0.45 s after the
/// password is typed (or stays, red, on failure).
struct DemoTimeline {
    let scenario: DemoRenderer.Scenario
    let open = 0.5
    var settle: Double { open + 1.2 }
    var close: Double? { scenario == .unlock ? settle + 0.2 + 0.45 : nil }
    var duration: Double { scenario == .unlock ? close! + 0.9 : settle + 1.8 }
}

private struct DemoScene: View {
    let time: Double
    let timeline: DemoTimeline

    private let notch = CGSize(width: 186, height: 32)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.36),
                                    Color(red: 0.42, green: 0.2, blue: 0.42),
                                    Color(red: 0.9, green: 0.48, blue: 0.4)],
                           startPoint: .top, endPoint: .bottom)
            // Lock screen clock, like macOS.
            VStack(spacing: 0) {
                Text("Tuesday, October 20")
                    .font(.system(size: 15, weight: .semibold))
                Text("9:41")
                    .font(.system(size: 76, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.top, 250)
            .opacity(1 - unlockFade)

            // After unlocking: the desktop's menu bar.
            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.bold)
                Text("File")
                Text("Edit")
                Text("View")
                Spacer()
                Image(systemName: "wifi")
                Text("Tue 20 Oct  9:41")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: notch.height)
            .background(.black.opacity(0.25))
            .opacity(unlockFade)

            panel
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                .fill(.black)
                .frame(width: notch.width, height: notch.height)
        }
        .frame(width: 560, height: 400)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    /// 0 on the lock screen, 1 on the desktop.
    private var unlockFade: Double {
        guard let close = timeline.close else { return 0 }
        return smooth(min(1, max(0, (time - close) / 0.35)))
    }

    /// The real panel: black, dropping from the notch with the app's spring
    /// (response 0.5, damping 0.78), closing in 0.22 s.
    @ViewBuilder private var panel: some View {
        let shown = time >= timeline.open && (timeline.close.map { time < $0 + 0.22 } ?? true)
        if shown {
            let progress: Double = {
                if let close = timeline.close, time >= close {
                    return 1 - smooth(min(1, (time - close) / 0.22))
                }
                return spring(time - timeline.open)
            }()
            let scannerTime = time - timeline.open
            let settleAt = timeline.settle - timeline.open
            let state: FaceIDScanner.State = time < timeline.settle
                ? .scanning : (timeline.scenario == .unlock ? .success : .failure)

            VStack(spacing: 10) {
                Spacer(minLength: notch.height)
                FaceIDScannerFrame(t: scannerTime, settleAt: time < timeline.settle ? nil : settleAt,
                                   state: state)
                    .modifier(FaceIDShake(animatableData: shake))
                    .frame(height: 104)
                Text(label(state))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state == .failure ? Color(red: 1.0, green: 0.4, blue: 0.35) : .white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 16)
                Spacer(minLength: 12)
            }
            .frame(width: 200, height: 200 + notch.height * 0.5)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 46, bottomTrailingRadius: 46, style: .continuous)
                    .fill(.black)
            )
            .scaleEffect(0.25 + 0.75 * progress, anchor: .top)
            .opacity(min(1, max(0, progress)))
        }
    }

    private var shake: CGFloat {
        guard timeline.scenario == .failure, time > timeline.settle else { return 0 }
        return CGFloat(min(1, (time - timeline.settle) / 0.5))
    }

    private func label(_ state: FaceIDScanner.State) -> String {
        switch state {
        case .scanning: return "Face ID"
        case .success: return "Unlocked"
        case .failure: return "Face not recognized · Try again"
        }
    }

    /// Damped spring step response, as SwiftUI's .spring(response:dampingFraction:).
    private func spring(_ t: Double, response: Double = 0.5, damping: Double = 0.78) -> Double {
        guard t > 0 else { return 0 }
        let w = 2 * .pi / response
        let wd = w * sqrt(1 - damping * damping)
        return 1 - exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
    }

    private func smooth(_ p: Double) -> Double { p * p * (3 - 2 * p) }
}
