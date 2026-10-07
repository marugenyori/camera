import SwiftUI
import WidgetKit

/// ウィジェットの一覧
/// - 共有アルバム：新しい写真（ホーム画面の小・中・大、ロック画面の丸・四角・1 行）
/// - 写真だけ：ロック画面の四角いっぱいに、新しい写真を 1 枚
/// - カメラ：選んだフィルタでカメラを開く（ロック画面の丸・四角・1 行、ホーム画面の小）
/// - 写真の枚数：今日・今週・全部の枚数（ロック画面の丸・四角・1 行、ホーム画面の小）
@main
struct FilmCameraWidgets: WidgetBundle {
    var body: some Widget {
        AlbumWidget()
        AlbumPhotoWidget()
        CameraWidget()
        AlbumCountWidget()
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct AlbumTimelineEntry: TimelineEntry {
    let date: Date
    let items: [Item]

    struct Item: Identifiable {
        let id: String
        let image: UIImage?
        /// ロック画面用：白黒にしてコントラストを上げたもの（ロック画面は写真が白黒の半透明になり、そのままだと薄くて見えない）
        let lockImage: UIImage?
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
        var items = data.entries.map { entry in
            AlbumTimelineEntry.Item(
                id: entry.file,
                image: AlbumWidgetData.image(entry.file),
                lockImage: nil,
                albumTitle: entry.albumTitle, who: entry.who, takenAt: entry.takenAt)
        }
        // ロック画面用の画像は、いちばん新しい 1 枚だけ作る
        if let first = items.first {
            items[0] = AlbumTimelineEntry.Item(id: first.id, image: first.image,
                                               lockImage: first.image.flatMap(Self.lockScreenImage),
                                               albumTitle: first.albumTitle, who: first.who, takenAt: first.takenAt)
        }
        return AlbumTimelineEntry(date: Date(), items: items)
    }

    /// 白黒・コントラスト強め・少し明るく（ロック画面の半透明の表示でも、何が写っているか分かるように）。
    /// ウィジェットは使えるメモリがとても少ないので、CoreImage は使わず、小さく縮めてから 1 画素ずつ計算する
    static func lockScreenImage(_ image: UIImage) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        let maxSide = 320.0
        let scale = min(1, maxSide / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale))
        let height = max(1, Int(Double(source.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        // ロック画面は暗い所ほど透けて消えるので、全体を持ち上げてからコントラストを付ける
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            let v = pow(Double(i) / 255, 0.75)
            table[i] = UInt8(max(0, min(255, ((v - 0.5) * 1.35 + 0.55) * 255)))
        }
        for i in 0..<(width * height) { pixels[i] = table[Int(pixels[i])] }
        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: image.imageOrientation)
    }
}

struct AlbumWidgetView: View {
    let entry: AlbumTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: home
        }
    }

    // MARK: ロック画面

    /// 丸：いちばん新しい写真を丸く切り抜く
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let image = entry.items.first.flatMap({ $0.lockImage ?? $0.image }) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "photo.stack")
                    .font(.title2)
            }
        }
        .widgetURL(URL(string: "filmcamera://album"))
    }

    /// 四角：写真と、アルバム名・入れた人・何分前か
    private var rectangular: some View {
        HStack(spacing: 6) {
            if let item = entry.items.first {
                if let image = item.lockImage ?? item.image {
                    // ウィジェットの高さいっぱいの正方形にする
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.albumTitle)
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    Text(item.who)
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(item.takenAt, style: .relative)前")
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            } else {
                Label("共有アルバムを開くと写真が出ます", systemImage: "photo.stack")
                    .font(.caption)
            }
        }
        .widgetURL(URL(string: "filmcamera://album"))
    }

    /// 1 行（時計の上）：だれが何分前に入れたか
    private var inline: some View {
        Group {
            if let item = entry.items.first {
                Label {
                    Text("\(item.who)・\(item.takenAt, style: .relative)前")
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
            } else {
                Label("共有アルバム", systemImage: "photo.stack")
            }
        }
        .widgetURL(URL(string: "filmcamera://album"))
    }

    // MARK: ホーム画面

    @ViewBuilder
    private var home: some View {
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

/// ロック画面の四角いっぱいに、共有アルバムのいちばん新しい写真を出す
struct AlbumPhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlbumPhotoWidget", provider: AlbumProvider()) { entry in
            AlbumPhotoWidgetView(entry: entry)
                .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.07), for: .widget)
        }
        .configurationDisplayName("写真だけ")
        .description("共有アルバムの新しい写真を、ロック画面に大きく表示します。")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct AlbumPhotoWidgetView: View {
    let entry: AlbumTimelineEntry

    var body: some View {
        Group {
            if let image = entry.items.first.flatMap({ $0.lockImage ?? $0.image }) {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Label("共有アルバム", systemImage: "photo.stack")
                        .font(.caption)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .widgetURL(URL(string: "filmcamera://album"))
    }
}
