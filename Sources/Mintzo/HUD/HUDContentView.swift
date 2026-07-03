import SwiftUI
import AppKit

// Vue de la capsule HUD — spec exacte : docs/design/design-language.md §4 (+ §7 motion).
// Hauteur 36 pt constante, largeurs par état 208 / 156 / 112 / ≤320,
// morphing spring(0.32, 0.8) séquencé fade-out → resize → fade-in.

/// Métriques locales du HUD non couvertes par MzHUD (à remonter au DesignSystem).
enum HUDLayout {
    static let badgeWidth: CGFloat = 24
    static let badgeHeight: CGFloat = 20
    static let badgeCornerRadius: CGFloat = 6
    /// 26 barres × 2 pt + 25 gaps × 2 pt (§4.2).
    static let waveformZoneWidth: CGFloat = 102
    /// Trait continu des états de traitement (§4.3 état 2).
    static let processingTraitWidth: CGFloat = 40
    static let hairlineWidth: CGFloat = 0.5
    /// Marge sous la capsule dans le panel — accueille l'ombre (y 8, blur 24).
    static let panelBottomInset: CGFloat = 34
    /// Marges latérales/hautes du panel — accueillent halo + ombre.
    static let panelPadding: CGFloat = 40
    static let panelWidth: CGFloat = 420
    static let panelHeight: CGFloat = 110
}

struct HUDContentView: View {
    let viewModel: HUDViewModel
    /// Le contrôleur du panel s'en sert pour ordonner/masquer la fenêtre (jamais de makeKey).
    var onVisibilityChange: ((Bool) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    /// État affiché — suit viewModel.state via la chorégraphie de morphing (§4.3).
    @State private var displayedState: HUDState = .idle
    @State private var contentOpacity: Double = 1
    @State private var capsuleScale: CGFloat = 0.85
    @State private var capsuleOpacity: Double = 0
    @State private var badgeScale: CGFloat = 1
    @State private var haloBreathing = false
    @State private var successWashX: CGFloat = -1
    @State private var morphTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            capsule
                .padding(.bottom, HUDLayout.panelBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.state) { oldState, newState in
            choreograph(from: oldState, to: newState)
        }
        .onChange(of: viewModel.languagePulse) {
            pulseBadge()
        }
        .onAppear {
            if viewModel.state.isVisible {
                choreograph(from: .idle, to: viewModel.state)
            }
        }
    }

    // MARK: Capsule

    private var capsule: some View {
        content(for: displayedState)
            .opacity(contentOpacity)
            .frame(height: MzHUD.height)
            .frame(width: capsuleWidth(for: displayedState))
            .background { hudMaterial }
            .overlay { successWash }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(hairlineColor, lineWidth: HUDLayout.hairlineWidth)
            }
            .background { listeningHalo }
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.20),
                    radius: 12, x: 0, y: 8)
            .scaleEffect(capsuleScale)
            .opacity(capsuleOpacity)
            .contentShape(Capsule())
            .onTapGesture { viewModel.capsuleTapped() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityStateLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: MzStrings.stop) { viewModel.capsuleTapped() }
    }

    @ViewBuilder
    private func content(for state: HUDState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .listening:
            listeningContent
        case .transcribing, .correcting:
            processingContent(for: state)
        case .success:
            successContent
        case .error(let message):
            errorContent(message)
        }
    }

    // MARK: État 1 — écoute (208 pt, §4.2)

    private var listeningContent: some View {
        HStack(spacing: MzHUD.itemSpacing) {
            languageBadge
            SeismographView(
                bars: viewModel.waveform.bars,
                lastBarDate: viewModel.lastBarDate,
                currentLevel: viewModel.currentLevel,
                reduceMotion: reduceMotion
            )
            .frame(width: HUDLayout.waveformZoneWidth,
                   height: WaveformMapper.maxHeight)
            Spacer(minLength: 0)
            timerText
        }
        .padding(.horizontal, MzHUD.paddingH)
    }

    private var languageBadge: some View {
        let language = viewModel.badgeLanguage
        let isUnresolvedAuto = language == .auto
        return Text(language.badgeText)
            .font(MzFont.hudBadge)
            .tracking(MzFont.hudBadgeTracking)
            .foregroundStyle(isUnresolvedAuto ? MzColor.inkSecondary : MzColor.gorri)
            .frame(width: HUDLayout.badgeWidth, height: HUDLayout.badgeHeight)
            .background {
                RoundedRectangle(cornerRadius: HUDLayout.badgeCornerRadius, style: .continuous)
                    .fill(MzColor.gorri.opacity(MzOpacity.tint))
            }
            .scaleEffect(badgeScale)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.cycleLanguage() }
            .help(MzStrings.languageBadgeHelp)
            .accessibilityHidden(true)
    }

    private var timerText: some View {
        let display = viewModel.timerDisplay
        return Text(display.text)
            .font(MzFont.hudTimer)
            .foregroundStyle(display.isCountdown ? MzColor.gorri : MzColor.inkSecondary)
    }

    // MARK: États 2-3 — traitement (156 pt, trait + shimmer + label)

    private func processingContent(for state: HUDState) -> some View {
        let label = state == .correcting ? MzStrings.correcting : MzStrings.transcribing
        return HStack(spacing: MzHUD.itemSpacing) {
            ProcessingTraitView(reduceMotion: reduceMotion)
            Text(label)
                .font(MzFont.hudLabel)
                .foregroundStyle(MzColor.ink)
                .lineLimit(1)
                .id(label)
                .transition(.opacity)
        }
    }

    // MARK: État 4 — succès (112 pt, 600 ms)

    private var successContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MzColor.success)
            Text(MzStrings.inserted)
                .font(MzFont.hudLabel)
                .foregroundStyle(MzColor.ink)
                .lineLimit(1)
        }
        .onAppear {
            successWashX = -1
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.3)) { successWashX = 1 }
        }
    }

    /// Wash `MzGorri` 12 % qui balaye la capsule à l'insertion (300 ms, §4.3 état 4).
    @ViewBuilder
    private var successWash: some View {
        if displayedState == .success {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, MzColor.gorri.opacity(MzOpacity.tint), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 60)
                .position(x: proxy.size.width / 2 + successWashX * (proxy.size.width / 2 + 60),
                          y: proxy.size.height / 2)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: État 5 — erreur (≤ 320 pt, 4 s ou clic)

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: MzHUD.itemSpacing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(message)
                .font(MzFont.hudLabel)
                .foregroundStyle(MzColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, MzHUD.paddingH)
    }

    // MARK: Largeurs exactes par état (§4.3)

    private func capsuleWidth(for state: HUDState) -> CGFloat? {
        if case .error(let message) = state {
            return Self.errorWidth(message: message)
        }
        return state.fixedWidth
    }

    /// Largeur au contenu pour l'erreur, plafonnée à 320 pt (§4.3 état 5).
    static func errorWidth(message: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let text = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let icon: CGFloat = 16
        let width = MzHUD.paddingH + icon + MzHUD.itemSpacing + text + MzHUD.paddingH
        return min(max(width, HUDState.success.fixedWidth ?? 112), HUDState.error(message: "").maxWidth)
    }

    // MARK: Matériau (§4.1)

    @ViewBuilder
    private var hudMaterial: some View {
        if reduceTransparency {
            Capsule().fill(MzColor.surface)
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Capsule())
        } else {
            VisualEffectCapsule()
        }
    }

    private var hairlineColor: Color {
        if case .error = displayedState {
            return Color(nsColor: .systemRed).opacity(0.40)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    /// Halo d'écoute : `MzGorriBizi` 12 % → 18 % → 12 %, opacité seule, 3,2 s (§7).
    @ViewBuilder
    private var listeningHalo: some View {
        if displayedState == .listening {
            Capsule()
                .fill(MzColor.gorriBizi)
                .padding(-5)
                .blur(radius: 14)
                .opacity(reduceMotion ? MzOpacity.tint : (haloBreathing ? 0.18 : MzOpacity.tint))
                .onAppear {
                    guard !reduceMotion else { return }
                    haloBreathing = false
                    withAnimation(MzMotion.breath) { haloBreathing = true }
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: Chorégraphie des transitions (§4.3, §7.2)

    private func choreograph(from oldState: HUDState, to newState: HUDState) {
        morphTask?.cancel()

        switch (oldState.isVisible, newState.isVisible) {
        case (false, true):
            // Apparition : scale 0.85 → 1 + fade, spring 180 ms.
            displayedState = newState
            contentOpacity = 1
            capsuleScale = reduceMotion ? 1 : 0.85
            capsuleOpacity = 0
            onVisibilityChange?(true)
            withAnimation(reduceMotion ? MzMotion.micro : MzMotion.enter) {
                capsuleScale = 1
                capsuleOpacity = 1
            }

        case (true, false):
            // Sortie : scale → 0.92 + fade, easeIn 220 ms, puis le panel se masque.
            withAnimation(reduceMotion ? MzMotion.micro : MzMotion.exit) {
                if !reduceMotion { capsuleScale = 0.92 }
                capsuleOpacity = 0
            }
            morphTask = Task {
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                onVisibilityChange?(false)
                displayedState = .idle
                capsuleScale = 0.85
            }

        case (true, true):
            if oldState.isProcessing && newState.isProcessing {
                // 2 → 3 : même largeur, crossfade du label seul (160 ms).
                withAnimation(MzMotion.micro) { displayedState = newState }
            } else {
                morphBetweenVisibleStates(to: newState)
            }

        case (false, false):
            displayedState = newState
        }
    }

    /// Séquence stricte : fade-out 120 ms → resize spring → fade-in 160 ms après.
    /// Jamais deux textes visibles simultanément (§4.3).
    private func morphBetweenVisibleStates(to newState: HUDState) {
        morphTask = Task {
            if reduceMotion {
                // Crossfade 160 ms sans changement d'échelle (§7.2).
                withAnimation(MzMotion.micro) { contentOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                displayedState = newState
                withAnimation(MzMotion.micro) { contentOpacity = 1 }
                return
            }
            withAnimation(.easeIn(duration: 0.12)) { contentOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(MzMotion.morph) { displayedState = newState }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { contentOpacity = 1 }
        }
    }

    /// Pulse unique du badge à la bascule de langue : scale 1 → 1.12 → 1, 220 ms (§4.4).
    private func pulseBadge() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.11)) { badgeScale = 1.12 }
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeIn(duration: 0.11)) { badgeScale = 1 }
        }
    }

    // MARK: Accessibilité (§10)

    private var accessibilityStateLabel: String {
        switch displayedState {
        case .idle: ""
        case .listening: MzStrings.listening
        case .transcribing: MzStrings.transcribing
        case .correcting: MzStrings.correcting
        case .success: MzStrings.inserted
        case .error(let message): message
        }
    }
}

// MARK: - Waveform sismographe (§4.2)

/// 26 barres 2 pt (gap 2), extrémités arrondies, défilement continu vers la gauche :
/// une barre entre à droite toutes les 66 ms, la sortante fade sur ses 8 derniers pt.
/// Reduce Motion : jauge statique (barre horizontale 2 pt dont la largeur suit le RMS).
private struct SeismographView: View {
    let bars: [CGFloat]
    let lastBarDate: Date
    let currentLevel: CGFloat
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            staticGauge
        } else {
            scrollingBars
        }
    }

    private var scrollingBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let step = MzHUD.waveformBarWidth + MzHUD.waveformBarGap
                let elapsed = timeline.date.timeIntervalSince(lastBarDate)
                let phase = min(1, max(0, elapsed / MzMotion.waveformTick))
                let shift = CGFloat(phase) * step
                for (index, height) in bars.enumerated() {
                    let x = CGFloat(index) * step - shift
                    guard x > -step, x < size.width else { continue }
                    var opacity = WaveformBuffer.isSilent(height) ? 0.28 : 0.90
                    // La barre sortante fade sur ses 8 derniers pt de course.
                    opacity *= Double(min(1, max(0, x / 8)))
                    guard opacity > 0 else { continue }
                    let rect = CGRect(x: x, y: (size.height - height) / 2,
                                      width: MzHUD.waveformBarWidth, height: height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: MzHUD.waveformBarWidth / 2),
                        with: .color(MzColor.gorriBizi.opacity(opacity))
                    )
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var staticGauge: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(MzColor.gorriBizi.opacity(0.90))
                .frame(width: gaugeWidth, height: 2)
                .animation(MzMotion.micro, value: gaugeWidth)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private var gaugeWidth: CGFloat {
        let range = WaveformMapper.maxHeight - WaveformMapper.minHeight
        let fraction = (currentLevel - WaveformMapper.minHeight) / range
        return max(4, fraction * HUDLayout.waveformZoneWidth)
    }
}

// MARK: - Trait de traitement + shimmer (§4.3 état 2, §7)

/// Trait continu 2 pt (40 pt de large) traversé par une onde de luminosité, 1,1 s linéaire.
private struct ProcessingTraitView: View {
    let reduceMotion: Bool

    var body: some View {
        Capsule()
            .fill(MzColor.gorriBizi.opacity(0.90))
            .frame(width: HUDLayout.processingTraitWidth, height: 2)
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: MzMotion.shimmerDuration) / MzMotion.shimmerDuration
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 16)
                        .offset(x: -28 + CGFloat(t) * (HUDLayout.processingTraitWidth + 32))
                    }
                    .clipShape(Capsule())
                }
            }
    }
}

// MARK: - Fallback matériau macOS 15 (§4.1)

/// `NSVisualEffectView` .hudWindow masquée en capsule (fallback avant Liquid Glass).
private struct VisualEffectCapsule: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.capsuleMask(height: MzHUD.height)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private static func capsuleMask(height: CGFloat) -> NSImage {
        let radius = height / 2
        let size = NSSize(width: height + 1, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 0, left: radius, bottom: 0, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
