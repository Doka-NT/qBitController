import Foundation
import SwiftUI

/// Настройки подключения. Храним в UserDefaults; пароль — тоже (для простоты,
/// при желании можно вынести в Keychain).
struct ServerSettings: Equatable {
    var host: String   // например http://192.168.0.2:8080
    var username: String
    var password: String

    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static let empty = ServerSettings(host: "", username: "", password: "")

    static func load() -> ServerSettings {
        let d = UserDefaults.standard
        return ServerSettings(
            host: d.string(forKey: "qb_host") ?? "",
            username: d.string(forKey: "qb_user") ?? "",
            password: d.string(forKey: "qb_pass") ?? ""
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: "qb_host")
        d.set(username, forKey: "qb_user")
        d.set(password, forKey: "qb_pass")
    }
}

enum QBError: LocalizedError {
    case notConfigured
    case badURL
    case auth
    case http(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Не задан адрес сервера. Откройте настройки."
        case .badURL: return "Некорректный адрес сервера."
        case .auth: return "Не удалось войти. Проверьте логин и пароль."
        case .http(let code): return "Ошибка сервера (HTTP \(code))."
        case .server(let msg): return msg
        }
    }
}

/// Клиент qBittorrent Web API v2. Авторизуется по cookie (SID),
/// который URLSession хранит автоматически.
@MainActor
final class QBittorrentClient: ObservableObject {
    @Published var settings: ServerSettings
    @Published var torrents: [Torrent] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isAuthenticated = false
    /// Включён ли режим альтернативных лимитов скорости («черепаха»).
    @Published var altSpeedLimitsEnabled = false

    private let session: URLSession

    init() {
        self.settings = ServerSettings.load()
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    private func baseURL() throws -> URL {
        guard settings.isConfigured else { throw QBError.notConfigured }
        var host = settings.host.trimmingCharacters(in: .whitespaces)
        if !host.hasPrefix("http://") && !host.hasPrefix("https://") {
            host = "http://" + host
        }
        guard let url = URL(string: host) else { throw QBError.badURL }
        return url
    }

    // MARK: - Запросы

    /// Логин. qBittorrent отдаёт тело "Ok." и ставит cookie SID.
    func login() async throws {
        let base = try baseURL()
        var req = URLRequest(url: base.appendingPathComponent("api/v2/auth/login"))
        req.httpMethod = "POST"
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        let body = "username=\(encode(settings.username))&password=\(encode(settings.password))"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        if http.statusCode == 403 { throw QBError.auth }
        guard http.statusCode == 200 else { throw QBError.http(http.statusCode) }
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("Fails") { throw QBError.auth }
        isAuthenticated = true
    }

    /// Получить список торрентов, при необходимости автоматически залогинившись.
    func fetchTorrents() async {
        guard settings.isConfigured else {
            errorMessage = QBError.notConfigured.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if !isAuthenticated { try await login() }
            torrents = try await requestTorrents()
            await refreshSpeedLimitsMode()
            errorMessage = nil
        } catch {
            // Возможно, протух SID — пробуем перелогиниться один раз.
            if isAuthenticated {
                isAuthenticated = false
                do {
                    try await login()
                    torrents = try await requestTorrents()
                    errorMessage = nil
                    return
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func requestTorrents() async throws -> [Torrent] {
        let base = try baseURL()
        var comps = URLComponents(url: base.appendingPathComponent("api/v2/torrents/info"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "sort", value: "added_on"),
                            URLQueryItem(name: "reverse", value: "true")]
        var req = URLRequest(url: comps.url!)
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        if http.statusCode == 403 { isAuthenticated = false; throw QBError.auth }
        guard http.statusCode == 200 else { throw QBError.http(http.statusCode) }
        return try JSONDecoder().decode([Torrent].self, from: data)
    }

    /// Опросить текущий режим лимитов: "1" — альтернативные включены, "0" — выключены.
    func refreshSpeedLimitsMode() async {
        do {
            let base = try baseURL()
            var req = URLRequest(url: base.appendingPathComponent("api/v2/transfer/speedLimitsMode"))
            req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            altSpeedLimitsEnabled = (text == "1")
        } catch {
            // Не критично — просто оставляем прежнее значение.
        }
    }

    /// Переключить режим альтернативных лимитов скорости.
    func toggleSpeedLimits() async {
        do {
            let base = try baseURL()
            if !isAuthenticated { try await login() }
            var req = URLRequest(url: base.appendingPathComponent("api/v2/transfer/toggleSpeedLimitsMode"))
            req.httpMethod = "POST"
            req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw QBError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
            }
            // Оптимистично переключаем сразу, затем подтверждаем у сервера.
            altSpeedLimitsEnabled.toggle()
            await refreshSpeedLimitsMode()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Поставить торренты на паузу. qBittorrent ≥5.0 использует /stop, ранее /pause.
    func pause(hashes: [String]) async {
        await action(path: "stop", legacyPath: "pause", hashes: hashes)
    }

    /// Запустить/возобновить торренты. qBittorrent ≥5.0 — /start, ранее /resume.
    func resume(hashes: [String]) async {
        await action(path: "start", legacyPath: "resume", hashes: hashes)
    }

    func delete(hashes: [String], deleteFiles: Bool) async {
        let extra = ["deleteFiles": deleteFiles ? "true" : "false"]
        await action(path: "delete", legacyPath: nil, hashes: hashes, extra: extra)
    }

    private func action(path: String, legacyPath: String?, hashes: [String],
                        extra: [String: String] = [:]) async {
        guard !hashes.isEmpty else { return }
        do {
            try await postTorrentAction(path: path, hashes: hashes, extra: extra)
        } catch QBError.http(404) where legacyPath != nil {
            // Старая версия API — повторяем со старым именем эндпоинта.
            try? await postTorrentAction(path: legacyPath!, hashes: hashes, extra: extra)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        await fetchTorrents()
    }

    private func postTorrentAction(path: String, hashes: [String],
                                   extra: [String: String]) async throws {
        let base = try baseURL()
        if !isAuthenticated { try await login() }
        var req = URLRequest(url: base.appendingPathComponent("api/v2/torrents/\(path)"))
        req.httpMethod = "POST"
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = ["hashes": hashes.joined(separator: "|")]
        params.merge(extra) { _, new in new }
        req.httpBody = params.map { "\($0.key)=\(encode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        guard (200...299).contains(http.statusCode) else { throw QBError.http(http.statusCode) }
    }

    /// Добавить торрент по magnet-ссылке или http(s) URL .torrent-файла.
    func addByURL(_ urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let base = try baseURL()
        if !isAuthenticated { try await login() }

        // multipart/form-data с полем "urls".
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: base.appendingPathComponent("api/v2/torrents/add"))
        req.httpMethod = "POST"
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"urls\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(trimmed)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        guard (200...299).contains(http.statusCode) else { throw QBError.http(http.statusCode) }
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("Fails") {
            throw QBError.server("Не удалось добавить торрент. Проверьте ссылку.")
        }
    }

    /// Получить список файлов торрента.
    func fetchFiles(hash: String) async throws -> [TorrentFile] {
        let base = try baseURL()
        if !isAuthenticated { try await login() }
        var comps = URLComponents(url: base.appendingPathComponent("api/v2/torrents/files"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "hash", value: hash)]
        var req = URLRequest(url: comps.url!)
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        if http.statusCode == 403 { isAuthenticated = false; throw QBError.auth }
        guard http.statusCode == 200 else { throw QBError.http(http.statusCode) }
        var files = try JSONDecoder().decode([TorrentFile].self, from: data)
        // Подставляем позицию как индекс, если сервер его не вернул.
        for i in files.indices where files[i].index < 0 { files[i].index = i }
        return files
    }

    /// Задать приоритет одному или нескольким файлам торрента.
    func setFilePriority(hash: String, ids: [Int], priority: Int) async throws {
        guard !ids.isEmpty else { return }
        let base = try baseURL()
        if !isAuthenticated { try await login() }
        var req = URLRequest(url: base.appendingPathComponent("api/v2/torrents/filePrio"))
        req.httpMethod = "POST"
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = ["hash": hash,
                      "id": ids.map(String.init).joined(separator: "|"),
                      "priority": String(priority)]
        req.httpBody = params.map { "\($0.key)=\(encode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        guard (200...299).contains(http.statusCode) else { throw QBError.http(http.statusCode) }
    }

    /// Добавить торренты из локальных .torrent-файлов (multipart-поле "torrents").
    func addByFiles(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { return }
        let base = try baseURL()
        if !isAuthenticated { try await login() }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: base.appendingPathComponent("api/v2/torrents/add"))
        req.httpMethod = "POST"
        req.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for url in urls {
            // Файл из пикера лежит вне песочницы — нужен security-scoped доступ.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let fileData = try Data(contentsOf: url)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"torrents\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/x-bittorrent\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw QBError.http(0) }
        guard (200...299).contains(http.statusCode) else { throw QBError.http(http.statusCode) }
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("Fails") {
            throw QBError.server("Не удалось добавить файл. Проверьте, что это корректный .torrent.")
        }
    }

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }
}
