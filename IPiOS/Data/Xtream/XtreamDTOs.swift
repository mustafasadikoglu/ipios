import Foundation

/// Xtream Codes `player_api.php` yanıtlarının ham karşılıkları.
///
/// Tüm alanlar `optional` kabul edilir: sağlayıcılar arasında alan isimleri ve
/// tipleri tutarsızdır (bazıları sayıyı string verir, bazıları hiç vermez).
/// Ham DTO'lar domain modellerine `Domain/…` tarafında dönüştürülür.
enum XtreamDTO {

    // MARK: - auth

    struct AuthResponse: Decodable {
        struct UserInfo: Decodable {
            let username: String?
            let status: String?
            let exp_date: String?
            let created_at: String?
            let is_trial: String?
            let active_cons: String?
            let max_connections: String?
        }

        struct ServerInfo: Decodable {
            let url: String?
            let port: String?
            let https_port: String?
            let server_protocol: String?
            let server_software: String?
            let timezone: String?
            let timestamp_now: FlexibleInt?
        }

        let user_info: UserInfo?
        let server_info: ServerInfo?
        /// Yanlış girişte bazı paneller bunu döner.
        let error: String?
    }

    // MARK: - Kategoriler

    struct CategoryDTO: Decodable {
        let category_id: FlexibleString?
        let category_name: String?
        let parent_id: FlexibleInt?
    }

    // MARK: - Canlı yayın

    struct LiveStreamDTO: Decodable {
        let num: FlexibleInt?
        let name: String?
        let stream_type: String?
        let stream_id: FlexibleInt?
        let stream_icon: String?
        let epg_channel_id: String?
        let added: FlexibleString?
        let category_id: FlexibleString?
        let custom_sid: String?
        let tv_archive: FlexibleInt?
        let direct_source: String?
        let tv_archive_duration: FlexibleInt?
    }

    // MARK: - VOD

    struct VODStreamDTO: Decodable {
        let num: FlexibleInt?
        let name: String?
        let stream_type: String?
        let stream_id: FlexibleInt?
        let stream_icon: String?
        let rating: FlexibleString?
        let rating_5based: FlexibleDouble?
        let added: FlexibleString?
        let category_id: FlexibleString?
        let container_extension: String?
        let plot: String?
        // Bu dört alan paneller arasında en tutarsız olanlardır: `cast` ve
        // `director` sık sık dizi olarak, `youtube_trailer` bazen sayı olarak
        // gelir. `FlexibleString` her iki biçimi de karşılar.
        let cast: FlexibleString?
        let director: FlexibleString?
        let genre: FlexibleString?
        let releaseDate: FlexibleString?
        let duration: FlexibleString?
        let year: FlexibleString?
        let tmdb: FlexibleString?
        let youtube_trailer: FlexibleString?
    }

    struct VODInfoResponse: Decodable {
        struct Info: Decodable {
            let movie_image: String?
            let plot: String?
            let duration: FlexibleString?
            let genre: FlexibleString?
            let rating: FlexibleString?
            let releaseDate: FlexibleString?
            let year: FlexibleString?
        }
        struct MovieData: Decodable {
            let stream_id: FlexibleInt?
            let name: String?
            let added: FlexibleString?
            let container_extension: String?
        }
        let info: Info?
        let movie_data: MovieData?
    }

    // MARK: - Dizi

    struct SeriesDTO: Decodable {
        let num: FlexibleInt?
        let name: String?
        let series_id: FlexibleInt?
        let cover: String?
        let plot: String?
        // Film DTO'sundaki aynı gerekçe: bu alanlar dizi/sayı olarak da gelir.
        let cast: FlexibleString?
        let director: FlexibleString?
        let genre: FlexibleString?
        let releaseDate: FlexibleString?
        let last_modified: FlexibleString?
        let rating: FlexibleString?
        let rating_5based: FlexibleDouble?
        let backdrop_path: [String]?
        let youtube_trailer: FlexibleString?
        let episode_run_time: FlexibleString?
        let category_id: FlexibleString?
    }

    /// `get_series_info` yanıtı: `episodes` anahtarı sezon numarasına göre sözlüktür.
    struct SeriesInfoResponse: Decodable {
        struct EpisodeDTO: Decodable {
            let id: FlexibleString?
            let episode_num: FlexibleInt?
            let title: String?
            let container_extension: String?
            let info: EpisodeInfo?
            let added: FlexibleString?
            let season: FlexibleInt?
        }

        struct EpisodeInfo: Decodable {
            let movie_image: String?
            let plot: String?
            let duration: FlexibleString?
            let releasedate: FlexibleString?
            let rating: FlexibleString?
        }

        struct DetailedInfo: Decodable {
            let name: String?
            let cover: String?
            let plot: String?
            let genre: FlexibleString?
            let releaseDate: FlexibleString?
            let rating: FlexibleString?
            let cast: FlexibleString?
        }

        let seasons: [SeasonDTO]?
        /// `"1": [ ...bölümler... ], "2": [ ... ]`
        let episodes: [String: [EpisodeDTO]]?
        let info: DetailedInfo?
    }

    struct SeasonDTO: Decodable {
        let season_number: FlexibleInt?
        let name: String?
        let cover: String?
        let episode_count: FlexibleInt?
    }

    // MARK: - EPG

    struct ShortEPGResponse: Decodable {
        struct Listing: Decodable {
            let id: FlexibleString?
            let epg_id: FlexibleString?
            let title: String?
            let lang: String?
            let start: String?
            let end: String?
            let description: String?
            let channel_id: String?
            let start_timestamp: FlexibleString?
            let stop_timestamp: FlexibleString?
        }
        let epg_listings: [Listing]?
    }
}

// MARK: - Esnek tip sarmalayıcıları

/// Sayı ya JSON number ya da string olarak gelebilir.
struct FlexibleInt: Decodable, Hashable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else if let string = try? container.decode(String.self) {
            value = Int(string)
        } else {
            value = nil
        }
    }

    init(_ value: Int?) { self.value = value }
}

/// Sayı veya string gelebilen ondalık değer.
struct FlexibleDouble: Decodable, Hashable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = Double(string.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }
}

/// Her zaman string beklenen ama sayı da gelebilen alan.
///
/// Ayrıca **dizi** de kabul edilir: Xtream panelleri `cast`, `director` ve
/// `genre` gibi alanları sık sık `["A", "B"]` biçiminde döndürür. Bu alanlar
/// `String?` olarak tanımlıyken tek bir panel çıktısı tüm yanıtın
/// çözümlemesini düşürüyordu; sonuç, film ve dizi listelerinin hiç
/// yüklenmemesiydi (canlı yayın listesi çalışmaya devam ediyordu, çünkü
/// `LiveStreamDTO` bu alanları hiç istemez). Dizi geldiğinde öğeler
/// birleştirilir.
struct FlexibleString: Decodable, Hashable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = String(bool)
        } else if let list = try? container.decode([FlexibleString].self) {
            let items = list.compactMap(\.value).filter { !$0.isEmpty }
            value = items.isEmpty ? nil : items.joined(separator: ", ")
        } else {
            value = nil
        }
    }

    init(_ value: String?) { self.value = value }
}

extension FlexibleInt {
    var intValue: Int? { value }
    var stringValue: String? { value.map(String.init) }
}

extension FlexibleString {
    var stringValue: String? { value }
    var nonEmpty: String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
