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

struct MartCustomer: Identifiable, Codable {
    enum Phase: String, Codable { case toBasket, toShelf, shopping, toQueue, queued, leaving }
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
    case capacity, speed, price, cashier, staff, hire
    var id: String { rawValue }
    static let maxLevel = 5

    var title: String {
        switch self {
        case .capacity: return "運べる数"
        case .speed: return "歩く速さ"
        case .price: return "売値アップ"
        case .cashier: return "レジのスピード"
        case .staff: return "係のスピード"
        case .hire: return "係を雇う"
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
    nonisolated static let basketReturn = CGPoint(x: 16.3, y: 6.7)
    nonisolated static let basketStandMax = 12
    /// ゴミ箱（間違えて取った商品を捨てる）
    nonisolated static let trashSpot = CGPoint(x: 3.3, y: 6.2)
    /// アップグレードの場所（左下）
    nonisolated static let upgradeZone = CGRect(x: 12.6, y: 14.0, width: 2.6, height: 1.6)
    /// 広げたあとの床の奥行き
    nonisolated static let expandedDepth: CGFloat = 23
    /// お客さんが通る縦の通路（棚とレジのあいだ）
    nonisolated static let aisleX: CGFloat = 17.6
    /// 品出し係が通る縦の通路（倉庫の台と棚のあいだ）
    nonisolated static let helperX: CGFloat = 2.9

    nonisolated static func shelfRect(_ k: Int) -> CGRect {
        CGRect(x: 4.2 + 3.4 * CGFloat(k % 4), y: [3.0, 8.5, 17.5][min(k / 4, 2)], width: 2.2, height: 1.0)
    }

    /// お客さんが立って商品を取る場所（棚の手前）
    nonisolated static func shelfFront(_ k: Int) -> CGPoint {
        let rect = shelfRect(k)
        return CGPoint(x: rect.midX, y: rect.maxY + 0.7)
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
        MartStep(kind: .shelf(10), cost: 95_000, pos: CGPoint(x: shelfRect(10).midX, y: shelfRect(10).midY)),
        MartStep(kind: .stocker, cost: 105_000, pos: CGPoint(x: 4.4, y: 12.6)),
        MartStep(kind: .customers, cost: 115_000, pos: CGPoint(x: 14.0, y: 12.6)),
        MartStep(kind: .shelf(11), cost: 130_000, pos: CGPoint(x: shelfRect(11).midX, y: shelfRect(11).midY)),
        MartStep(kind: .speed, cost: 140_000, pos: CGPoint(x: 10.8, y: 12.6)),
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
    /// お店を広げたか（床が奥へのびる）
    private(set) var expanded = false
    var floorRect: CGRect { CGRect(x: 0, y: 0, width: Self.floor.width, height: expanded ? Self.expandedDepth : Self.floor.height) }
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
                     returnedBaskets: returnedBaskets, upgrades: upgrades)
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
        }
        guard role != .guest else { return }
        for index in players.indices { handleSupplyAndShelves(index, dt) }
        handleRegister(dt)
        handleBaskets(dt)
        handleCash(dt)
        handlePads(dt)
        spawnCustomers(dt)
        for index in customers.indices { updateCustomer(&customers[index], dt) }
        customers.removeAll { $0.phase == .leaving && $0.path.isEmpty }
        for index in helpers.indices {
            // ほかの係が向かっている棚（書き換え中の配列を読まないよう、先に調べる）
            let busy = Set(helpers.enumerated().filter { $0.offset != index && $0.element.phase != .idle }.map(\.element.target))
            updateHelper(&helpers[index], busy: busy, dt)
        }
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
            want = CGVector(dx: wx * speed * length, dy: wy * speed * length)
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
        var walls = [Self.counter, CGRect(x: Self.trashSpot.x - 0.3, y: Self.trashSpot.y - 0.3, width: 0.6, height: 0.6)]
        walls += unlocked.map { Self.shelfRect($0) }
        for k in unlocked {
            let spot = Self.supplySpot(k)
            walls.append(CGRect(x: spot.x - 1.1, y: spot.y - 0.5, width: 0.75, height: 1.0))
        }
        return walls.contains { $0.insetBy(dx: -r, dy: -r).contains(point) }
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
        let amount = sale(customer.product, count: customer.got)
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
        expanded = false
        var stockers = upgradeLevel(.hire)
        for index in done.sorted() where Self.steps.indices.contains(index) {
            switch Self.steps[index].kind {
            case .shelf(let k): unlocked.insert(k)
            case .cashier: hasCashier = true
            case .stocker: stockers += 1
            case .capacity: capacity += 2
            case .speed: speed += 0.9
            case .customers: maxCustomers += 3
            case .expand: expanded = true
            }
        }
        // 列がお店からはみ出さないよう、お客さんの上限をおさえる
        maxCustomers = min(maxCustomers, expanded ? 22 : 14)
        capacity += 2 * upgradeLevel(.capacity)
        speed *= 1 + 0.12 * CGFloat(upgradeLevel(.speed))
        if role != .guest {
            while helpers.count < stockers { helpers.append(MartHelper(walker: MartWalker(pos: CGPoint(x: 2.9, y: 13.5)))) }
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
        guard spawnTimer <= 0, customers.count < maxCustomers, let product = unlockedProducts.randomElement() else { return }
        spawnTimer = Double.random(in: 0.5...1.4)
        let want = Int.random(in: 1...min(4, 1 + level / 3))
        var customer = MartCustomer(walker: MartWalker(pos: Self.outside), product: product, want: want,
                                    shirt: Int.random(in: 0..<8))
        customer.path = [Self.door, CGPoint(x: Self.basketStand.x, y: Self.door.y), CGPoint(x: Self.basketStand.x, y: Self.basketStand.y + 0.8)]
        customer.phase = .toBasket
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
                let front = Self.shelfFront(customer.product.rawValue)
                customer.path = [CGPoint(x: Self.aisleX, y: Self.door.y - 0.6), CGPoint(x: Self.aisleX, y: front.y), front]
            } else {
                // かごがない：しばらく待ち、待ちすぎたら怒って帰る
                customer.waited += dt
                if customer.waited > 20 {
                    customer.angry = true
                    customer.phase = .leaving
                    customer.path = [Self.door, Self.outside]
                }
            }
        case .toShelf:
            if follow(&customer.walker, path: &customer.path, speed: 3.4, dt: dt) {
                customer.phase = .shopping
                // 棚のほうを向く
                customer.walker.heading = -.pi / 2
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
                    customer.phase = .leaving
                    let front = Self.shelfFront(k)
                    customer.path = [CGPoint(x: Self.aisleX, y: front.y), CGPoint(x: Self.aisleX, y: Self.door.y), Self.door, Self.outside]
                    return
                }
            }
            if customer.got >= customer.want, customer.timer <= 0 {
                queue.append(customer.id)
                customer.phase = .toQueue
                let front = Self.shelfFront(k)
                customer.path = [CGPoint(x: Self.aisleX, y: front.y)]
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
                customer.phase = .leaving
                customer.path = [CGPoint(x: Self.serveSpot.x - 0.6, y: customer.walker.pos.y), CGPoint(x: Self.serveSpot.x - 0.6, y: Self.door.y),
                                 Self.door, Self.outside]
                return
            }
            let index = queue.firstIndex(of: customer.id) ?? 0
            var target = Self.serveSpot
            target.y += 0.85 * CGFloat(index)
            var path = [target]
            if follow(&customer.walker, path: &path, speed: 3.4, dt: dt) {
                customer.walker.heading = 0
            }
        case .leaving:
            _ = follow(&customer.walker, path: &customer.path, speed: 3.9, dt: dt)
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
            helper.path = [CGPoint(x: Self.helperX, y: helper.walker.pos.y), CGPoint(x: Self.helperX, y: supply.y)]
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
                helper.path = [CGPoint(x: Self.helperX, y: front.y), front]
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
    }

    func save() {
        guard role != .guest else { return }
        let data = SaveData(money: money, done: Array(done), paid: paid, stock: stock, cash: cash, stats: stats,
                            questIndex: questIndex, questBase: questBase, savedAt: Date(), unit: 2,
                            upgrades: upgrades, standBaskets: standBaskets, returnedBaskets: returnedBaskets)
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
        customers = []
        queue = []
        for index in players.indices {
            players[index].pos = CGPoint(x: 9.0 + CGFloat(index), y: 13.5)
            players[index].carry = []
        }
        rebuildUnlocks()
    }
}
