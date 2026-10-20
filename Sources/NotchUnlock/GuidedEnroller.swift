import CoreMedia
import CoreVideo
import Foundation

/// Step-by-step guided enrollment, Face ID style.
///
/// Five explicit poses, each with a prompt and an arrow, so it is always clear
/// which way to move. Sign-agnostic: the first left/right and up/down step
/// accepts whichever direction the head actually moved, then the opposite step
/// requires the other direction. That way a wrong assumption about Vision's
/// yaw/pitch sign cannot stall enrollment.
public final class GuidedEnroller: CameraCaptureDelegate {
    public enum EnrollError: Error {
        case noFaceDetected
        case cancelled
        case notEnoughAngles
    }

    public enum Step: Int, CaseIterable {
        case center
        case left
        case right
        case tiltLeft
        case tiltRight

        public var title: String {
            switch self {
            case .center: return L10n.t("step.center")
            case .left: return L10n.t("step.left")
            case .right: return L10n.t("step.right")
            case .tiltLeft: return L10n.t("step.tiltLeft")
            case .tiltRight: return L10n.t("step.tiltRight")
            }
        }

        public var symbol: String {
            switch self {
            case .center: return "face.smiling"
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .tiltLeft: return "arrow.counterclockwise"
            case .tiltRight: return "arrow.clockwise"
            }
        }
    }

    public struct Progress {
        public var stepIndex: Int
        public var stepCount: Int
        /// 0…1 how close the head is to satisfying the current step.
        public var stepProgress: Float
        public var step: Step
        public var samples: Int
    }

    public static let stepCount = Step.allCases.count
    public static let timeout: TimeInterval = 40
    public static let minimumSamples = 3

    private static let yawThreshold: Float = 0.16
    private static let rollThreshold: Float = 0.13
    private static let centerTolerance: Float = 0.11
    private static let centerRollTolerance: Float = 0.18
    private static let holdFramesRequired = 2

    public var onProgress: ((Progress) -> Void)?
    /// Camera frames for the live preview (main thread).
    public var onFrame: ((CVPixelBuffer) -> Void)?
    /// What's stopping the current step, for the on-screen hint (main thread).
    public var onHint: ((String) -> Void)?
    private var lastDiagnostic = Date.distantPast

    /// Enrollment diagnostics: ~/Library/Application Support/NotchUnlock/faceunlock.log
    static func diagnostic(_ message: String) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchUnlock", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("faceunlock.log")
        let line = "\(Date.now.formatted(date: .omitted, time: .standard)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// At most one diagnostic line per second.
    private func trace(_ message: @autoclosure () -> String) {
        guard Date().timeIntervalSince(lastDiagnostic) >= 1 else { return }
        lastDiagnostic = Date()
        Self.diagnostic(message())
    }
    public var completion: ((Result<[FaceEmbedding], Error>) -> Void)?

    private let capture: CameraCapture
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder

    private var stepIndex = 0
    private var embeddings: [FaceEmbedding] = []
    private var holdFrames = 0
    private var yawSign: Float?
    private var rollSign: Float?
    private var frameCounter = 0
    private var startedAt = Date()
    private var finished = false

    public init(embedder: FaceEmbedder = EmbedderFactory.make(), capture: CameraCapture = .shared) {
        self.embedder = embedder
        self.capture = capture
    }

    public func start() {
        reset()
        capture.addDelegate(self)
        do {
            try capture.acquire()
            Self.diagnostic("enroll start: camera acquired, embedder=\(type(of: embedder))")
        } catch {
            Self.diagnostic("enroll start: camera FAILED \(error)")
            finish(.failure(error))
        }
    }

    public func cancel() {
        guard !finished else { return }
        finish(.failure(EnrollError.cancelled))
    }

    private func reset() {
        stepIndex = 0
        embeddings = []
        holdFrames = 0
        yawSign = nil
        rollSign = nil
        frameCounter = 0
        finished = false
        startedAt = Date()
        publish(progress: 0, step: .center)
    }

    public func cameraCapture(_ capture: CameraCapture, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime) {
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(pixelBuffer)
            self?.process(pixelBuffer)
        }
    }

    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard !finished else { return }
        guard stepIndex < Step.allCases.count else { return }
        frameCounter += 1
        guard frameCounter % 2 == 0 else { return }

        let faces: [DetectedFace]
        do {
            faces = try detector.detect(in: pixelBuffer)
        } catch {
            trace("detect error: \(error)")
            faces = []
        }
        let biggest = faces.max(by: { $0.area < $1.area })
        guard let face = biggest, face.area >= 0.02 else {
            trace("step=\(currentStep) faces=\(faces.count) area=\(biggest.map { String(format: "%.3f", $0.area) } ?? "-") size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
            onHint?(faces.isEmpty ? tr("No face detected") : tr("Move closer to the camera"))
            holdFrames = 0
            publish(progress: 0, step: currentStep)
            checkTimeout()
            return
        }

        let step = currentStep
        let (satisfied, progress) = evaluate(step: step, face: face)
        publish(progress: progress, step: step)
        trace(String(format: "step=%@ area=%.3f yaw=%.3f roll=%.3f pitch=%.3f ok=%@ samples=%d",
                     "\(step)", face.area, face.yaw, face.roll, face.pitch, satisfied ? "yes" : "no", embeddings.count))
        onHint?(satisfied ? tr("Perfect, hold still…") : (step == .center ? tr("Look straight at the screen") : ""))

        guard satisfied else {
            holdFrames = 0
            checkTimeout()
            return
        }

        holdFrames += 1
        guard holdFrames >= Self.holdFramesRequired else {
            checkTimeout()
            return
        }

        let embedding: FaceEmbedding
        do {
            embedding = try embedder.embed(FaceInput(pixelBuffer: pixelBuffer, face: face))
        } catch {
            Self.diagnostic("embed FAILED at step=\(step): \(error)")
            onHint?(tr("Can't read your face, try again with more light"))
            checkTimeout()
            return
        }
        Self.diagnostic("captured step=\(step) (\(embeddings.count + 1) samples)")

        embeddings.append(embedding)
        learnSigns(for: step, face: face)
        holdFrames = 0
        stepIndex += 1

        if stepIndex >= Step.allCases.count {
            finish(.success(embeddings))
        } else {
            publish(progress: 0, step: currentStep)
            checkTimeout()
        }
    }

    private var currentStep: Step {
        Step.allCases[min(stepIndex, Step.allCases.count - 1)]
    }

    private func learnSigns(for step: Step, face: DetectedFace) {
        switch step {
        case .left, .right:
            if yawSign == nil, abs(face.yaw) >= Self.yawThreshold {
                yawSign = face.yaw >= 0 ? 1 : -1
            }
        case .tiltLeft, .tiltRight:
            if rollSign == nil, abs(face.roll) >= Self.rollThreshold {
                rollSign = face.roll >= 0 ? 1 : -1
            }
        case .center:
            break
        }
    }

    private func evaluate(step: Step, face: DetectedFace) -> (Bool, Float) {
        switch step {
        case .center:
            let magnitude = max(abs(face.yaw), abs(face.roll))
            let progress = max(0, 1 - magnitude / Self.centerTolerance)
            let ok = abs(face.yaw) <= Self.centerTolerance && abs(face.roll) <= Self.centerRollTolerance
            return (ok, progress)

        case .left, .right:
            let magnitude = abs(face.yaw)
            let progress = min(magnitude / Self.yawThreshold, 1)
            guard magnitude >= Self.yawThreshold else { return (false, progress) }
            // The first of the pair accepts either direction and records it.
            guard let sign = yawSign else { return (true, 1) }
            let wanted: Float = step == .left ? sign : -sign
            return (face.yaw * wanted > 0, progress)

        case .tiltLeft, .tiltRight:
            let magnitude = abs(face.roll)
            let progress = min(magnitude / Self.rollThreshold, 1)
            guard magnitude >= Self.rollThreshold else { return (false, progress) }
            guard let sign = rollSign else { return (true, 1) }
            let wanted: Float = step == .tiltLeft ? sign : -sign
            return (face.roll * wanted > 0, progress)
        }
    }

    private func checkTimeout() {
        guard Date().timeIntervalSince(startedAt) > Self.timeout else { return }
        if embeddings.count >= Self.minimumSamples {
            finish(.success(embeddings))
        } else {
            finish(.failure(EnrollError.notEnoughAngles))
        }
    }

    private func publish(progress: Float, step: Step) {
        onProgress?(Progress(
            stepIndex: stepIndex,
            stepCount: Step.allCases.count,
            stepProgress: progress,
            step: step,
            samples: embeddings.count
        ))
    }

    private func finish(_ result: Result<[FaceEmbedding], Error>) {
        Self.diagnostic("enroll finish: \(result.map { "\($0.count) samples" })")
        guard !finished else { return }
        finished = true
        capture.removeDelegate(self)
        capture.relinquish()
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async {
            completion?(result)
        }
    }
}
