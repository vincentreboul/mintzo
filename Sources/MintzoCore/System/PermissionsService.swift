import AVFoundation
import AppKit
import ApplicationServices

/// État d'une permission TCC.
public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// Photographie des permissions nécessaires à Mintzo.
public struct PermissionsSnapshot: Sendable, Equatable {
    /// Microphone (capture). `notDetermined` = jamais demandée.
    public let microphone: PermissionStatus
    /// Accessibilité (collage simulé au curseur). L'API système ne distingue
    /// pas « jamais demandée » de « refusée » : jamais `.notDetermined`.
    public let accessibility: PermissionStatus

    public init(microphone: PermissionStatus, accessibility: PermissionStatus) {
        self.microphone = microphone
        self.accessibility = accessibility
    }

    public var allGranted: Bool {
        microphone == .granted && accessibility == .granted
    }
}

/// Sondes système injectables (tests headless sans TCC).
public struct PermissionProbes: Sendable {
    public var microphoneStatus: @Sendable () -> PermissionStatus
    public var accessibilityTrusted: @Sendable () -> Bool

    public init(
        microphoneStatus: @escaping @Sendable () -> PermissionStatus,
        accessibilityTrusted: @escaping @Sendable () -> Bool
    ) {
        self.microphoneStatus = microphoneStatus
        self.accessibilityTrusted = accessibilityTrusted
    }

    public static let live = PermissionProbes(
        microphoneStatus: {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notDetermined
            case .denied, .restricted: .denied
            @unknown default: .denied
            }
        },
        accessibilityTrusted: { AXIsProcessTrusted() }
    )
}

/// État et demande des permissions micro + Accessibilité, avec flux de
/// changements pour l'écran « santé des permissions ».
///
/// Le flux `changes()` sonde toutes les `pollInterval` (2 s) tant qu'une
/// permission manque — il n'existe aucune notification TCC publique — et
/// ralentit (×5) quand tout est accordé, pour détecter une révocation à
/// moindre coût. Ne publie que les changements (+ l'état initial).
@MainActor
public final class PermissionsService {
    private let probes: PermissionProbes
    private let pollInterval: Duration

    public init(probes: PermissionProbes = .live, pollInterval: Duration = .seconds(2)) {
        self.probes = probes
        self.pollInterval = pollInterval
    }

    /// État instantané des permissions.
    public func snapshot() -> PermissionsSnapshot {
        Self.read(probes)
    }

    /// Demande l'accès micro (affiche le prompt système si `notDetermined`).
    public func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Demande l'approbation Accessibilité : affiche le prompt système qui
    /// renvoie vers Réglages. Retourne l'état actuel (l'octroi effectif se
    /// fait dans Réglages Système ; suivre via `changes()`).
    ///
    /// Clé en littéral : `kAXTrustedCheckOptionPrompt` est une `var` C non
    /// concurrency-safe en Swift 6 ; sa valeur est stable et documentée.
    @discardableResult
    public func requestAccessibilityAccess() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Deep-link vers Réglages Système > Confidentialité > Accessibilité.
    public func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Deep-link vers Réglages Système > Confidentialité > Microphone.
    public func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    /// Flux des changements de permissions : publie l'état initial puis chaque
    /// changement détecté par polling. Se termine quand le consommateur annule.
    public func changes() -> AsyncStream<PermissionsSnapshot> {
        let probes = self.probes
        let interval = self.pollInterval
        let (stream, continuation) = AsyncStream.makeStream(of: PermissionsSnapshot.self)
        let poller = Task {
            var last = Self.read(probes)
            continuation.yield(last)
            while !Task.isCancelled {
                let wait = last.allGranted ? interval * 5 : interval
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { break }
                let current = Self.read(probes)
                if current != last {
                    last = current
                    continuation.yield(current)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in poller.cancel() }
        return stream
    }

    // MARK: - Interne

    private nonisolated static func read(_ probes: PermissionProbes) -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphone: probes.microphoneStatus(),
            accessibility: probes.accessibilityTrusted() ? .granted : .denied
        )
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
