import SwiftUI

/// Одна строка списка: название, прогресс-бар, скорости и кнопка play/pause.
struct TorrentRowView: View {
    @EnvironmentObject var client: QBittorrentClient
    let torrent: Torrent

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(torrent.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                ProgressView(value: torrent.progress)
                    .tint(progressColor)

                HStack(spacing: 8) {
                    Text(torrent.localizedState)
                        .foregroundStyle(stateColor)
                    Text("·")
                    Text("\(Int(torrent.progress * 100))%")
                    Spacer()
                    if torrent.dlspeed > 0 {
                        Label(Formatting.speed(torrent.dlspeed), systemImage: "arrow.down")
                            .foregroundStyle(.blue)
                    }
                    if torrent.upspeed > 0 {
                        Label(Formatting.speed(torrent.upspeed), systemImage: "arrow.up")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(Formatting.size(torrent.size))
                    if !torrent.isFinished, torrent.eta > 0 {
                        Text("· осталось \(Formatting.eta(torrent.eta))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Button {
                Task {
                    if torrent.isActive {
                        await client.pause(hashes: [torrent.hash])
                    } else {
                        await client.resume(hashes: [torrent.hash])
                    }
                }
            } label: {
                Image(systemName: torrent.isActive ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(torrent.isActive ? .orange : .green)
            }
            // .borderless даёт кнопке собственный хит-тест внутри строки-NavigationLink,
            // чтобы тап по ней не открывал экран файлов.
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var progressColor: Color {
        if torrent.state == "error" { return .red }
        return torrent.isFinished ? .green : .blue
    }

    private var stateColor: Color {
        switch torrent.state {
        case "error", "missingFiles": return .red
        case let s where s.hasPrefix("paused") || s.hasPrefix("stopped"): return .secondary
        default: return .primary
        }
    }
}
