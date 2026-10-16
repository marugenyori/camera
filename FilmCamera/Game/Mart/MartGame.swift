import SwiftUI

/// 「まちかどマート」：お店の経営ゲーム（スーパーマーケット・シミュレーション）。
/// 指でなぞって店員を動かし、倉庫の台で商品を受け取り（頭の上まで積んで運ぶ）、棚のそばに行くと並べる。
/// お客さんは棚から商品を取ってレジに並び、店員がレジの場所に立つと会計してお金が出る。お金のそばを通ると拾える。
/// 床の点線の「解放マーク」の上に立つとお金を払い、新しい棚・レジ係・品出し係・運べる数・速さなどが増える。
/// 座標はお店の床のマス（x は右下、y は左下へ）。描くのは MartRenderer
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

    var color: Color {
        switch self {
        case .soda: return Color(red: 0.9, green: 0.2, blue: 0.25)
        case .snack: return Color(red: 1, green: 0.75, blue: 0.15)
        case .noodle: return Color(red: 0.95, green: 0.95, blue: 0.9)
        case .sandwich: return Color(red: 0.95, green: 0.6, blue: 0.3)
        case .fruit: return Color(red: 0.4, green: 0.8, blue: 0.3)
        case .toy: return Color(red: 0.6, green: 0.45, blue: 0.95)
        }
    }

    var accent: Color {
        switch self {
        case .soda: return Color(red: 0.2, green: 0.4, blue: 0.9)
        case .snack: return Color(red: 0.9, green: 0.25, blue: 0.2)
        case .noodle: return Color(red: 0.9, green: 0.3, blue: 0.2)
        case .sandwich: return Color(red: 0.4, green: 0.7, blue: 0.3)
        case .fruit: return Color(red: 0.95, green: 0.3, blue: 0.3)
        case .toy: return Color(red: 1, green: 0.85, blue: 0.3)
        }
    }

    var price: Int {
        switch self {
        case .soda: return 4
        case .snack: return 5
        case .noodle: return 7
        case .sandwich: return 9
        case .fruit: return 11
        case .toy: return 15
        }
    }
}

/// 歩く人（店員・お客さん・係）
struct MartWalker {
    var pos: CGPoint
    var facing: CGFloat = 1
    var moving = false
    var step: Double = 0
    var carry: [MartProduct] = []
}

struct MartCustomer: Identifiable {
    enum Phase { case toShelf, shopping, toQueue, queued, leaving }
    let id = UUID()
    var walker: MartWalker
    var phase: Phase = .toShelf
    var product: MartProduct
    var want: Int
    var got = 0
    var path: [CGPoint] = []
    var timer: Double = 0
    var shirt: Int
}

struct MartHelper {
    enum Phase { case idle, toSupply, loading, toShelf, unloading }
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
        case .shelf(let k): return MartProduct(rawValue: k)?.name ?? "棚"
        case .cashier: return "レジ係"
        case .stocker: return "品出し係"
        case .capacity: return "運べる数 +2"
        case .speed: return "足が速くなる"
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

@MainActor
final class MartGame: ObservableObject {
    // 店の形
    static let floor = CGRect(x: 0, y: 0, width: 14.5, height: 11)
    static let counter = CGRect(x: 12.0, y: 2.6, width: 1.0, height: 2.3)
    static let cashierSpot = CGPoint(x: 13.65, y: 3.75)
    static let serveSpot = CGPoint(x: 11.35, y: 3.75)
    static let cashSpot = CGPoint(x: 12.5, y: 5.7)
    static let door = CGPoint(x: 14.2, y: 10)
    static let outside = CGPoint(x: 16.5, y: 10)

    static func shelfRect(_ k: Int) -> CGRect {
        CGRect(x: 2.4 + 2.0 * CGFloat(k % 4), y: k < 4 ? 2.0 : 6.0, width: 1.6, height: 0.8)
    }

    /// お客さんが立って商品を取る場所（棚の手前）
    static func shelfFront(_ k: Int) -> CGPoint {
        let rect = shelfRect(k)
        return CGPoint(x: rect.midX, y: rect.maxY + 0.5)
    }

    /// 倉庫の台（左の壁ぞい）
    static func supplySpot(_ k: Int) -> CGPoint {
        CGPoint(x: 0.95, y: 1.4 + 1.5 * CGFloat(k))
    }

    static let shelfCapacity = 8

    static let steps: [MartStep] = [
        MartStep(kind: .shelf(1), cost: 20, pos: CGPoint(x: shelfRect(1).midX, y: shelfRect(1).midY)),
        MartStep(kind: .capacity, cost: 40, pos: CGPoint(x: 5.2, y: 9.9)),
        MartStep(kind: .shelf(2), cost: 70, pos: CGPoint(x: shelfRect(2).midX, y: shelfRect(2).midY)),
        MartStep(kind: .cashier, cost: 100, pos: CGPoint(x: 13.65, y: 2.2)),
        MartStep(kind: .shelf(3), cost: 150, pos: CGPoint(x: shelfRect(3).midX, y: shelfRect(3).midY)),
        MartStep(kind: .speed, cost: 140, pos: CGPoint(x: 7.0, y: 9.9)),
        MartStep(kind: .stocker, cost: 220, pos: CGPoint(x: 2.2, y: 9.9)),
        MartStep(kind: .shelf(4), cost: 260, pos: CGPoint(x: shelfRect(4).midX, y: shelfRect(4).midY)),
        MartStep(kind: .customers, cost: 200, pos: CGPoint(x: 8.8, y: 9.9)),
        MartStep(kind: .capacity, cost: 320, pos: CGPoint(x: 5.2, y: 9.9)),
        MartStep(kind: .shelf(5), cost: 420, pos: CGPoint(x: shelfRect(5).midX, y: shelfRect(5).midY)),
        MartStep(kind: .stocker, cost: 500, pos: CGPoint(x: 2.2, y: 9.9)),
        MartStep(kind: .customers, cost: 450, pos: CGPoint(x: 8.8, y: 9.9)),
        MartStep(kind: .speed, cost: 600, pos: CGPoint(x: 7.0, y: 9.9)),
    ]

    @Published private(set) var money = 0
    @Published private(set) var level = 0
    /// 解放したときの合図（画面に出す文）
    @Published var banner: String?

    var player = MartWalker(pos: CGPoint(x: 6.5, y: 9.0))
    /// 画面の真ん中に映す場所（店員を少し遅れて追いかける）
    private(set) var camera = CGPoint(x: 6.5, y: 9.0)
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
    private(set) var speed: CGFloat = 3.0
    private(set) var maxCustomers = 3
    /// 会計の進み具合（0〜1）
    private(set) var serving: Double = 0
    /// 指で動かす向き（画面から入れる。長さ 0〜1）
    var stick: CGVector = .zero

    private var queue: [UUID] = []
    private var spawnTimer: Double = 1
    private var pickTimer: Double = 0
    private var dropTimer: Double = 0
    private var cashTimer: Double = 0
    private var payCarry: Double = 0
    private var saveTimer: Double = 0
    private var soundTimer: Double = 0

    init() { load() }

    var unlockedProducts: [MartProduct] {
        MartProduct.allCases.filter { unlocked.contains($0.rawValue) }
    }

    /// いま見せる解放マーク（まだのものから順に 2 つ）
    var visibleSteps: [(Int, MartStep)] {
        Self.steps.enumerated().filter { !done.contains($0.offset) }.prefix(2).map { ($0.offset, $0.element) }
    }

    func paidAmount(_ index: Int) -> Int { paid[index] ?? 0 }

    func queueIndex(of id: UUID) -> Int? { queue.firstIndex(of: id) }

    // MARK: - 1 コマ進める

    func update(_ dt: Double) {
        soundTimer -= dt
        movePlayer(dt)
        let follow = min(1, CGFloat(dt) * 6)
        camera.x += (player.pos.x - camera.x) * follow
        camera.y += (player.pos.y - camera.y) * follow
        handleSupplyAndShelves(dt)
        handleRegister(dt)
        handleCash(dt)
        handlePads(dt)
        spawnCustomers(dt)
        for index in customers.indices { updateCustomer(&customers[index], dt) }
        customers.removeAll { $0.phase == .leaving && $0.path.isEmpty }
        for index in helpers.indices { updateHelper(&helpers[index], dt) }
        saveTimer += dt
        if saveTimer > 5 {
            saveTimer = 0
            save()
        }
    }

    private func movePlayer(_ dt: Double) {
        // 画面の向き → 床の向き（斜め上から見ているので変換する）
        let sx = stick.dx, sy = stick.dy
        let length = min((sx * sx + sy * sy).squareRoot(), 1)
        guard length > 0.08 else {
            player.moving = false
            return
        }
        var wx = sx / 2 + sy
        var wy = sy - sx / 2
        let norm = (wx * wx + wy * wy).squareRoot()
        wx /= norm
        wy /= norm
        let distance = speed * CGFloat(dt) * length
        var next = player.pos
        next.x += wx * distance
        if blocked(next) { next.x = player.pos.x }
        next.y += wy * distance
        if blocked(next) { next.y = player.pos.y }
        player.pos = next
        player.moving = true
        player.step += Double(distance)
        if abs(sx) > 0.05 { player.facing = sx > 0 ? 1 : -1 }
    }

    /// 店員がそこに立てないか（壁・棚・レジ台）
    private func blocked(_ point: CGPoint) -> Bool {
        let r: CGFloat = 0.28
        let inner = Self.floor.insetBy(dx: r + 0.1, dy: r + 0.1)
        if !inner.contains(point) { return true }
        var walls = [Self.counter]
        walls += unlocked.map { Self.shelfRect($0) }
        return walls.contains { $0.insetBy(dx: -r, dy: -r).contains(point) }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func handleSupplyAndShelves(_ dt: Double) {
        pickTimer -= dt
        dropTimer -= dt
        // 倉庫の台：のっている間、運べる数まで受け取る
        for product in unlockedProducts where distance(player.pos, Self.supplySpot(product.rawValue)) < 0.75 {
            if player.carry.count < capacity, pickTimer <= 0 {
                player.carry.append(product)
                pickTimer = 0.12
                tick()
            }
        }
        // 棚のそば：その棚の商品を並べる
        for product in unlockedProducts {
            let zone = Self.shelfRect(product.rawValue).insetBy(dx: -0.75, dy: -0.75)
            guard zone.contains(player.pos), dropTimer <= 0, stock[product.rawValue] < Self.shelfCapacity,
                  let index = player.carry.lastIndex(of: product) else { continue }
            player.carry.remove(at: index)
            stock[product.rawValue] += 1
            dropTimer = 0.1
            tick()
        }
    }

    private func handleRegister(_ dt: Double) {
        let staffed = hasCashier || distance(player.pos, Self.cashierSpot) < 0.7
        guard staffed, let first = queue.first, let index = customers.firstIndex(where: { $0.id == first }),
              customers[index].phase == .queued, distance(customers[index].walker.pos, Self.serveSpot) < 0.15 else {
            serving = 0
            return
        }
        serving += dt / (hasCashier ? 0.9 : 0.6)
        guard serving >= 1 else { return }
        serving = 0
        let customer = customers[index]
        cash += customer.got * customer.product.price
        queue.removeFirst()
        customers[index].phase = .leaving
        customers[index].path = [CGPoint(x: Self.serveSpot.x, y: 10), Self.door, Self.outside]
        GameAudio.shared.play(.tap)
    }

    private func handleCash(_ dt: Double) {
        cashTimer -= dt
        guard cash > 0, distance(player.pos, Self.cashSpot) < 1.0, cashTimer <= 0 else { return }
        let take = max(1, cash / 6)
        cash -= take
        money += take
        cashTimer = 0.05
        if soundTimer <= 0 {
            GameAudio.shared.play(.pop(combo: 1))
            soundTimer = 0.25
        }
    }

    private func handlePads(_ dt: Double) {
        for (index, step) in visibleSteps where distance(player.pos, step.pos) < 0.75 && money > 0 {
            let rate = max(Double(step.cost) / 1.3, 25)
            payCarry += rate * dt
            let amount = min(Int(payCarry), money, step.cost - paidAmount(index))
            guard amount > 0 else { continue }
            payCarry -= Double(amount)
            money -= amount
            paid[index] = paidAmount(index) + amount
            if soundTimer <= 0 {
                GameAudio.shared.tick()
                soundTimer = 0.08
            }
            if paidAmount(index) >= step.cost { complete(index, step) }
        }
    }

    private func complete(_ index: Int, _ step: MartStep) {
        done.insert(index)
        paid[index] = nil
        level = done.count
        switch step.kind {
        case .shelf(let k):
            unlocked.insert(k)
            // 新しい棚に店員がはまらないよう、手前に出す
            if Self.shelfRect(k).insetBy(dx: -0.3, dy: -0.3).contains(player.pos) {
                player.pos = Self.shelfFront(k)
            }
        case .cashier:
            hasCashier = true
        case .stocker:
            helpers.append(MartHelper(walker: MartWalker(pos: CGPoint(x: 1.8, y: 9.5))))
        case .capacity:
            capacity += 2
        case .speed:
            speed += 0.6
        case .customers:
            maxCustomers += 2
        }
        banner = "🎉 \(step.title)"
        GameAudio.shared.play(.complete)
        save()
    }

    private func tick() {
        if soundTimer <= 0 {
            GameAudio.shared.play(.tap)
            soundTimer = 0.09
        }
    }

    // MARK: - お客さん

    private func spawnCustomers(_ dt: Double) {
        spawnTimer -= dt
        guard spawnTimer <= 0, customers.count < maxCustomers, let product = unlockedProducts.randomElement() else { return }
        spawnTimer = Double.random(in: 1.5...3.5)
        let front = Self.shelfFront(product.rawValue)
        let want = Int.random(in: 1...min(3, 1 + level / 3))
        var customer = MartCustomer(walker: MartWalker(pos: Self.outside), product: product, want: want,
                                    shirt: Int.random(in: 0..<8))
        customer.path = [Self.door, CGPoint(x: 11.0, y: 10), CGPoint(x: 11.0, y: front.y), front]
        customers.append(customer)
    }

    private func updateCustomer(_ customer: inout MartCustomer, _ dt: Double) {
        switch customer.phase {
        case .toShelf:
            if follow(&customer.walker, path: &customer.path, speed: 1.9, dt: dt) { customer.phase = .shopping }
        case .shopping:
            customer.timer -= dt
            let k = customer.product.rawValue
            if customer.timer <= 0, stock[k] > 0, customer.got < customer.want {
                stock[k] -= 1
                customer.got += 1
                customer.timer = 0.45
            }
            if customer.got >= customer.want, customer.timer <= 0 {
                queue.append(customer.id)
                customer.phase = .toQueue
                let front = Self.shelfFront(k)
                customer.path = [CGPoint(x: 11.0, y: front.y)]
            }
        case .toQueue:
            if follow(&customer.walker, path: &customer.path, speed: 1.9, dt: dt) { customer.phase = .queued }
        case .queued:
            let index = queue.firstIndex(of: customer.id) ?? 0
            var target = Self.serveSpot
            target.y += 0.75 * CGFloat(index)
            var path = [target]
            _ = follow(&customer.walker, path: &path, speed: 1.9, dt: dt)
        case .leaving:
            _ = follow(&customer.walker, path: &customer.path, speed: 2.2, dt: dt)
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
        }
        walker.moving = d > 0.01
        // 画面の左右の向き（x − y が増えると右）
        let screenDX = dx - dy
        if abs(screenDX) > 0.01 { walker.facing = screenDX > 0 ? 1 : -1 }
        return path.isEmpty
    }

    // MARK: - 品出し係

    private func updateHelper(_ helper: inout MartHelper, _ dt: Double) {
        switch helper.phase {
        case .idle:
            // いちばん減っている棚を選ぶ
            guard let product = unlockedProducts.min(by: { stock[$0.rawValue] < stock[$1.rawValue] }),
                  stock[product.rawValue] < Self.shelfCapacity - 1 else {
                helper.walker.moving = false
                return
            }
            helper.target = product
            let supply = Self.supplySpot(product.rawValue)
            helper.path = [CGPoint(x: 1.8, y: helper.walker.pos.y), CGPoint(x: 1.8, y: supply.y), supply]
            helper.phase = .toSupply
        case .toSupply:
            if follow(&helper.walker, path: &helper.path, speed: 2.2, dt: dt) { helper.phase = .loading }
        case .loading:
            helper.timer -= dt
            if helper.timer <= 0 {
                helper.walker.carry.append(helper.target)
                helper.timer = 0.15
            }
            if helper.walker.carry.count >= 4 {
                let front = Self.shelfFront(helper.target.rawValue)
                helper.path = [CGPoint(x: 1.8, y: helper.walker.pos.y), CGPoint(x: 1.8, y: front.y), front]
                helper.phase = .toShelf
            }
        case .toShelf:
            if follow(&helper.walker, path: &helper.path, speed: 2.2, dt: dt) { helper.phase = .unloading }
        case .unloading:
            helper.timer -= dt
            let k = helper.target.rawValue
            if helper.timer <= 0, !helper.walker.carry.isEmpty {
                if stock[k] < Self.shelfCapacity {
                    helper.walker.carry.removeLast()
                    stock[k] += 1
                    helper.timer = 0.15
                } else {
                    helper.walker.carry.removeAll()
                }
            }
            if helper.walker.carry.isEmpty {
                let front = Self.shelfFront(k)
                helper.walker.pos = front
                helper.phase = .idle
            }
        }
    }

    // MARK: - 保存

    private struct SaveData: Codable {
        var money: Int
        var done: [Int]
        var paid: [Int: Int]
        var stock: [Int]
        var cash: Int
    }

    func save() {
        let data = SaveData(money: money, done: Array(done), paid: paid, stock: stock, cash: cash)
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "martSave")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "martSave"),
              let saved = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        money = saved.money
        paid = saved.paid
        cash = saved.cash
        if saved.stock.count == stock.count { stock = saved.stock }
        // 解放したものを、順にもう一度当てはめる
        for index in saved.done.sorted() where Self.steps.indices.contains(index) {
            done.insert(index)
            switch Self.steps[index].kind {
            case .shelf(let k): unlocked.insert(k)
            case .cashier: hasCashier = true
            case .stocker: helpers.append(MartHelper(walker: MartWalker(pos: CGPoint(x: 1.8, y: 9.5))))
            case .capacity: capacity += 2
            case .speed: speed += 0.6
            case .customers: maxCustomers += 2
            }
        }
        level = done.count
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: "martSave")
        money = 0
        level = 0
        done = []
        paid = [:]
        stock = Array(repeating: 0, count: MartProduct.allCases.count)
        unlocked = [0]
        cash = 0
        hasCashier = false
        capacity = 4
        speed = 3.0
        maxCustomers = 3
        helpers = []
        customers = []
        queue = []
        player = MartWalker(pos: CGPoint(x: 6.5, y: 9.0))
    }
}
