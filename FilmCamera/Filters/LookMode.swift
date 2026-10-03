import CoreGraphics

/// 撮影モード（見え方）
enum LookMode: String, CaseIterable, Identifiable {
    case film
    case flash
    case instant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: return "フィルム"
        case .flash: return "フラッシュ"
        case .instant: return "インスタント"
        }
    }

    var caption: String {
        switch self {
        case .film: return "色あせ・粒子・周辺減光"
        case .flash: return "中央が明るく、背景が落ちる"
        case .instant: return "淡い色と白フチ（正方形）"
        }
    }
}

/// フィルタにかけるときの設定
struct LookOptions {
    var mode: LookMode
    var dateStamp: Bool
    /// 粒子（グレイン）の模様をずらす量。毎フレーム変えると粒子が動いて見える
    var grainSeed: CGPoint = CGPoint(x: CGFloat.random(in: 0..<512), y: CGFloat.random(in: 0..<512))
}
