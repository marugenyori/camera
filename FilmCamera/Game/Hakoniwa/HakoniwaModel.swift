import SwiftUI

/// 箱庭ゲームの中身：12×12 のマス。マスごとに地面の種類・高さ・置いたもの。
/// 人や動物（いきもの）はマスの上を勝手に歩きまわる。時間（朝・昼・夕方・夜）と天気（晴れ・雨・雪）がある。
/// 作った箱庭は UserDefaults に自動で保存する
enum HGround: String, Codable, CaseIterable, Identifiable {
    case grass, meadow, sand, water, path, farm, snow
    var id: String { rawValue }

    var name: String {
        switch self {
        case .grass: return "草"
        case .meadow: return "花畑"
        case .sand: return "砂"
        case .water: return "水"
        case .path: return "石の道"
        case .farm: return "畑"
        case .snow: return "雪"
        }
    }

    /// 上の面の色（となりのマスと少しずつ色を変えて、模様にする）
    func top(_ odd: Bool) -> Color {
        switch self {
        case .grass: return odd ? Color(red: 0.49, green: 0.76, blue: 0.36) : Color(red: 0.45, green: 0.72, blue: 0.33)
        case .meadow: return odd ? Color(red: 0.58, green: 0.8, blue: 0.4) : Color(red: 0.54, green: 0.77, blue: 0.38)
        case .sand: return odd ? Color(red: 0.95, green: 0.86, blue: 0.62) : Color(red: 0.93, green: 0.83, blue: 0.58)
        case .water: return odd ? Color(red: 0.36, green: 0.68, blue: 0.92) : Color(red: 0.33, green: 0.65, blue: 0.9)
        case .path: return odd ? Color(red: 0.78, green: 0.74, blue: 0.68) : Color(red: 0.74, green: 0.7, blue: 0.64)
        case .farm: return odd ? Color(red: 0.6, green: 0.42, blue: 0.27) : Color(red: 0.56, green: 0.39, blue: 0.25)
        case .snow: return odd ? Color(red: 0.97, green: 0.98, blue: 1) : Color(red: 0.92, green: 0.95, blue: 0.99)
        }
    }

    /// 横の面のいちばん上の帯の色
    var band: Color {
        switch self {
        case .grass, .meadow: return Color(red: 0.36, green: 0.6, blue: 0.27)
        case .sand: return Color(red: 0.85, green: 0.74, blue: 0.5)
        case .water: return Color(red: 0.25, green: 0.52, blue: 0.8)
        case .path: return Color(red: 0.62, green: 0.58, blue: 0.53)
        case .farm: return Color(red: 0.47, green: 0.32, blue: 0.2)
        case .snow: return Color(red: 0.85, green: 0.89, blue: 0.95)
        }
    }
}

enum HItem: String, Codable, CaseIterable, Identifiable {
    case tree, pine, sakura, bush, flowers, rock, house, lamp, fence, bench, tent, boat
    var id: String { rawValue }

    var name: String {
        switch self {
        case .tree: return "木"
        case .pine: return "もみの木"
        case .sakura: return "桜"
        case .bush: return "しげみ"
        case .flowers: return "花"
        case .rock: return "岩"
        case .house: return "家"
        case .lamp: return "街灯"
        case .fence: return "さく"
        case .bench: return "ベンチ"
        case .tent: return "テント"
        case .boat: return "ボート"
        }
    }

    /// 水の上にしか置けない
    var onWater: Bool { self == .boat }
    /// いきものが通れない
    var blocks: Bool {
        switch self {
        case .tree, .pine, .sakura, .rock, .house, .fence, .tent, .bush: return true
        default: return false
        }
    }
    /// 置くたびに色を選ぶ（家の屋根・テント・花）
    var tints: Int {
        switch self {
        case .house: return 5
        case .tent: return 3
        default: return 1
        }
    }
}

enum HCritterKind: String, Codable, CaseIterable, Identifiable {
    case person, cat, dog, duck, chicken
    var id: String { rawValue }

    var name: String {
        switch self {
        case .person: return "人"
        case .cat: return "ねこ"
        case .dog: return "いぬ"
        case .duck: return "あひる"
        case .chicken: return "にわとり"
        }
    }

    /// 1 秒に進むマス
    var speed: Double {
        switch self {
        case .person: return 0.9
        case .cat: return 1.2
        case .dog: return 1.5
        case .duck: return 0.5
        case .chicken: return 0.8
        }
    }

    var swims: Bool { self == .duck }
}

struct HCell: Codable, Equatable {
    var ground: HGround = .grass
    /// 0〜4
    var height: Int = 1
    var item: HItem?
    var tint: Int = 0
}

struct HCritter: Codable, Identifiable {
    var id = UUID()
    var kind: HCritterKind
    /// マスの中の位置（マスの真ん中は x + 0.5）
    var x: Double
    var y: Double
    var tx: Int
    var ty: Int
    var tint: Int
    var wait: Double = 0
    /// 歩いた量（足の動きに使う）
    var step: Double = 0
}

@MainActor
final class HakoniwaModel: ObservableObject {
    static let size = 12
    static let maxHeight = 4

    enum Tool: String, CaseIterable, Identifiable {
        case ground, height, item, critter, erase, look
        var id: String { rawValue }
        var name: String {
            switch self {
            case .ground: return "地面"
            case .height: return "高さ"
            case .item: return "もの"
            case .critter: return "いきもの"
            case .erase: return "消す"
            case .look: return "見る"
            }
        }
        var symbol: String {
            switch self {
            case .ground: return "square.fill.on.square.fill"
            case .height: return "arrow.up.and.down.square"
            case .item: return "tree.fill"
            case .critter: return "figure.walk"
            case .erase: return "eraser.fill"
            case .look: return "hand.draw.fill"
            }
        }
    }

    enum HeightAction: String, CaseIterable, Identifiable {
        case up, down, flat
        var id: String { rawValue }
        var name: String {
            switch self {
            case .up: return "上げる"
            case .down: return "下げる"
            case .flat: return "ならす"
            }
        }
    }

    enum TimeMode: String, Codable, CaseIterable, Identifiable {
        case auto, morning, noon, evening, night
        var id: String { rawValue }
        var name: String {
            switch self {
            case .auto: return "時間が進む"
            case .morning: return "朝"
            case .noon: return "昼"
            case .evening: return "夕方"
            case .night: return "夜"
            }
        }
        var symbol: String {
            switch self {
            case .auto: return "clock.arrow.circlepath"
            case .morning: return "sunrise.fill"
            case .noon: return "sun.max.fill"
            case .evening: return "sunset.fill"
            case .night: return "moon.stars.fill"
            }
        }
    }

    enum Weather: String, Codable, CaseIterable, Identifiable {
        case clear, rain, snow
        var id: String { rawValue }
        var name: String {
            switch self {
            case .clear: return "晴れ"
            case .rain: return "雨"
            case .snow: return "雪"
            }
        }
        var symbol: String {
            switch self {
            case .clear: return "sun.max"
            case .rain: return "cloud.rain.fill"
            case .snow: return "snowflake"
            }
        }
    }

    enum Template: String, CaseIterable, Identifiable {
        case blank, island, random
        var id: String { rawValue }
        var name: String {
            switch self {
            case .blank: return "まっさら"
            case .island: return "島"
            case .random: return "おまかせ"
            }
        }
    }

    @Published var cells: [HCell]
    @Published var tool: Tool = .ground
    @Published var ground: HGround = .grass
    @Published var item: HItem = .tree
    @Published var critterKind: HCritterKind = .person
    @Published var heightAction: HeightAction = .up
    @Published var rotation = 0
    @Published var timeMode: TimeMode = .auto { didSet { save() } }
    @Published var weather: Weather = .clear { didSet { save() } }
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero

    /// いきもの（1 秒に何十回も動かすので、@Published にしない。画面は TimelineView で描き直す）
    private(set) var critters: [HCritter]
    /// 時間が進むときの、いまの時刻（0＝真夜中、0.25＝朝、0.5＝昼、0.75＝夕方）
    private(set) var clock: Double = 0.4

    private static let saveKey = "hakoniwaSave"

    private struct SaveData: Codable {
        var cells: [HCell]
        var critters: [HCritter]
        var timeMode: TimeMode
        var weather: Weather
        var rotation: Int
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.saveKey),
           let saved = try? JSONDecoder().decode(SaveData.self, from: data),
           saved.cells.count == Self.size * Self.size {
            cells = saved.cells
            critters = saved.critters
            rotation = saved.rotation
            timeMode = saved.timeMode
            weather = saved.weather
        } else {
            cells = []
            critters = []
            cells = Self.make(.random)
            critters = Self.startingCritters(cells)
        }
    }

    // MARK: - マス

    func index(_ x: Int, _ y: Int) -> Int { y * Self.size + x }

    func cell(_ x: Int, _ y: Int) -> HCell? {
        guard (0..<Self.size).contains(x), (0..<Self.size).contains(y) else { return nil }
        return cells[index(x, y)]
    }

    /// 道具を 1 マスに使う。何か変わったら true
    @discardableResult
    func apply(at x: Int, _ y: Int) -> Bool {
        guard var cell = cell(x, y) else { return false }
        let before = cell
        switch tool {
        case .ground:
            cell.ground = ground
            if ground == .water, let item = cell.item, !item.onWater { cell.item = nil }
            if ground != .water, cell.item == .boat { cell.item = nil }
        case .height:
            switch heightAction {
            case .up: cell.height = min(cell.height + 1, Self.maxHeight)
            case .down: cell.height = max(cell.height - 1, 0)
            case .flat: cell.height = 1
            }
        case .item:
            guard item.onWater == (cell.ground == .water) else {
                GameAudio.shared.play(.invalid)
                return false
            }
            cell.item = item
            cell.tint = Int.random(in: 0..<max(item.tints, 1))
        case .critter:
            let walkable = critterKind.swims ? cell.ground == .water : (cell.ground != .water && !(cell.item?.blocks ?? false))
            guard walkable, critters.count < 40 else {
                GameAudio.shared.play(.invalid)
                return false
            }
            critters.append(HCritter(kind: critterKind, x: Double(x) + 0.5, y: Double(y) + 0.5, tx: x, ty: y,
                                     tint: Int.random(in: 0..<6), wait: 0.5))
            GameAudio.shared.play(.place)
            return true
        case .erase:
            let count = critters.count
            critters.removeAll { Int($0.x) == x && Int($0.y) == y }
            if critters.count != count { GameAudio.shared.tick(); return true }
            cell.item = nil
        case .look:
            return false
        }
        guard cell != before else { return false }
        cells[index(x, y)] = cell
        if tool == .item { GameAudio.shared.play(.place) } else { GameAudio.shared.tick() }
        return true
    }

    func newGarden(_ template: Template) {
        cells = Self.make(template)
        critters = template == .blank ? [] : Self.startingCritters(cells)
        pan = .zero
        zoom = 1
        GameAudio.shared.play(.complete)
        save()
    }

    func rotate(_ step: Int) {
        rotation = (rotation + step + 4) % 4
        GameAudio.shared.tick()
        save()
    }

    // MARK: - 時間と いきもの

    /// いまの明るさの時刻（時間が進むときは clock、決めてあるときはその時刻）
    var timeOfDay: Double {
        switch timeMode {
        case .auto: return clock
        case .morning: return 0.27
        case .noon: return 0.5
        case .evening: return 0.74
        case .night: return 0.02
        }
    }

    func tick(_ dt: Double) {
        // 1 日を 4 分で
        clock = (clock + dt / 240).truncatingRemainder(dividingBy: 1)
        for index in critters.indices {
            move(&critters[index], dt)
        }
    }

    private func walkable(_ x: Int, _ y: Int, for critter: HCritter, from: HCell) -> Bool {
        guard let cell = cell(x, y) else { return false }
        if critter.kind.swims { return cell.ground == .water }
        if cell.ground == .water || (cell.item?.blocks ?? false) { return false }
        return abs(cell.height - from.height) <= 1
    }

    private func move(_ critter: inout HCritter, _ dt: Double) {
        if critter.wait > 0 {
            critter.wait -= dt
            return
        }
        let goalX = Double(critter.tx) + 0.5
        let goalY = Double(critter.ty) + 0.5
        let dx = goalX - critter.x
        let dy = goalY - critter.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let stride = critter.kind.speed * dt
        if distance > stride {
            critter.x += dx / distance * stride
            critter.y += dy / distance * stride
            critter.step += stride
            return
        }
        critter.x = goalX
        critter.y = goalY
        // 着いた：ときどき立ち止まり、となりの歩けるマスへ
        if Double.random(in: 0...1) < 0.25 {
            critter.wait = Double.random(in: 0.5...2.5)
            return
        }
        guard let here = cell(critter.tx, critter.ty) else { return }
        let options = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            .map { (critter.tx + $0.0, critter.ty + $0.1) }
            .filter { walkable($0.0, $0.1, for: critter, from: here) }
        if let next = options.randomElement() {
            critter.tx = next.0
            critter.ty = next.1
        } else {
            critter.wait = 1
        }
    }

    // MARK: - 保存

    func save() {
        let data = SaveData(cells: cells, critters: critters, timeMode: timeMode, weather: weather, rotation: rotation)
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.saveKey)
        }
    }

    // MARK: - はじめの箱庭

    private static func make(_ template: Template) -> [HCell] {
        let n = size
        var cells = Array(repeating: HCell(), count: n * n)
        func set(_ x: Int, _ y: Int, _ change: (inout HCell) -> Void) {
            guard (0..<n).contains(x), (0..<n).contains(y) else { return }
            change(&cells[y * n + x])
        }
        switch template {
        case .blank:
            break
        case .island:
            let c = Double(n - 1) / 2
            for y in 0..<n {
                for x in 0..<n {
                    let d = ((Double(x) - c) * (Double(x) - c) + (Double(y) - c) * (Double(y) - c)).squareRoot()
                    set(x, y) { cell in
                        if d > 4.6 {
                            cell.ground = .water
                            cell.height = 0
                        } else if d > 3.6 {
                            cell.ground = .sand
                            cell.height = 1
                        } else {
                            cell.ground = .grass
                            cell.height = d < 1.6 ? 2 : 1
                        }
                    }
                }
            }
            let placements: [(Int, Int, HItem)] = [(5, 5, .house), (6, 4, .tree), (4, 6, .sakura), (7, 7, .pine),
                                                   (5, 7, .flowers), (6, 6, .lamp), (3, 4, .bush), (9, 9, .boat),
                                                   (2, 8, .rock)]
            for (x, y, item) in placements {
                set(x, y) { cell in
                    if item.onWater == (cell.ground == .water) { cell.item = item; cell.tint = Int.random(in: 0..<item.tints) }
                }
            }
        case .random:
            // なだらかな丘：いくつかの山の高さを足し合わせる
            let hills = (0..<3).map { _ in (Double.random(in: 0...Double(n)), Double.random(in: 0...Double(n)),
                                            Double.random(in: 1.5...3)) }
            for y in 0..<n {
                for x in 0..<n {
                    var h = 0.6
                    for hill in hills {
                        let d = ((Double(x) - hill.0) * (Double(x) - hill.0) + (Double(y) - hill.1) * (Double(y) - hill.1)).squareRoot()
                        h += hill.2 * max(0, 1 - d / 4.5)
                    }
                    set(x, y) { cell in
                        cell.height = min(maxHeight, max(1, Int(h.rounded())))
                        if cell.height >= 4 { cell.ground = .snow }
                    }
                }
            }
            // 川：左から右へ、くねくね
            var ry = Int.random(in: 2..<(n - 2))
            for x in 0..<n {
                set(x, ry) { cell in cell.ground = .water; cell.height = 0; cell.item = nil }
                set(x, ry + 1) { cell in if cell.ground != .water { cell.ground = .sand; cell.height = 1 } }
                if Bool.random() { ry = min(max(ry + Int.random(in: -1...1), 1), n - 3) }
                set(x, ry) { cell in cell.ground = .water; cell.height = 0 }
            }
            // 道と家
            let px = Int.random(in: 2..<(n - 2))
            for y in 0..<n {
                set(px, y) { cell in
                    if cell.ground != .water { cell.ground = .path } else { cell.item = .boat }
                }
            }
            for _ in 0..<3 {
                let x = min(max(px + (Bool.random() ? 1 : -1), 0), n - 1)
                let y = Int.random(in: 0..<n)
                set(x, y) { cell in
                    if cell.ground != .water { cell.item = .house; cell.tint = Int.random(in: 0..<5) }
                }
            }
            // 木と花
            for _ in 0..<26 {
                let x = Int.random(in: 0..<n), y = Int.random(in: 0..<n)
                set(x, y) { cell in
                    guard cell.item == nil, cell.ground == .grass || cell.ground == .snow else { return }
                    let choices: [HItem] = cell.ground == .snow ? [.pine, .pine, .rock]
                        : [.tree, .tree, .pine, .sakura, .bush, .flowers, .flowers, .rock]
                    cell.item = choices.randomElement()
                }
            }
            for _ in 0..<5 {
                let x = Int.random(in: 0..<n), y = Int.random(in: 0..<n)
                set(x, y) { cell in if cell.ground == .grass && cell.item == nil { cell.ground = .meadow } }
            }
        }
        return cells
    }

    private static func startingCritters(_ cells: [HCell]) -> [HCritter] {
        var result: [HCritter] = []
        let n = size
        let kinds: [HCritterKind] = [.person, .person, .cat, .dog, .chicken, .duck]
        for kind in kinds {
            let spots = (0..<(n * n)).filter { index in
                let cell = cells[index]
                return kind.swims ? cell.ground == .water : (cell.ground != .water && !(cell.item?.blocks ?? false))
            }
            guard let spot = spots.randomElement() else { continue }
            let x = spot % n, y = spot / n
            result.append(HCritter(kind: kind, x: Double(x) + 0.5, y: Double(y) + 0.5, tx: x, ty: y,
                                   tint: Int.random(in: 0..<6)))
        }
        return result
    }
}
