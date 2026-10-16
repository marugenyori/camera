import Foundation

/// 「ふたりの文明」のルール。シビライゼーションへのオマージュで、2 人が 1 つの文明を交代で育てる協力ゲーム。
/// - 自分の番では「行動」を 3 回まで使える：都市を作る・土地を改良する（畑・鉱山・港）・都市に建物を建てる・
///   世界の不思議を建てる・霧の向こうを探検する
/// - 番を終えると、都市が働いて資材（🔨）と知識（📖）が入り、食料で人口が増える。知識で技術を研究すると、建てられるものが増える
/// - 宇宙船を打ち上げたら 2 人の勝ち
/// 状態（CivState）はまるごと相手に送る（近くなら直接、離れていれば iCloud の共有アルバム）。version が大きいほうが新しい
enum CivTerrain: String, Codable, CaseIterable {
    case grass, plains, forest, hills, mountain, water, desert

    var name: String {
        switch self {
        case .grass: return "草原"
        case .plains: return "平原"
        case .forest: return "森"
        case .hills: return "丘"
        case .mountain: return "山"
        case .water: return "海"
        case .desert: return "砂漠"
        }
    }

    var height: Int {
        switch self {
        case .water: return 0
        case .hills: return 2
        case .mountain: return 3
        default: return 1
        }
    }

    var isLand: Bool { self != .water }

    /// 何もしていない土地の、食料・資材・知識
    var yield: CivYield {
        switch self {
        case .grass: return CivYield(food: 2)
        case .plains: return CivYield(food: 1, prod: 1)
        case .forest: return CivYield(food: 1, prod: 2)
        case .hills: return CivYield(prod: 2)
        case .mountain: return CivYield(prod: 1)
        case .water: return CivYield(food: 1, sci: 1)
        case .desert: return CivYield()
        }
    }
}

struct CivYield: Codable, Equatable {
    var food = 0
    var prod = 0
    var sci = 0

    static func + (a: CivYield, b: CivYield) -> CivYield {
        CivYield(food: a.food + b.food, prod: a.prod + b.prod, sci: a.sci + b.sci)
    }

    /// 都市が働く土地を選ぶときの点数（食料を少し重く見る）
    var score: Int { food * 3 + prod * 2 + sci * 2 }
}

enum CivImprovement: String, Codable, CaseIterable {
    case farm, mine, harbor

    var name: String {
        switch self {
        case .farm: return "畑"
        case .mine: return "鉱山"
        case .harbor: return "港"
        }
    }

    var cost: Int {
        switch self {
        case .farm: return 10
        case .mine: return 15
        case .harbor: return 20
        }
    }

    var tech: CivTech {
        switch self {
        case .farm: return .agriculture
        case .mine: return .mining
        case .harbor: return .sailing
        }
    }

    func allowed(on terrain: CivTerrain) -> Bool {
        switch self {
        case .farm: return [.grass, .plains, .desert].contains(terrain)
        case .mine: return [.hills, .mountain].contains(terrain)
        case .harbor: return terrain == .water
        }
    }

    func bonus(on terrain: CivTerrain) -> CivYield {
        switch self {
        case .farm: return CivYield(food: terrain == .desert ? 2 : 1)
        case .mine: return CivYield(prod: 2)
        case .harbor: return CivYield(food: 1, prod: 1)
        }
    }
}

enum CivTech: String, Codable, CaseIterable, Identifiable {
    case agriculture, pottery, mining, bronze, writing, sailing, masonry, mysticism, currency, literature,
         education, industry, electricity, rocketry
    var id: String { rawValue }

    var name: String {
        switch self {
        case .agriculture: return "農業"
        case .pottery: return "陶器"
        case .mining: return "採掘"
        case .bronze: return "青銅器"
        case .writing: return "文字"
        case .sailing: return "航海"
        case .masonry: return "石工"
        case .mysticism: return "神秘"
        case .currency: return "通貨"
        case .literature: return "文学"
        case .education: return "教育"
        case .industry: return "産業"
        case .electricity: return "電気"
        case .rocketry: return "ロケット"
        }
    }

    var symbol: String {
        switch self {
        case .agriculture: return "leaf.fill"
        case .pottery: return "cup.and.saucer.fill"
        case .mining: return "hammer.fill"
        case .bronze: return "shield.fill"
        case .writing: return "pencil.and.scribble"
        case .sailing: return "sailboat.fill"
        case .masonry: return "building.columns.fill"
        case .mysticism: return "sparkles"
        case .currency: return "dollarsign.circle.fill"
        case .literature: return "book.fill"
        case .education: return "graduationcap.fill"
        case .industry: return "gearshape.2.fill"
        case .electricity: return "bolt.fill"
        case .rocketry: return "airplane.departure"
        }
    }

    var requires: [CivTech] {
        switch self {
        case .agriculture, .mining: return []
        case .pottery: return [.agriculture]
        case .bronze, .masonry: return [.mining]
        case .writing, .sailing: return [.pottery]
        case .mysticism: return [.writing]
        case .currency: return [.bronze]
        case .literature: return [.writing]
        case .education: return [.literature, .currency]
        case .industry: return [.education, .sailing]
        case .electricity: return [.industry]
        case .rocketry: return [.electricity, .masonry]
        }
    }

    var cost: Int {
        switch self {
        case .agriculture, .mining: return 12
        case .pottery, .bronze, .masonry: return 20
        case .writing, .sailing, .mysticism: return 30
        case .currency, .literature: return 45
        case .education: return 70
        case .industry: return 100
        case .electricity: return 130
        case .rocketry: return 170
        }
    }

    /// 研究すると何ができるようになるか
    var unlocks: String {
        let improvements = CivImprovement.allCases.filter { $0.tech == self }.map(\.name)
        let buildings = CivBuilding.allCases.filter { $0.tech == self }.map(\.name)
        let wonders = CivWonder.allCases.filter { $0.tech == self }.map(\.name)
        let all = improvements + buildings + wonders
        return all.isEmpty ? "—" : all.joined(separator: "・")
    }
}

enum CivBuilding: String, Codable, CaseIterable, Identifiable {
    case granary, workshop, library, temple, market, university, factory, powerPlant
    var id: String { rawValue }

    var name: String {
        switch self {
        case .granary: return "穀物庫"
        case .workshop: return "工房"
        case .library: return "図書館"
        case .temple: return "神殿"
        case .market: return "市場"
        case .university: return "大学"
        case .factory: return "工場"
        case .powerPlant: return "発電所"
        }
    }

    var symbol: String {
        switch self {
        case .granary: return "archivebox.fill"
        case .workshop: return "hammer.circle.fill"
        case .library: return "books.vertical.fill"
        case .temple: return "building.columns"
        case .market: return "cart.fill"
        case .university: return "graduationcap.fill"
        case .factory: return "building.2.fill"
        case .powerPlant: return "bolt.circle.fill"
        }
    }

    var cost: Int {
        switch self {
        case .granary: return 25
        case .workshop: return 30
        case .library: return 35
        case .temple: return 30
        case .market: return 45
        case .university: return 70
        case .factory: return 90
        case .powerPlant: return 110
        }
    }

    var tech: CivTech {
        switch self {
        case .granary: return .pottery
        case .workshop: return .bronze
        case .library: return .writing
        case .temple: return .mysticism
        case .market: return .currency
        case .university: return .education
        case .factory: return .industry
        case .powerPlant: return .electricity
        }
    }

    var yield: CivYield {
        switch self {
        case .granary: return CivYield(food: 2)
        case .workshop: return CivYield(prod: 2)
        case .library: return CivYield(sci: 3)
        case .temple: return CivYield()
        case .market: return CivYield(food: 1, prod: 2, sci: 1)
        case .university: return CivYield(sci: 5)
        case .factory: return CivYield(prod: 5)
        case .powerPlant: return CivYield(prod: 4, sci: 3)
        }
    }

    var effect: String {
        switch self {
        case .granary: return "食料 +2"
        case .workshop: return "資材 +2"
        case .library: return "知識 +3"
        case .temple: return "領土が広がる（まわり 2 マス）"
        case .market: return "食料 +1・資材 +2・知識 +1"
        case .university: return "知識 +5"
        case .factory: return "資材 +5"
        case .powerPlant: return "資材 +4・知識 +3"
        }
    }
}

enum CivWonder: String, Codable, CaseIterable, Identifiable {
    case pyramids, colossus, greatLibrary, spaceship
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pyramids: return "ピラミッド"
        case .colossus: return "巨像"
        case .greatLibrary: return "大図書館"
        case .spaceship: return "宇宙船"
        }
    }

    var cost: Int {
        switch self {
        case .pyramids: return 80
        case .colossus: return 70
        case .greatLibrary: return 110
        case .spaceship: return 300
        }
    }

    var tech: CivTech {
        switch self {
        case .pyramids: return .masonry
        case .colossus: return .sailing
        case .greatLibrary: return .literature
        case .spaceship: return .rocketry
        }
    }

    var effect: String {
        switch self {
        case .pyramids: return "すべての都市で資材 +1"
        case .colossus: return "海のマスで食料 +1"
        case .greatLibrary: return "知識 +6"
        case .spaceship: return "打ち上げたら 2 人の勝ち！"
        }
    }
}

struct CivTile: Codable, Equatable {
    var terrain: CivTerrain
    var improvement: CivImprovement?
    var revealed = false
    /// 遺跡（探検すると何かが見つかる）
    var ruin = false
}

struct CivCity: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var x: Int
    var y: Int
    var pop = 1
    /// たまった食料（いっぱいになると人口が増える）
    var food = 0
    var buildings: [CivBuilding] = []
    /// 作った人（players の番号）
    var founder: Int

    var growThreshold: Int { 6 + pop * 3 }
    var radius: Int { buildings.contains(.temple) ? 2 : (pop >= 5 ? 2 : 1) }
}

struct CivPlayer: Codable, Equatable {
    /// 近く・ひとり：この端末の ID、離れて：iCloud のユーザー ID
    var id: String
    var name: String
    var color: Int
}

struct CivLog: Codable, Equatable {
    var turn: Int
    var text: String
}

struct CivState: Codable, Equatable {
    static let size = 14
    static let actionsPerTurn = 3

    var version = 0
    var tiles: [CivTile]
    var cities: [CivCity] = []
    var players: [CivPlayer]
    var turn = 1
    var current = 0
    var actions = CivState.actionsPerTurn
    /// たまっている資材
    var production = 15
    var techs: [CivTech] = [.agriculture]
    var research: CivTech? = .mining
    /// 研究にたまった知識
    var progress = 0
    var wonders: [CivWonder] = []
    var log: [CivLog] = []
    var won = false
    var nameIndex = 0

    static let cityNames = ["はじまりの都", "みなと町", "さくら村", "いしの里", "ひかり市", "もりの郷", "かぜの町",
                            "ほしの都", "ゆきの村", "こはく市", "あおぞら町", "つきの里", "にじ市", "すずらん村"]

    // MARK: - 始める

    static func new(host: CivPlayer) -> CivState {
        let n = size
        var tiles: [CivTile] = []
        // 大陸：いくつかの丸い島を重ねる
        let blobs = (0..<4).map { _ in (Double.random(in: 3...Double(n - 4)), Double.random(in: 3...Double(n - 4)),
                                        Double.random(in: 3...5)) }
        for y in 0..<n {
            for x in 0..<n {
                var land = 0.0
                for blob in blobs {
                    let d = ((Double(x) - blob.0) * (Double(x) - blob.0) + (Double(y) - blob.1) * (Double(y) - blob.1)).squareRoot()
                    land = max(land, 1 - d / blob.2)
                }
                land += Double.random(in: -0.15...0.15)
                let terrain: CivTerrain
                if land < 0.12 {
                    terrain = .water
                } else {
                    let r = Double.random(in: 0...1)
                    if land > 0.7 && r < 0.18 {
                        terrain = .mountain
                    } else if land > 0.45 && r < 0.3 {
                        terrain = .hills
                    } else if r < 0.48 {
                        terrain = .grass
                    } else if r < 0.68 {
                        terrain = .plains
                    } else if r < 0.88 {
                        terrain = .forest
                    } else {
                        terrain = .desert
                    }
                }
                tiles.append(CivTile(terrain: terrain))
            }
        }
        var state = CivState(tiles: tiles, players: [host])
        // 遺跡
        let landIndices = tiles.indices.filter { tiles[$0].terrain.isLand && tiles[$0].terrain != .mountain }
        for index in landIndices.shuffled().prefix(5) { state.tiles[index].ruin = true }
        // 首都：真ん中に近い、草原か平原
        let center = Double(n - 1) / 2
        let start = landIndices
            .filter { [.grass, .plains].contains(tiles[$0].terrain) }
            .min { a, b in
                let da = abs(Double(a % n) - center) + abs(Double(a / n) - center)
                let db = abs(Double(b % n) - center) + abs(Double(b / n) - center)
                return da < db
            } ?? (n / 2) * n + n / 2
        state.tiles[start].terrain = .grass
        state.tiles[start].ruin = false
        state.addCity(at: start % n, start / n, by: 0)
        state.note("\(host.name)さんが文明をおこしました")
        return state
    }

    // MARK: - マス

    func index(_ x: Int, _ y: Int) -> Int { y * Self.size + x }

    func tile(_ x: Int, _ y: Int) -> CivTile? {
        guard (0..<Self.size).contains(x), (0..<Self.size).contains(y) else { return nil }
        return tiles[index(x, y)]
    }

    func city(at x: Int, _ y: Int) -> Int? {
        cities.firstIndex { $0.x == x && $0.y == y }
    }

    /// そのマスを持っている都市（いちばん近い都市。領土の外なら nil）
    func owner(of x: Int, _ y: Int) -> Int? {
        var best: (Int, Int)?
        for (index, city) in cities.enumerated() {
            let d = max(abs(city.x - x), abs(city.y - y))
            guard d <= city.radius else { continue }
            if best == nil || d < best!.1 { best = (index, d) }
        }
        return best?.0
    }

    func yield(of x: Int, _ y: Int) -> CivYield {
        guard let tile = tile(x, y) else { return CivYield() }
        var result = tile.terrain.yield
        if let improvement = tile.improvement { result = result + improvement.bonus(on: tile.terrain) }
        if tile.terrain == .water && wonders.contains(.colossus) { result.food += 1 }
        return result
    }

    /// 都市が働く土地（人口 + 1 マスを、点数の高い順に）
    func workedTiles(of cityIndex: Int) -> [(Int, Int)] {
        let city = cities[cityIndex]
        var candidates: [(Int, Int)] = []
        for dy in -city.radius...city.radius {
            for dx in -city.radius...city.radius where dx != 0 || dy != 0 {
                let x = city.x + dx, y = city.y + dy
                guard let tile = tile(x, y), tile.revealed, owner(of: x, y) == cityIndex else { continue }
                candidates.append((x, y))
            }
        }
        return Array(candidates.sorted { yield(of: $0.0, $0.1).score > yield(of: $1.0, $1.1).score }.prefix(city.pop + 1))
    }

    func cityYield(_ cityIndex: Int) -> CivYield {
        let city = cities[cityIndex]
        var total = CivYield(food: 2, prod: 1, sci: 1 + city.pop / 2)
        for (x, y) in workedTiles(of: cityIndex) { total = total + yield(of: x, y) }
        for building in city.buildings { total = total + building.yield }
        if wonders.contains(.pyramids) { total.prod += 1 }
        if wonders.contains(.greatLibrary) && cityIndex == 0 { total.sci += 6 }
        return total
    }

    /// 1 回の番で入る資材と知識
    var income: CivYield {
        cities.indices.map { cityYield($0) }.reduce(CivYield(), +)
    }

    var era: String {
        switch techs.count {
        case ..<4: return "古代"
        case ..<8: return "中世"
        case ..<12: return "近代"
        default: return "未来"
        }
    }

    func canResearch(_ tech: CivTech) -> Bool {
        !techs.contains(tech) && tech.requires.allSatisfy { techs.contains($0) }
    }

    // MARK: - 行動

    enum Action {
        case foundCity(Int, Int)
        case improve(Int, Int, CivImprovement)
        case build(Int, CivBuilding)
        case wonder(Int, CivWonder)
        case explore(Int, Int)
        case research(CivTech)
    }

    static let cityCost = 30

    /// その行動ができない理由（できるなら nil）
    func problem(_ action: Action) -> String? {
        if case .research(let tech) = action {
            return canResearch(tech) ? nil : "まだ研究できません"
        }
        if won { return "ゲームは終わりました" }
        if actions <= 0 { return "この番の行動はもうありません" }
        switch action {
        case .foundCity(let x, let y):
            guard let tile = tile(x, y), tile.revealed else { return "見えていない場所です" }
            guard tile.terrain.isLand, tile.terrain != .mountain else { return "ここには都市を作れません" }
            if cities.contains(where: { max(abs($0.x - x), abs($0.y - y)) < 3 }) { return "ほかの都市に近すぎます" }
            if production < Self.cityCost { return "資材が足りません（🔨\(Self.cityCost)）" }
        case .improve(let x, let y, let kind):
            guard let tile = tile(x, y), tile.revealed else { return "見えていない場所です" }
            guard techs.contains(kind.tech) else { return "「\(kind.tech.name)」の研究が必要です" }
            guard kind.allowed(on: tile.terrain) else { return "ここには作れません" }
            guard owner(of: x, y) != nil, city(at: x, y) == nil else { return "都市の領土の中だけです" }
            guard tile.improvement == nil else { return "もう改良してあります" }
            if production < kind.cost { return "資材が足りません（🔨\(kind.cost)）" }
        case .build(let cityIndex, let building):
            guard cities.indices.contains(cityIndex) else { return "都市がありません" }
            guard techs.contains(building.tech) else { return "「\(building.tech.name)」の研究が必要です" }
            if cities[cityIndex].buildings.contains(building) { return "もう建っています" }
            if production < building.cost { return "資材が足りません（🔨\(building.cost)）" }
        case .wonder(let cityIndex, let wonder):
            guard cities.indices.contains(cityIndex) else { return "都市がありません" }
            guard techs.contains(wonder.tech) else { return "「\(wonder.tech.name)」の研究が必要です" }
            if wonders.contains(wonder) { return "もう建っています" }
            if production < wonder.cost { return "資材が足りません（🔨\(wonder.cost)）" }
        case .explore(let x, let y):
            guard let tile = tile(x, y) else { return "見えていない場所です" }
            if tile.revealed {
                // 見えている遺跡は、そのまま調べられる
                if !tile.ruin { return "もう見えています" }
            } else {
                let near = (-1...1).contains { dy in (-1...1).contains { dx in self.tile(x + dx, y + dy)?.revealed == true } }
                if !near { return "見えている場所のとなりだけ探検できます" }
            }
        case .research:
            break
        }
        return nil
    }

    /// 行動する（できなければ false）。who は行動した人の番号
    mutating func perform(_ action: Action, by who: Int) -> Bool {
        guard problem(action) == nil else { return false }
        let name = players.indices.contains(who) ? players[who].name : "だれか"
        switch action {
        case .research(let tech):
            research = tech
            version += 1
            return true
        case .foundCity(let x, let y):
            production -= Self.cityCost
            addCity(at: x, y, by: who)
            note("\(name)さんが「\(cities.last?.name ?? "")」を作りました")
        case .improve(let x, let y, let kind):
            production -= kind.cost
            tiles[index(x, y)].improvement = kind
            note("\(name)さんが\(kind.name)を作りました")
        case .build(let cityIndex, let building):
            production -= building.cost
            cities[cityIndex].buildings.append(building)
            note("\(name)さんが\(cities[cityIndex].name)に\(building.name)を建てました")
        case .wonder(_, let wonder):
            production -= wonder.cost
            wonders.append(wonder)
            if wonder == .spaceship {
                won = true
                note("🚀 宇宙船が打ち上がりました！ \(turn) ターンで 2 人の勝ち")
            } else {
                note("🏛 \(name)さんが世界の不思議「\(wonder.name)」を完成させました")
            }
        case .explore(let x, let y):
            reveal(x, y, radius: 1)
            if tiles[index(x, y)].ruin {
                tiles[index(x, y)].ruin = false
                findRuin(by: name)
            } else {
                note("\(name)さんが探検しました")
            }
        }
        actions -= 1
        version += 1
        return true
    }

    private mutating func findRuin(by name: String) {
        switch Int.random(in: 0..<3) {
        case 0:
            production += 25
            note("🏺 \(name)さんが遺跡で宝物を見つけました（🔨+25）")
        case 1:
            progress += 20
            note("📜 \(name)さんが遺跡で古い巻物を見つけました（📖+20）")
        default:
            if let index = cities.indices.randomElement() {
                cities[index].pop += 1
                note("👪 \(name)さんが遺跡で旅の一族に出会い、\(cities[index].name)に住みました（人口+1）")
            }
        }
    }

    mutating func addCity(at x: Int, _ y: Int, by who: Int) {
        let name = Self.cityNames[nameIndex % Self.cityNames.count]
        nameIndex += 1
        cities.append(CivCity(name: name, x: x, y: y, founder: who))
        tiles[index(x, y)].improvement = nil
        reveal(x, y, radius: 2)
    }

    mutating func reveal(_ x: Int, _ y: Int, radius: Int) {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let tx = x + dx, ty = y + dy
                guard (0..<Self.size).contains(tx), (0..<Self.size).contains(ty) else { continue }
                tiles[index(tx, ty)].revealed = true
            }
        }
    }

    mutating func note(_ text: String) {
        log.append(CivLog(turn: turn, text: text))
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    // MARK: - 番を終える

    mutating func endTurn() {
        guard !won else { return }
        let name = players.indices.contains(current) ? players[current].name : ""
        // 都市が働く
        for index in cities.indices {
            let y = cityYield(index)
            production += y.prod
            progress += y.sci
            cities[index].food += y.food - cities[index].pop * 2
            if cities[index].food >= cities[index].growThreshold {
                cities[index].pop += 1
                cities[index].food = cities[index].buildings.contains(.granary) ? cities[index].growThreshold / 3 : 0
                note("👶 \(cities[index].name)の人口が \(cities[index].pop) になりました")
                reveal(cities[index].x, cities[index].y, radius: cities[index].radius + 1)
            } else if cities[index].food < 0 {
                cities[index].food = 0
            }
        }
        // 研究
        if let tech = research, progress >= tech.cost {
            progress -= tech.cost
            techs.append(tech)
            research = CivTech.allCases.first { canResearch($0) }
            note("💡「\(tech.name)」を発見！ \(tech.unlocks)が使えるようになりました")
        }
        // ときどき起きること
        if Int.random(in: 0..<4) == 0 { randomEvent() }
        note("\(name)さんが番を終えました")
        current = players.isEmpty ? 0 : (current + 1) % players.count
        if current == 0 { turn += 1 }
        actions = Self.actionsPerTurn
        version += 1
    }

    private mutating func randomEvent() {
        switch Int.random(in: 0..<5) {
        case 0:
            if let index = cities.indices.randomElement() {
                cities[index].food += 5
                note("🌾 \(cities[index].name)で豊作！ 食料がたくさんとれました")
            }
        case 1:
            progress += 10
            note("🔭 学者がひらめきました（📖+10）")
        case 2:
            production += 15
            note("🧱 職人たちががんばりました（🔨+15）")
        case 3:
            let farms = tiles.indices.filter { tiles[$0].improvement == .farm }
            if let farm = farms.randomElement() {
                tiles[farm].improvement = nil
                note("🌀 嵐で畑が 1 つ流されました")
            } else {
                note("🌈 おだやかな日が続いています")
            }
        default:
            note("🎉 \(cities.randomElement()?.name ?? "都")でお祭りがありました")
        }
    }

    // MARK: - 参加

    /// 2 人目が参加する（もういれば何もしない）。変わったら true
    mutating func join(_ player: CivPlayer) -> Bool {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            if players[index].name != player.name {
                players[index].name = player.name
                version += 1
                return true
            }
            return false
        }
        guard players.count < 2 else { return false }
        var newcomer = player
        newcomer.color = players.count
        players.append(newcomer)
        note("🤝 \(player.name)さんが参加しました")
        version += 1
        return true
    }
}
