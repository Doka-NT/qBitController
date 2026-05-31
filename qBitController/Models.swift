import Foundation

/// Одна запись торрента из ответа qBittorrent Web API (`/api/v2/torrents/info`).
struct Torrent: Identifiable, Decodable, Equatable {
    let hash: String
    let name: String
    /// Размер в байтах.
    let size: Int64
    /// Прогресс 0.0...1.0.
    let progress: Double
    /// Состояние, см. https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API
    let state: String
    /// Скорость загрузки, байт/с.
    let dlspeed: Int64
    /// Скорость отдачи, байт/с.
    let upspeed: Int64
    /// Оставшееся время в секундах (8640000 = ∞).
    let eta: Int64
    let numSeeds: Int
    let numLeechs: Int
    /// Время добавления, Unix-время (секунды).
    let addedOn: Int64

    var id: String { hash }

    enum CodingKeys: String, CodingKey {
        case hash, name, size, progress, state, dlspeed, upspeed, eta
        case numSeeds = "num_seeds"
        case numLeechs = "num_leechs"
        case addedOn = "added_on"
    }

    /// Группа для сортировки по статусу: 0 — загружается, 1 — раздаётся, 2 — остальное.
    var statusRank: Int {
        switch state {
        case "downloading", "forcedDL", "metaDL", "stalledDL", "queuedDL", "checkingDL":
            return 0
        case "uploading", "forcedUP", "stalledUP", "queuedUP", "checkingUP":
            return 1
        default:
            return 2
        }
    }

    /// Активен ли торрент (качается или раздаётся) — для выбора иконки play/pause.
    var isActive: Bool {
        !state.hasPrefix("paused") && !state.hasPrefix("stopped") && state != "error"
    }

    var isFinished: Bool { progress >= 1.0 }

    /// Человекочитаемое состояние на русском.
    var localizedState: String {
        switch state {
        case "downloading", "forcedDL", "metaDL": return "Загрузка"
        case "uploading", "forcedUP", "stalledUP": return "Раздача"
        case "stalledDL": return "Ожидание пиров"
        case "pausedDL", "stoppedDL": return "Пауза"
        case "pausedUP", "stoppedUP": return "Завершён"
        case "queuedDL", "queuedUP": return "В очереди"
        case "checkingDL", "checkingUP", "checkingResumeData": return "Проверка"
        case "error", "missingFiles": return "Ошибка"
        case "moving": return "Перемещение"
        default: return state
        }
    }
}

/// Варианты сортировки списка торрентов.
enum TorrentSort: String, CaseIterable, Identifiable {
    case dateNewest
    case dateOldest
    case sizeLargest
    case sizeSmallest
    case status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateNewest: return "Сначала новые"
        case .dateOldest: return "Сначала старые"
        case .sizeLargest: return "Размер: больше"
        case .sizeSmallest: return "Размер: меньше"
        case .status: return "По статусу"
        }
    }

    var systemImage: String {
        switch self {
        case .dateNewest: return "calendar.badge.clock"
        case .dateOldest: return "calendar"
        case .sizeLargest: return "arrow.down.to.line"
        case .sizeSmallest: return "arrow.up.to.line"
        case .status: return "arrow.up.arrow.down.circle"
        }
    }

    /// Отсортировать список согласно выбранному режиму.
    func apply(to torrents: [Torrent]) -> [Torrent] {
        switch self {
        case .dateNewest:
            return torrents.sorted { $0.addedOn > $1.addedOn }
        case .dateOldest:
            return torrents.sorted { $0.addedOn < $1.addedOn }
        case .sizeLargest:
            return torrents.sorted { $0.size > $1.size }
        case .sizeSmallest:
            return torrents.sorted { $0.size < $1.size }
        case .status:
            // Сначала загружающиеся, затем раздающиеся, затем остальные;
            // внутри группы — сначала новые.
            return torrents.sorted {
                $0.statusRank != $1.statusRank
                    ? $0.statusRank < $1.statusRank
                    : $0.addedOn > $1.addedOn
            }
        }
    }
}

/// Файл внутри торрента (`/api/v2/torrents/files`).
struct TorrentFile: Identifiable, Decodable, Equatable {
    /// Индекс файла — он же `id` для `/filePrio`. В старых версиях API может
    /// отсутствовать, тогда подставляем позицию в массиве при загрузке.
    var index: Int
    let name: String
    let size: Int64
    let progress: Double
    var priority: Int

    var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index, name, size, progress, priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? -1
        name = try c.decode(String.self, forKey: .name)
        size = try c.decode(Int64.self, forKey: .size)
        progress = try c.decode(Double.self, forKey: .progress)
        priority = try c.decode(Int.self, forKey: .priority)
    }

    /// Имя без пути (лист).
    var leafName: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// Папка (путь без имени файла), если есть.
    var folder: String? {
        let parts = name.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }
}

/// Приоритет файла в qBittorrent.
enum FilePriority: Int, CaseIterable, Identifiable {
    case doNotDownload = 0
    case normal = 1
    case high = 6
    case maximal = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .doNotDownload: return "Не загружать"
        case .normal: return "Нормальный"
        case .high: return "Высокий"
        case .maximal: return "Максимальный"
        }
    }

    /// Короткая подпись для строки файла.
    var shortLabel: String {
        switch self {
        case .doNotDownload: return "Выкл"
        case .normal: return "Обычный"
        case .high: return "Высокий"
        case .maximal: return "Макс"
        }
    }

    var systemImage: String {
        switch self {
        case .doNotDownload: return "xmark.circle"
        case .normal: return "equal.circle"
        case .high: return "arrow.up.circle"
        case .maximal: return "arrow.up.circle.fill"
        }
    }

    /// Описание произвольного значения приоритета (включая «смешанный» 2–5).
    static func describe(_ value: Int) -> String {
        FilePriority(rawValue: value)?.shortLabel ?? "Смешанный"
    }
}

enum Formatting {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func speed(_ bytesPerSec: Int64) -> String {
        guard bytesPerSec > 0 else { return "0 КБ/с" }
        return ByteCountFormatter.string(fromByteCount: bytesPerSec, countStyle: .file) + "/с"
    }

    static func eta(_ seconds: Int64) -> String {
        guard seconds > 0, seconds < 8_640_000 else { return "∞" }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute, .second]
        f.maximumUnitCount = 2
        f.unitsStyle = .abbreviated
        return f.string(from: TimeInterval(seconds)) ?? "—"
    }
}
