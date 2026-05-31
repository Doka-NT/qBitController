import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var client: QBittorrentClient
    @Environment(\.dismiss) private var dismiss

    @State private var host: String
    @State private var username: String
    @State private var password: String
    @State private var testing = false
    @State private var testResult: TestResult?

    enum TestResult { case ok, fail(String) }

    /// Засеваем поля из сохранённых настроек прямо в init — без гонки с onAppear,
    /// которая могла затирать ввод пользователя.
    init() {
        let s = ServerSettings.load()
        _host = State(initialValue: s.host.isEmpty ? "http://192.168.0.2:8080" : s.host)
        _username = State(initialValue: s.username)
        _password = State(initialValue: s.password)
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Сервер") {
                    TextField("http://192.168.0.2:8080", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.next)
                }
                Section("Авторизация") {
                    TextField("Логин", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль", text: $password)
                }
                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Проверить подключение")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || !canSubmit)

                    if let result = testResult {
                        switch result {
                        case .ok:
                            Label("Подключение успешно", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .fail(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                } footer: {
                    Text("Адрес Web UI qBittorrent (с http:// и портом). Включается в qBittorrent → Настройки → Web UI.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func test() async {
        testing = true
        testResult = nil
        defer { testing = false }
        let probe = QBittorrentClient()
        probe.settings = ServerSettings(host: host, username: username, password: password)
        do {
            try await probe.login()
            testResult = .ok
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            testResult = .fail(msg)
        }
    }

    private func save() {
        let s = ServerSettings(host: host, username: username, password: password)
        s.save()
        client.settings = s
        client.isAuthenticated = false
        client.errorMessage = nil
        dismiss()
        Task { await client.fetchTorrents() }
    }
}

#Preview {
    SettingsView().environmentObject(QBittorrentClient())
}
