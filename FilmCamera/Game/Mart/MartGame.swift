import SwiftUI

/// 「まちかどマート」：お店の経営ゲーム（スーパーマーケット・シミュレーション）。
/// 指でなぞって店員を動かし、倉庫の台で商品を受け取り（手の上に高く積んで運ぶ）、棚のそばに行くと並べる。
/// お客さんは棚から商品を取ってレジに並び、店員がレジの奥に立つと会計してお金が出る。お金のそばを通ると拾える。
/// 床の点線の「解放マーク」の上に立つとお金を払い、新しい棚・レジ係・品出し係・運べる数・速さなどが増える。
/// 2 人で遊ぶとき（近くの iPhone と直接つなぐ）は、お店を開いた人（ホスト）がお店を動かし、
/// 遊びに来た人（ゲスト）は自分の位置を送って、ホストから 1 秒に 15 回お店の様子（MartSnapshot）を受け取る。
/// お金は 2 人で共通。座標はお店の床のマス（x は右下、y は左下へ）。描くのは MartScene（SceneKit の 3D）
enum MartProduct: Int, CaseIterable, Codable {
    case soda, snack, noodle, sandwich, fruit, toy

    var name: String {
        switch self {
        case .soda: return "ジュース"
        case .snack: return "おかし"
        case .noodle: return "カップめん"
        case .sandwich: return "サンド"
        case .fruit: return "くだもの"
        case .toy: return "おもちゃ"
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
}

struct MartCustomer: Identifiable, Codable {
    enum Phase: String, Codable { case toShelf, shopping, toQueue, queued, leaving }
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
    enum Kind: Equatable { case shelf(Int), cashier, stocker, capacity, speed, customers }
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
        case .customers: return "お客さん +2"
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
        }
    }
}

/// ゲストに送るお店の様子
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
}

@MainActor
final class MartGame: ObservableObject {
    enum Role { case solo, host, guest }

    // 店の形
    nonisolated static let floor = CGRect(x: 0, y: 0, width: 14.5, height: 11)
    nonisolated static let counter = CGRect(x: 12.0, y: 2.6, width: 1.0, height: 2.3)
    nonisolated static let cashierSpot = CGPoint(x: 13.65, y: 3.75)
    nonisolated static let serveSpot = CGPoint(x: 11.35, y: 3.75)
    nonisolated static let cashSpot = CGPoint(x: 12.5, y: 5.8)
    nonisolated static let door = CGPoint(x: 14.2, y: 10)
    nonisolated static let outside = CGPoint(x: 17, y: 10)
    nonisolated static let shelfCapacity = 8

    nonisolated static func shelfRect(_ k: Int) -> CGRect {
        CGRect(x: 2.4 + 2.0 * CGFloat(k % 4), y: k < 4 ? 2.0 : 6.0, width: 1.6, height: 0.8)
    }

    /// お客さんが立って商品を取る場所（棚の手前）
    nonisolated static func shelfFront(_ k: Int) -> CGPoint {
        let rect = shelfRect(k)
        return CGPoint(x: rect.midX, y: rect.maxY + 0.5)
    }

    /// 倉庫の台（左の壁ぞい）
    nonisolated static func supplySpot(_ k: Int) -> CGPoint {
        CGPoint(x: 0.95, y: 1.4 + 1.5 * CGFloat(k))
    }

    nonisolated static let steps: [MartStep] = [
        MartStep(kind: .shelf(1), cost: 600, pos: CGPoint(x: shelfRect(1).midX, y: shelfRect(1).midY)),
        MartStep(kind: .capacity, cost: 1200, pos: CGPoint(x: 5.2, y: 9.9)),
        MartStep(kind: .shelf(2), cost: 2100, pos: CGPoint(x: shelfRect(2).midX, y: shelfRect(2).midY)),
        MartStep(kind: .cashier, cost: 3000, pos: CGPoint(x: 13.65, y: 2.0)),
        MartStep(kind: .shelf(3), cost: 4500, pos: CGPoint(x: shelfRect(3).midX, y: shelfRect(3).midY)),
        MartStep(kind: .speed, cost: 4200, pos: CGPoint(x: 7.0, y: 9.9)),
        MartStep(kind: .stocker, cost: 6600, pos: CGPoint(x: 2.4, y: 9.9)),
        MartStep(kind: .shelf(4), cost: 7800, pos: CGPoint(x: shelfRect(4).midX, y: shelfRect(4).midY)),
        MartStep(kind: .customers, cost: 6000, pos: CGPoint(x: 8.8, y: 9.9)),
        MartStep(kind: .capacity, cost: 9600, pos: CGPoint(x: 5.2, y: 9.9)),
        MartStep(kind: .shelf(5), cost: 12600, pos: CGPoint(x: shelfRect(5).midX, y: shelfRect(5).midY)),
        MartStep(kind: .stocker, cost: 15000, pos: CGPoint(x: 2.4, y: 9.9)),
        MartStep(kind: .customers, cost: 13500, pos: CGPoint(x: 8.8, y: 9.9)),
        MartStep(kind: .speed, cost: 18000, pos: CGPoint(x: 7.0, y: 9.9)),
    ]

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

    private(set) var players: [MartWalker] = [MartWalker(pos: CGPoint(x: 6.5, y: 9.0))]
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
    private(set) var speed: CGFloat = 3.2
    private(set) var maxCustomers = 3
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
            players.append(MartWalker(pos: CGPoint(x: 7.5, y: 9.4)))
        }
    }

    var unlockedProducts: [MartProduct] {
        MartProduct.allCases.filter { unlocked.contains($0.rawValue) }
    }

    /// いま見せる解放マーク（まだのものから順に 2 つ）
    var visibleSteps: [(Int, MartStep)] {
        Self.steps.enumerated().filter { !done.contains($0.offset) }.prefix(2).map { ($0.offset, $0.element) }
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
        players.append(MartWalker(pos: CGPoint(x: 7.5, y: 9.4)))
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
                     questIndex: questIndex, questBase: questBase)
    }

    /// ホストから届いたお店の様子を当てはめる（ゲスト。自分の位置はそのまま）
    func apply(_ snapshot: MartSnapshot) {
        let mine = players.indices.contains(me) ? players[me] : nil
        players = snapshot.players
        while players.count < 2 { players.append(MartWalker(pos: CGPoint(x: 7.5, y: 9.4))) }
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
        guard role != .guest else { return }
        for index in players.indices { handleSupplyAndShelves(index, dt) }
        handleRegister(dt)
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
        let inner = Self.floor.insetBy(dx: r + 0.1, dy: r + 0.1)
        if !inner.contains(point) { return true }
        var walls = [Self.counter]
        walls += unlocked.map { Self.shelfRect($0) }
        for k in unlocked {
            let spot = Self.supplySpot(k)
            walls.append(CGRect(x: spot.x - 0.75, y: spot.y - 0.35, width: 0.4, height: 0.7))
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
        // 倉庫の台：そばにいる間、運べる数まで受け取る
        for product in unlockedProducts where distance(pos, Self.supplySpot(product.rawValue)) < 0.8 {
            if players[index].carry.count < capacity, pickTimers[index] <= 0 {
                players[index].carry.append(product)
                pickTimers[index] = 0.1
                tick()
            }
        }
        // 棚のそば：その棚の商品を並べる
        for product in unlockedProducts {
            let zone = Self.shelfRect(product.rawValue).insetBy(dx: -0.75, dy: -0.75)
            guard zone.contains(pos), dropTimers[index] <= 0, stock[product.rawValue] < Self.shelfCapacity,
                  let at = players[index].carry.lastIndex(of: product) else { continue }
            players[index].carry.remove(at: at)
            stock[product.rawValue] += 1
            stats.shelved += 1
            dropTimers[index] = 0.09
            tick()
        }
    }

    private func handleRegister(_ dt: Double) {
        let staffed = hasCashier || players.contains { distance($0.pos, Self.cashierSpot) < 0.7 }
        guard staffed, let first = queue.first, let index = customers.firstIndex(where: { $0.id == first }),
              customers[index].phase == .queued, distance(customers[index].walker.pos, Self.serveSpot) < 0.15 else {
            serving = 0
            return
        }
        serving += dt / (hasCashier ? 0.8 : 0.55)
        guard serving >= 1 else { return }
        serving = 0
        let customer = customers[index]
        cash += customer.got * customer.product.price
        stats.served += 1
        stats.earned += customer.got * customer.product.price
        queue.removeFirst()
        customers[index].phase = .leaving
        customers[index].path = [CGPoint(x: Self.serveSpot.x, y: 10), Self.door, Self.outside]
        GameAudio.shared.play(.tap)
    }

    private func handleCash(_ dt: Double) {
        cashTimer -= dt
        guard cash > 0, players.contains(where: { distance($0.pos, Self.cashSpot) < 1.0 }), cashTimer <= 0 else { return }
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
        for (index, step) in visibleSteps where players.contains(where: { distance($0.pos, step.pos) < 0.8 }) && money > 0 {
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
        speed = 3.2
        maxCustomers = 3
        var stockers = 0
        for index in done.sorted() where Self.steps.indices.contains(index) {
            switch Self.steps[index].kind {
            case .shelf(let k): unlocked.insert(k)
            case .cashier: hasCashier = true
            case .stocker: stockers += 1
            case .capacity: capacity += 2
            case .speed: speed += 0.7
            case .customers: maxCustomers += 2
            }
        }
        if role != .guest {
            while helpers.count < stockers { helpers.append(MartHelper(walker: MartWalker(pos: CGPoint(x: 1.8, y: 9.5)))) }
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
        spawnTimer = Double.random(in: 1.2...3.0)
        let front = Self.shelfFront(product.rawValue)
        let want = Int.random(in: 1...min(4, 1 + level / 3))
        var customer = MartCustomer(walker: MartWalker(pos: Self.outside), product: product, want: want,
                                    shirt: Int.random(in: 0..<8))
        customer.path = [Self.door, CGPoint(x: 11.0, y: 10), CGPoint(x: 11.0, y: front.y), front]
        customers.append(customer)
    }

    private func updateCustomer(_ customer: inout MartCustomer, _ dt: Double) {
        switch customer.phase {
        case .toShelf:
            if follow(&customer.walker, path: &customer.path, speed: 2.0, dt: dt) {
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
                customer.timer = 0.4
                customer.waited = 0
            } else if stock[k] == 0, customer.got < customer.want {
                customer.waited += dt
                if customer.waited > 25 {
                    // 品切れのまま待たされて、怒って帰る（取った分は棚にもどす）
                    stock[k] = min(stock[k] + customer.got, Self.shelfCapacity)
                    customer.got = 0
                    customer.angry = true
                    customer.phase = .leaving
                    let front = Self.shelfFront(k)
                    customer.path = [CGPoint(x: 11.0, y: front.y), CGPoint(x: 11.0, y: 10), Self.door, Self.outside]
                    return
                }
            }
            if customer.got >= customer.want, customer.timer <= 0 {
                queue.append(customer.id)
                customer.phase = .toQueue
                let front = Self.shelfFront(k)
                customer.path = [CGPoint(x: 11.0, y: front.y)]
            }
        case .toQueue:
            if follow(&customer.walker, path: &customer.path, speed: 2.0, dt: dt) {
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
                customer.angry = true
                customer.phase = .leaving
                customer.path = [CGPoint(x: Self.serveSpot.x - 0.6, y: customer.walker.pos.y), CGPoint(x: Self.serveSpot.x - 0.6, y: 10),
                                 Self.door, Self.outside]
                return
            }
            let index = queue.firstIndex(of: customer.id) ?? 0
            var target = Self.serveSpot
            target.y += 0.75 * CGFloat(index)
            var path = [target]
            if follow(&customer.walker, path: &path, speed: 2.0, dt: dt) {
                customer.walker.heading = 0
            }
        case .leaving:
            _ = follow(&customer.walker, path: &customer.path, speed: 2.4, dt: dt)
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
            helper.path = [CGPoint(x: 1.85, y: helper.walker.pos.y), CGPoint(x: 1.85, y: supply.y)]
            helper.phase = .toSupply
        case .toSupply:
            if follow(&helper.walker, path: &helper.path, speed: 2.4, dt: dt) { helper.phase = .loading }
        case .loading:
            helper.timer -= dt
            if helper.timer <= 0 {
                helper.walker.carry.append(helper.target)
                helper.timer = 0.13
            }
            if helper.walker.carry.count >= 5 {
                let front = Self.shelfFront(helper.target.rawValue)
                helper.path = [CGPoint(x: 1.85, y: front.y), front]
                helper.phase = .toShelf
            }
        case .toShelf:
            if follow(&helper.walker, path: &helper.path, speed: 2.4, dt: dt) { helper.phase = .unloading }
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
    }

    func save() {
        guard role != .guest else { return }
        let data = SaveData(money: money, done: Array(done), paid: paid, stock: stock, cash: cash, stats: stats,
                            questIndex: questIndex, questBase: questBase, savedAt: Date(), unit: 2)
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
        if saved.stock.count == stock.count { stock = saved.stock }
        done = Set(saved.done.filter { Self.steps.indices.contains($0) })
        stats = saved.stats ?? MartStats()
        stats.earned *= scale
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
        helpers = []
        customers = []
        queue = []
        for index in players.indices {
            players[index].pos = CGPoint(x: 6.5 + CGFloat(index), y: 9.0)
            players[index].carry = []
        }
        rebuildUnlocks()
    }
}
