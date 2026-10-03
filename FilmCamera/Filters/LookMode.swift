import CoreGraphics

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

    var caption: String {
        switch self {
        case .film: return "低いコントラスト・暖かい白・粒子"
        case .flash: return "直射フラッシュのコンデジ写真"
        case .iwai: return "淡い水色・白飛び・やわらかな光"
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
