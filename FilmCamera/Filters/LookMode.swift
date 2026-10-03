import CoreGraphics
import CoreImage

/// 撮影モード（見え方）
enum LookMode: String, CaseIterable, Identifiable {
    case film
    case flash
    case warmFlash
    case iwai
    case cross
    case double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: return "フィルム"
        case .flash: return "フラッシュ"
        case .warmFlash: return "暖フラッシュ"
        case .iwai: return "岩井俊二風"
        case .cross: return "クロス"
        case .double: return "多重露光"
        }
    }

    /// 距離（LiDAR など）を使うモードか
    var usesDepth: Bool { self == .flash || self == .warmFlash }

    var caption: String {
        switch self {
        case .film: return "低いコントラスト・暖かい白・にじむ光"
        case .flash: return "直射フラッシュのコンデジ写真"
        case .warmFlash: return "暖かい色のフラッシュ写真"
        case .iwai: return "淡い水色・白飛び・やわらかな光"
        case .cross: return "暖色と寒色がぶつかる、濃く硬い色"
        case .double: return "2回シャッターを切って重ねる"
        }
    }
}

/// フィルタにかけるときの設定
struct LookOptions {
    var mode: LookMode
    var dateStamp: Bool
    /// 距離（メートル）。写真や映像と同じ向き。大きさはそろっていなくてよい
    var depth: CIImage? = nil
    /// 主な被写体までの距離（メートル）。フラッシュの光がちょうどよく当たる距離になる
    var subjectDistance: CGFloat? = nil
    /// 多重露光の 1 枚目（向きは適用済み）。あれば今の像に重ねる
    var overlay: CIImage? = nil
    /// 粒子（グレイン）の模様をずらす量。毎フレーム変えると粒子が動いて見える
    var grainSeed: CGPoint = CGPoint(x: CGFloat.random(in: 0..<512), y: CGFloat.random(in: 0..<512))
}
