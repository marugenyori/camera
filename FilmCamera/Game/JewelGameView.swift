import PhotosUI
import SwiftUI
import UIKit

/// 隠しゲーム「ジュエル塗り絵」（Jewel Coloring のような、宝石を並べ替えて絵を完成させるパズル）。
/// 宝石のドット絵の一部が、ちがう色の宝石とまざっている。マスのふちに見える色が、そのマスの正しい色。
/// 色がちがう宝石をタップすると下のトレイに移り、空いたマスと同じ色の宝石がトレイにあれば、自動で飛んでいく。
/// トレイがいっぱいになると負け（3 回までマスを増やせる）。全部正しい色になればレベルクリア
struct JewelGameView: View {
    /// 写真で遊ぶときに使う写真（最後に撮った写真）
    let initialImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = JewelGame()
    @State private var pickerItem: PhotosPickerItem?
    @State private var muted = GameAudio.shared.isMuted

    private static let background = Color(red: 0.92, green: 0.92, blue: 0.99)

    var body: some View {
        ZStack {
            Self.background.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                if let puzzle = game.puzzle {
                    GeometryReader { geo in
                        let cell = min(geo.size.width / CGFloat(puzzle.columns), geo.size.height / CGFloat(puzzle.rows))
                        boardView(puzzle, cell: cell)
                            .frame(width: cell * CGFloat(puzzle.columns), height: cell * CGFloat(puzzle.rows))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    trayView(puzzle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            if game.showConfetti { ConfettiView() }
            if game.state != .playing { resultBanner }
        }
        .preferredColorScheme(.light)
        .onAppear {
            game.photo = initialImage
            game.startLevel()
            GameAudio.shared.playMusic(.jewel)
        }
        .onDisappear { GameAudio.shared.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    game.startPhoto(image)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            roundButton("xmark") { dismiss() }
            Spacer()
            Text(game.isPhotoMode ? "写真で遊ぶ" : "レベル \(game.level)")
                .font(.title.weight(.heavy))
                .foregroundStyle(Color(red: 0.62, green: 0.62, blue: 0.85))
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 1, green: 0.66, blue: 0.45)))
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 3)
            }
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
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 1, green: 0.66, blue: 0.45)))
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 3)
        }
    }

    // MARK: - 絵

    private func boardView(_ puzzle: JewelPuzzle, cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for index in puzzle.targets.indices {
                    let rect = CGRect(x: CGFloat(index % puzzle.columns) * cell, y: CGFloat(index / puzzle.columns) * cell,
                                      width: cell, height: cell)
                    let target = puzzle.palette[puzzle.targets[index]]
                    // マスの土台（正しい色を薄く）
                    context.fill(Path(rect), with: .color(target.opacity(0.35)))
                    if let jewel = game.current[index], !game.flyingTo.contains(index) {
                        let correct = jewel == puzzle.targets[index]
                        // まちがった宝石は少し小さく置き、ふちに正しい色が見えるようにする
                        drawGem(in: rect.insetBy(dx: cell * (correct ? 0.04 : 0.16), dy: cell * (correct ? 0.04 : 0.16)),
                                color: puzzle.palette[jewel], context: &context)
                    } else {
                        // 空いたマス：くぼみ
                        let hole = rect.insetBy(dx: cell * 0.18, dy: cell * 0.18)
                        context.fill(Path(ellipseIn: hole), with: .color(target.opacity(0.55)))
                        context.stroke(Path(ellipseIn: hole), with: .color(.black.opacity(0.12)), lineWidth: 1)
                    }
                }
            }
            ForEach(game.flights) { flight in
                FlyingGem(flight: flight, color: puzzle.palette[flight.color], cell: cell, columns: puzzle.columns,
                          boardHeight: cell * CGFloat(puzzle.rows))
            }
            ForEach(game.bursts) { burst in
                BurstView(burst: burst, cell: cell)
            }
            ForEach(game.floats) { item in
                FloatingTextView(item: item, cell: cell)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let column = Int(location.x / cell)
            let row = Int(location.y / cell)
            guard column >= 0, row >= 0, column < puzzle.columns, row < puzzle.rows else { return }
            game.tap(row * puzzle.columns + column)
        }
    }

    // MARK: - トレイ

    private func trayView(_ puzzle: JewelPuzzle) -> some View {
        let columns = 7
        let rows = Int(ceil(Double(game.capacity) / Double(columns)))
        return VStack(spacing: 8) {
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<columns, id: \.self) { column in
                            let slot = row * columns + column
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.93, green: 0.82, blue: 0.68))
                                    .opacity(slot < game.capacity ? 1 : 0)
                                if slot < game.tray.count {
                                    GemShape(color: puzzle.palette[game.tray[slot]])
                                        .padding(4)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: 38, height: 38)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(red: 1, green: 0.95, blue: 0.9)))
            .shadow(color: Color(red: 0.85, green: 0.75, blue: 0.65), radius: 0, x: 0, y: 5)
            HStack {
                Text("トレイ \(game.tray.count)/\(game.capacity)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(game.tray.count >= game.capacity - 2 ? Color.red : Color.secondary)
                Spacer()
                Button {
                    game.addSlots()
                } label: {
                    Label("+7 マス（のこり \(game.extraUses)回）", systemImage: "plus.square.fill")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(red: 0.4, green: 0.8, blue: 0.3)))
                }
                .disabled(game.extraUses == 0)
                .opacity(game.extraUses == 0 ? 0.4 : 1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.tray)
    }

    private var resultBanner: some View {
        VStack(spacing: 14) {
            Text(game.state == .cleared ? "完成！" : "トレイがいっぱい！")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(game.state == .cleared ? Color.orange : Color.purple)
            Text(game.state == .cleared ? "きれいな宝石の絵ができました" : "マスを増やすか、やり直そう")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if game.state == .cleared {
                if let image = game.finishedImage {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("ジュエル塗り絵", image: Image(uiImage: image))) {
                        Label("保存・共有", systemImage: "square.and.arrow.up")
                    }
                }
                Button(game.isPhotoMode ? "もう一度" : "次のレベルへ") { game.nextLevel() }
                    .buttonStyle(.borderedProminent).tint(.green)
            } else {
                if game.extraUses > 0 {
                    Button("+7 マスで続ける") { game.addSlots() }
                        .buttonStyle(.borderedProminent).tint(.green)
                }
                Button("やり直す") { game.restart() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white))
        .shadow(radius: 20)
        .padding(32)
    }
}

// MARK: - 宝石の絵

/// 八角形にカットした宝石（上が明るく、下が暗い面、まんなかに平らな面）
private func drawGem(in rect: CGRect, color: Color, context: inout GraphicsContext) {
    let outline = octagon(in: rect)
    context.fill(outline, with: .color(color))
    context.drawLayer { layer in
        layer.clip(to: outline)
        layer.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.42)),
                   with: .color(.white.opacity(0.35)))
        layer.fill(Path(CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.28, width: rect.width, height: rect.height * 0.28)),
                   with: .color(.black.opacity(0.18)))
    }
    let table = octagon(in: rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25))
    context.fill(table, with: .color(color))
    context.fill(table, with: .color(.white.opacity(0.15)))
    context.stroke(outline, with: .color(.black.opacity(0.18)), lineWidth: max(0.6, rect.width * 0.05))
    let spark = CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.16,
                       width: rect.width * 0.16, height: rect.height * 0.16)
    context.fill(Path(ellipseIn: spark), with: .color(.white.opacity(0.85)))
}

private func octagon(in rect: CGRect) -> Path {
    let k = min(rect.width, rect.height) * 0.29
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + k, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - k, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + k))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - k))
    path.addLine(to: CGPoint(x: rect.maxX - k, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + k, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - k))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + k))
    path.closeSubpath()
    return path
}

/// トレイなどに置く宝石 1 粒
private struct GemShape: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            drawGem(in: CGRect(origin: .zero, size: size), color: color, context: &context)
        }
    }
}

/// トレイとマスのあいだを飛ぶ宝石
private struct FlyingGem: View {
    let flight: JewelGame.Flight
    let color: Color
    let cell: CGFloat
    let columns: Int
    let boardHeight: CGFloat
    @State private var arrived = false

    var body: some View {
        let cellPoint = CGPoint(x: (CGFloat(flight.cell % columns) + 0.5) * cell,
                                y: (CGFloat(flight.cell / columns) + 0.5) * cell)
        // トレイは盤の下のほうにあるとみなす
        let trayPoint = CGPoint(x: cell * CGFloat(columns) / 2, y: boardHeight + 120)
        let from = flight.toTray ? cellPoint : trayPoint
        let to = flight.toTray ? trayPoint : cellPoint
        GemShape(color: color)
            .frame(width: cell * 0.92, height: cell * 0.92)
            .scaleEffect(arrived ? 1 : 1.4)
            .position(arrived ? to : from)
            .onAppear { withAnimation(.easeInOut(duration: 0.32)) { arrived = true } }
            .allowsHitTesting(false)
    }
}

// MARK: - 遊びの決まり

@MainActor
final class JewelGame: ObservableObject {
    enum State { case playing, cleared, full }

    struct Flight: Identifiable {
        let id = UUID()
        let cell: Int
        let color: Int
        let toTray: Bool
    }

    @Published private(set) var puzzle: JewelPuzzle?
    /// 各マスにいま置いてある宝石の色（nil = 空き）
    @Published private(set) var current: [Int?] = []
    @Published private(set) var tray: [Int] = []
    @Published private(set) var capacity = 14
    @Published private(set) var extraUses = 3
    @Published private(set) var state: State = .playing
    @Published private(set) var flights: [Flight] = []
    /// 宝石が飛んでいる最中のマス（着くまで描かない）
    @Published private(set) var flyingTo: Set<Int> = []
    @Published private(set) var level: Int
    @Published private(set) var isPhotoMode = false
    @Published private(set) var finishedImage: UIImage?
    /// 演出：はじける粒、浮かぶ文字、完成の紙吹雪
    @Published private(set) var bursts: [Burst] = []
    @Published private(set) var floats: [FloatingText] = []
    @Published private(set) var showConfetti = false
    var photo: UIImage?
    /// 続けて宝石がはまった数（テンポよくはまるほど音が高くなる）
    private var streak = 0
    private var lastPlaced = Date.distantPast

    init() {
        level = max(1, UserDefaults.standard.integer(forKey: "jewelLevel"))
    }

    /// レベルの問題：はじめの 3 つは用意したドット絵、そのあとは写真（なければ見本の絵）を宝石にする
    func startLevel() {
        isPhotoMode = false
        if level <= JewelPuzzle.presets.count {
            begin(JewelPuzzle.presets[level - 1])
        } else if let made = JewelPuzzle(image: photo ?? JewelPuzzle.sampleImage(),
                                         columns: min(14 + level, 22), colors: min(5 + level / 2, 10)) {
            begin(made)
        }
    }

    func startPhoto(_ image: UIImage) {
        guard let made = JewelPuzzle(image: image, columns: 20, colors: 9) else { return }
        isPhotoMode = true
        begin(made)
    }

    func restart() {
        guard let puzzle else { return }
        begin(puzzle)
    }

    func nextLevel() {
        if isPhotoMode {
            restart()
            return
        }
        level += 1
        UserDefaults.standard.set(level, forKey: "jewelLevel")
        startLevel()
    }

    /// 宝石を並べ、一部のマスどうしで入れ替えてバラバラにする（レベルが上がるほど多く）
    private func begin(_ made: JewelPuzzle) {
        puzzle = made
        var jewels: [Int?] = made.targets.map { $0 }
        let ratio = min(0.6, 0.25 + Double(level) * 0.04)
        let count = max(4, Int(Double(jewels.count) * ratio))
        let chosen = Array(jewels.indices.shuffled().prefix(count))
        let shuffled = chosen.map { jewels[$0] }.shuffled()
        for (cell, jewel) in zip(chosen, shuffled) { jewels[cell] = jewel }
        current = jewels
        tray = []
        capacity = 14
        extraUses = 3
        flights = []
        flyingTo = []
        finishedImage = nil
        bursts = []
        floats = []
        showConfetti = false
        streak = 0
        state = jewels.enumerated().allSatisfy({ $0.element == made.targets[$0.offset] }) ? .cleared : .playing
    }

    func addSlots() {
        guard extraUses > 0 else { return }
        extraUses -= 1
        capacity += 7
        if state == .full { state = .playing }
        GameAudio.shared.play(.special)
    }

    /// マスをタップ：色がちがう宝石ならトレイへ移し、空いたマスに合う宝石をトレイから飛ばす
    func tap(_ index: Int) {
        guard state == .playing, let puzzle, current.indices.contains(index),
              let jewel = current[index] else { return }
        if jewel == puzzle.targets[index] {
            GameAudio.shared.tick()       // 正しい宝石はそのまま
            return
        }
        guard tray.count < capacity else {
            state = .full
            GameAudio.shared.play(.invalid)
            return
        }
        current[index] = nil
        GameAudio.shared.play(.tap)
        launch(Flight(cell: index, color: jewel, toTray: true))
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            tray.append(jewel)
            await fillFromTray()
            if tray.count >= capacity && !canProgress() { state = .full; GameAudio.shared.play(.lose) }
        }
    }

    /// 空いているマスのうち、トレイに同じ色の宝石があるものへ飛ばす
    private func fillFromTray() async {
        guard let puzzle else { return }
        var moved = true
        while moved {
            moved = false
            for cell in current.indices where current[cell] == nil && !flyingTo.contains(cell) {
                let need = puzzle.targets[cell]
                guard let slot = tray.firstIndex(of: need) else { continue }
                tray.remove(at: slot)
                flyingTo.insert(cell)
                current[cell] = need
                launch(Flight(cell: cell, color: need, toTray: false))
                moved = true
                try? await Task.sleep(for: .milliseconds(90))
                let landed = cell
                Task {
                    try? await Task.sleep(for: .milliseconds(320))
                    flyingTo.remove(landed)
                    landedEffects(at: landed, color: need)
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(340))
        if current.enumerated().allSatisfy({ $0.element == puzzle.targets[$0.offset] }) && state == .playing {
            state = .cleared
            showConfetti = true
            finishedImage = JewelBoardImage.render(puzzle)
            GameAudio.shared.play(.complete)
        }
    }

    /// 宝石がはまったときの演出：粒がはじけ、テンポよく続くと音が上がり、1 色そろうと大きくお祝い
    private func landedEffects(at cell: Int, color: Int) {
        guard let puzzle else { return }
        let x = CGFloat(cell % puzzle.columns) + 0.5
        let y = CGFloat(cell / puzzle.columns) + 0.5
        addBursts([Burst(x: x, y: y, color: puzzle.palette[color], count: 8, power: 0.8)])
        streak = Date().timeIntervalSince(lastPlaced) < 1.2 ? streak + 1 : 1
        lastPlaced = Date()
        if streak >= 3 {
            GameAudio.shared.play(.pop(combo: min(streak - 1, 8)))
            if streak % 3 == 0 {
                addFloat(FloatingText(text: "×\(streak)", x: x, y: y, color: .orange))
            }
        } else {
            GameAudio.shared.play(.place)
        }
        // この色が全部そろったら
        let left = current.indices.filter { puzzle.targets[$0] == color && current[$0] != color }.count
        if left == 0 {
            GameAudio.shared.play(.special)
            let cells = puzzle.targets.indices.filter { puzzle.targets[$0] == color }.shuffled().prefix(30)
            addBursts(cells.map {
                Burst(x: CGFloat($0 % puzzle.columns) + 0.5, y: CGFloat($0 / puzzle.columns) + 0.5,
                      color: puzzle.palette[color], count: 6, power: 1.2)
            })
            addFloat(FloatingText(text: "この色コンプリート！", x: CGFloat(puzzle.columns) / 2,
                                  y: CGFloat(puzzle.rows) / 2, color: .pink, big: true))
        }
    }

    private func addBursts(_ items: [Burst]) {
        bursts.append(contentsOf: items)
        let ids = Set(items.map(\.id))
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            bursts.removeAll { ids.contains($0.id) }
        }
    }

    private func addFloat(_ item: FloatingText) {
        floats.append(item)
        let id = item.id
        Task {
            try? await Task.sleep(for: .milliseconds(1100))
            floats.removeAll { $0.id == id }
        }
    }

    /// トレイがいっぱいでも、まだ進められるか（空きマスに合う宝石がトレイにあるなど）
    private func canProgress() -> Bool {
        guard let puzzle else { return false }
        return current.indices.contains { current[$0] == nil && tray.contains(puzzle.targets[$0]) }
    }

    private func launch(_ flight: Flight) {
        flights.append(flight)
        let id = flight.id
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            flights.removeAll { $0.id == id }
        }
    }
}

/// 完成した宝石の絵を画像にする
enum JewelBoardImage {
    @MainActor
    static func render(_ puzzle: JewelPuzzle) -> UIImage? {
        let cell: CGFloat = 40
        let view = Canvas { context, _ in
            for index in puzzle.targets.indices {
                let rect = CGRect(x: CGFloat(index % puzzle.columns) * cell, y: CGFloat(index / puzzle.columns) * cell,
                                  width: cell, height: cell)
                context.fill(Path(rect), with: .color(puzzle.palette[puzzle.targets[index]].opacity(0.35)))
                drawGem(in: rect.insetBy(dx: 1.5, dy: 1.5), color: puzzle.palette[puzzle.targets[index]], context: &context)
            }
        }
        .frame(width: cell * CGFloat(puzzle.columns), height: cell * CGFloat(puzzle.rows))
        .background(Color.white)
        return ImageRenderer(content: view).uiImage
    }
}
