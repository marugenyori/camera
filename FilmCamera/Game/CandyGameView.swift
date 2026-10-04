import SwiftUI

/// 隠しゲーム「キャンディ・マッチ」（Candy Crush のような 3 つそろえ）。
/// となりのキャンディをスワイプで入れ替え、3 つ以上そろえると消える。
/// 4 つでしま模様（1 列消し）、L・T 字で包み（まわり 3×3 を 2 回爆発）、5 つでチョコボール（同じ色を全部消す）。
/// 連鎖すると「スイート！」などの声かけ。BGM・効果音・振動つき
struct CandyGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = CandyGame()
    @State private var dragStarted = false
    @State private var muted = GameAudio.shared.isMuted

    var body: some View {
        ZStack {
            background
            VStack(spacing: 14) {
                header
                scoreBoard
                board
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            if let praise = game.praise {
                PraiseText(text: praise)
                    .id(game.praiseID)
                    .allowsHitTesting(false)
            }
            if game.state != .playing { resultBanner }
        }
        .preferredColorScheme(.light)
        .onAppear { GameAudio.shared.playMusic(.candy) }
        .onDisappear { GameAudio.shared.stop() }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.75, blue: 1.0), Color(red: 0.62, green: 0.45, blue: 0.95)],
                           startPoint: .top, endPoint: .bottom)
            // 背景のふわふわした丸
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: CGFloat(60 + i * 18))
                    .offset(x: CGFloat((i * 73) % 300) - 150, y: CGFloat((i * 131) % 700) - 350)
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            roundButton("xmark") { dismiss() }
            Spacer()
            Text("レベル \(game.level)")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .shadow(color: .purple.opacity(0.6), radius: 0, x: 0, y: 2)
            Spacer()
            roundButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                muted.toggle()
                GameAudio.shared.isMuted = muted
            }
        }
        .padding(.top, 6)
    }

    private func roundButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color(red: 1, green: 0.45, blue: 0.6)))
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 3)
        }
    }

    private var scoreBoard: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text("のこり").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                Text("\(game.moves)").font(.largeTitle.weight(.black).monospacedDigit()).foregroundStyle(.white)
            }
            .frame(width: 84, height: 72)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.3, green: 0.2, blue: 0.6).opacity(0.75)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("スコア \(game.score)")
                        .font(.headline.weight(.heavy).monospacedDigit())
                    Spacer()
                    Text("目標 \(game.target)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule()
                            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(1, CGFloat(game.score) / CGFloat(game.target)))
                            .animation(.spring, value: game.score)
                        HStack {
                            ForEach(1...3, id: \.self) { star in
                                Spacer()
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(game.score >= game.target * star / 3 ? .yellow : .white.opacity(0.5))
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
                .frame(height: 16)
            }
            .padding(12)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.3, green: 0.2, blue: 0.6).opacity(0.75)))
        }
    }

    // MARK: - 盤面

    private var board: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(CandyGame.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.2, green: 0.25, blue: 0.55).opacity(0.55))
                ForEach(0..<CandyGame.size * CandyGame.size, id: \.self) { i in
                    RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                        .fill(.white.opacity((i / CandyGame.size + i % CandyGame.size).isMultiple(of: 2) ? 0.2 : 0.12))
                        .frame(width: cell - 3, height: cell - 3)
                        .position(x: (CGFloat(i % CandyGame.size) + 0.5) * cell,
                                  y: (CGFloat(i / CandyGame.size) + 0.5) * cell)
                }
                ForEach(game.candies) { candy in
                    CandyView(kind: candy.kind, special: candy.special, size: cell * 0.9)
                        .scaleEffect(game.clearing.contains(candy.id) ? 1.4 : (game.hint.contains(candy.id) ? 1.12 : 1))
                        .opacity(game.clearing.contains(candy.id) ? 0 : 1)
                        .position(x: (CGFloat(candy.column) + 0.5) * cell,
                                  y: (CGFloat(candy.row) + 0.5) * cell)
                        .transition(.asymmetric(insertion: .offset(y: -cell * 3).combined(with: .opacity),
                                                removal: .scale(scale: 1.5).combined(with: .opacity)))
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: game.hint.contains(candy.id))
                }
                ForEach(game.blasts) { blast in
                    BlastView(blast: blast, cell: cell)
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        guard !dragStarted else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard max(abs(dx), abs(dy)) > cell * 0.3 else { return }
                        dragStarted = true
                        let start = CandyGame.Position(row: Int(value.startLocation.y / cell),
                                                       column: Int(value.startLocation.x / cell))
                        let target = abs(dx) > abs(dy)
                            ? CandyGame.Position(row: start.row, column: start.column + (dx > 0 ? 1 : -1))
                            : CandyGame.Position(row: start.row + (dy > 0 ? 1 : -1), column: start.column)
                        Task { await game.swap(start, target) }
                    }
                    .onEnded { _ in dragStarted = false }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var resultBanner: some View {
        VStack(spacing: 14) {
            Text(game.state == .cleared ? "レベルクリア！" : "ざんねん…")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(game.state == .cleared ? Color.orange : Color.purple)
            if game.state == .cleared {
                HStack {
                    ForEach(1...3, id: \.self) { star in
                        Image(systemName: "star.fill")
                            .font(.largeTitle)
                            .foregroundStyle(game.score >= game.target * (2 + star) / 3 ? .yellow : .gray.opacity(0.4))
                    }
                }
            }
            Text(game.state == .cleared ? "スコア \(game.score)" : "あと \(max(0, game.target - game.score)) 点でした")
                .font(.headline)
            Button(game.state == .cleared ? "次のレベルへ" : "もう一度") {
                if game.state == .cleared { game.nextLevel() } else { game.retry() }
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Capsule().fill(LinearGradient(colors: [.green, Color(red: 0.1, green: 0.65, blue: 0.3)],
                                                      startPoint: .top, endPoint: .bottom)))
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white))
        .shadow(radius: 20)
        .padding(32)
        .transition(.scale.combined(with: .opacity))
    }
}

/// 連鎖のときの声かけ（大きな文字が弾んで消える）
private struct PraiseText: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).weight(.black))
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .pink], startPoint: .top, endPoint: .bottom))
            .shadow(color: .purple, radius: 0, x: 2, y: 3)
            .scaleEffect(shown ? 1.2 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { shown = true }
                withAnimation(.easeIn(duration: 0.3).delay(0.8)) { shown = false }
            }
    }
}

/// しま模様・包み・チョコボールが弾けたときの光
private struct BlastView: View {
    let blast: CandyGame.Blast
    let cell: CGFloat
    @State private var go = false

    var body: some View {
        Group {
            switch blast.shape {
            case .row:
                Capsule().fill(.white)
                    .frame(width: go ? cell * CGFloat(CandyGame.size) : cell, height: cell * 0.35)
                    .position(x: cell * CGFloat(CandyGame.size) / 2, y: (CGFloat(blast.row) + 0.5) * cell)
            case .column:
                Capsule().fill(.white)
                    .frame(width: cell * 0.35, height: go ? cell * CGFloat(CandyGame.size) : cell)
                    .position(x: (CGFloat(blast.column) + 0.5) * cell, y: cell * CGFloat(CandyGame.size) / 2)
            case .area:
                Circle().fill(RadialGradient(colors: [.white, .yellow.opacity(0.6), .clear],
                                             center: .center, startRadius: 0, endRadius: cell * 1.6))
                    .frame(width: cell * (go ? 3.4 : 1), height: cell * (go ? 3.4 : 1))
                    .position(x: (CGFloat(blast.column) + 0.5) * cell, y: (CGFloat(blast.row) + 0.5) * cell)
            }
        }
        .opacity(go ? 0 : 0.9)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { go = true } }
        .allowsHitTesting(false)
    }
}

/// キャンディ 1 粒。種類ごとにお菓子らしい形（ジェリービーンズ、トローチ、レモンドロップ、
/// 四角いガム、丸いあめ、紫のクラスター）と、つやの光。しま模様・包み・チョコボールの見た目も描く
private struct CandyView: View {
    let kind: Int
    let special: CandyGame.Special
    let size: CGFloat

    static let colors: [(Color, Color)] = [
        (Color(red: 1.0, green: 0.35, blue: 0.4), Color(red: 0.8, green: 0.05, blue: 0.15)),   // 赤
        (Color(red: 1.0, green: 0.75, blue: 0.3), Color(red: 0.95, green: 0.45, blue: 0.0)),   // オレンジ
        (Color(red: 1.0, green: 0.95, blue: 0.45), Color(red: 0.95, green: 0.75, blue: 0.0)),  // 黄
        (Color(red: 0.5, green: 0.95, blue: 0.45), Color(red: 0.1, green: 0.65, blue: 0.15)),  // 緑
        (Color(red: 0.45, green: 0.75, blue: 1.0), Color(red: 0.05, green: 0.35, blue: 0.9)),  // 青
        (Color(red: 0.85, green: 0.55, blue: 1.0), Color(red: 0.5, green: 0.15, blue: 0.8)),   // 紫
    ]

    var body: some View {
        ZStack {
            if special == .bomb {
                chocolateBall
            } else {
                candyShape
                    .fill(LinearGradient(colors: [Self.colors[kind].0, Self.colors[kind].1],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(candyShape.stroke(Self.colors[kind].1.opacity(0.9), lineWidth: size * 0.04))
                    .overlay(stripes)
                    .overlay(alignment: .topLeading) {
                        Capsule()
                            .fill(.white.opacity(0.7))
                            .frame(width: size * 0.26, height: size * 0.12)
                            .rotationEffect(.degrees(-30))
                            .offset(x: size * 0.2, y: size * 0.18)
                    }
                    .frame(width: size * 0.78, height: size * 0.78)
                if special == .wrapped { wrapper }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 2)
    }

    private var candyShape: AnyShape {
        switch kind {
        case 0: return AnyShape(Capsule().rotation(.degrees(-25)))                       // ジェリービーンズ
        case 1: return AnyShape(RoundedRectangle(cornerRadius: size * 0.3).rotation(.degrees(45)).scale(0.82)) // トローチ
        case 2: return AnyShape(Ellipse().scale(x: 0.85, y: 1))                           // レモンドロップ
        case 3: return AnyShape(RoundedRectangle(cornerRadius: size * 0.16))              // 四角いガム
        case 4: return AnyShape(Circle())                                                  // 丸いあめ
        default: return AnyShape(Star())                                                    // 紫のクラスター
        }
    }

    @ViewBuilder private var stripes: some View {
        if special == .stripedRow || special == .stripedColumn {
            VStack(spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.85)).frame(height: size * 0.07)
                }
            }
            .padding(size * 0.12)
            .rotationEffect(.degrees(special == .stripedColumn ? 90 : 0))
            .mask(candyShape)
        }
    }

    private var wrapper: some View {
        HStack(spacing: size * 0.5) {
            Triangle().fill(Self.colors[kind].1).frame(width: size * 0.2, height: size * 0.3).rotationEffect(.degrees(-90))
            Triangle().fill(Self.colors[kind].1).frame(width: size * 0.2, height: size * 0.3).rotationEffect(.degrees(90))
        }
        .overlay(Circle().stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.05, dash: [size * 0.06])).frame(width: size * 0.62))
    }

    /// チョコボールの上のカラフルなトッピング 1 粒
    private func sprinkle(_ i: Int) -> some View {
        let angle: Double = Double(i) * 2.1
        let radius: CGFloat = size * 0.24
        let x: CGFloat = CGFloat(cos(angle)) * radius
        let y: CGFloat = CGFloat(sin(angle)) * radius
        let color: Color = Self.colors[i % Self.colors.count].0
        return Capsule()
            .fill(color)
            .frame(width: size * 0.12, height: size * 0.05)
            .rotationEffect(.degrees(Double(i) * 47))
            .offset(x: x, y: y)
    }

    private var chocolateBall: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.2), Color(red: 0.25, green: 0.12, blue: 0.05)],
                                         center: .topLeading, startRadius: 0, endRadius: size * 0.6))
            ForEach(0..<10, id: \.self) { i in
                sprinkle(i)
            }
        }
        .frame(width: size * 0.82, height: size * 0.82)
    }
}

private struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outer : outer * 0.55
            let angle = Double(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 遊びの決まり

@MainActor
final class CandyGame: ObservableObject {
    static let size = 8
    static let kinds = 6

    struct Position: Equatable, Hashable {
        var row: Int
        var column: Int
        var isValid: Bool { (0..<CandyGame.size).contains(row) && (0..<CandyGame.size).contains(column) }
    }

    enum Special { case none, stripedRow, stripedColumn, wrapped, bomb }

    struct Candy: Identifiable {
        let id = UUID()
        var kind: Int
        var special: Special = .none
        var row: Int
        var column: Int
        var position: Position { Position(row: row, column: column) }
    }

    struct Blast: Identifiable {
        enum Shape { case row, column, area }
        let id = UUID()
        let shape: Shape
        let row: Int
        let column: Int
    }

    enum State { case playing, cleared, failed }

    @Published private(set) var candies: [Candy] = []
    @Published private(set) var clearing: Set<UUID> = []
    @Published private(set) var blasts: [Blast] = []
    @Published private(set) var hint: Set<UUID> = []
    @Published private(set) var score = 0
    @Published private(set) var moves = 20
    @Published private(set) var level = 1
    @Published private(set) var state: State = .playing
    @Published private(set) var praise: String?
    @Published private(set) var praiseID = 0
    private var busy = false
    private var hintTask: Task<Void, Never>?

    var target: Int { 2000 + (level - 1) * 1500 }

    init() {
        level = max(1, UserDefaults.standard.integer(forKey: "candyLevel"))
        startLevel()
    }

    func retry() { startLevel() }

    func nextLevel() {
        level += 1
        UserDefaults.standard.set(level, forKey: "candyLevel")
        startLevel()
    }

    private func startLevel() {
        score = 0
        moves = 20 + min(level, 10)
        state = .playing
        clearing = []
        candies = Self.freshBoard()
        busy = false
        scheduleHint()
    }

    private static func freshBoard() -> [Candy] {
        var kinds = Array(repeating: Array(repeating: 0, count: size), count: size)
        for row in 0..<size {
            for column in 0..<size {
                var kind: Int
                repeat {
                    kind = Int.random(in: 0..<CandyGame.kinds)
                } while (column >= 2 && kinds[row][column - 1] == kind && kinds[row][column - 2] == kind)
                    || (row >= 2 && kinds[row - 1][column] == kind && kinds[row - 2][column] == kind)
                kinds[row][column] = kind
            }
        }
        return (0..<size * size).map { Candy(kind: kinds[$0 / size][$0 % size], row: $0 / size, column: $0 % size) }
    }

    private func index(at position: Position) -> Int? {
        candies.firstIndex { $0.row == position.row && $0.column == position.column }
    }

    // MARK: - 入れ替え

    func swap(_ a: Position, _ b: Position) async {
        guard !busy, state == .playing, a.isValid, b.isValid,
              let i = index(at: a), let j = index(at: b) else { return }
        busy = true
        hint = []
        hintTask?.cancel()
        defer {
            busy = false
            scheduleHint()
        }
        GameAudio.shared.play(.swap)
        withAnimation(.snappy(duration: 0.18)) {
            candies[i].row = b.row; candies[i].column = b.column
            candies[j].row = a.row; candies[j].column = a.column
        }
        try? await Task.sleep(for: .milliseconds(200))

        // チョコボールを入れ替えたら、相手と同じ色を全部消す
        if candies[i].special == .bomb || candies[j].special == .bomb {
            moves -= 1
            let bomb = candies[i].special == .bomb ? i : j
            let other = bomb == i ? j : i
            var toClear: Set<Position> = [candies[bomb].position]
            if candies[other].special == .bomb {
                candies.forEach { _ = toClear.insert($0.position) }          // チョコボール同士：全部
            } else {
                let kind = candies[other].kind
                candies.filter { $0.kind == kind }.forEach { _ = toClear.insert($0.position) }
            }
            GameAudio.shared.play(.bomb)
            await clear(toClear, created: [], combo: 1)
            await resolve(swapped: [], startCombo: 2)
            finishMove()
            return
        }

        let groups = findGroups(preferring: [a, b])
        if groups.cells.isEmpty {
            GameAudio.shared.play(.invalid)
            withAnimation(.snappy(duration: 0.18)) {
                candies[i].row = a.row; candies[i].column = a.column
                candies[j].row = b.row; candies[j].column = b.column
            }
            try? await Task.sleep(for: .milliseconds(200))
            return
        }
        moves -= 1
        await resolve(swapped: [a, b], startCombo: 1)
        finishMove()
    }

    private func finishMove() {
        if score >= target {
            state = .cleared
            GameAudio.shared.play(.win)
        } else if moves <= 0 {
            state = .failed
            GameAudio.shared.play(.lose)
        } else if findPossibleMove() == nil {
            withAnimation(.snappy) { candies = Self.freshBoard() }
        }
    }

    // MARK: - そろったものを消す

    private func resolve(swapped: [Position], startCombo: Int) async {
        var combo = startCombo
        var preferred = swapped
        while true {
            let groups = findGroups(preferring: preferred)
            if groups.cells.isEmpty { break }
            await clear(groups.cells, created: groups.created, combo: combo)
            if combo >= 2 { showPraise(combo) }
            combo += 1
            preferred = []
        }
    }

    /// 消すマス（特別なキャンディが巻き込まれたら、その効果も広げる）を消し、新しい特別なキャンディを置き、落とす
    private func clear(_ cells: Set<Position>, created: [(Position, Special, Int)], combo: Int) async {
        var toClear = cells
        var queue = Array(cells)
        var newBlasts: [Blast] = []
        var exploded = Set<Position>()
        while let position = queue.popLast() {
            guard let i = index(at: position), !exploded.contains(position) else { continue }
            exploded.insert(position)
            var affected: [Position] = []
            switch candies[i].special {
            case .none: continue
            case .stripedRow:
                affected = (0..<Self.size).map { Position(row: position.row, column: $0) }
                newBlasts.append(Blast(shape: .row, row: position.row, column: position.column))
            case .stripedColumn:
                affected = (0..<Self.size).map { Position(row: $0, column: position.column) }
                newBlasts.append(Blast(shape: .column, row: position.row, column: position.column))
            case .wrapped:
                for dr in -1...1 { for dc in -1...1 { affected.append(Position(row: position.row + dr, column: position.column + dc)) } }
                newBlasts.append(Blast(shape: .area, row: position.row, column: position.column))
            case .bomb:
                let kind = Int.random(in: 0..<Self.kinds)
                affected = candies.filter { $0.kind == kind }.map(\.position)
                newBlasts.append(Blast(shape: .area, row: position.row, column: position.column))
            }
            for p in affected where p.isValid && !toClear.contains(p) {
                toClear.insert(p)
                queue.append(p)
            }
        }
        // 新しく作る特別なキャンディのマスは消さずに残す
        let keep = Set(created.map(\.0))
        let removing = toClear.subtracting(keep)
        let ids = Set(candies.filter { removing.contains($0.position) }.map(\.id))

        score += ids.count * 30 * combo + newBlasts.count * 120
        if newBlasts.isEmpty {
            GameAudio.shared.play(.pop(combo: combo))
        } else {
            GameAudio.shared.play(.bomb)
            blasts = newBlasts
        }
        withAnimation(.easeIn(duration: 0.16)) { clearing = ids }
        try? await Task.sleep(for: .milliseconds(180))
        candies.removeAll { ids.contains($0.id) }
        clearing = []
        for (position, special, kind) in created {
            if let i = index(at: position) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    candies[i].special = special
                    candies[i].kind = kind
                }
            }
        }
        if !created.isEmpty { GameAudio.shared.play(.special) }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { dropAndRefill() }
        try? await Task.sleep(for: .milliseconds(360))
        blasts = []
    }

    private func dropAndRefill() {
        for column in 0..<Self.size {
            let inColumn = candies.indices
                .filter { candies[$0].column == column }
                .sorted { candies[$0].row > candies[$1].row }
            var row = Self.size - 1
            for i in inColumn {
                candies[i].row = row
                row -= 1
            }
            while row >= 0 {
                candies.append(Candy(kind: Int.random(in: 0..<Self.kinds), row: row, column: column))
                row -= 1
            }
        }
    }

    private func showPraise(_ combo: Int) {
        let words = ["", "", "スイート！", "テイスティ！", "デリシャス！", "ディバイン！", "シュガー・クラッシュ！"]
        praise = words[min(combo, words.count - 1)]
        praiseID += 1
        let id = praiseID
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if praiseID == id { praise = nil }
        }
    }

    // MARK: - そろいの見つけ方

    /// 3 つ以上の並び。4 つはしま模様、5 つはチョコボール、縦横が交わる L・T 字は包みを作る
    private func findGroups(preferring preferred: [Position]) -> (cells: Set<Position>, created: [(Position, Special, Int)]) {
        var grid = Array(repeating: Array(repeating: -1, count: Self.size), count: Self.size)
        for candy in candies where candy.position.isValid && candy.special != .bomb {
            grid[candy.row][candy.column] = candy.kind
        }
        var horizontal: [[Position]] = []
        var vertical: [[Position]] = []
        for row in 0..<Self.size {
            var run: [Position] = []
            for column in 0...Self.size {
                let kind = column < Self.size ? grid[row][column] : -2
                if let first = run.first, kind == grid[first.row][first.column], kind >= 0 {
                    run.append(Position(row: row, column: column))
                } else {
                    if run.count >= 3 { horizontal.append(run) }
                    run = kind >= 0 ? [Position(row: row, column: column)] : []
                }
            }
        }
        for column in 0..<Self.size {
            var run: [Position] = []
            for row in 0...Self.size {
                let kind = row < Self.size ? grid[row][column] : -2
                if let first = run.first, kind == grid[first.row][first.column], kind >= 0 {
                    run.append(Position(row: row, column: column))
                } else {
                    if run.count >= 3 { vertical.append(run) }
                    run = kind >= 0 ? [Position(row: row, column: column)] : []
                }
            }
        }
        var cells = Set<Position>()
        for run in horizontal + vertical { for p in run { cells.insert(p) } }
        var created: [(Position, Special, Int)] = []
        var used = Set<Position>()
        func spot(in run: [Position]) -> Position {
            run.first(where: { preferred.contains($0) }) ?? run[run.count / 2]
        }
        // 5 つ以上：チョコボール
        for run in horizontal + vertical where run.count >= 5 {
            let p = spot(in: run)
            guard !used.contains(p) else { continue }
            created.append((p, .bomb, grid[p.row][p.column])); used.insert(p)
        }
        // L・T 字：包み
        for h in horizontal {
            for v in vertical {
                if let cross = h.first(where: { v.contains($0) }), !used.contains(cross) {
                    created.append((cross, .wrapped, grid[cross.row][cross.column])); used.insert(cross)
                }
            }
        }
        // 4 つ：しま模様（横の並びなら縦に消す、縦の並びなら横に消す）
        for run in horizontal where run.count == 4 && !run.contains(where: { used.contains($0) }) {
            let p = spot(in: run)
            created.append((p, .stripedColumn, grid[p.row][p.column])); used.insert(p)
        }
        for run in vertical where run.count == 4 && !run.contains(where: { used.contains($0) }) {
            let p = spot(in: run)
            created.append((p, .stripedRow, grid[p.row][p.column])); used.insert(p)
        }
        return (cells, created)
    }

    // MARK: - ヒント

    /// しばらく何もしなければ、そろう手を光らせて教える
    private func scheduleHint() {
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.state == .playing, !self.busy,
                  let move = self.findPossibleMove() else { return }
            self.hint = Set(self.candies.filter { $0.position == move.0 || $0.position == move.1 }.map(\.id))
        }
    }

    private func findPossibleMove() -> (Position, Position)? {
        var kinds = Array(repeating: Array(repeating: -1, count: Self.size), count: Self.size)
        for candy in candies where candy.position.isValid { kinds[candy.row][candy.column] = candy.kind }
        if candies.contains(where: { $0.special == .bomb }), let bomb = candies.first(where: { $0.special == .bomb }) {
            let p = bomb.position
            let n = Position(row: p.row, column: p.column < Self.size - 1 ? p.column + 1 : p.column - 1)
            return (p, n)
        }
        func line(_ k: [[Int]], _ r: Int, _ c: Int) -> Bool {
            let kind = k[r][c]
            var h = 1, v = 1
            var x = c - 1; while x >= 0 && k[r][x] == kind { h += 1; x -= 1 }
            x = c + 1; while x < Self.size && k[r][x] == kind { h += 1; x += 1 }
            var y = r - 1; while y >= 0 && k[y][c] == kind { v += 1; y -= 1 }
            y = r + 1; while y < Self.size && k[y][c] == kind { v += 1; y += 1 }
            return h >= 3 || v >= 3
        }
        for r in 0..<Self.size {
            for c in 0..<Self.size {
                for (dr, dc) in [(0, 1), (1, 0)] {
                    let r2 = r + dr, c2 = c + dc
                    guard r2 < Self.size, c2 < Self.size else { continue }
                    var k = kinds
                    k[r][c] = kinds[r2][c2]
                    k[r2][c2] = kinds[r][c]
                    if line(k, r, c) || line(k, r2, c2) {
                        return (Position(row: r, column: c), Position(row: r2, column: c2))
                    }
                }
            }
        }
        return nil
    }
}
