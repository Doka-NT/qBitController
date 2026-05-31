import SwiftUI
import UniformTypeIdentifiers

/// Добавление торрента по magnet/URL-ссылке или из локального .torrent-файла.
struct AddTorrentView: View {
    @EnvironmentObject var client: QBittorrentClient
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var adding = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

    /// Тип .torrent. Если система не знает расширение — допускаем любой файл.
    private let torrentType = UTType(filenameExtension: "torrent") ?? .data

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("magnet:?xt=… или https://…/file.torrent",
                              text: $urlText, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Ссылка")
                } footer: {
                    Text("Поддерживаются magnet-ссылки и прямые ссылки на .torrent-файлы. Можно вставить несколько ссылок с новой строки.")
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Label("Выбрать файл", systemImage: "doc.badge.plus")
                            Spacer()
                            if adding { ProgressView() }
                        }
                    }
                    .disabled(adding)
                } header: {
                    Text("Файл")
                } footer: {
                    Text("Выберите один или несколько .torrent-файлов из «Файлов» или iCloud — они будут добавлены сразу.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Новый торрент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await addByURL() }
                    } label: {
                        if adding { ProgressView() } else { Text("Добавить") }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || adding)
                    .fontWeight(.semibold)
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [torrentType],
                          allowsMultipleSelection: true) { result in
                Task { await handleFileSelection(result) }
            }
        }
    }

    private func addByURL() async {
        adding = true
        errorMessage = nil
        defer { adding = false }
        do {
            try await client.addByURL(urlText)
            await client.fetchTorrents()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            adding = true
            errorMessage = nil
            defer { adding = false }
            do {
                try await client.addByFiles(urls)
                await client.fetchTorrents()
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddTorrentView().environmentObject(QBittorrentClient())
}
