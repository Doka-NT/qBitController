import SwiftUI

struct ContentView: View {
    @EnvironmentObject var client: QBittorrentClient
    @State private var showSettings = false
    @State private var showAdd = false
    /// Торрент, для которого запрошено удаление (показывает диалог подтверждения).
    @State private var torrentToDelete: Torrent?
    /// Выбранная сортировка (сохраняется между запусками). По умолчанию — сначала новые.
    @AppStorage("torrentSort") private var sortRaw = TorrentSort.dateNewest.rawValue
    /// Автообновление списка каждые 3 секунды.
    @State private var timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var sort: TorrentSort { TorrentSort(rawValue: sortRaw) ?? .dateNewest }
    private var sortedTorrents: [Torrent] { sort.apply(to: client.torrents) }

    var body: some View {
        NavigationStack {
            Group {
                if !client.settings.isConfigured {
                    notConfiguredView
                } else if client.torrents.isEmpty && client.isLoading {
                    ProgressView("Загрузка…")
                } else if client.torrents.isEmpty {
                    emptyView
                } else {
                    list
                }
            }
            .navigationTitle("Торренты")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Сортировка", selection: $sortRaw) {
                            ForEach(TorrentSort.allCases) { option in
                                Label(option.label, systemImage: option.systemImage)
                                    .tag(option.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .disabled(!client.settings.isConfigured)
                    .accessibilityLabel("Сортировка списка")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await client.toggleSpeedLimits() }
                    } label: {
                        Image(systemName: client.altSpeedLimitsEnabled ? "tortoise.fill" : "tortoise")
                    }
                    .tint(client.altSpeedLimitsEnabled ? .orange : nil)
                    .disabled(!client.settings.isConfigured)
                    .accessibilityLabel(client.altSpeedLimitsEnabled
                                        ? "Выключить ограничение скорости"
                                        : "Включить ограничение скорости")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!client.settings.isConfigured)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(client)
            }
            .sheet(isPresented: $showAdd) {
                AddTorrentView().environmentObject(client)
            }
            .overlay(alignment: .bottom) {
                if let msg = client.errorMessage {
                    errorBanner(msg)
                }
            }
        }
        .task { await client.fetchTorrents() }
        .onReceive(timer) { _ in
            guard client.settings.isConfigured, !showSettings, !showAdd else { return }
            Task { await client.fetchTorrents() }
        }
    }

    private var list: some View {
        List {
            ForEach(sortedTorrents) { torrent in
                NavigationLink {
                    TorrentFilesView(torrent: torrent).environmentObject(client)
                } label: {
                    TorrentRowView(torrent: torrent)
                }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            torrentToDelete = torrent
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if torrent.isActive {
                            Button {
                                Task { await client.pause(hashes: [torrent.hash]) }
                            } label: {
                                Label("Пауза", systemImage: "pause.fill")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                Task { await client.resume(hashes: [torrent.hash]) }
                            } label: {
                                Label("Старт", systemImage: "play.fill")
                            }
                            .tint(.green)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .refreshable { await client.fetchTorrents() }
        .confirmationDialog(
            "Удалить торрент?",
            isPresented: Binding(get: { torrentToDelete != nil },
                                 set: { if !$0 { torrentToDelete = nil } }),
            titleVisibility: .visible,
            presenting: torrentToDelete
        ) { torrent in
            Button("Удалить торрент", role: .destructive) {
                Task { await client.delete(hashes: [torrent.hash], deleteFiles: false) }
            }
            Button("Удалить с данными", role: .destructive) {
                Task { await client.delete(hashes: [torrent.hash], deleteFiles: true) }
            }
            Button("Отмена", role: .cancel) {}
        } message: { torrent in
            Text(torrent.name)
        }
    }

    private var notConfiguredView: some View {
        ContentUnavailableView {
            Label("Нет подключения", systemImage: "server.rack")
        } description: {
            Text("Укажите адрес сервера qBittorrent в настройках.")
        } actions: {
            Button("Открыть настройки") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Нет торрентов", systemImage: "tray")
        } description: {
            Text("Нажмите + чтобы добавить торрент.")
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.red, in: RoundedRectangle(cornerRadius: 10))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { client.errorMessage = nil }
    }
}

#Preview {
    ContentView().environmentObject(QBittorrentClient())
}
