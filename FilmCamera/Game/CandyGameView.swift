import SwiftUI

/// 隠しゲーム「キャンディ・マッチ」（Candy Crush のような 3 つそろえ）。
/// となりのキャンディをスワイプで入れ替え、縦か横に 3 つ以上そろえると消える。
/// 消えた分は上から落ちてきて、続けてそろうと連鎖。決まった手数で目標の点を目指す
struct CandyGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = CandyGame()
    @State private var dragStart: CandyGame.Position?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.35, green: 0.15, blue: 0.5), Color(red: 0.1, green: 0.1, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                header
                scoreBoard
                board
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            if game.state != .playing { resultBanner }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: game.score)
    }

    private var header: some View {
        HStack {
            Button("閉じる") { dismiss() }
            Spacer()
            Text("キャンディ・マッチ").font(.headline)
            Spacer()
            Button {
                game.newGame()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("最初から")
        }
        .padding(.top, 8)
    }

    private var scoreBoard: some View {
        HStack {
            stat("レベル", "\(game.level)")
            stat("スコア", "\(game.score)")
            stat("目標", "\(game.target)")
            stat("のこり手数", "\(game.moves)")
        }
        .padding(.vertical, 10)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 盤面

    private var board: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(CandyGame.size)
            ZStack(alignment: .topLeading) {
                // 盤のマス目
                ForEach(0..<CandyGame.size * CandyGame.size, id: \.self) { i in
                    RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                        .fill(.white.opacity((i / CandyGame.size + i % CandyGame.size).isMultiple(of: 2) ? 0.12 : 0.07))
                        .frame(width: cell - 2, height: cell - 2)
                        .position(x: (CGFloat(i % CandyGame.size) + 0.5) * cell,
                                  y: (CGFloat(i / CandyGame.size) + 0.5) * cell)
                }
                ForEach(game.candies) { candy in
                    CandyView(kind: candy.kind, size: cell * 0.86)
                        .scaleEffect(game.clearing.contains(candy.id) ? 0.1 : 1)
                        .opacity(game.clearing.contains(candy.id) ? 0 : 1)
                        .position(x: (CGFloat(candy.column) + 0.5) * cell,
                                  y: (CGFloat(candy.row) + 0.5) * cell)
                        .transition(.offset(y: -cell * 2).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard dragStart == nil else { return }
                        let start = CandyGame.Position(row: Int(value.startLocation.y / cell),
                                                       column: Int(value.startLocation.x / cell))
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard max(abs(dx), abs(dy)) > cell * 0.35 else { return }
                        dragStart = start
                        let target = abs(dx) > abs(dy)
                            ? CandyGame.Position(row: start.row, column: start.column + (dx > 0 ? 1 : -1))
                            : CandyGame.Position(row: start.row + (dy > 0 ? 1 : -1), column: start.column)
                        Task { await game.swap(start, target) }
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var resultBanner: some View {
        VStack(spacing: 14) {
            Text(game.state == .cleared ? "クリア！" : "ざんねん…")
                .font(.largeTitle.weight(.heavy))
            Text(game.state == .cleared
                 ? "スコア \(game.score)。次のレベルへ進もう"
                 : "あと \(max(0, game.target - game.score)) 点でした")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Button(game.state == .cleared ? "次のレベル" : "もう一度") {
                if game.state == .cleared { game.nextLevel() } else { game.newGame() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(32)
    }
}

/// キャンディ 1 粒（種類ごとに形と色を変える）
private struct CandyView: View {
    let kind: Int
    let size: CGFloat

    private static let symbols = ["circle.fill", "square.fill", "diamond.fill", "triangle.fill", "star.fill", "heart.fill"]
    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.25, blue: 0.3), Color(red: 1.0, green: 0.6, blue: 0.1),
        Color(red: 1.0, green: 0.85, blue: 0.15), Color(red: 0.25, green: 0.85, blue: 0.35),
        Color(red: 0.2, green: 0.55, blue: 1.0), Color(red: 0.75, green: 0.35, blue: 1.0),
    ]

    var body: some View {
        let color = Self.colors[kind % Self.colors.count]
        Image(systemName: Self.symbols[kind % Self.symbols.count])
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.85), color, color.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(alignment: .topLeading) {
                // つやの光
                Ellipse()
                    .fill(.white.opacity(0.55))
                    .frame(width: size * 0.22, height: size * 0.14)
                    .offset(x: size * 0.24, y: size * 0.2)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
            .frame(width: size * 0.8, height: size * 0.8)
            .frame(width: size, height: size)
    }
}

// MARK: - 遊びの決まり

@MainActor
final class CandyGame: ObservableObject {
    static let size = 8
    static let kinds = 6

    struct Position: Equatable {
        var row: Int
        var column: Int
        var isValid: Bool { (0..<CandyGame.size).contains(row) && (0..<CandyGame.size).contains(column) }
    }

    struct Candy: Identifiable {
        let id = UUID()
        let kind: Int
        var row: Int
        var column: Int
    }

    enum State { case playing, cleared, failed }

    @Published private(set) var candies: [Candy] = []
    /// 消えかけのキャンディ（縮んで消えるアニメーション用）
    @Published private(set) var clearing: Set<UUID> = []
    @Published private(set) var score = 0
    @Published private(set) var moves = 20
    @Published private(set) var level = 1
    @Published private(set) var state: State = .playing
    private var busy = false

    var target: Int { 1500 + (level - 1) * 1000 }

    init() { newGame() }

    func newGame() {
        level = 1
        startLevel()
    }

    func nextLevel() {
        level += 1
        startLevel()
    }

    private func startLevel() {
        score = 0
        moves = 20
        state = .playing
        clearing = []
        candies = Self.freshBoard()
        busy = false
    }

    /// 最初から 3 つそろっていない盤面を作る
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

    /// となり同士を入れ替える。そろわなければ元に戻す
    func swap(_ a: Position, _ b: Position) async {
        guard !busy, state == .playing, a.isValid, b.isValid,
              let i = index(at: a), let j = index(at: b) else { return }
        busy = true
        defer { busy = false }
        withAnimation(.snappy(duration: 0.2)) {
            candies[i].row = b.row
            candies[i].column = b.column
            candies[j].row = a.row
            candies[j].column = a.column
        }
        try? await Task.sleep(for: .milliseconds(220))
        if findMatches().isEmpty {
            withAnimation(.snappy(duration: 0.2)) {
                candies[i].row = a.row
                candies[i].column = a.column
                candies[j].row = b.row
                candies[j].column = b.column
            }
            try? await Task.sleep(for: .milliseconds(220))
            return
        }
        moves -= 1
        await resolve()
        if score >= target {
            state = .cleared
        } else if moves <= 0 {
            state = .failed
        } else if !hasPossibleMove() {
            withAnimation(.snappy) { candies = Self.freshBoard() }
        }
    }

    /// そろった分を消し、落とし、足し、また そろえば続ける（連鎖ほど点が高い）
    private func resolve() async {
        var combo = 1
        while true {
            let matched = findMatches()
            if matched.isEmpty { break }
            score += matched.count * 20 * combo
            withAnimation(.easeIn(duration: 0.18)) { clearing = matched }
            try? await Task.sleep(for: .milliseconds(200))
            candies.removeAll { matched.contains($0.id) }
            clearing = []
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dropAndRefill() }
            try? await Task.sleep(for: .milliseconds(380))
            combo += 1
        }
    }

    /// すき間を詰めて下に落とし、空いた上のほうに新しいキャンディを足す
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

    /// 縦か横に 3 つ以上並んだキャンディ
    private func findMatches() -> Set<UUID> {
        var grid = Array(repeating: Array<Candy?>(repeating: nil, count: Self.size), count: Self.size)
        for candy in candies where Position(row: candy.row, column: candy.column).isValid {
            grid[candy.row][candy.column] = candy
        }
        var matched = Set<UUID>()
        for row in 0..<Self.size {
            var run: [Candy] = []
            for column in 0..<Self.size {
                if let candy = grid[row][column], let last = run.last, last.kind == candy.kind {
                    run.append(candy)
                } else {
                    if run.count >= 3 { run.forEach { matched.insert($0.id) } }
                    run = grid[row][column].map { [$0] } ?? []
                }
            }
            if run.count >= 3 { run.forEach { matched.insert($0.id) } }
        }
        for column in 0..<Self.size {
            var run: [Candy] = []
            for row in 0..<Self.size {
                if let candy = grid[row][column], let last = run.last, last.kind == candy.kind {
                    run.append(candy)
                } else {
                    if run.count >= 3 { run.forEach { matched.insert($0.id) } }
                    run = grid[row][column].map { [$0] } ?? []
                }
            }
            if run.count >= 3 { run.forEach { matched.insert($0.id) } }
        }
        return matched
    }

    /// 入れ替えてそろう手が 1 つでも残っているか
    private func hasPossibleMove() -> Bool {
        var kinds = Array(repeating: Array(repeating: -1, count: Self.size), count: Self.size)
        for candy in candies { kinds[candy.row][candy.column] = candy.kind }
        func lineAt(_ k: [[Int]], _ r: Int, _ c: Int) -> Bool {
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
                    if lineAt(k, r, c) || lineAt(k, r2, c2) { return true }
                }
            }
        }
        return false
    }
}
