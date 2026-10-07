import SwiftUI
import WidgetKit

/// ホーム画面のウィジェット：共有アルバムの新しい写真（小：1 枚、中：大きい 1 枚と小さい 2 枚、大：4 枚）
@main
struct FilmCameraWidgets: WidgetBundle {
    var body: some Widget {
        AlbumWidget()
    }
}

struct AlbumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlbumWidget", provider: AlbumProvider()) { entry in
            AlbumWidgetView(entry: entry)
                .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.07), for: .widget)
        }
        .configurationDisplayName("共有アルバム")
        .description("友だちと共有しているアルバムの、新しい写真を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct AlbumTimelineEntry: TimelineEntry {
    let date: Date
    let items: [Item]

    struct Item: Identifiable {
        let id: String
        let image: UIImage?
        let albumTitle: String
        let who: String
        let takenAt: Date
    }
}

struct AlbumProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlbumTimelineEntry {
        AlbumTimelineEntry(date: Date(), items: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (AlbumTimelineEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlbumTimelineEntry>) -> Void) {
        // 写真はアプリが更新したときに書き換わる（アプリから再読み込みを頼む）。念のため 1 時間ごとにも読み直す
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func load() -> AlbumTimelineEntry {
        let data = AlbumWidgetData.load()
        let items = data.entries.map { entry in
            AlbumTimelineEntry.Item(
                id: entry.file,
                image: AlbumWidgetData.imageURL(entry.file).flatMap { UIImage(contentsOfFile: $0.path) },
                albumTitle: entry.albumTitle, who: entry.who, takenAt: entry.takenAt)
        }
        return AlbumTimelineEntry(date: Date(), items: items)
    }
}

struct AlbumWidgetView: View {
    let entry: AlbumTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.5))
                Text("共有アルバムを開くと\nここに写真が出ます")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            default: tile(entry.items[0], caption: true)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 2) {
            tile(entry.items[0], caption: true)
            if entry.items.count > 1 {
                VStack(spacing: 2) {
                    ForEach(entry.items.dropFirst().prefix(2)) { item in
                        tile(item, caption: false)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var large: some View {
        let items = Array(entry.items.prefix(4))
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(items.prefix(2)) { tile($0, caption: true) }
            }
            if items.count > 2 {
                HStack(spacing: 2) {
                    ForEach(items.dropFirst(2)) { tile($0, caption: true) }
                }
            }
        }
    }

    private func tile(_ item: AlbumTimelineEntry.Item, caption: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color(white: 0.15)
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                if caption {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.albumTitle)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                        Text("\(item.who)・\(item.takenAt, style: .relative)前")
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                }
            }
        }
    }
}
