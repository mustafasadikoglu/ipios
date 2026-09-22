import SwiftUI

/// Tam ekran oynatıcı.
///
/// Bu görünüm yalnızca bir kabuktur: oynatma durumu uygulama ömrü boyunca tek
/// olan `PlayerViewModel` içinde yaşar (bkz. `PlayerPresenter`). Böylece
/// oynatıcı kapanıp yeniden açıldığında motor ve konum kaybolmaz.
///
/// Katmanlar:
/// 1. Görüntü yüzeyi (`VideoSurfaceView`)
/// 2. Tampon göstergesi ve "kaldığınız yerden" bilgisi
/// 3. Dokunuşla açılıp kapanan kontrol katmanı
///
/// `EnvironmentObject`'ler `init` içinde okunamadığı için gövde iki parçaya
/// ayrılır: bu tür sunucudan `viewModel`'i ödünç alır ve asıl çizimi
/// `PlayerContent`'e devreder.
struct PlayerView: View {

    @EnvironmentObject private var presenter: PlayerPresenter

    let item: PlayableItem

    var body: some View {
        PlayerContent(item: item, viewModel: presenter.viewModel)
    }
}

// MARK: - Asıl ekran

private struct PlayerContent: View {

    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var environment: AppEnvironment

    /// Oynatma tercihleri (yatayda tam ekran). Ayar değişirse oynatıcı
    /// yeniden çizilir ve davranış anında güncellenir.
    @EnvironmentObject private var settings: AppSettings

    @ObservedObject var viewModel: PlayerViewModel

    @StateObject private var pip = PictureInPictureController()

    /// Kullanıcı çubuğu sürüklerken geçici olarak gösterilen konum.
    /// `nil` ise motorun anlık konumu gösterilir.
    @State private var scrubTarget: Double?

    @State private var showsResumeNotice = false
    @State private var showsTapHint = false
    @State private var isScrubbing = false

    let item: PlayableItem

    init(item: PlayableItem, viewModel: PlayerViewModel) {
        self.item = item
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Görüntü **her zaman** oranı korunarak sığdırılır.
            //
            // Canlı yayında daha önce ekranı dolduran kip kullanılıyordu: o kip
            // ekranı doldurur ama taşan kenarları **kırpar**, yani yayının bir
            // kısmı hiç görünmez (kanal logoları, alt bantlar, skor tabelaları
            // kesilir). Kullanıcı bunu "ekran uzamış, görüntü sığmıyor" olarak
            // bildirdi. Canlı ile VOD arasında davranış farkı olması da
            // beklenmedikti; tek kip kullanılır.
            //
            // Ölçekleme artık burada verilmez: libvlc görüntüyü kendi çizdiği
            // alt katmana yerleştirir ve `videoFitMode` ile ayarlanır
            // (bkz. `VLCPlayerEngine.configurePlayer`). SwiftUI'dan yapılan bir
            // katman ayarı onu etkilemezdi.
            VideoSurfaceView(player: viewModel.engine.player)
                .ignoresSafeArea()

            if viewModel.engine.isBuffering {
                bufferingIndicator
            }

            overlay
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.showsControls)
        .statusBarHidden(viewModel.isFullscreen)
        // Home göstergesi yalnızca tam ekrandayken gizlenir; bu değiştirici
        // iOS 17 ile geldiği için alt sürümlerde atlanır (uygulama iOS 16'yı
        // da destekler).
        .modifier(SystemOverlayHiding(hidden: viewModel.isFullscreen))
        .preferredColorScheme(.dark)
        .onAppear {
            pip.onRestore = { viewModel.isFullscreen = false }
            viewModel.showControls()
            viewModel.scheduleControlsHide()
            if viewModel.engine.didResumeFromSavedPosition {
                announceResume()
            }
            announceTapHint()
        }
        .onChange(of: viewModel.engine.state.isPlaying) { isPlaying in
            // Oynatma başladığında kontroller geri çekilir, duraklatıldığında
            // ekranda kalır: kullanıcı devam etmek için dokunmak zorunda kalmaz.
            if isPlaying { viewModel.scheduleControlsHide() } else { viewModel.showControls() }
        }
        .onChange(of: viewModel.engine.didResumeFromSavedPosition) { resumed in
            if resumed { announceResume() }
        }
        .onChange(of: viewModel.showsControls) { visible in
            // Kullanıcı kontrolleri kendisi açtıysa ipucu artık gereksizdir.
            if visible { showsTapHint = false }
        }
        .onDisappear {
            pip.stop()
            Task { await viewModel.engine.persistPosition() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            handleOrientationChange()
        }
        .alert(
            L.t("player.error.title"),
            isPresented: $viewModel.showsErrorAlert
        ) {
            Button(L.t("player.error.retry")) {
                Task { await viewModel.retry() }
            }
            Button(L.t("common.close"), role: .cancel) {
                presenter.dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Katman

    private var overlay: some View {
        ZStack {
            // Dokunuş alanı: kontroller gizliyken de görünür kalır.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isScrubbing else { return }
                    viewModel.toggleControls()
                }

            // "Kontroller için dokunun" ipucu kontrol katmanının üstünde değil
            // altında çizilir; kullanıcı dokunduğunda yalnızca bir kez görünür
            // ve ardından bir daha rahatsız etmez.
            if viewModel.showsControls {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    centerControls
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
            } else if showsTapHint {
                VStack {
                    Spacer()
                    Text(L.t("player.hint.tap"))
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45))
                        .clipShape(Capsule())
                        .padding(.bottom, Theme.Metrics.gutter * 2)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            if showsResumeNotice {
                VStack {
                    Spacer()
                    resumeBadge
                    Spacer().frame(height: 96)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Üst çubuk

    private var topBar: some View {
        HStack(alignment: .center, spacing: Theme.Metrics.rowSpacing) {
            Button {
                presenter.dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text(L.t("player.action.back")))

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = viewModel.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLive {
                BadgeLabel(text: L.t("player.live"), style: .live)
            }

            if pip.isSupported {
                Button {
                    pip.toggle()
                } label: {
                    Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .accessibilityLabel(Text(L.t("player.action.pip")))
            }

            Button {
                viewModel.isFullscreen.toggle()
                viewModel.showControls()
            } label: {
                Image(systemName: viewModel.isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .accessibilityLabel(
                Text(L.t(viewModel.isFullscreen
                         ? "player.action.exitFullscreen"
                         : "player.action.fullscreen"))
            )
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.top, Theme.Metrics.gutter)
        .background(topScrim)
    }

    // MARK: - Orta kontroller

    private var centerControls: some View {
        HStack(spacing: 36) {
            if !viewModel.isLive {
                skipButton(systemImage: "gobackward.10", label: L.t("player.action.backward")) {
                    viewModel.seek(by: -10)
                }
            }

            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text(L.t("player.action.playPause")))

            if !viewModel.isLive {
                skipButton(systemImage: "goforward.10", label: L.t("player.action.forward")) {
                    viewModel.seek(by: 10)
                }
            }
        }
    }

    private func skipButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
        }
        .accessibilityLabel(Text(label))
    }

    // MARK: - Alt çubuk

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if !viewModel.isLive, let duration = viewModel.engine.duration, duration > 0 {
                scrubber(duration: duration)
            } else if viewModel.isLive {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.liveRed)
                        .frame(width: 8, height: 8)
                    Text(L.t("player.live"))
                        .font(Theme.Fonts.badge)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, Theme.Metrics.gutter)
        .background(bottomScrim)
    }

    /// Sürükleme sırasında motorun konumu değiştirilmez; bırakıldığında atlanır.
    /// Böylece her karede `seek` çağrısı yapılmaz ve oynatma takılmaz.
    private func scrubber(duration: Double) -> some View {
        let current = min(max(scrubTarget ?? viewModel.engine.currentTime, 0), duration)

        return VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { current },
                    set: { scrubTarget = $0 }
                ),
                in: 0...max(duration, 0.1)
            ) { editing in
                isScrubbing = editing
                if editing {
                    viewModel.showControls()
                } else {
                    if let target = scrubTarget {
                        viewModel.seek(to: target)
                    }
                    scrubTarget = nil
                    viewModel.scheduleControlsHide()
                }
            }
            .tint(Theme.accent)

            HStack {
                Text(Format.duration(current))
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(Format.duration(duration))
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Yardımcı görünümler

    private var bufferingIndicator: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text(L.t("player.buffering"))
                .font(Theme.Fonts.rowSubtitle)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .allowsHitTesting(false)
    }

    private var resumeBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .semibold))
            Text(L.t("player.resumed"))
                .font(Theme.Fonts.rowSubtitle)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.6))
        .clipShape(Capsule())
    }

    /// Üst ve alt kenarlarda kontrollerin okunabilirliğini artıran yumuşak
    /// karartma. Düz siyah yerine gradyan kullanılır ki görüntü boğulmasın.
    private var topScrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.65), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var bottomScrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    // MARK: - Davranışlar

    private var errorMessage: String {
        if case .failed(let message) = viewModel.engine.state { return message }
        return L.t("player.error.unknown")
    }


    /// Kontroller ilk kez gizlendikten sonra "dokunun" ipucu bir kez gösterilir.
    ///
    /// Neden bir kez: uygulamayı ilk kez açan kullanıcı kontrol katmanının
    /// varlığını bilmeyebilir; ancak aynı ipucu her açılışta tekrarlanırsa
    /// gürültüye dönüşür ve oynatıcı "acemi" hissi verir.
    private func announceTapHint() {
        guard !Self.didShowTapHint else { return }
        Self.didShowTapHint = true

        Task {
            try? await Task.sleep(for: .seconds(6))
            guard viewModel.isPlaying else { return }
            withAnimation(.easeOut(duration: 0.25)) { showsTapHint = true }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { showsTapHint = false }
        }
    }

    /// Oturum başına bir kez gösterildiği için kalıcı olarak saklanmaz:
    /// uygulama kapandığında sıfırlanması kabul edilebilir.
    private static var didShowTapHint = false

    /// "Kaldığınız yerden devam ediliyor" bilgisi kısa süre gösterilir.
    private func announceResume() {
        withAnimation(.easeOut(duration: 0.2)) { showsResumeNotice = true }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.2)) { showsResumeNotice = false }
        }
    }

    /// Yalnızca ayar açıkken ve cihaz yatayken tam ekrana geçilir.
    private func handleOrientationChange() {
        guard settings.fullscreenOnRotate else { return }
        let isLandscape = UIDevice.current.orientation.isLandscape
        let isPortrait = UIDevice.current.orientation.isPortrait
        guard isLandscape || isPortrait else { return }
        viewModel.isFullscreen = isLandscape
    }
}

// MARK: - Sürüm uyumluluğu

/// Home göstergesini tam ekranda gizler.
///
/// `persistentSystemOverlays` iOS 17 ile geldi; uygulamanın en düşük hedefi
/// iOS 16 olduğu için sürüm kontrolü burada tek yerde toplanır. Böylece
/// `if #available` yayılmaz ve çağrı yerleri sade kalır.
private struct SystemOverlayHiding: ViewModifier {

    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.persistentSystemOverlays(hidden ? .hidden : .automatic)
        } else {
            content
        }
    }
}
