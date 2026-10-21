//
//  FaceIDVisuals.swift
//  NotchUnlock
//
//  Apple-style Face ID visuals: the animated Face ID glyph used in the notch,
//  and the circular enrollment ring with the live camera preview.
//

import QuartzCore
import SwiftUI

// MARK: - Face ID glyph

/// The Face ID face (corner brackets, eyes, nose, smile), animated per state:
/// breathes while scanning, morphs into a green check on success, shakes on failure.
struct FaceIDGlyph: View {
    enum State: Equatable { case idle, scanning, success, failure }

    var state: State
    var size: CGFloat = 24
    var color: Color = .white

    @SwiftUI.State private var breathe = false
    @SwiftUI.State private var shakes: CGFloat = 0

    private static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    private static let red = Color(red: 1.0, green: 0.27, blue: 0.23)

    var body: some View {
        let success = state == .success
        let line = max(1.4, size * 0.075)
        ZStack {
            // Face ID face
            ZStack {
                FaceIDCorners()
                    .stroke(state == .failure ? Self.red : color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .scaleEffect(state == .scanning && breathe ? 0.86 : 1)
                FaceIDFace()
                    .stroke(state == .failure ? Self.red : color, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                    .opacity(state == .scanning ? (breathe ? 0.55 : 1) : 1)
            }
            .opacity(success ? 0 : 1)
            .scaleEffect(success ? 0.6 : 1)
            .modifier(ShakeEffect(animatableData: shakes))

            // Success: circle + check drawing in
            ZStack {
                Circle()
                    .stroke(Self.green, lineWidth: line)
                Checkmark()
                    .trim(from: 0, to: success ? 1 : 0)
                    .stroke(Self.green, style: StrokeStyle(lineWidth: line * 1.15, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.27)
            }
            .opacity(success ? 1 : 0)
            .scaleEffect(success ? 1 : 1.25)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state)
        .animation(state == .scanning ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: breathe)
        .onAppear { breathe = state == .scanning }
        .onChange(of: state) { _, new in
            breathe = new == .scanning
            if new == .failure {
                withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            }
        }
    }
}

/// Four rounded corner brackets.
private struct FaceIDCorners: Shape {
    func path(in r: CGRect) -> Path {
        let l = r.width * 0.28 // bracket length
        let c = r.width * 0.16 // corner radius
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Eyes, nose and smile.
struct FaceIDFace: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width
        var p = Path()
        // eyes
        for x in [0.34, 0.66] {
            p.move(to: CGPoint(x: r.minX + w * x, y: r.minY + w * 0.34))
            p.addLine(to: CGPoint(x: r.minX + w * x, y: r.minY + w * 0.43))
        }
        // nose
        p.move(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + w * 0.34))
        p.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + w * 0.56))
        p.addLine(to: CGPoint(x: r.minX + w * 0.44, y: r.minY + w * 0.56))
        // smile
        p.move(to: CGPoint(x: r.minX + w * 0.34, y: r.minY + w * 0.67))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.66, y: r.minY + w * 0.67),
                       control: CGPoint(x: r.minX + w * 0.5, y: r.minY + w * 0.8))
        return p
    }
}

private struct Checkmark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY - r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.12))
        return p
    }
}

/// Horizontal "no" shake, like a wrong passcode.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 6), y: 0))
    }
}

// MARK: - Enrollment ring

/// Apple-style enrollment: live camera in a circle, ringed by tick marks that turn
/// green as each head position is captured.
struct FaceEnrollmentRing: View {
    let preview: CGImage?
    /// Completed steps (0...stepCount) and progress within the current step (0...1).
    let completedSteps: Int
    let stepProgress: Double
    let stepCount: Int
    var done = false
    var diameter: CGFloat = 190

    private let tickCount = 72
    private static let green = Color(red: 0.19, green: 0.82, blue: 0.35)

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(width: 2.2, height: lit(i) > 0 ? 16 : 11)
                    .offset(y: -(diameter / 2 + 16))
                    .rotationEffect(.degrees(Double(i) / Double(tickCount) * 360))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: lit(i))
            }

            Group {
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(x: -1, y: 1) // mirror, like a selfie camera
                } else {
                    Color(white: 0.1)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                if done {
                    Circle().fill(.black.opacity(0.55))
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.32, weight: .semibold))
                        .foregroundStyle(Self.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(width: diameter + 60, height: diameter + 60)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: done)
    }

    /// Each step owns an arc of the ring: completed arcs are full, the current one
    /// fills with the head-turn progress. Returns 0 (unlit), or 1 (lit).
    private func lit(_ tick: Int) -> Int {
        if done { return 1 }
        let perStep = Double(tickCount) / Double(stepCount)
        // Step order around the ring: start at the bottom and go clockwise.
        let rotated = (tick + tickCount / 2) % tickCount
        let step = Int(Double(rotated) / perStep)
        if step < completedSteps { return 1 }
        if step == completedSteps {
            let within = Double(rotated) - Double(step) * perStep
            return within < perStep * stepProgress ? 1 : 0
        }
        return 0
    }

    private func color(for tick: Int) -> Color {
        lit(tick) > 0 ? Self.green : Color.white.opacity(0.22)
    }
}

/// The whole Apple-like flow, shown as a sheet from the NotchUnlock settings.
struct FaceEnrollmentFlow: View {
    @ObservedObject var manager = NotchUnlockManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

    var body: some View {
        VStack(spacing: 18) {
            switch stage {
            case .intro:
                Spacer(minLength: 0)
                FaceIDGlyph(state: .scanning, size: 84, color: .primary)
                Text("Set Up NotchUnlock")
                    .font(.system(size: 22, weight: .bold))
                Text("Position your face in front of the camera and slowly move your head to complete the circle.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Spacer(minLength: 0)
                Button {
                    started = true
                    manager.startEnrollment()
                } label: {
                    Text("Get Started").frame(maxWidth: 220)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

            case .scanning:
                FaceEnrollmentRing(
                    preview: manager.enrollPreview,
                    completedSteps: manager.enrollStepIndex,
                    stepProgress: manager.enrollStepProgress,
                    stepCount: GuidedEnroller.stepCount
                )
                Text(instruction)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: instruction)
                Text(manager.enrollHint.isEmpty ? tr("Slowly move your head to complete the circle.") : manager.enrollHint)
                    .font(.system(size: 12))
                    .foregroundStyle(manager.enrollHint.isEmpty ? .secondary : .primary)
                    .animation(.smooth, value: manager.enrollHint)
                Button("Cancel") {
                    manager.cancelEnrollment()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            case .done:
                FaceEnrollmentRing(
                    preview: manager.enrollPreview,
                    completedSteps: GuidedEnroller.stepCount,
                    stepProgress: 1,
                    stepCount: GuidedEnroller.stepCount,
                    done: true
                )
                Text("NotchUnlock Is Set Up")
                    .font(.system(size: 20, weight: .bold))
                Text("You can now unlock your Mac by looking at the screen.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    dismiss()
                } label: {
                    Text("Done").frame(maxWidth: 220)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            case .failed(let message):
                FaceIDGlyph(state: .failure, size: 70, color: .primary)
                Text("Enrollment Failed")
                    .font(.system(size: 20, weight: .bold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { dismiss() }
                    Button("Try Again") { manager.startEnrollment() }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 400, height: 440)
        .animation(.smooth(duration: 0.3), value: stageKey)
    }

    private enum Stage: Equatable {
        case intro, scanning, done
        case failed(String)
    }

    private var stage: Stage {
        switch manager.enrollPhase {
        case .running: return .scanning
        case .done: return started ? .done : .intro
        case .failed(let message): return started ? .failed(message) : .intro
        case .idle: return .intro
        }
    }

    private var stageKey: String { "\(stage)" }

    private var instruction: String {
        if case .running(let title, _, _, _) = manager.enrollPhase { return title }
        return ""
    }
}

// MARK: - iPhone-style Face ID square

/// iPhone-style Face ID animation (Dynamic Island): two green rings spinning in
/// 3D around slowly turning axes, out of phase. On success they brake smoothly
/// (no speed jump) until flat, merging into one circle, and the face appears;
/// on failure they settle red and shake.
struct FaceIDScanner: View {
    enum State: Equatable { case scanning, success, failure }

    var state: State
    var size: CGFloat = 96
    @SwiftUI.State private var shakes: CGFloat = 0
    @SwiftUI.State private var start = Date()
    @SwiftUI.State private var settledAt: Date?

    static let green = Color(red: 0.44, green: 0.85, blue: 0.48)
    static let red = Color(red: 1.0, green: 0.3, blue: 0.27)

    /// Spin speed while scanning (deg/s), azimuth drift (deg/s), brake length (s).
    private static let spinSpeed = 720.0
    private static let azSpeed = 120.0
    static let brakeTime = 0.45

    var body: some View {
        // No minimumInterval: run at the display's native rate (120 Hz on ProMotion).
        TimelineView(.animation) { timeline in
            FaceIDScannerFrame(
                t: timeline.date.timeIntervalSince(start),
                settleAt: settledAt.map { max(0, $0.timeIntervalSince(start)) },
                state: state,
                size: size
            )
        }
        .modifier(FaceIDShake(animatableData: shakes))
        .onAppear {
            start = Date()
            settledAt = state == .scanning ? nil : Date()
        }
        .onChange(of: state) { _, new in
            settledAt = new == .scanning ? nil : Date()
            if new == .failure { withAnimation(.linear(duration: 0.5)) { shakes += 1 } }
        }
    }

    struct RingPose {
        var az: Double, spin: Double, wobble: Double
        /// 0 while scanning, 1 once flat.
        var braking: Double
        var brakeTime: Double
    }

    /// Ring orientation at time `t`. While scanning it spins at constant speed;
    /// from `settleAt` it brakes for exactly `brakeTime`, starting at the spin
    /// speed (no jump) and landing flat on the next multiple of 180° that is
    /// 180–360° ahead. A fixed brake keeps the success face visible before the
    /// panel closes.
    static func pose(t: Double, settleAt: Double?, phase: Double, dir: Double) -> RingPose {
        func wob(_ t: Double) -> Double { sin(t * 2 * .pi * 0.64 + phase / 60) * 25 }
        guard let ts = settleAt, t > ts else {
            return RingPose(az: phase * 0.6 + dir * azSpeed * t,
                            spin: phase + dir * spinSpeed * t,
                            wobble: wob(t), braking: 0, brakeTime: brakeTime)
        }
        let spin0 = phase + dir * spinSpeed * ts
        let target = dir > 0
            ? (floor((spin0 + 180) / 180) * 180 + 180)
            : (ceil((spin0 - 180) / 180) * 180 - 180)
        let travel = abs(target - spin0)
        let s = min(1, (t - ts) / brakeTime)
        // Cubic with x(0)=0, x'(0)=c (the spin speed), x(1)=1, x'(1)=0; monotonic
        // for c in (0, 3], and c = 720*0.45/travel stays within 0.9...1.8.
        let c = spinSpeed * brakeTime / travel
        let x = (c - 2) * s * s * s + (3 - 2 * c) * s * s + c * s
        return RingPose(az: phase * 0.6 + dir * azSpeed * (ts + brakeTime * (s - s * s / 2)),
                        spin: spin0 + (target - spin0) * x,
                        wobble: wob(t) * (1 - easeInOut(s)),
                        braking: x, brakeTime: brakeTime)
    }

    static func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    static func easeInOut(_ p: Double) -> Double { p * p * (3 - 2 * p) }
}

/// One frame of the Face ID rings at time `t` (seconds since they appeared),
/// settling from `settleAt` when the scan ends. Pure function of time, so it can
/// be driven by a TimelineView or rendered frame by frame for the README demo.
struct FaceIDScannerFrame: View {
    let t: Double
    let settleAt: Double?
    let state: FaceIDScanner.State
    var size: CGFloat = 96

    var body: some View {
        let tint = state == .failure ? FaceIDScanner.red : FaceIDScanner.green
        let r1 = FaceIDScanner.pose(t: t, settleAt: settleAt, phase: 0, dir: 1)
        let r2 = FaceIDScanner.pose(t: t, settleAt: settleAt, phase: 90, dir: -1)
        let appear = FaceIDScanner.easeOut(min(1, t / 0.3))
        let braking = min(r1.braking, r2.braking)
        let faceStart = settleAt.map { $0 + FaceIDScanner.brakeTime - 0.08 }
        let faceIn = state == .success && faceStart != nil && t > faceStart!
            ? FaceIDScanner.easeOut(min(1, (t - faceStart!) / 0.26)) : 0

        ZStack {
            ZStack {
                ring(r1, tint: tint)
                ring(r2, tint: tint)
            }
            // Motion blur that clears as the rings slow down.
            .blur(radius: size * 0.019 * CGFloat(1 - braking))
            FaceIDFace()
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.86, height: size * 0.86)
                .scaleEffect(CGFloat(0.92 + 0.08 * faceIn))
                .opacity(faceIn)
        }
        .frame(width: size, height: size)
        .opacity(appear)
    }

    private func ring(_ pose: FaceIDScanner.RingPose, tint: Color) -> some View {
        Circle()
            .inset(by: size * 0.025)
            .stroke(tint, lineWidth: size * 0.05)
            .frame(width: size, height: size)
            // CSS reference: perspective 380px on an 84px ring.
            .modifier(RingTumble(pose: pose, perspective: size * 380 / 84))
    }

}

/// One 3D transform per ring, like the CSS
/// `rotateZ(az) rotateX(spin) rotateY(wobble) rotateZ(-az)` with perspective.
private struct RingTumble: GeometryEffect {
    var pose: FaceIDScanner.RingPose
    var perspective: CGFloat
    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let rad = { (d: Double) in CGFloat(d * .pi / 180) }
        // CATransform3DConcat(a, b) applies a first, then b.
        var m = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(rad(-pose.az), 0, 0, 1))
        m = CATransform3DConcat(m, CATransform3DMakeRotation(rad(pose.wobble), 0, 1, 0))
        m = CATransform3DConcat(m, CATransform3DMakeRotation(rad(pose.spin), 1, 0, 0))
        m = CATransform3DConcat(m, CATransform3DMakeRotation(rad(pose.az), 0, 0, 1))
        var persp = CATransform3DIdentity
        persp.m34 = -1 / perspective
        m = CATransform3DConcat(m, persp)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0))
        return ProjectionTransform(m)
    }
}

private struct CheckmarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct FaceIDShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// The square that drops out of the notch when Face ID is needed (lock screen).
struct FaceIDSquare: View {
    @ObservedObject var manager = NotchUnlockManager.shared
    /// Height of the hardware notch, so the content sits below it.
    let notchHeight: CGFloat

    /// Expanded: wide and short, like an expanded Dynamic Island.
    static let width: CGFloat = 340
    /// Height below the notch.
    static let bodyHeight: CGFloat = 128
    static let cornerRadius: CGFloat = 38
    static let scannerSize: CGFloat = 84
    /// Compact preview: as wide as the panel, with a lip below the notch.
    static let compactLip: CGFloat = 8
    static let compactRadius: CGFloat = 14

    private var isCompact: Bool { manager.phase == .prompted }
    @State private var hovering = false

    /// How much the preview's lip grows under the pointer, to show it can be clicked.
    static let hoverBump: CGFloat = 6

    /// Height below the notch: the lip (a bit longer under the pointer) or the full body.
    private var bodyHeight: CGFloat {
        isCompact ? Self.compactLip + (hovering ? Self.hoverBump : 0) : Self.bodyHeight
    }

    var body: some View {
        let radius = isCompact ? Self.compactRadius : Self.cornerRadius
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        // Same width in both states: clicking only makes the panel drop down.
        ZStack(alignment: .top) {
            if isCompact {
                FaceIDPreview(notchHeight: notchHeight)
                    .transition(.opacity)
            } else {
                expanded
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: Self.width, height: notchHeight + bodyHeight, alignment: .top)
        .background(shape.fill(.black))
        .clipShape(shape)
        // Springy bump on hover; a smooth drop when it opens.
        .animation(isCompact ? .spring(response: 0.28, dampingFraction: 0.45)
                             : .spring(response: 0.45, dampingFraction: 0.82),
                   value: bodyHeight)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            (inside && isCompact ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        .onTapGesture { _ = manager.retryIfPossible() }
    }

    private var expanded: some View {
        VStack(spacing: 8) {
            Spacer(minLength: notchHeight)
            content
                .frame(height: Self.scannerSize)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .contentTransition(.opacity)
                .animation(.smooth, value: label)
            Spacer(minLength: 12)
        }
        .frame(width: Self.width, height: notchHeight + Self.bodyHeight)
    }

    @ViewBuilder private var content: some View {
        switch manager.phase {
        case .scanning, .matched, .failed, .prompted:
            // One view for all three, so the rings settle smoothly instead of restarting.
            FaceIDScanner(state: scannerState, size: Self.scannerSize)
        case .hidden:
            EmptyView()
        }
    }

    private var scannerState: FaceIDScanner.State {
        switch manager.phase {
        case .matched: return .success
        case .failed: return .failure
        default: return .scanning
        }
    }

    private var label: String {
        switch manager.phase {
        case .prompted: return ""
        case .scanning: return "Face ID"
        case .matched: return tr("Unlocked")
        case .failed(let reason): return reason.isEmpty ? tr("Try Again") : String(format: tr("%@ · Try again"), reason)
        case .hidden: return ""
        }
    }

    private var labelColor: Color {
        if case .failed = manager.phase { return Color(red: 1.0, green: 0.4, blue: 0.35) }
        return .white.opacity(0.85)
    }
}

/// The compact preview shown while locked: a small breathing Face ID glyph in
/// the left wing. Clicking it opens the panel and starts the scan.
struct FaceIDPreview: View {
    let notchHeight: CGFloat

    var body: some View {
        HStack {
            FaceIDGlyph(state: .scanning, size: 16)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: notchHeight)
    }
}
