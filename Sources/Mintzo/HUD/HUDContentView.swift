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

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    /// Réglages accessibilité, forçables en DEBUG pour la QA
    /// (`MINTZO_REDUCE_MOTION=1`, `MINTZO_REDUCE_TRANSPARENCY=1`).
    private var reduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MINTZO_REDUCE_MOTION"] == "1" { return true }
        #endif
        return systemReduceMotion
    }

    private var reduceTransparency: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MINTZO_REDUCE_TRANSPARENCY"] == "1" { return true }
        #endif
        return systemReduceTransparency
    }

    /// État affiché — suit viewModel.state via la chorégraphie de morphing (§4.3).
    @State private var displayedState: HUDState = .idle
    @State private var contentOpacity: Double = 1
    @State private var capsuleScale: CGFloat = 0.85
    @State private var capsuleOpacity: Double = 0
    @State private var badgeScale: CGFloat = 1
    @State private var haloBreathing = false
    @State private var successWashX: CGFloat = -1
    @State private var morphTask: Task<Void, Never>?
    @State private var cancelHovering = false

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
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark
                        ? MzHUD.shadowOpacityDark : MzHUD.shadowOpacityLight),
                    radius: MzHUD.shadowBlur / 2, x: 0, y: MzHUD.shadowY)
            // Halo APRÈS l'ombre (pas d'ombre teintée) mais dessiné derrière la capsule ;
            // .background propose la taille de la capsule, le flou déborde librement.
            .background { listeningHalo }
            .scaleEffect(capsuleScale)
            .opacity(capsuleOpacity)
            .contentShape(Capsule())
            .onTapGesture { viewModel.capsuleTapped() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityStateLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: MzStrings.stop) { viewModel.capsuleTapped() }
            .accessibilityAction(named: MzStrings.cancel) { viewModel.cancelTapped() }
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
        case .success(let message):
            successContent(message)
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
            timerText
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            cancelButton
        }
        .padding(.horizontal, MzHUD.paddingH)
    }

    /// Croix d'annulation — visible dans tous les états actifs (écoute,
    /// transcription, correction). Le seul « abandonne » : le clic capsule
    /// hors croix reste « stop et transcris » pendant l'écoute (§4.1).
    private var cancelButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MzColor.inkSecondary)
            .frame(width: 18, height: 18)
            .background {
                if cancelHovering {
                    Circle().fill(MzColor.ink.opacity(0.10))
                }
            }
            .contentShape(Circle())
            .onHover { cancelHovering = $0 }
            .onTapGesture { viewModel.cancelTapped() }
            .help(MzStrings.cancel)
            .accessibilityHidden(true) // la capsule expose l'action « Utzi » (§10)
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
        // Langue de la SESSION (détectée/choisie au stop), pas de l'interface.
        let label = state == .correcting
            ? MzStrings.correcting(session: viewModel.labelLanguage)
            : MzStrings.transcribing(session: viewModel.labelLanguage)
        return HStack(spacing: MzHUD.itemSpacing) {
            ProcessingTraitView(reduceMotion: reduceMotion)
            Text(label)
                .font(MzFont.hudLabel)
                .foregroundStyle(MzColor.ink)
                .lineLimit(1)
                .id(label)
                .transition(.opacity)
            cancelButton
        }
    }

    // MARK: État 4 — succès (112 pt « Itsatsita » 600 ms ; message custom ≤ 320 pt, 1,5 s)

    private func successContent(_ message: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MzColor.success)
            Text(message ?? MzStrings.inserted(session: viewModel.labelLanguage))
                .font(MzFont.hudLabel)
                .foregroundStyle(MzColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, MzHUD.paddingH)
        .onAppear {
            successWashX = -1
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.3)) { successWashX = 1 }
        }
    }

    /// Wash `MzGorri` 12 % qui balaye la capsule à l'insertion (300 ms, §4.3 état 4).
    @ViewBuilder
    private var successWash: some View {
        if case .success = displayedState {
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
        switch state {
        case .error(let message):
            return Self.contentWidth(message: message)
        case .success(let message?):
            return Self.contentWidth(message: message)
        default:
            return state.fixedWidth
        }
    }

    /// Largeur au contenu (erreur §4.3 état 5, succès à message custom) :
    /// plancher 112 pt, plafond 320 pt.
    static func contentWidth(message: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let text = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let icon: CGFloat = 18   // exclamationmark.triangle / checkmark à 13 pt
        let safety: CGFloat = 4  // arrondis de rendu — jamais de troncature d'un texte qui tient
        let width = MzHUD.paddingH + icon + MzHUD.itemSpacing + text + safety + MzHUD.paddingH
        return min(max(width, MzHUD.widthSuccess), MzHUD.widthErrorMax)
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
        return MzColor.hudHairline
    }

    /// Halo d'écoute : capsule `MzGorriBizi` floutée derrière la capsule,
    /// opacité seule 12 % → 18 % → 12 %, 3,2 s (§7). Sur le verre réel (givré),
    /// il se lit comme une lueur de bord — le rendu offscreen l'exagère.
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
        // VoiceOver dit la même chose que l'œil : langue de session (§10).
        case .transcribing: MzStrings.transcribing(session: viewModel.labelLanguage)
        case .correcting: MzStrings.correcting(session: viewModel.labelLanguage)
        case .success(let message): message ?? MzStrings.inserted(session: viewModel.labelLanguage)
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
