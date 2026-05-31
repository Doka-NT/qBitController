import SwiftUI

/// Содержимое торрента: список файлов, прогресс и управление приоритетами.
/// Поддерживает массовый выбор (EditButton) и приоритет для каждого файла.
struct TorrentFilesView: View {
    @EnvironmentObject var client: QBittorrentClient
    let torrent: Torrent

    @State private var files: [TorrentFile] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selection = Set<Int>()
    @Environment(\.editMode) private var editMode

    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }

    var body: some View {
        List(selection: $selection) {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                ForEach(files) { file in
                    fileRow(file).tag(file.index)
                }
            } header: {
                Text("\(files.count) файлов · \(Formatting.size(torrent.size))")
            }
        }
        .navigationTitle(torrent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !files.isEmpty { EditButton() }
            }
            ToolbarItem(placement: .bottomBar) {
                if isEditing {
                    bottomPriorityBar
                }
            }
        }
        .overlay {
            if loading && files.isEmpty {
                ProgressView("Загрузка файлов…")
            } else if files.isEmpty && errorMessage == nil && !loading {
                ContentUnavailableView("Нет файлов", systemImage: "folder")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Строка файла

    @ViewBuilder
    private func fileRow(_ file: TorrentFile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(file.leafName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let folder = file.folder {
                    Text(folder)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                ProgressView(value: file.progress)
                    .tint(file.priority == 0 ? .gray : (file.progress >= 1 ? .green : .blue))
                HStack(spacing: 8) {
                    Text(Formatting.size(file.size))
                    Text("· \(Int(file.progress * 100))%")
                    Spacer()
                    Label(FilePriority.describe(file.priority),
                          systemImage: FilePriority(rawValue: file.priority)?.systemImage ?? "questionmark.circle")
                        .foregroundStyle(file.priority == 0 ? Color.secondary : Color.blue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Быстрая смена приоритета одному файлу (вне режима выбора).
            if !isEditing {
                Menu {
                    priorityButtons(ids: [file.index])
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Массовое управление

    private var bottomPriorityBar: some View {
        HStack {
            Text(selection.isEmpty ? "Выберите файлы" : "Выбрано: \(selection.count)")
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                priorityButtons(ids: Array(selection))
            } label: {
                Label("Приоритет", systemImage: "slider.horizontal.3")
            }
            .disabled(selection.isEmpty)
        }
    }

    @ViewBuilder
    private func priorityButtons(ids: [Int]) -> some View {
        ForEach(FilePriority.allCases) { priority in
            Button {
                Task { await setPriority(priority, ids: ids) }
            } label: {
                Label(priority.label, systemImage: priority.systemImage)
            }
        }
    }

    // MARK: - Действия

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            files = try await client.fetchFiles(hash: torrent.hash)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setPriority(_ priority: FilePriority, ids: [Int]) async {
        guard !ids.isEmpty else { return }
        do {
            try await client.setFilePriority(hash: torrent.hash, ids: ids, priority: priority.rawValue)
            selection.removeAll()
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
