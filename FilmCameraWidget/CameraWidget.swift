import AppIntents
import SwiftUI
import WidgetKit

/// カメラのウィジェット：タップすると、選んだフィルタでカメラが開く。
/// ロック画面に置けば、iPhone のロックを外してすぐ撮れる
struct CameraWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CameraWidget", intent: CameraWidgetIntent.self, provider: CameraProvider()) { entry in
            CameraWidgetView(look: entry.look)
                .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.07), for: .widget)
        }
        .configurationDisplayName("カメラ")
        .description("選んだフィルタで、すぐにカメラを開きます。長押しの「ウィジェットを編集」でフィルタを選べます。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

/// ウィジェットで選べるフィルタ（アプリの LookMode と同じ名前。current は「前回のまま」）
enum CameraLook: String, AppEnum {
    case current, standard, film, flash, warmFlash, compact, iwai, cross, harinezumi, warmHarinezumi, double, contact

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "フィルタ"

    static var caseDisplayRepresentations: [CameraLook: DisplayRepresentation] = [
        .current: "前回のまま",
        .standard: "標準",
        .film: "フィルム",
        .flash: "フラッシュ",
        .warmFlash: "暖フラッシュ",
        .compact: "コンデジ",
        .iwai: "岩井俊二風",
        .cross: "クロス",
        .harinezumi: "ハリネズミ",
        .warmHarinezumi: "暖ハリネズミ",
        .double: "多重露光",
        .contact: "分割",
    ]

    var title: String {
        switch self {
        case .current: return "カメラ"
        case .standard: return "標準"
        case .film: return "フィルム"
        case .flash: return "フラッシュ"
        case .warmFlash: return "暖フラッシュ"
        case .compact: return "コンデジ"
        case .iwai: return "岩井俊二風"
        case .cross: return "クロス"
        case .harinezumi: return "ハリネズミ"
        case .warmHarinezumi: return "暖ハリネズミ"
        case .double: return "多重露光"
        case .contact: return "分割"
        }
    }

    /// 丸いウィジェットに入る短い名前
    var shortTitle: String {
        switch self {
        case .current: return "撮る"
        case .warmFlash: return "暖フラ"
        case .iwai: return "岩井"
        case .harinezumi: return "ハリネ"
        case .warmHarinezumi: return "暖ハリ"
        case .double: return "多重"
        default: return title
        }
    }

    var systemImage: String {
        switch self {
        case .current: return "camera.fill"
        case .standard: return "camera"
        case .film: return "film"
        case .flash, .warmFlash: return "bolt.fill"
        case .compact: return "camera.compact"
        case .iwai: return "sun.haze.fill"
        case .cross: return "circle.lefthalf.filled"
        case .harinezumi, .warmHarinezumi: return "camera.aperture"
        case .double: return "square.on.square"
        case .contact: return "square.grid.2x2"
        }
    }

    var url: URL? {
        URL(string: self == .current ? "filmcamera://camera" : "filmcamera://camera?mode=\(rawValue)")
    }
}

struct CameraWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "カメラを開く"
    static var description = IntentDescription("選んだフィルタでカメラを開きます。")

    @Parameter(title: "フィルタ", default: .current)
    var look: CameraLook

    init() {}
}

struct CameraEntry: TimelineEntry {
    let date: Date
    let look: CameraLook
}

struct CameraProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CameraEntry {
        CameraEntry(date: Date(), look: .current)
    }

    func snapshot(for configuration: CameraWidgetIntent, in context: Context) async -> CameraEntry {
        CameraEntry(date: Date(), look: configuration.look)
    }

    func timeline(for configuration: CameraWidgetIntent, in context: Context) async -> Timeline<CameraEntry> {
        // 中身は変わらないので、書き直しは要らない
        Timeline(entries: [CameraEntry(date: Date(), look: configuration.look)], policy: .never)
    }
}

struct CameraWidgetView: View {
    let look: CameraLook
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(look.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: look.systemImage)
                        .font(.title3)
                        .widgetAccentable()
                    Text(look.shortTitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                ZStack {
                    AccessoryWidgetBackground()
                        .clipShape(Circle())
                    Image(systemName: look.systemImage)
                        .font(.title3)
                        .widgetAccentable()
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text("フィルムカメラ")
                        .font(.headline)
                        .lineLimit(1)
                    Text(look == .current ? "タップして撮る" : "\(look.title)で撮る")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label(look == .current ? "カメラを開く" : "\(look.title)で撮る", systemImage: look.systemImage)
        default:
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.55, blue: 0.2))
                        .frame(width: 64, height: 64)
                    Image(systemName: look.systemImage)
                        .font(.title)
                        .foregroundStyle(.white)
                }
                Text(look == .current ? "撮る" : look.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
