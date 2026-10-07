import SwiftUI
import WidgetKit

/// 写真の枚数のウィジェット：選んでいる共有アルバムに、今日・今週・全部で何枚入ったか
struct AlbumCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlbumCountWidget", provider: AlbumCountProvider()) { entry in
            AlbumCountView(entry: entry)
                .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.07), for: .widget)
        }
        .configurationDisplayName("写真の枚数")
        .description("共有アルバムに、今日・今週・全部で何枚入ったかを表示します。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct AlbumCountEntry: TimelineEntry {
    let date: Date
    let albumTitle: String?
    let today: Int
    let week: Int
    let total: Int
}

struct AlbumCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlbumCountEntry {
        AlbumCountEntry(date: Date(), albumTitle: "共有アルバム", today: 3, week: 12, total: 128)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlbumCountEntry) -> Void) {
        completion(load(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlbumCountEntry>) -> Void) {
        // 日付が変わったら「今日」を数え直す（写真が増えたときはアプリが書き直しを頼む）
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        completion(Timeline(entries: [load(at: now), load(at: midnight)], policy: .after(midnight.addingTimeInterval(3600))))
    }

    private func load(at date: Date) -> AlbumCountEntry {
        let data = AlbumWidgetData.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? today
        return AlbumCountEntry(date: date, albumTitle: data.entries.first?.albumTitle,
                               today: data.count(since: today), week: data.count(since: week),
                               total: data.totalCount ?? data.entries.count)
    }
}

struct AlbumCountView: View {
    let entry: AlbumCountEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: "filmcamera://album"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("今日")
                        .font(.caption2)
                    Text("\(entry.today)")
                        .font(.title2.weight(.bold))
                        .widgetAccentable()
                        .minimumScaleFactor(0.5)
                    Text("枚")
                        .font(.caption2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label(entry.albumTitle ?? "共有アルバム", systemImage: "photo.stack")
                    .font(.headline)
                    .widgetAccentable()
                    .lineLimit(1)
                Text("今日 \(entry.today) 枚・今週 \(entry.week) 枚")
                    .font(.caption)
                    .lineLimit(1)
                Text("全部で \(entry.total) 枚")
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("今日 \(entry.today) 枚・全 \(entry.total) 枚", systemImage: "photo.stack")
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label(entry.albumTitle ?? "共有アルバム", systemImage: "photo.stack")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.today)")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.2))
                    Text("枚 今日")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text("今週 \(entry.week) 枚・全部で \(entry.total) 枚")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
