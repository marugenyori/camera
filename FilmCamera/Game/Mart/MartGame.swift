import SwiftUI

/// 「まちかどマート」：お店の経営ゲーム（スーパーマーケット・シミュレーション）。
/// 指でなぞって店員を動かし、倉庫の台で商品を受け取り（手の上に高く積んで運ぶ）、棚のそばに行くと並べる。
/// お客さんは棚から商品を取ってレジに並び、店員がレジの奥に立つと会計してお金が出る。お金のそばを通ると拾える。
/// 床の点線の「解放マーク」の上に立つとお金を払い、新しい棚・レジ係・品出し係・運べる数・速さなどが増える。
/// 2 人で遊ぶとき（近くの iPhone と直接つなぐ）は、お店を開いた人（ホスト）がお店を動かし、
/// 遊びに来た人（ゲスト）は自分の位置を送って、ホストから 1 秒に 15 回お店の様子（MartSnapshot）を受け取る。
/// お金は 2 人で共通。座標はお店の床のマス（x は右下、y は左下へ）。描くのは MartScene（SceneKit の 3D）
enum MartProduct: Int, CaseIterable, Codable {
    case soda, snack, noodle, sandwich, fruit, toy, bread, milk, iceCream, flower, cake, game

    var name: String {
        switch self {
        case .soda: return "ジュース"
        case .snack: return "おかし"
        case .noodle: return "カップめん"
        case .sandwich: return "サンド"
        case .fruit: return "くだもの"
        case .toy: return "おもちゃ"
        case .bread: return "パン"
        case .milk: return "牛乳"
        case .iceCream: return "アイス"
        case .flower: return "花束"
        case .cake: return "ケーキ"
        case .game: return "ゲーム"
        }
    }

    var label: String {
        switch self {
        case .soda: return "SODA"
        case .snack: return "SNACK"
        case .noodle: return "NOODLE"
        case .sandwich: return "SANDWICH"
        case .fruit: return "FRUIT"
        case .toy: return "TOY"
        case .bread: return "BREAD"
        case .milk: return "MILK"
        case .iceCream: return "ICE"
        case .flower: return "FLOWER"
        case .cake: return "CAKE"
        case .game: return "GAME"
        }
    }

    var color: UIColor {
        switch self {
        case .soda: return UIColor(red: 0.92, green: 0.2, blue: 0.24, alpha: 1)
        case .snack: return UIColor(red: 1, green: 0.78, blue: 0.15, alpha: 1)
        case .noodle: return UIColor(red: 0.97, green: 0.95, blue: 0.9, alpha: 1)
        case .sandwich: return UIColor(red: 0.98, green: 0.72, blue: 0.4, alpha: 1)
        case .fruit: return UIColor(red: 0.98, green: 0.4, blue: 0.3, alpha: 1)
        case .toy: return UIColor(red: 0.62, green: 0.45, blue: 0.98, alpha: 1)
        case .bread: return UIColor(red: 0.93, green: 0.68, blue: 0.38, alpha: 1)
        case .milk: return UIColor(white: 0.98, alpha: 1)
        case .iceCream: return UIColor(red: 1, green: 0.7, blue: 0.8, alpha: 1)
        case .flower: return UIColor(red: 1, green: 0.45, blue: 0.62, alpha: 1)
        case .cake: return UIColor(red: 1, green: 0.97, blue: 0.94, alpha: 1)
        case .game: return UIColor(red: 0.25, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    /// 絵文字のアイコン（文字の代わりに出す）
    var icon: String {
        switch self {
        case .soda: return "🥤"
        case .snack: return "🍿"
        case .noodle: return "🍜"
        case .sandwich: return "🥪"
        case .fruit: return "🍎"
        case .toy: return "🧸"
        case .bread: return "🍞"
        case .milk: return "🥛"
        case .iceCream: return "🍦"
        case .flower: return "💐"
        case .cake: return "🎂"
        case .game: return "🎮"
        }
    }

    var accent: UIColor {
        switch self {
        case .soda: return UIColor(red: 0.2, green: 0.4, blue: 0.92, alpha: 1)
        case .snack: return UIColor(red: 0.92, green: 0.25, blue: 0.2, alpha: 1)
        case .noodle: return UIColor(red: 0.92, green: 0.3, blue: 0.22, alpha: 1)
        case .sandwich: return UIColor(red: 0.45, green: 0.75, blue: 0.3, alpha: 1)
        case .fruit: return UIColor(red: 0.4, green: 0.75, blue: 0.3, alpha: 1)
        case .toy: return UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        case .bread: return UIColor(red: 0.62, green: 0.4, blue: 0.22, alpha: 1)
        case .milk: return UIColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 1)
        case .iceCream: return UIColor(red: 0.85, green: 0.6, blue: 0.35, alpha: 1)
        case .flower: return UIColor(red: 0.35, green: 0.7, blue: 0.38, alpha: 1)
        case .cake: return UIColor(red: 0.95, green: 0.3, blue: 0.42, alpha: 1)
        case .game: return UIColor(red: 0.25, green: 0.8, blue: 0.9, alpha: 1)
        }
    }

    var price: Int {
        switch self {
        case .soda: return 120
        case .snack: return 150
        case .noodle: return 220
        case .sandwich: return 280
        case .fruit: return 350
        case .toy: return 480
        case .bread: return 300
        case .milk: return 380
        case .iceCream: return 450
        case .flower: return 600
        case .cake: return 800
        case .game: return 1_500
        }
    }
}

/// 円の表示（¥12,340）
enum MartYen {
    static func text(_ value: Int) -> String {
        "¥" + value.formatted(.number.grouping(.automatic))
    }
}

/// 歩く人（店員・お客さん・係）
struct MartWalker: Codable {
    var pos: CGPoint
    /// 向き（床の上の角度。atan2(dy, dx)）
    var heading: CGFloat = .pi * 0.75
    var moving = false
    var step: Double = 0
    var carry: [MartProduct] = []
    /// 運んでいるかご（返しに行く）
    var baskets = 0
}

/// お店の出来事（プレゼント箱・タイムセール・評判・コンボ）
struct MartEvents: Codable, Equatable {
    /// 床に落ちているプレゼント箱（拾うとお金）
    var gift: CGPoint?
    var giftValue = 0
    /// タイムセールの残り秒（0 ならふだん）
    var saleTime: Double = 0
    /// お店の評判（1〜5）。喜んだ客で上がり、怒った客で下がる。高いほどお客さんがよく来る
    var rating: Double = 3
    /// レジのコンボ（続けて会計すると増える）
    var combo = 0
    /// ガチャで当てた「スピードアップ」の残り秒
    var boostTime: Double = 0
    /// ガチャで当てた「VIP がまとめて来る」の残り人数
    var vipRush = 0
}

/// ガチャの景品
enum MartPrize: String, Codable, CaseIterable {
    case jackpot, coins, speed, refill, vipRush, lucky

    var icon: String {
        switch self {
        case .jackpot: return "💰"
        case .coins: return "🪙"
        case .speed: return "⚡"
        case .refill: return "📦"
        case .vipRush: return "👑"
        case .lucky: return "🍀"
        }
    }

    var title: String {
        switch self {
        case .jackpot: return "大当たり！"
        case .coins: return "半分もどってきた"
        case .speed: return "30 秒スピードアップ"
        case .refill: return "全部の売り場が満タン"
        case .vipRush: return "VIP が 5 人来る"
        case .lucky: return "レジのお金が 2 倍"
        }
    }

    /// 当たりやすさ（合計 100）
    var weight: Int {
        switch self {
        case .jackpot: return 8
        case .coins: return 27
        case .speed: return 20
        case .refill: return 20
        case .vipRush: return 15
        case .lucky: return 10
        }
    }
}

struct MartCustomer: Identifiable, Codable {
    enum Phase: String, Codable { case toBasket, toShelf, shopping, toQueue, queued, selfPay, leaving }
    /// ふつう・VIP（たくさん買って 3 倍払う）・どろぼう（商品を取って逃げる。店員がさわると捕まえられる）
    enum Kind: String, Codable { case normal, vip, thief }
    var kind: Kind = .normal
    /// セルフレジを使うときの台の番号（-1 = 使わない）
    var machine = -1
    var id = UUID()
    var walker: MartWalker
    var phase: Phase = .toShelf
    var product: MartProduct
    var want: Int
    var got = 0
    var path: [CGPoint] = []
    var timer: Double = 0
    var shirt: Int
    /// 待たされた時間（長すぎると怒って帰る）
    var waited: Double = 0
    var angry = false
    /// かごを持っているか
    var basket = false
}

struct MartHelper: Codable {
    enum Phase: String, Codable { case idle, toSupply, loading, toShelf, unloading }
    var walker: MartWalker
    var phase: Phase = .idle
    var target: MartProduct = .soda
    var path: [CGPoint] = []
    var timer: Double = 0
}

/// 解放マーク（お金を払うと何かが増える）
struct MartStep {
    enum Kind: Equatable { case shelf(Int), cashier, stocker, capacity, speed, customers, expand }
    let kind: Kind
    let cost: Int
    let pos: CGPoint

    var title: String {
        switch kind {
        case .shelf(let k): return (MartProduct(rawValue: k)?.name ?? "") + "の棚"
        case .cashier: return "レジ係"
        case .stocker: return "品出し係"
        case .capacity: return "運べる数 +2"
        case .speed: return "スピードアップ"
        case .customers: return "お客さん +3"
        case .expand: return "お店を広げる"
        }
    }

    var symbol: String {
        switch kind {
        case .shelf: return "cabinet.fill"
        case .cashier: return "person.crop.square.fill"
        case .stocker: return "figure.walk"
        case .capacity: return "shippingbox.fill"
        case .speed: return "hare.fill"
        case .customers: return "person.3.fill"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// ゲストに送るお店の様子
/// アップグレード（床の UPGRADE の場所で、お金を払ってレベルを上げる）
enum MartUpgrade: String, CaseIterable, Codable, Identifiable {
    case capacity, speed, price, cashier, staff, hire, baskets, ads, tips, selfCheckout
    var id: String { rawValue }
    static let maxLevel = 5

    var title: String {
        switch self {
        case .capacity: return "運べる数"
        case .speed: return "歩く速さ"
        case .price: return "売値"
        case .cashier: return "レジのスピード"
        case .staff: return "係のスピード"
        case .hire: return "品出し係を雇う"
        case .baskets: return "かご係を雇う"
        case .ads: return "宣伝（お客さん）"
        case .tips: return "チップの確率"
        case .selfCheckout: return "セルフレジ"
        }
    }

    var symbol: String {
        switch self {
        case .capacity: return "shippingbox.fill"
        case .speed: return "figure.run"
        case .price: return "yensign.circle.fill"
        case .cashier: return "barcode.viewfinder"
        case .staff: return "person.2.fill"
        case .hire: return "person.badge.plus"
        case .baskets: return "basket.fill"
        case .ads: return "megaphone.fill"
        case .tips: return "heart.circle.fill"
        case .selfCheckout: return "creditcard.fill"
        }
    }

    func effect(_ level: Int) -> String {
        switch self {
        case .capacity: return "+\(level * 2) 個"
        case .speed: return "+\(level * 12)%"
        case .price: return "+\(level * 15)%"
        case .cashier: return "+\(level * 20)%"
        case .staff: return "+\(level * 20)%"
        case .hire: return "+\(level) 人"
        case .baskets: return "+\(level) 人"
        case .ads: return "+\(level) 人"
        case .tips: return "\(level * 10)%"
        case .selfCheckout: return level <= 3 ? "\(level) 台" : "3 台・速さ+\((level - 3) * 25)%"
        }
    }

    func cost(_ level: Int) -> Int {
        let base: Double
        switch self {
        case .capacity: base = 1_500
        case .speed: base = 1_200
        case .price: base = 2_500
        case .cashier: base = 1_800
        case .staff: base = 2_200
        case .hire: base = 8_000
        case .baskets: base = 3_000
        case .ads: base = 4_000
        case .tips: base = 5_000
        case .selfCheckout: base = 6_000
        }
        return Int((base * pow(2.1, Double(level)) / 100).rounded()) * 100
    }
}

/// クエスト（目標）。こなすと報酬
struct MartQuest {
    enum Kind: Int, Codable { case shelve, serve, earn }
    let kind: Kind
    let target: Int
    let reward: Int

    static func make(_ index: Int) -> MartQuest {
        let round = index / 3
        switch index % 3 {
        case 0: return MartQuest(kind: .shelve, target: 12 + round * 10, reward: 800 + round * 900)
        case 1: return MartQuest(kind: .serve, target: 4 + round * 3, reward: 1_000 + round * 1_000)
        default: return MartQuest(kind: .earn, target: 2_000 + round * 2_500, reward: 1_200 + round * 1_400)
        }
    }

    var title: String {
        switch kind {
        case .shelve: return "商品を \(target) 個並べる"
        case .serve: return "お客さん \(target) 人をお会計"
        case .earn: return "\(MartYen.text(target)) かせぐ"
        }
    }

    var symbol: String {
        switch kind {
        case .shelve: return "shippingbox.fill"
        case .serve: return "person.2.fill"
        case .earn: return "banknote.fill"
        }
    }
}

/// これまでの数（クエストに使う）
struct MartStats: Codable {
    var shelved = 0
    var served = 0
    var earned = 0

    func value(_ kind: MartQuest.Kind) -> Int {
        switch kind {
        case .shelve: return shelved
        case .serve: return served
        case .earn: return earned
        }
    }
}

struct MartSnapshot: Codable {
    var players: [MartWalker]
    var customers: [MartCustomer]
    var helpers: [MartWalker]
    var stock: [Int]
    var cash: Int
    var money: Int
    var done: [Int]
    var paid: [Int: Int]
    var serving: Double
    var stats: MartStats
    var questIndex: Int
    var questBase: Int
    var standBaskets: Int
    var returnedBaskets: Int
    var upgrades: [MartUpgrade: Int]
    var basketHelpers: [MartWalker]
    var events: MartEvents
}

@MainActor
final class MartGame: ObservableObject {
    enum Role { case solo, host, guest }

    // 店の形
    nonisolated static let floor = CGRect(x: 0, y: 0, width: 22, height: 16)
    nonisolated static let counter = CGRect(x: 19.2, y: 3.5, width: 1.2, height: 3.0)
    nonisolated static let cashierSpot = CGPoint(x: 21.15, y: 5.0)
    nonisolated static let serveSpot = CGPoint(x: 18.35, y: 5.0)
    nonisolated static let cashSpot = CGPoint(x: 19.9, y: 8.3)
    nonisolated static let door = CGPoint(x: 21.7, y: 14.5)
    nonisolated static let outside = CGPoint(x: 25, y: 14.5)
    nonisolated static let shelfCapacity = 8
    /// かご置き場（入口のそば）と、使い終わったかごがたまる場所（レジのそば）
    nonisolated static let basketStand = CGPoint(x: 20.3, y: 12.4)
    nonisolated static let basketReturn = CGPoint(x: 16.4, y: 10.4)
    nonisolated static let basketStandMax = 12
    /// ゴミ箱（間違えて取った商品を捨てる）
    nonisolated static let trashSpot = CGPoint(x: 3.2, y: 10.6)
    /// セルフレジ（右の壁ぞい、最大 3 台）。台の前にお客さんが立つ
    nonisolated static func selfMachine(_ index: Int) -> CGPoint { CGPoint(x: 21.25, y: 7.4 + 1.4 * CGFloat(index)) }
    nonisolated static func selfStand(_ index: Int) -> CGPoint { CGPoint(x: 20.4, y: 7.4 + 1.4 * CGFloat(index)) }
    /// ガチャの台
    nonisolated static let gachaSpot = CGPoint(x: 10.6, y: 15.0)
    /// アップグレードの場所（左下）
    nonisolated static let upgradeZone = CGRect(x: 12.6, y: 14.0, width: 2.6, height: 1.6)
    /// 広げるごとにのびる奥行き
    nonisolated static let areaDepth: CGFloat = 7

    /// 売り場の向き（お客さんが立つ側）
    enum Facing { case south, north, east, west }

    /// 売り場の置き方：中心・向き・長さ（商品が並ぶ方向）・奥行き。本家のように、壁ぞいの冷蔵庫や島の台をばらばらに置く
    nonisolated static let layout: [(center: CGPoint, facing: Facing, length: CGFloat, depth: CGFloat)] = [
        (CGPoint(x: 5.4, y: 0.75), .south, 2.8, 0.9),   // ジュース：奥の壁の冷蔵庫
        (CGPoint(x: 4.6, y: 5.6), .east, 2.4, 1.0),     // おかし：縦向きの台
        (CGPoint(x: 9.6, y: 0.7), .south, 2.6, 0.8),    // カップめん：奥の壁の棚
        (CGPoint(x: 14.2, y: 0.75), .south, 2.8, 0.9),  // サンド：奥の壁の冷蔵庫
        (CGPoint(x: 9.4, y: 5.2), .north, 2.6, 1.2),    // くだもの：木箱の島
        (CGPoint(x: 15.6, y: 7.0), .west, 2.4, 1.0),    // おもちゃ：右の島
        (CGPoint(x: 6.2, y: 9.2), .south, 2.4, 1.0),    // パン：パン屋の台
        (CGPoint(x: 12.2, y: 8.6), .north, 2.6, 1.0),   // 牛乳：低い冷蔵台
        (CGPoint(x: 6.0, y: 18.4), .south, 2.4, 1.2),   // アイス：冷凍ケース（スイーツのエリア）
        (CGPoint(x: 11.0, y: 20.6), .north, 2.6, 1.0),  // ケーキ：ショーケース
        (CGPoint(x: 6.0, y: 26.0), .east, 2.4, 1.0),    // 花束：花のバケツ（ギフトのエリア）
        (CGPoint(x: 13.0, y: 27.4), .north, 3.0, 1.0),  // ゲーム：ゲームの台
    ]

    nonisolated static func shelfRect(_ k: Int) -> CGRect {
        let place = layout[min(max(k, 0), layout.count - 1)]
        let size = place.facing == .south || place.facing == .north
            ? CGSize(width: place.length, height: place.depth) : CGSize(width: place.depth, height: place.length)
        return CGRect(x: place.center.x - size.width / 2, y: place.center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// お客さんが立って商品を取る場所（売り場の手前）
    nonisolated static func shelfFront(_ k: Int) -> CGPoint {
        let rect = shelfRect(k)
        switch layout[min(max(k, 0), layout.count - 1)].facing {
        case .south: return CGPoint(x: rect.midX, y: rect.maxY + 0.7)
        case .north: return CGPoint(x: rect.midX, y: rect.minY - 0.7)
        case .east: return CGPoint(x: rect.maxX + 0.7, y: rect.midY)
        case .west: return CGPoint(x: rect.minX - 0.7, y: rect.midY)
        }
    }

    /// 倉庫の台（左の壁ぞい）
    nonisolated static func supplySpot(_ k: Int) -> CGPoint {
        CGPoint(x: 1.6, y: 2.2 + 1.75 * CGFloat(k))
    }

    nonisolated static let steps: [MartStep] = baseSteps + moreSteps + endlessSteps

    private nonisolated static let baseSteps: [MartStep] = [
        MartStep(kind: .shelf(1), cost: 600, pos: CGPoint(x: shelfRect(1).midX, y: shelfRect(1).midY)),
        MartStep(kind: .capacity, cost: 1200, pos: CGPoint(x: 7.6, y: 12.6)),
        MartStep(kind: .shelf(2), cost: 2100, pos: CGPoint(x: shelfRect(2).midX, y: shelfRect(2).midY)),
        MartStep(kind: .cashier, cost: 3000, pos: CGPoint(x: 21.15, y: 2.4)),
        MartStep(kind: .shelf(3), cost: 4500, pos: CGPoint(x: shelfRect(3).midX, y: shelfRect(3).midY)),
        MartStep(kind: .speed, cost: 4200, pos: CGPoint(x: 10.8, y: 12.6)),
        MartStep(kind: .stocker, cost: 6600, pos: CGPoint(x: 4.4, y: 12.6)),
        MartStep(kind: .shelf(4), cost: 7800, pos: CGPoint(x: shelfRect(4).midX, y: shelfRect(4).midY)),
        MartStep(kind: .customers, cost: 6000, pos: CGPoint(x: 14.0, y: 12.6)),
        MartStep(kind: .capacity, cost: 9600, pos: CGPoint(x: 7.6, y: 12.6)),
        MartStep(kind: .shelf(5), cost: 12600, pos: CGPoint(x: shelfRect(5).midX, y: shelfRect(5).midY)),
        MartStep(kind: .stocker, cost: 15000, pos: CGPoint(x: 4.4, y: 12.6)),
        MartStep(kind: .customers, cost: 13500, pos: CGPoint(x: 14.0, y: 12.6)),
        MartStep(kind: .speed, cost: 18000, pos: CGPoint(x: 10.8, y: 12.6)),
    ]

    /// 2 列目の残りの棚・お店を広げる・奥の列の棚（あとから足したので、保存の番号を変えないよう後ろに続ける）
    private nonisolated static let moreSteps: [MartStep] = [
        MartStep(kind: .shelf(6), cost: 22_000, pos: CGPoint(x: shelfRect(6).midX, y: shelfRect(6).midY)),
        MartStep(kind: .stocker, cost: 26_000, pos: CGPoint(x: 4.4, y: 12.6)),
        MartStep(kind: .shelf(7), cost: 32_000, pos: CGPoint(x: shelfRect(7).midX, y: shelfRect(7).midY)),
        MartStep(kind: .expand, cost: 45_000, pos: CGPoint(x: 8.0, y: 14.9)),
        MartStep(kind: .shelf(8), cost: 52_000, pos: CGPoint(x: shelfRect(8).midX, y: shelfRect(8).midY)),
        MartStep(kind: .customers, cost: 60_000, pos: CGPoint(x: 14.0, y: 12.6)),
        MartStep(kind: .stocker, cost: 66_000, pos: CGPoint(x: 4.4, y: 12.6)),
        MartStep(kind: .shelf(9), cost: 75_000, pos: CGPoint(x: shelfRect(9).midX, y: shelfRect(9).midY)),
        MartStep(kind: .capacity, cost: 82_000, pos: CGPoint(x: 7.6, y: 12.6)),
        MartStep(kind: .expand, cost: 110_000, pos: CGPoint(x: 15.0, y: 21.6)),
        MartStep(kind: .shelf(10), cost: 120_000, pos: CGPoint(x: shelfRect(10).midX, y: shelfRect(10).midY)),
        MartStep(kind: .stocker, cost: 128_000, pos: CGPoint(x: 4.4, y: 12.6)),
        MartStep(kind: .shelf(11), cost: 140_000, pos: CGPoint(x: shelfRect(11).midX, y: shelfRect(11).midY)),
        MartStep(kind: .speed, cost: 150_000, pos: CGPoint(x: 10.8, y: 12.6)),
    ]

    /// そのあとも、係・お客さん・運べる数を順に増やし続ける（値段は少しずつ上がる）
    private nonisolated static let endlessSteps: [MartStep] = (0..<30).map { index in
        let kinds: [(MartStep.Kind, CGPoint)] = [(.stocker, CGPoint(x: 4.4, y: 12.6)), (.customers, CGPoint(x: 14.0, y: 12.6)),
                                                 (.capacity, CGPoint(x: 7.6, y: 12.6))]
        let (kind, pos) = kinds[index % kinds.count]
        let cost = Int((160_000 * pow(1.22, Double(index)) / 1_000).rounded()) * 1_000
        return MartStep(kind: kind, cost: cost, pos: pos)
    }

    let role: Role
    /// 自分の店員（players の番号。ゲストは 1）
    var me: Int { role == .guest ? 1 : 0 }

    @Published private(set) var money = 0
    @Published private(set) var level = 0
    /// 解放したときの合図（画面に出す文）
    @Published var banner: String?
    /// 留守のあいだにかせいだお金（開いたときに見せる）
    @Published var offlineEarned = 0
    @Published private(set) var stats = MartStats()
    @Published private(set) var questIndex = 0
    /// いまのクエストを始めたときの数
    @Published private(set) var questBase = 0

    private(set) var players: [MartWalker] = [MartWalker(pos: CGPoint(x: 9.0, y: 13.5))]
    private(set) var customers: [MartCustomer] = []
    private(set) var helpers: [MartHelper] = []
    private(set) var events = MartEvents()
    /// 画面に出す：タイムセールの残り秒・評判（0.5 きざみ）
    @Published private(set) var saleSeconds = 0
    @Published private(set) var stars: Double = 3
    private var giftTimer: Double = 25
    /// セルフレジの台の数
    var selfMachines: Int { min(upgradeLevel(.selfCheckout), 3) }
    /// このコマで使われているセルフレジ（お客さんの配列を書き換え中に読まないよう、先に調べておく）
    private var claimedMachines: Set<Int> = []
    /// ガチャの台のそばにいる
    @Published private(set) var atGacha = false
    /// いま当てた景品（画面に出す）
    @Published var lastPrize: MartPrize?
    /// ゲストのとき、ガチャをホストに頼む
    var onGacha: (() -> Void)?
    /// 画面に出す：スピードアップの残り秒
    @Published private(set) var boostSeconds = 0

    /// ガチャ 1 回の値段（お店が育つほど高い）
    var gachaCost: Int { max(500, (level + 1) * 600) / 100 * 100 }

    /// ガチャを回す（ゲストはホストに頼む）
    func spinGacha() {
        if role == .guest {
            onGacha?()
            return
        }
        guard money >= gachaCost else {
            GameAudio.shared.play(.invalid)
            return
        }
        let cost = gachaCost
        money -= cost
        var roll = Int.random(in: 0..<100)
        var prize = MartPrize.coins
        for candidate in MartPrize.allCases {
            if roll < candidate.weight {
                prize = candidate
                break
            }
            roll -= candidate.weight
        }
        switch prize {
        case .jackpot: money += cost * 5
        case .coins: money += cost / 2
        case .speed: events.boostTime = 30
        case .refill: for k in unlocked { stock[k] = Self.shelfCapacity }
        case .vipRush: events.vipRush += 5
        case .lucky: cash += max(cash, cost * 2)
        }
        lastPrize = prize
        banner = "\(prize.icon) \(prize.title)"
        GameAudio.shared.play(prize == .coins ? .tap : .win)
        save()
    }
    private var saleCooldown: Double = 90
    private var comboTimer: Double = 0

    private func publishEvents() {
        let seconds = Int(events.saleTime.rounded(.up))
        if seconds != saleSeconds { saleSeconds = seconds }
        let boost = Int(events.boostTime.rounded(.up))
        if boost != boostSeconds { boostSeconds = boost }
        let shown = (events.rating * 2).rounded() / 2
        if shown != stars { stars = shown }
    }

    /// 評判を変える
    private func rate(_ amount: Double) {
        events.rating = min(max(events.rating + amount, 1), 5)
    }

    /// かご係（使い終わったかごを、かご置き場へ戻す）
    private(set) var basketHelpers: [MartHelper] = []
    private(set) var stock: [Int] = Array(repeating: 0, count: MartProduct.allCases.count)
    private(set) var unlocked: Set<Int> = [0]
    private(set) var done: Set<Int> = []
    private(set) var paid: [Int: Int] = [:]
    /// レジの横にたまったお金
    private(set) var cash = 0
    private(set) var hasCashier = false
    private(set) var capacity = 4
    private(set) var speed: CGFloat = 4.3
    private(set) var maxCustomers = 5
    /// お店を広げた回数（1 回で床が 7 のびる。1 回目はスイーツ、2 回目はギフトのエリア）
    private(set) var expansions = 0
    var expanded: Bool { expansions > 0 }
    var floorRect: CGRect { CGRect(x: 0, y: 0, width: Self.floor.width, height: Self.floor.height + Self.areaDepth * CGFloat(expansions)) }
    /// かご置き場のかご・返ってきたかご
    private(set) var standBaskets = 6
    private(set) var returnedBaskets = 0
    private var basketTimer: Double = 0
    /// アップグレードのレベル
    @Published private(set) var upgrades: [MartUpgrade: Int] = [:]
    /// 自分の店員がアップグレードの場所にいる
    @Published private(set) var atUpgrade = false
    /// ゲストのとき、アップグレードをホストに頼む
    var onUpgrade: ((MartUpgrade) -> Void)?

    func upgradeLevel(_ upgrade: MartUpgrade) -> Int { upgrades[upgrade] ?? 0 }

    func buyUpgrade(_ upgrade: MartUpgrade) {
        let level = upgradeLevel(upgrade)
        guard level < MartUpgrade.maxLevel else { return }
        if role == .guest {
            onUpgrade?(upgrade)
            return
        }
        let cost = upgrade.cost(level)
        guard money >= cost else {
            GameAudio.shared.play(.invalid)
            return
        }
        money -= cost
        upgrades[upgrade] = level + 1
        rebuildUnlocks()
        banner = "⬆️ \(upgrade.title) Lv.\(level + 1)"
        GameAudio.shared.play(.complete)
        save()
    }

    /// 売値（アップグレードで上がる）
    func sale(_ product: MartProduct, count: Int) -> Int {
        Int(Double(product.price * count) * (1 + 0.15 * Double(upgradeLevel(.price))))
    }

    /// 会計の進み具合（0〜1）
    private(set) var serving: Double = 0
    /// 指で動かす向き（画面から入れる。長さ 0〜1）
    var stick: CGVector = .zero

    private var queue: [UUID] = []
    private var spawnTimer: Double = 1
    private var pickTimers: [Double] = [0, 0]
    private var dropTimers: [Double] = [0, 0]
    private var cashTimer: Double = 0
    private var payCarry: Double = 0
    /// 続けて拾った金額
    private var haul = 0
    private var saveTimer: Double = 0
    private var soundTimer: Double = 0

    init(role: Role) {
        self.role = role
        if role != .guest { load() }
        if role == .guest {
            players.append(MartWalker(pos: CGPoint(x: 10.0, y: 13.9)))
        }
    }

    var unlockedProducts: [MartProduct] {
        MartProduct.allCases.filter { unlocked.contains($0.rawValue) }
    }

    /// いま見せる解放マーク（まだのものから順に 2 つ）
    var visibleSteps: [(Int, MartStep)] {
        // まだ広げていないときは、床の外のマークは出さない
        Self.steps.enumerated().filter { !done.contains($0.offset) && $0.element.pos.y < floorRect.maxY }
            .prefix(2).map { ($0.offset, $0.element) }
    }

    func paidAmount(_ index: Int) -> Int { paid[index] ?? 0 }

    var quest: MartQuest { MartQuest.make(questIndex) }
    var questProgress: Int { max(0, min(stats.value(quest.kind) - questBase, quest.target)) }
    var questDone: Bool { questProgress >= quest.target }

    /// クエストの報酬を受け取る（ゲストのときはホストに頼む）
    var onClaim: (() -> Void)?

    func claimQuest() {
        guard questDone else { return }
        if role == .guest {
            onClaim?()
            return
        }
        money += quest.reward
        banner = "🏆 クエスト達成！ +\(MartYen.text(quest.reward))"
        GameAudio.shared.play(.win)
        questIndex += 1
        questBase = stats.value(quest.kind)
        save()
    }

    // MARK: - 2 人

    /// ゲストが来た（ホスト）
    func addGuest() {
        guard players.count < 2 else { return }
        players.append(MartWalker(pos: CGPoint(x: 10.0, y: 13.9)))
        banner = "🤝 友だちが来ました"
    }

    func removeGuest() {
        guard role == .host, players.count > 1 else { return }
        players.removeLast()
    }

    /// ゲストの位置を受け取る（ホスト）
    func setGuest(_ walker: MartWalker) {
        guard players.count > 1 else { addGuest(); return }
        players[1].pos = walker.pos
        players[1].heading = walker.heading
        players[1].moving = walker.moving
        players[1].step = walker.step
    }

    func snapshot() -> MartSnapshot {
        MartSnapshot(players: players, customers: customers, helpers: helpers.map(\.walker), stock: stock, cash: cash,
                     money: money, done: Array(done), paid: paid, serving: serving, stats: stats,
                     questIndex: questIndex, questBase: questBase, standBaskets: standBaskets,
                     returnedBaskets: returnedBaskets, upgrades: upgrades, basketHelpers: basketHelpers.map(\.walker), events: events)
    }

    /// ホストから届いたお店の様子を当てはめる（ゲスト。自分の位置はそのまま）
    func apply(_ snapshot: MartSnapshot) {
        let mine = players.indices.contains(me) ? players[me] : nil
        players = snapshot.players
        while players.count < 2 { players.append(MartWalker(pos: CGPoint(x: 10.0, y: 13.9))) }
        if let mine {
            players[me].pos = mine.pos
            players[me].heading = mine.heading
            players[me].moving = mine.moving
            players[me].step = mine.step
        }
        customers = snapshot.customers
        helpers = snapshot.helpers.map { MartHelper(walker: $0) }
        basketHelpers = snapshot.basketHelpers.map { MartHelper(walker: $0) }
        events = snapshot.events
        publishEvents()
        stock = snapshot.stock
        cash = snapshot.cash
        money = snapshot.money
        paid = snapshot.paid
        serving = snapshot.serving
        if snapshot.questIndex > questIndex { banner = "🏆 クエスト達成！" }
        stats = snapshot.stats
        questIndex = snapshot.questIndex
        questBase = snapshot.questBase
        standBaskets = snapshot.standBaskets
        returnedBaskets = snapshot.returnedBaskets
        if upgrades != snapshot.upgrades {
            upgrades = snapshot.upgrades
            rebuildUnlocks()
        }
        let newDone = Set(snapshot.done)
        if newDone != done {
            let added = newDone.subtracting(done)
            done = newDone
            rebuildUnlocks()
            if let index = added.max(), Self.steps.indices.contains(index) {
                banner = "🎉 \(Self.steps[index].title)"
            }
        }
    }

    // MARK: - 1 コマ進める

    func update(_ dt: Double) {
        soundTimer -= dt
        movePlayer(me, dt)
        if players.indices.contains(me) {
            let inside = Self.upgradeZone.insetBy(dx: -0.3, dy: -0.3).contains(players[me].pos)
            if inside != atUpgrade { atUpgrade = inside }
            let near = distance(players[me].pos, Self.gachaSpot) < 1.0
            if near != atGacha { atGacha = near }
        }
        guard role != .guest else { return }
        for index in players.indices { handleSupplyAndShelves(index, dt) }
        handleRegister(dt)
        handleBaskets(dt)
        handleCash(dt)
        handlePads(dt)
        handleEvents(dt)
        spawnCustomers(dt)
        claimedMachines = Set(customers.map(\.machine).filter { $0 >= 0 })
        for index in customers.indices { updateCustomer(&customers[index], dt) }
        catchThieves()
        // 逃げきったどろぼう：商品はなくなり、評判が下がる
        if customers.contains(where: { $0.kind == .thief && $0.phase == .leaving && $0.path.isEmpty && $0.got > 0 }) {
            banner = "💨 にげられた…"
            rate(-0.3)
        }
        customers.removeAll { $0.phase == .leaving && $0.path.isEmpty }
        publishEvents()
        for index in helpers.indices {
            // ほかの係が向かっている棚（書き換え中の配列を読まないよう、先に調べる）
            let busy = Set(helpers.enumerated().filter { $0.offset != index && $0.element.phase != .idle }.map(\.element.target))
            updateHelper(&helpers[index], busy: busy, dt)
        }
        for index in basketHelpers.indices { updateBasketHelper(&basketHelpers[index], dt) }
        saveTimer += dt
        if saveTimer > 5 {
            saveTimer = 0
            save()
        }
    }

    /// 自分の店員の速さ（歩き出し・止まりをなめらかにするため、指の向きへ少しずつ近づける）
    private var velocity = CGVector.zero

    private func movePlayer(_ index: Int, _ dt: Double) {
        guard players.indices.contains(index) else { return }
        // 画面の向き → 床の向き（右手前ななめ上から見下ろしているので変換する）
        let sx = stick.dx, sy = stick.dy
        let length = min((sx * sx + sy * sy).squareRoot(), 1)
        var want = CGVector.zero
        if length > 0.08 {
            var wx = 0.707 * sx + sy
            var wy = sy - 0.707 * sx
            let norm = (wx * wx + wy * wy).squareRoot()
            wx /= norm
            wy /= norm
            let boost: CGFloat = events.boostTime > 0 ? 1.5 : 1
            want = CGVector(dx: wx * speed * boost * length, dy: wy * speed * boost * length)
        }
        // 加速は速く、止まるのは少しだけゆっくり
        let rate: CGFloat = length > 0.08 ? 16 : 11
        let blend = 1 - CGFloat(exp(-Double(rate) * dt))
        velocity.dx += (want.dx - velocity.dx) * blend
        velocity.dy += (want.dy - velocity.dy) * blend
        let moved = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        guard moved > 0.05 else {
            velocity = .zero
            players[index].moving = false
            return
        }
        let start = players[index].pos
        var next = start
        next.x += velocity.dx * CGFloat(dt)
        if blocked(next) {
            next.x = start.x
            velocity.dx = 0
        }
        next.y += velocity.dy * CGFloat(dt)
        if blocked(next) {
            next.y = start.y
            velocity.dy = 0
        }
        players[index].pos = next
        players[index].moving = moved > 0.3
        players[index].step += Double(moved) * dt
        if length > 0.08 { players[index].heading = atan2(want.dy, want.dx) }
    }

    /// 店員がそこに立てないか（壁・棚・レジ台）
    private func blocked(_ point: CGPoint) -> Bool {
        let r: CGFloat = 0.28
        let inner = floorRect.insetBy(dx: r + 0.1, dy: r + 0.1)
        if !inner.contains(point) { return true }
        return obstacles.contains { $0.insetBy(dx: -r, dy: -r).contains(point) }
    }

    /// 通れない場所：レジ台・ゴミ箱・売り場・倉庫の台
    private var obstacles: [CGRect] {
        var walls = [Self.counter, CGRect(x: Self.trashSpot.x - 0.3, y: Self.trashSpot.y - 0.3, width: 0.6, height: 0.6)]
        walls += unlocked.map { Self.shelfRect($0) }
        for index in 0..<selfMachines {
            let machine = Self.selfMachine(index)
            walls.append(CGRect(x: machine.x - 0.3, y: machine.y - 0.35, width: 0.6, height: 0.7))
        }
        walls.append(CGRect(x: Self.gachaSpot.x - 0.3, y: Self.gachaSpot.y - 0.3, width: 0.6, height: 0.6))
        for k in unlocked {
            let spot = Self.supplySpot(k)
            walls.append(CGRect(x: spot.x - 1.1, y: spot.y - 0.5, width: 0.75, height: 1.0))
        }
        return walls
    }

    // MARK: - 道さがし（売り場をよけて歩く）

    private static let cell: CGFloat = 0.4
    private var grid: (key: Int, columns: Int, rows: Int, open: [Bool])?

    /// 通れるマスの表（売り場が増えたり床が広がったときだけ作り直す）
    private func walkGrid() -> (columns: Int, rows: Int, open: [Bool]) {
        let key = unlocked.reduce((expansions << 20) + (selfMachines << 16)) { $0 + 1 << $1 }
        if let grid, grid.key == key { return (grid.columns, grid.rows, grid.open) }
        let floor = floorRect
        let columns = Int(floor.width / Self.cell), rows = Int(floor.height / Self.cell)
        let walls = obstacles.map { $0.insetBy(dx: -0.3, dy: -0.3) }
        var open = [Bool](repeating: true, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(x: (CGFloat(column) + 0.5) * Self.cell, y: (CGFloat(row) + 0.5) * Self.cell)
                if walls.contains(where: { $0.contains(point) }) { open[row * columns + column] = false }
            }
        }
        grid = (key, columns, rows, open)
        return (columns, rows, open)
    }

    /// from から to まで、売り場をよけた道すじ（最後は to ちょうど）。見つからなければまっすぐ
    func route(from: CGPoint, to: CGPoint) -> [CGPoint] {
        let (columns, rows, open) = walkGrid()
        func index(_ point: CGPoint) -> Int {
            let column = min(max(Int(point.x / Self.cell), 0), columns - 1)
            let row = min(max(Int(point.y / Self.cell), 0), rows - 1)
            return row * columns + column
        }
        func center(_ index: Int) -> CGPoint {
            CGPoint(x: (CGFloat(index % columns) + 0.5) * Self.cell, y: (CGFloat(index / columns) + 0.5) * Self.cell)
        }
        /// いちばん近い通れるマス
        func nearestOpen(_ start: Int) -> Int {
            if open[start] { return start }
            var seen: Set<Int> = [start]
            var queue = [start]
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                if open[current] { return current }
                for next in [current - 1, current + 1, current - columns, current + columns] where next >= 0 && next < open.count && !seen.contains(next) {
                    seen.insert(next)
                    queue.append(next)
                }
            }
            return start
        }
        let start = nearestOpen(index(from)), goal = nearestOpen(index(to))
        // A*（8 方向。角をすり抜けない）
        var cost = [CGFloat](repeating: .infinity, count: open.count)
        var parent = [Int](repeating: -1, count: open.count)
        var heap: [(CGFloat, Int)] = [(0, start)]
        cost[start] = 0
        let goalPoint = center(goal)
        func push(_ item: (CGFloat, Int)) {
            heap.append(item)
            var child = heap.count - 1
            while child > 0 {
                let up = (child - 1) / 2
                guard heap[child].0 < heap[up].0 else { break }
                heap.swapAt(child, up)
                child = up
            }
        }
        func pop() -> (CGFloat, Int) {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var node = 0
                while true {
                    let left = node * 2 + 1, right = left + 1
                    var smallest = node
                    if left < heap.count, heap[left].0 < heap[smallest].0 { smallest = left }
                    if right < heap.count, heap[right].0 < heap[smallest].0 { smallest = right }
                    if smallest == node { break }
                    heap.swapAt(node, smallest)
                    node = smallest
                }
            }
            return top
        }
        var found = false
        while !heap.isEmpty {
            let (_, current) = pop()
            if current == goal {
                found = true
                break
            }
            let column = current % columns, row = current / columns
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nc = column + dx, nr = row + dy
                    guard nc >= 0, nc < columns, nr >= 0, nr < rows else { continue }
                    let next = nr * columns + nc
                    guard open[next] else { continue }
                    if dx != 0 && dy != 0 && (!open[row * columns + nc] || !open[nr * columns + column]) { continue }
                    let step: CGFloat = dx != 0 && dy != 0 ? 1.414 : 1
                    let total = cost[current] + step
                    guard total < cost[next] else { continue }
                    cost[next] = total
                    parent[next] = current
                    let p = center(next)
                    push((total + hypot(p.x - goalPoint.x, p.y - goalPoint.y) / Self.cell, next))
                }
            }
        }
        guard found else { return [to] }
        var cells: [Int] = []
        var current = goal
        while current != start, current >= 0 {
            cells.append(current)
            current = parent[current]
        }
        let points = cells.reversed().map(center) + [to]
        // 見通せるところは、まっすぐつなぐ（カクカクしない）
        func clear(_ a: CGPoint, _ b: CGPoint) -> Bool {
            let steps = max(Int(hypot(b.x - a.x, b.y - a.y) / (Self.cell * 0.5)), 1)
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let at = index(p)
                if !open[at], at != goal, at != index(to) { return false }
            }
            return true
        }
        var result: [CGPoint] = []
        var anchor = from
        var i = 0
        while i < points.count {
            var far = i
            while far + 1 < points.count, clear(anchor, points[far + 1]) { far += 1 }
            result.append(points[far])
            anchor = points[far]
            i = far + 1
        }
        return result
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func handleSupplyAndShelves(_ index: Int, _ dt: Double) {
        pickTimers[index] -= dt
        dropTimers[index] -= dt
        let pos = players[index].pos
        // 使い終わったかご：手が空いていれば拾い、かご置き場で返す
        if players[index].carry.isEmpty, returnedBaskets > 0, distance(pos, Self.basketReturn) < 1.2,
           players[index].baskets < capacity + 2, pickTimers[index] <= 0 {
            returnedBaskets -= 1
            players[index].baskets += 1
            pickTimers[index] = 0.07
            tick()
        }
        if players[index].baskets > 0, distance(pos, Self.basketStand) < 1.3, standBaskets < Self.basketStandMax,
           dropTimers[index] <= 0 {
            players[index].baskets -= 1
            standBaskets += 1
            dropTimers[index] = 0.06
            tick()
        }
        // ゴミ箱：そばにいると、持っている商品を 1 つずつ捨てる
        if !players[index].carry.isEmpty, distance(pos, Self.trashSpot) < 0.85, dropTimers[index] <= 0 {
            players[index].carry.removeLast()
            dropTimers[index] = 0.06
            tick()
        }
        // 倉庫の台：そばにいる間、運べる数まで受け取る（かごを持っていないとき）
        for product in unlockedProducts where distance(pos, Self.supplySpot(product.rawValue)) < 0.95 && players[index].baskets == 0 {
            if players[index].carry.count < capacity, pickTimers[index] <= 0 {
                players[index].carry.append(product)
                pickTimers[index] = 0.07
                tick()
            }
        }
        // 棚のそば：その棚の商品を並べる
        for product in unlockedProducts {
            let zone = Self.shelfRect(product.rawValue).insetBy(dx: -1.0, dy: -1.0)
            guard zone.contains(pos), dropTimers[index] <= 0, stock[product.rawValue] < Self.shelfCapacity,
                  let at = players[index].carry.lastIndex(of: product) else { continue }
            players[index].carry.remove(at: at)
            stock[product.rawValue] += 1
            stats.shelved += 1
            dropTimers[index] = 0.06
            tick()
        }
    }

    private func handleRegister(_ dt: Double) {
        let staffed = hasCashier || players.contains { distance($0.pos, Self.cashierSpot) < 1.0 }
        guard staffed, let first = queue.first, let index = customers.firstIndex(where: { $0.id == first }),
              customers[index].phase == .queued, distance(customers[index].walker.pos, Self.serveSpot) < 0.15 else {
            serving = 0
            return
        }
        serving += dt / (hasCashier ? 0.6 : 0.4) * (1 + 0.2 * Double(upgradeLevel(.cashier)))
        guard serving >= 1 else { return }
        serving = 0
        let customer = customers[index]
        var amount = sale(customer.product, count: customer.got)
        // チップ：アップグレードした分だけ、ときどき多めに払ってくれる
        if Double.random(in: 0..<1) < 0.1 * Double(upgradeLevel(.tips)) { amount += amount / 2 }
        // VIP は 3 倍
        if customer.kind == .vip { amount *= 3 }
        // コンボ：5 秒以内に続けて会計すると、1 回ごとに 1 割ずつ増える（最大 2 倍）
        events.combo = comboTimer > 0 ? events.combo + 1 : 1
        comboTimer = 5
        amount = amount * (10 + min(events.combo - 1, 10)) / 10
        rate(customer.kind == .vip ? 0.1 : 0.04)
        cash += amount
        returnedBaskets = min(returnedBaskets + (customer.basket ? 1 : 0), 20)
        stats.served += 1
        stats.earned += amount
        queue.removeFirst()
        customers[index].phase = .leaving
        customers[index].path = [CGPoint(x: Self.serveSpot.x, y: Self.door.y), Self.door, Self.outside]
        GameAudio.shared.play(.tap)
    }

    /// かごの数をお客さんの数に合わせて増やす。レジ係がいると、ひまなときに少しずつかごを戻してくれる
    private func handleBaskets(_ dt: Double) {
        let total = standBaskets + returnedBaskets + customers.filter(\.basket).count + players.reduce(0) { $0 + $1.baskets }
            + basketHelpers.reduce(0) { $0 + $1.walker.baskets }
        if total < maxCustomers + 3, standBaskets < Self.basketStandMax { standBaskets += 1 }
        guard hasCashier, returnedBaskets > 0, standBaskets < Self.basketStandMax else {
            basketTimer = 0
            return
        }
        basketTimer += dt
        if basketTimer > 6 {
            basketTimer = 0
            returnedBaskets -= 1
            standBaskets += 1
        }
    }

    private func handleCash(_ dt: Double) {
        cashTimer -= dt
        guard cash > 0, players.contains(where: { distance($0.pos, Self.cashSpot) < 1.4 }), cashTimer <= 0 else { return }
        let take = max(1, min(cash, 60 + cash / 7))
        cash -= take
        money += take
        haul += take
        cashTimer = 0.035
        if cash == 0 {
            // 一度にたくさん拾ったら「大もうけ」
            if haul >= 3_000 { banner = "💰 大もうけ！ +\(MartYen.text(haul))" }
            haul = 0
        }
        if soundTimer <= 0 {
            GameAudio.shared.play(.pop(combo: 1))
            soundTimer = 0.2
        }
    }

    private func handlePads(_ dt: Double) {
        for (index, step) in visibleSteps where players.contains(where: { distance($0.pos, step.pos) < 1.0 }) && money > 0 {
            let rate = max(Double(step.cost) / 1.2, 900)
            payCarry += rate * dt
            let amount = min(Int(payCarry), money, step.cost - paidAmount(index))
            guard amount > 0 else { continue }
            payCarry -= Double(amount)
            money -= amount
            paid[index] = paidAmount(index) + amount
            if soundTimer <= 0 {
                GameAudio.shared.tick()
                soundTimer = 0.07
            }
            if paidAmount(index) >= step.cost { complete(index) }
        }
    }

    private func complete(_ index: Int) {
        done.insert(index)
        paid[index] = nil
        rebuildUnlocks()
        let step = Self.steps[index]
        // 新しい棚に店員がはまらないよう、手前に出す
        if case .shelf(let k) = step.kind {
            for p in players.indices where Self.shelfRect(k).insetBy(dx: -0.35, dy: -0.35).contains(players[p].pos) {
                players[p].pos = Self.shelfFront(k)
            }
        }
        banner = "🎉 \(step.title)"
        GameAudio.shared.play(.complete)
        save()
    }

    /// 解放したものから、棚・係・運べる数などを決め直す
    private func rebuildUnlocks() {
        unlocked = [0]
        hasCashier = false
        capacity = 4
        speed = 4.8
        maxCustomers = 5
        expansions = 0
        var stockers = upgradeLevel(.hire)
        for index in done.sorted() where Self.steps.indices.contains(index) {
            switch Self.steps[index].kind {
            case .shelf(let k): unlocked.insert(k)
            case .cashier: hasCashier = true
            case .stocker: stockers += 1
            case .capacity: capacity += 2
            case .speed: speed += 0.9
            case .customers: maxCustomers += 3
            case .expand: expansions += 1
            }
        }
        // 列がお店からはみ出さないよう、お客さんの上限をおさえる
        maxCustomers += upgradeLevel(.ads)
        maxCustomers = min(maxCustomers, 14 + 6 * expansions)
        capacity += 2 * upgradeLevel(.capacity)
        speed *= 1 + 0.12 * CGFloat(upgradeLevel(.speed))
        if role != .guest {
            while helpers.count < stockers { helpers.append(MartHelper(walker: MartWalker(pos: CGPoint(x: 2.9, y: 13.5)))) }
            while basketHelpers.count < upgradeLevel(.baskets) {
                basketHelpers.append(MartHelper(walker: MartWalker(pos: CGPoint(x: 18.0, y: 13.0))))
            }
        }
        level = done.count
    }

    private func tick() {
        if soundTimer <= 0 {
            GameAudio.shared.play(.tap)
            soundTimer = 0.08
        }
    }

    // MARK: - お客さん

    private func spawnCustomers(_ dt: Double) {
        spawnTimer -= dt
        let rush = events.saleTime > 0
        guard spawnTimer <= 0, customers.count < maxCustomers + (rush ? 4 : 0), let product = unlockedProducts.randomElement() else { return }
        // 評判がいいほど、セール中ほど、よく来る
        let ratingFactor = 1.3 - 0.12 * (events.rating - 1)
        spawnTimer = Double.random(in: 0.5...1.4) / (1 + 0.15 * Double(upgradeLevel(.ads))) * ratingFactor / (rush ? 2.5 : 1)
        let want = Int.random(in: 1...min(4, 1 + level / 3))
        var customer = MartCustomer(walker: MartWalker(pos: Self.outside), product: product, want: want,
                                    shirt: Int.random(in: 0..<8))
        customer.path = [Self.door] + route(from: Self.door, to: CGPoint(x: Self.basketStand.x, y: Self.basketStand.y + 0.8))
        customer.phase = .toBasket
        if level >= 3, !customers.contains(where: { $0.kind == .thief }), Int.random(in: 0..<22) == 0 {
            // どろぼう：かごは取らずに売り場へ
            customer.kind = .thief
            customer.want = 3
            customer.phase = .toShelf
            customer.path = [Self.door] + route(from: Self.door, to: Self.shelfFront(product.rawValue))
        } else if events.vipRush > 0 || (level >= 2 && Int.random(in: 0..<10) == 0) {
            if events.vipRush > 0 { events.vipRush -= 1 }
            customer.kind = .vip
            customer.want = Int.random(in: 5...7)
        }
        customers.append(customer)
    }

    private func updateCustomer(_ customer: inout MartCustomer, _ dt: Double) {
        switch customer.phase {
        case .toBasket:
            guard follow(&customer.walker, path: &customer.path, speed: 3.4, dt: dt) else { return }
            customer.walker.heading = -.pi / 2
            if standBaskets > 0 {
                // かごを取って、棚へ
                standBaskets -= 1
                customer.basket = true
                customer.waited = 0
                customer.phase = .toShelf
                customer.path = route(from: customer.walker.pos, to: Self.shelfFront(customer.product.rawValue))
            } else {
                // かごがない：しばらく待ち、待ちすぎたら怒って帰る
                customer.waited += dt
                if customer.waited > 20 {
                    customer.angry = true
                    rate(-0.2)
                    customer.phase = .leaving
                    customer.path = [Self.door, Self.outside]
                }
            }
        case .toShelf:
            if follow(&customer.walker, path: &customer.path, speed: 3.4, dt: dt) {
                customer.phase = .shopping
                // 売り場のほうを向く
                let rect = Self.shelfRect(customer.product.rawValue)
                customer.walker.heading = atan2(rect.midY - customer.walker.pos.y, rect.midX - customer.walker.pos.x)
            }
        case .shopping where customer.kind == .thief:
            // どろぼう：すばやく取って、逃げる（なければあきらめて帰る）
            customer.timer -= dt
            let k = customer.product.rawValue
            if customer.timer <= 0, stock[k] > 0, customer.got < customer.want {
                stock[k] -= 1
                customer.got += 1
                customer.timer = 0.15
            }
            customer.waited += dt
            if customer.got >= customer.want || (stock[k] == 0 && (customer.got > 0 || customer.waited > 6)) {
                customer.phase = .leaving
                customer.path = route(from: customer.walker.pos, to: Self.door) + [Self.outside]
            }
        case .shopping:
            customer.timer -= dt
            let k = customer.product.rawValue
            if customer.timer <= 0, stock[k] > 0, customer.got < customer.want {
                stock[k] -= 1
                customer.got += 1
                customer.timer = 0.25
                customer.waited = 0
            } else if stock[k] == 0, customer.got < customer.want {
                customer.waited += dt
                if customer.waited > 25 {
                    // 品切れのまま待たされて、怒って帰る（取った分は棚にもどす）
                    stock[k] = min(stock[k] + customer.got, Self.shelfCapacity)
                    customer.got = 0
                    if customer.basket { returnedBaskets = min(returnedBaskets + 1, 20) }
                    customer.basket = false
                    customer.angry = true
                    rate(-0.2)
                    customer.phase = .leaving
                    customer.path = route(from: customer.walker.pos, to: Self.door) + [Self.outside]
                    return
                }
            }
            // セルフレジがあいていて、レジに人が並んでいたら（またはときどき）セルフレジへ
            if customer.got >= customer.want, customer.timer <= 0,
               let free = (0..<selfMachines).first(where: { !claimedMachines.contains($0) }),
               !queue.isEmpty || Bool.random() {
                claimedMachines.insert(free)
                customer.machine = free
                customer.phase = .selfPay
                customer.timer = 0
                customer.path = route(from: customer.walker.pos, to: Self.selfStand(free))
                return
            }
            if customer.got >= customer.want, customer.timer <= 0 {
                queue.append(customer.id)
                customer.phase = .toQueue
                // 列のうしろあたりまで、売り場をよけて歩く
                let tail = CGPoint(x: Self.serveSpot.x, y: min(Self.serveSpot.y + 0.85 * CGFloat(queue.count), floorRect.maxY - 1))
                customer.path = route(from: customer.walker.pos, to: tail)
            }
        case .toQueue:
            if follow(&customer.walker, path: &customer.path, speed: 3.4, dt: dt) {
                customer.phase = .queued
                customer.waited = 0
            }
        case .queued:
            customer.waited += dt
            if customer.waited > 35, let at = queue.firstIndex(of: customer.id), at > 0 || !hasCashier {
                // レジでずっと待たされて、怒って帰る
                queue.remove(at: at)
                stock[customer.product.rawValue] = min(stock[customer.product.rawValue] + customer.got, Self.shelfCapacity)
                customer.got = 0
                if customer.basket { returnedBaskets = min(returnedBaskets + 1, 20) }
                customer.basket = false
                customer.angry = true
                rate(-0.2)
                customer.phase = .leaving
                customer.path = route(from: CGPoint(x: Self.serveSpot.x - 0.6, y: customer.walker.pos.y), to: Self.door) + [Self.outside]
                return
            }
            let index = queue.firstIndex(of: customer.id) ?? 0
            var target = Self.serveSpot
            target.y += 0.85 * CGFloat(index)
            var path = [target]
            if follow(&customer.walker, path: &path, speed: 3.4, dt: dt) {
                customer.walker.heading = 0
            }
        case .selfPay:
            // セルフレジ：台の前で商品を読みとって、自分で払う（お金はレジの横の山へ）
            guard follow(&customer.walker, path: &customer.path, speed: 3.4, dt: dt) else { return }
            customer.walker.heading = 0
            customer.timer += dt
            let duration = 2.4 / (1 + 0.25 * Double(max(upgradeLevel(.selfCheckout) - 3, 0)))
            guard customer.timer >= duration else { return }
            var amount = sale(customer.product, count: customer.got)
            if customer.kind == .vip { amount *= 3 }
            cash += amount
            stats.served += 1
            stats.earned += amount
            if customer.basket { returnedBaskets = min(returnedBaskets + 1, 20) }
            customer.basket = false
            customer.machine = -1
            rate(customer.kind == .vip ? 0.1 : 0.04)
            customer.phase = .leaving
            customer.path = route(from: customer.walker.pos, to: Self.door) + [Self.outside]
            GameAudio.shared.play(.tap)
        case .leaving:
            _ = follow(&customer.walker, path: &customer.path, speed: customer.kind == .thief && customer.got > 0 ? 4.2 : 3.9, dt: dt)
        }
    }

    /// 道すじにそって歩く（着いたら true）
    private func follow(_ walker: inout MartWalker, path: inout [CGPoint], speed: CGFloat, dt: Double) -> Bool {
        guard let target = path.first else {
            walker.moving = false
            return true
        }
        let dx = target.x - walker.pos.x, dy = target.y - walker.pos.y
        let d = hypot(dx, dy)
        let stride = speed * CGFloat(dt)
        if d <= stride {
            walker.pos = target
            path.removeFirst()
        } else {
            walker.pos.x += dx / d * stride
            walker.pos.y += dy / d * stride
            walker.step += Double(stride)
            walker.heading = atan2(dy, dx)
        }
        walker.moving = d > 0.01
        return path.isEmpty
    }

    // MARK: - 出来事

    private func handleEvents(_ dt: Double) {
        // タイムセール：ときどき 30 秒、お客さんがどっと来る
        if events.saleTime > 0 {
            events.saleTime = max(events.saleTime - dt, 0)
            if events.saleTime == 0 { banner = "⏰ タイムセールおわり" }
        } else if level >= 2 {
            saleCooldown -= dt
            if saleCooldown <= 0 {
                events.saleTime = 30
                saleCooldown = Double.random(in: 150...240)
                banner = "⏰ タイムセール！"
                GameAudio.shared.play(.special)
            }
        }
        if events.boostTime > 0 { events.boostTime = max(events.boostTime - dt, 0) }
        // レジのコンボは 5 秒あくと切れる
        if comboTimer > 0 {
            comboTimer -= dt
            if comboTimer <= 0 { events.combo = 0 }
        }
        // プレゼント箱：ときどき床に出る。店員が拾うとお金
        if let gift = events.gift {
            if players.contains(where: { distance($0.pos, gift) < 0.9 }) {
                money += events.giftValue
                stats.earned += events.giftValue
                banner = "🎁 +\(MartYen.text(events.giftValue))"
                events.gift = nil
                GameAudio.shared.play(.win)
            }
        } else {
            giftTimer -= dt
            if giftTimer <= 0 {
                giftTimer = Double.random(in: 40...70)
                if let spot = randomOpenSpot() {
                    events.gift = spot
                    let value = max(unlockedProducts.map(\.price).reduce(0, +) * 4, 500)
                    events.giftValue = value / 100 * 100
                }
            }
        }
    }

    /// 通れる場所からひとつ（壁から少しはなれたところ）
    private func randomOpenSpot() -> CGPoint? {
        let (columns, rows, open) = walkGrid()
        for _ in 0..<40 {
            let column = Int.random(in: 6..<(columns - 6)), row = Int.random(in: 4..<(rows - 3))
            guard open[row * columns + column] else { continue }
            let point = CGPoint(x: (CGFloat(column) + 0.5) * Self.cell, y: (CGFloat(row) + 0.5) * Self.cell)
            if distance(point, Self.serveSpot) < 3 || distance(point, CGPoint(x: Self.upgradeZone.midX, y: Self.upgradeZone.midY)) < 2 { continue }
            return point
        }
        return nil
    }

    /// 逃げるどろぼうに店員がさわると、捕まえて商品をとりもどす
    private func catchThieves() {
        for index in customers.indices where customers[index].kind == .thief && customers[index].phase == .leaving
            && customers[index].got > 0 {
            let pos = customers[index].walker.pos
            guard players.contains(where: { distance($0.pos, pos) < 1.0 }) else { continue }
            let k = customers[index].product.rawValue
            stock[k] = min(stock[k] + customers[index].got, Self.shelfCapacity)
            let reward = sale(customers[index].product, count: customers[index].got) * 2 + 500
            customers[index].got = 0
            customers[index].angry = true
            money += reward
            stats.earned += reward
            rate(0.3)
            banner = "🚨 どろぼうをつかまえた！ +\(MartYen.text(reward))"
            GameAudio.shared.play(.win)
        }
    }

    // MARK: - かご係

    private func updateBasketHelper(_ helper: inout MartHelper, _ dt: Double) {
        let speed = 3.7 * (1 + 0.2 * CGFloat(upgradeLevel(.staff)))
        switch helper.phase {
        case .idle:
            helper.walker.moving = false
            // かごが 2 つ以上たまったら取りに行く（置き場が空なら 1 つでも）
            guard returnedBaskets >= 2 || (returnedBaskets > 0 && standBaskets == 0) else { return }
            helper.path = route(from: helper.walker.pos, to: Self.basketReturn)
            helper.phase = .toSupply
        case .toSupply:
            if follow(&helper.walker, path: &helper.path, speed: speed, dt: dt) { helper.phase = .loading }
        case .loading:
            helper.timer -= dt
            if helper.timer <= 0, returnedBaskets > 0, helper.walker.baskets < 8 {
                returnedBaskets -= 1
                helper.walker.baskets += 1
                helper.timer = 0.12
            }
            if returnedBaskets == 0 || helper.walker.baskets >= 8 {
                if helper.walker.baskets == 0 {
                    helper.phase = .idle
                } else {
                    helper.path = route(from: helper.walker.pos, to: CGPoint(x: Self.basketStand.x - 0.9, y: Self.basketStand.y))
                    helper.phase = .toShelf
                }
            }
        case .toShelf:
            if follow(&helper.walker, path: &helper.path, speed: speed, dt: dt) { helper.phase = .unloading }
        case .unloading:
            helper.timer -= dt
            if helper.timer <= 0, helper.walker.baskets > 0 {
                helper.walker.baskets -= 1
                if standBaskets < Self.basketStandMax { standBaskets += 1 } else { returnedBaskets += 1 }
                helper.timer = 0.12
            }
            if helper.walker.baskets == 0 { helper.phase = .idle }
        }
    }

    // MARK: - 品出し係

    private func updateHelper(_ helper: inout MartHelper, busy: Set<MartProduct>, _ dt: Double) {
        switch helper.phase {
        case .idle:
            helper.walker.moving = false
            // いちばん減っている棚を選ぶ（ほかの係と同じ棚は避ける）
            let candidates = unlockedProducts.filter { stock[$0.rawValue] < Self.shelfCapacity - 1 && !busy.contains($0) }
            guard let product = candidates.min(by: { stock[$0.rawValue] < stock[$1.rawValue] }) else { return }
            helper.target = product
            let supply = Self.supplySpot(product.rawValue)
            helper.path = route(from: helper.walker.pos, to: supply)
            helper.phase = .toSupply
        case .toSupply:
            if follow(&helper.walker, path: &helper.path, speed: 3.7 * (1 + 0.2 * CGFloat(upgradeLevel(.staff))), dt: dt) { helper.phase = .loading }
        case .loading:
            helper.timer -= dt
            if helper.timer <= 0 {
                helper.walker.carry.append(helper.target)
                helper.timer = 0.13
            }
            if helper.walker.carry.count >= 5 {
                let front = Self.shelfFront(helper.target.rawValue)
                helper.path = route(from: helper.walker.pos, to: front)
                helper.phase = .toShelf
            }
        case .toShelf:
            if follow(&helper.walker, path: &helper.path, speed: 3.7 * (1 + 0.2 * CGFloat(upgradeLevel(.staff))), dt: dt) { helper.phase = .unloading }
        case .unloading:
            helper.timer -= dt
            let k = helper.target.rawValue
            if helper.timer <= 0, !helper.walker.carry.isEmpty {
                if stock[k] < Self.shelfCapacity {
                    helper.walker.carry.removeLast()
                    stock[k] += 1
                    stats.shelved += 1
                    helper.timer = 0.13
                } else {
                    helper.walker.carry.removeAll()
                }
            }
            if helper.walker.carry.isEmpty { helper.phase = .idle }
        }
    }

    // MARK: - 保存（ひとり・ホスト）

    private struct SaveData: Codable {
        var money: Int
        var done: [Int]
        var paid: [Int: Int]
        var stock: [Int]
        var cash: Int
        var stats: MartStats?
        var questIndex: Int?
        var questBase: Int?
        var savedAt: Date?
        /// 2 = 円（30 倍）にしたあと
        var unit: Int?
        var upgrades: [MartUpgrade: Int]?
        var standBaskets: Int?
        var returnedBaskets: Int?
        var rating: Double?
    }

    func save() {
        guard role != .guest else { return }
        let data = SaveData(money: money, done: Array(done), paid: paid, stock: stock, cash: cash, stats: stats,
                            questIndex: questIndex, questBase: questBase, savedAt: Date(), unit: 2,
                            upgrades: upgrades, standBaskets: standBaskets, returnedBaskets: returnedBaskets,
                            rating: events.rating)
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "martSave")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "martSave"),
              let saved = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        // 前の版（小さい単位）の保存は 30 倍にする
        let scale = (saved.unit ?? 1) >= 2 ? 1 : 30
        money = saved.money * scale
        paid = saved.paid.mapValues { $0 * scale }
        cash = saved.cash * scale
        for (k, count) in saved.stock.enumerated() where stock.indices.contains(k) { stock[k] = count }
        done = Set(saved.done.filter { Self.steps.indices.contains($0) })
        stats = saved.stats ?? MartStats()
        stats.earned *= scale
        upgrades = saved.upgrades ?? [:]
        standBaskets = saved.standBaskets ?? 6
        returnedBaskets = saved.returnedBaskets ?? 0
        events.rating = saved.rating ?? 3
        stars = (events.rating * 2).rounded() / 2
        questIndex = saved.questIndex ?? 0
        questBase = saved.questBase ?? 0
        if scale > 1, MartQuest.make(questIndex).kind == .earn { questBase *= scale }
        rebuildUnlocks()
        // 留守のあいだも、お店は少しかせぐ（係がいるほど多い。2 時間まで）
        if let savedAt = saved.savedAt {
            let minutes = min(Date().timeIntervalSince(savedAt), 7200) / 60
            let perMinute = Double(unlockedProducts.map(\.price).reduce(0, +)) * 1.2
                * (hasCashier ? 1 : 0.35) * (helpers.isEmpty ? 0.4 : 1 + 0.3 * Double(helpers.count - 1))
            let earned = Int(minutes * perMinute)
            if earned >= 100 {
                cash += earned
                offlineEarned = earned
            }
        }
    }

    func reset() {
        guard role != .guest else { return }
        UserDefaults.standard.removeObject(forKey: "martSave")
        money = 0
        done = []
        paid = [:]
        stock = Array(repeating: 0, count: MartProduct.allCases.count)
        cash = 0
        stats = MartStats()
        questIndex = 0
        questBase = 0
        upgrades = [:]
        standBaskets = 6
        returnedBaskets = 0
        helpers = []
        basketHelpers = []
        events = MartEvents()
        customers = []
        queue = []
        for index in players.indices {
            players[index].pos = CGPoint(x: 9.0 + CGFloat(index), y: 13.5)
            players[index].carry = []
        }
        rebuildUnlocks()
    }
}
