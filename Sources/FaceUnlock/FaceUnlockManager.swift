import AppKit
import AVFoundation
import Combine
import CoreImage
import Foundation

/// Bridges the face-unlock engine (ported from FaceMac, GPL-3.0) to the notch UI.
@MainActor
final class FaceUnlockManager: ObservableObject {
    static let shared = FaceUnlockManager()

    enum Phase: Equatable {
        case hidden
        /// Locked with the camera off: tap the notch to scan.
        case prompted
        case scanning
        case matched(similarity: Float)
        case failed(String)
    }

    enum EnrollPhase: Equatable {
        case idle
        case running(title: String, symbol: String, step: Int, stepCount: Int)
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var enrollPhase: EnrollPhase = .idle
    /// Live camera image and ring progress for the Apple-style enrollment screen.
    @Published private(set) var enrollPreview: CGImage?
    @Published private(set) var enrollStepIndex = 0
    @Published private(set) var enrollStepProgress: Double = 0
    @Published private(set) var enrollHint = ""
    private let previewContext = CIContext()
    private var previewFrame = 0
    @Published private(set) var hasEnrollment = false
    @Published private(set) var hasPassword = false
    @Published private(set) var accessibilityTrusted = KeyboardInjector.isAccessibilityTrusted
    @Published private(set) var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    let modelAvailable = EmbedderFactory.isModelAvailable

    let settings = AppSettings.shared
    private let store = EnrollmentStore.shared
    private let keychain = KeychainStore.shared
    private lazy var coordinator = UnlockCoordinator(settings: settings, store: store, keychain: keychain)
    private var guided: GuidedEnroller?
    private var hideTask: Task<Void, Never>?

    var isEnabled: Bool {
        get { settings.isEnabled }
        set {
            settings.isEnabled = newValue
            objectWillChange.send()
            coordinator.stop()
            if newValue { coordinator.start() }
        }
    }

    func start() {
        guard modelAvailable else { return }
        coordinator.stateHandler = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        refresh()
        coordinator.start()
        // Permissions granted in System Settings show up when the app is back in front.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FaceUnlockManager.shared.refresh() }
        }
    }

    func refresh() {
        hasEnrollment = ((try? store.load())?.embeddings.isEmpty == false)
        hasPassword = ((try? keychain.password()) ?? nil) != nil
        accessibilityTrusted = KeyboardInjector.isAccessibilityTrusted
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    var allPermissionsGranted: Bool { cameraAuthorized && accessibilityTrusted }

    /// Asks for every permission the app needs, one dialog after the other:
    /// camera first, then Accessibility (to type the password).
    func requestAllPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                Task { @MainActor in
                    self.refresh()
                    self.requestAccessibilityIfNeeded()
                }
            }
        case .denied, .restricted:
            Self.openPrivacySettings("Privacy_Camera")
            requestAccessibilityIfNeeded()
        default:
            requestAccessibilityIfNeeded()
        }
    }

    private func requestAccessibilityIfNeeded() {
        if !KeyboardInjector.isAccessibilityTrusted { requestAccessibility() }
    }

    func openCameraSettings() { Self.openPrivacySettings("Privacy_Camera") }

    private static func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Tap on the notch while a scan can be (re)started.
    func retryIfPossible() -> Bool {
        switch phase {
        case .prompted, .failed:
            coordinator.retryScan()
            return true
        default:
            return false
        }
    }

    // MARK: Settings actions

    func requestAccessibility() {
        KeyboardInjector.requestAccessibility(prompt: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    func savePassword(_ password: String) {
        guard !password.isEmpty else { return }
        try? keychain.setPassword(password)
        refresh()
    }

    func deleteAll() {
        try? store.delete()
        try? keychain.deletePassword()
        coordinator.handleEnrollmentChanged()
        refresh()
    }

    func startEnrollment() {
        guard modelAvailable, guided == nil else { return }
        let enroller = GuidedEnroller()
        guided = enroller
        enrollPhase = .running(title: GuidedEnroller.Step.center.title, symbol: "face.smiling", step: 0, stepCount: GuidedEnroller.stepCount)
        enrollStepIndex = 0
        enrollStepProgress = 0
        enrollHint = ""
        enroller.onHint = { [weak self] hint in
            MainActor.assumeIsolated { if self?.enrollHint != hint { self?.enrollHint = hint } }
        }
        enroller.onFrame = { [weak self] buffer in
            MainActor.assumeIsolated { self?.updatePreview(buffer) }
        }
        enroller.onProgress = { [weak self] progress in
            Task { @MainActor in
                self?.enrollStepIndex = progress.stepIndex
                self?.enrollStepProgress = Double(progress.stepProgress)
                self?.enrollPhase = .running(
                    title: progress.step.title,
                    symbol: progress.step.symbol,
                    step: progress.stepIndex,
                    stepCount: progress.stepCount
                )
            }
        }
        enroller.completion = { [weak self] result in
            Task { @MainActor in self?.finishEnrollment(result) }
        }
        enroller.start()
    }

    func cancelEnrollment() {
        guided?.cancel()
    }

    /// ~15 fps preview for the enrollment ring.
    private func updatePreview(_ buffer: CVPixelBuffer) {
        previewFrame += 1
        guard previewFrame % 2 == 0 else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        enrollPreview = previewContext.createCGImage(image, from: image.extent)
    }

    private func finishEnrollment(_ result: Result<[FaceEmbedding], Error>) {
        guided = nil
        switch result {
        case .success(let embeddings):
            let tag = EmbedderFactory.make().modelTag
            do {
                try store.save(Enrollment(name: NSFullUserName(), embeddings: embeddings, modelTag: tag))
                enrollStepIndex = GuidedEnroller.stepCount
                enrollStepProgress = 1
                enrollPhase = .done
            } catch {
                enrollPhase = .failed("\(error)")
            }
            coordinator.handleEnrollmentChanged()
        case .failure(let error):
            if case GuidedEnroller.EnrollError.cancelled = error {
                enrollPhase = .idle
            } else {
                enrollPhase = .failed(tr("Enrollment Failed"))
            }
        }
        refresh()
    }

    // MARK: Engine state -> notch

    private func apply(_ state: UnlockCoordinator.State) {
        hideTask?.cancel()
        switch state {
        case .idle, .disabled, .armed:
            // `.armed` right after a typed password: keep the check visible briefly.
            if case .matched = phase { schedule(after: 0.45) } else { phase = .hidden }
        case .prompted: phase = .prompted
        case .scanning: phase = .scanning
        case .unlocking(let similarity): phase = .matched(similarity: similarity)
        case .failed(let reason): phase = .failed(reason)
        case .timedOut: phase = .failed(tr("Not recognized"))
        case .rejected: phase = .failed(tr("Face not recognized"))
        case .spoof: phase = .failed(tr("A real face is needed"))
        }
    }

    private func schedule(after seconds: Double) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.phase = .hidden
        }
    }
}
