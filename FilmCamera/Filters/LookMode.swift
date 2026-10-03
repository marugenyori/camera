import CoreGraphics
import CoreImage

/// 撮影モード（見え方）
enum LookMode: String, CaseIterable, Identifiable {
    case film
    case flash
    case iwai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: return "フィルム"
        case .flash: return "フラッシュ"
        case .iwai: return "岩井俊二風"
        }
    }

    /// 距離（LiDAR など）を使うモードか
    var usesDepth: Bool { self == .flash }

    var caption: String {
        switch self {
        case .film: return "低いコントラスト・暖かい白・にじむ光"
        case .flash: return "直射フラッシュのコンデジ写真"
        case .iwai: return "淡い水色・白飛び・やわらかな光"
        }
    }
}

/// フィルタにかけるときの設定
struct LookOptions {
    var mode: LookMode
    var dateStamp: Bool
    /// 距離（メートル）。写真や映像と同じ向き。大きさはそろっていなくてよい
    var depth: CIImage? = nil
    /// 粒子（グレイン）の模様をずらす量。毎フレーム変えると粒子が動いて見える
    var grainSeed: CGPoint = CGPoint(x: CGFloat.random(in: 0..<512), y: CGFloat.random(in: 0..<512))
}
