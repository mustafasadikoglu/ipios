import Combine
import Foundation

/// Uygulama genelinde paylaşılan bağımlılıkları tutar.
///
/// Basit bir bağımlılık kabı: SwiftUI `EnvironmentObject` zincirini şişirmemek
/// için depolar burada toplanır ve ihtiyaç duyan ViewModel'lere elle verilir.
@MainActor
final class AppEnvironment: ObservableObject {

    let sources: SourcesRepository
    let favorites: FavoritesRepository
    let recents: RecentsRepository
    let library: ContentLibrary
    let player: VLCPlayerEngine

    /// Kullanıcı tercihleri (yalnızca hassas olmayan ayarlar).
    ///
    /// `AppEnvironment` dışında ayrıca tutulur çünkü hem kök görünüm (yasal
    /// uyarı kapısı) hem de Ayarlar ekranı aynı örneği paylaşmalıdır.
    let settings: AppSettings

    /// Açılışta yüklemelerin tamamlanıp tamamlanmadığı.
    @Published private(set) var isReady = false
    @Published private(set) var startupError: String?

    private var sourceObservation: AnyCancellable?

    /// Bağımlılıklar verilmezse varsayılan örnekler burada üretilir.
    ///
    /// Varsayılan argüman olarak `SourcesRepository()` yazmak cazip görünür
    /// ama o ifadeler ana aktöre izole tipleri kurar ve varsayılan argümanlar
    /// ana aktör dışında değerlendirilebilir; bu da "call to main
    /// actor-isolated initializer in a synchronous nonisolated context"
    /// hatasına yol açar. `nil` varsayıp örnekleri gövdede kurmak bu sorunu
    /// tümüyle ortadan kaldırır.
    init(
        sources: SourcesRepository? = nil,
        favorites: FavoritesRepository? = nil,
        recents: RecentsRepository? = nil,
        library: ContentLibrary? = nil,
        settings: AppSettings? = nil
    ) {
        let sources = sources ?? SourcesRepository()
        let favorites = favorites ?? FavoritesRepository()
        let recents = recents ?? RecentsRepository()
        let library = library ?? ContentLibrary()
        let settings = settings ?? AppSettings()

        self.sources = sources
        self.favorites = favorites
        self.recents = recents
        self.library = library
        self.settings = settings
        self.player = VLCPlayerEngine(recents: recents)

        // Aktif kaynak değiştiğinde bellekteki liste geçersizleşir: yeni
        // kaynağın kanalları eskisinin üzerine yazılmalı ki kullanıcı bir
        // an bile yanlış kaynağın içeriğini görmesin.
        sourceObservation = sources.$activeSourceID
            .removeDuplicates()
            .sink { [weak self] id in
                self?.library.prepare(for: id)
            }
    }

    /// Kayıtlı kaynak, favori ve izleme geçmişini diskten okur.
    ///
    /// Kaynak listesi okunamazsa bu ölümcül bir hatadır: uygulama oynatacak
    /// hiçbir şey bulamaz ve kullanıcı, verisinin kaybolduğunu sanabilir. Bu
    /// yüzden hata `startupError` üzerinden kök görünüme taşınır ve yeniden
    /// deneme yolu sunulur. Favoriler ve izleme geçmişi ise ikincil verilerdir;
    /// okunamazlarsa boş kabul edilip uygulama açılmaya devam eder.
    func bootstrap() async {
        guard !isReady else { return }

        do {
            try await sources.load()
        } catch {
            Log.storage.error("Kaynaklar yuklenemedi: \(error.localizedDescription, privacy: .public)")
            startupError = L.t("startup.error")
            return
        }

        async let favoritesLoad: Void = favorites.load()
        async let recentsLoad: Void = recents.load()
        _ = await (favoritesLoad, recentsLoad)

        library.prepare(for: sources.activeSourceID)
        startupError = nil
        isReady = true
    }

    /// Aktif kaynak yoksa kullanıcıyı kaynak ekleme ekranına yönlendirmek için
    /// kullanılan kısayol.
    var needsSource: Bool {
        isReady && sources.sources.isEmpty
    }

    /// Aktif kaynağın listesini (gerekiyorsa) indirir. Birden fazla ekran aynı
    /// anda çağırsa bile `ContentLibrary` yalnızca eksik türleri indirir.
    func loadLibrary(_ kinds: [CategoryKind], force: Bool = false) async throws {
        guard let source = sources.activeSource,
              let provider = try sources.activeProvider() else {
            throw AppError.sourceUnreachable
        }
        library.prepare(for: source.id)
        try await library.ensureLoaded(kinds, using: provider, force: force)
    }
}
