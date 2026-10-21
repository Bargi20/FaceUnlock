import AppKit
import SwiftUI

/// Renders the README demo: the real Face ID panel and rings, frame by frame,
/// over a mock desktop. Run with
/// `NotchUnlock --render-demo <unlock|failure> <output folder>`;
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
/// app: the compact preview appears at the notch, the pointer clicks it, the
/// panel opens and scans, the rings brake, then the panel closes 0.45 s after
/// the password is typed (or, on failure, folds back into the preview).
struct DemoTimeline {
    let scenario: DemoRenderer.Scenario
    let preview = 0.3
    let pointerStart = 0.8
    let open = 1.6
    var settle: Double { open + 1.2 }
    var close: Double? { scenario == .unlock ? settle + 0.2 + 0.45 : nil }
    var collapse: Double? { scenario == .failure ? settle + 2.5 : nil }
    var duration: Double { scenario == .unlock ? close! + 0.9 : collapse! + 0.9 }
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
            .padding(.top, 215)
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
            pointer
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

    /// The real panel: the compact preview pops out of the notch, grows into
    /// the full panel on click (spring 0.45 / 0.8), and closes in 0.22 s.
    @ViewBuilder private var panel: some View {
        let shown = time >= timeline.preview && (timeline.close.map { time < $0 + 0.22 } ?? true)
        if shown {
            // Appearing from hidden (and closing after unlock).
            let appear: Double = {
                if let close = timeline.close, time >= close {
                    return 1 - smooth(min(1, (time - close) / 0.22))
                }
                return spring(time - timeline.preview)
            }()
            // 0 = compact preview, 1 = full panel.
            let expand: Double = {
                if let collapse = timeline.collapse, time >= collapse {
                    return 1 - spring(time - collapse, response: 0.28, damping: 0.45)
                }
                return spring(time - timeline.open, response: 0.45, damping: 0.82)
            }()
            let lip = FaceIDSquare.compactLip + FaceIDSquare.hoverBump * hoverBump
            let height = notch.height + lip + (FaceIDSquare.bodyHeight - lip) * expand
            let radius = FaceIDSquare.compactRadius + (FaceIDSquare.cornerRadius - FaceIDSquare.compactRadius) * expand
            let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

            ZStack(alignment: .top) {
                FaceIDPreview(notchHeight: notch.height)
                    .opacity(1 - min(1, expand * 2))
                // Slides down from under the notch, like .move(edge: .top).
                expanded
                    .offset(y: -(1 - expand) * (notch.height + FaceIDSquare.bodyHeight))
                    .opacity(min(1, max(0, expand)))
            }
            .frame(width: FaceIDSquare.width, height: height, alignment: .top)
            .background(shape.fill(.black))
            .clipShape(shape)
            .scaleEffect(0.25 + 0.75 * appear, anchor: .top)
            .opacity(min(1, max(0, appear)))
        }
    }

    /// 0...1 (with overshoot): the pointer arrives at `open - 0.2`.
    private var hoverBump: Double {
        spring(time - (timeline.open - 0.25), response: 0.28, damping: 0.45)
    }

    private var expanded: some View {
        let scanning = time < timeline.settle
        let state: FaceIDScanner.State = scanning
            ? .scanning : (timeline.scenario == .unlock ? .success : .failure)
        return VStack(spacing: 8) {
            Spacer(minLength: notch.height)
            FaceIDScannerFrame(t: max(0, time - timeline.open),
                               settleAt: scanning ? nil : timeline.settle - timeline.open,
                               state: state, size: FaceIDSquare.scannerSize)
                .modifier(FaceIDShake(animatableData: shake))
                .frame(height: FaceIDSquare.scannerSize)
            Text(label(state))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(state == .failure ? Color(red: 1.0, green: 0.4, blue: 0.35) : .white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
            Spacer(minLength: 12)
        }
        .frame(width: FaceIDSquare.width, height: notch.height + FaceIDSquare.bodyHeight)
    }

    /// A mouse pointer gliding from the lower right onto the preview, then
    /// clicking it (a quick press at `open`).
    private var pointer: some View {
        let p = smooth(min(1, max(0, (time - timeline.pointerStart) / (timeline.open - 0.2 - timeline.pointerStart))))
        let start = CGPoint(x: 470, y: 330), end = CGPoint(x: 300, y: 30)
        return PointerShape()
            .fill(.white)
            .overlay(PointerShape().stroke(.black, lineWidth: 1.2))
            .frame(width: 14, height: 21)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .scaleEffect(1 - 0.18 * sin(.pi * min(1, max(0, (time - timeline.open + 0.12) / 0.24))), anchor: .topLeading)
            .position(x: start.x + (end.x - start.x) * p, y: start.y + (end.y - start.y) * p)
            .opacity(min(1, max(0, (time - timeline.pointerStart + 0.3) / 0.3)))
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

/// Classic arrow pointer.
private struct PointerShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.78))
        p.addLine(to: CGPoint(x: r.minX + w * 0.3, y: r.minY + h * 0.58))
        p.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h))
        p.addLine(to: CGPoint(x: r.minX + w * 0.68, y: r.minY + h * 0.92))
        p.addLine(to: CGPoint(x: r.minX + w * 0.48, y: r.minY + h * 0.52))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.52))
        p.closeSubpath()
        return p
    }
}
