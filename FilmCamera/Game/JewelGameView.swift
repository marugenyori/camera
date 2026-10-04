import PhotosUI
import SwiftUI
import UIKit

/// 隠しゲーム「ジュエル塗り絵」（Jewel Coloring のような、番号どおりに宝石を置いていく塗り絵）。
/// 写真を細かいマス目（横 48 マス）に分け、色を 24 色ほどにまとめて番号をふる。
/// 2 本指でつまんで拡大・移動し、色を選んで 1 本指でなぞると、番号が合うマスにだけ宝石がはまる
struct JewelGameView: View {
    /// 最初に使う写真（最後に撮った写真。なければ見本の絵）
    let initialImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = JewelGame()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color(white: 0.1).ignoresSafeArea()
            if let puzzle = game.puzzle {
                VStack(spacing: 10) {
                    progressBar
                    JewelBoard(game: game)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("2 本指で拡大・移動、1 本指でなぞって宝石を置く")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    palette(puzzle)
                }
                .padding(.horizontal, 10)
            } else {
                ProgressView().tint(.white)
            }
            if game.isComplete, let image = game.finishedImage {
                completeBanner(image)
            }
        }
        .safeAreaInset(edge: .top) { header }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: game.isComplete)
        .task { game.start(with: initialImage ?? JewelPuzzle.sampleImage()) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    game.start(with: image)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("閉じる") { dismiss() }
            Spacer()
            Text("ジュエル塗り絵").font(.headline)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            .accessibilityLabel("ほかの写真で遊ぶ")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(game.filledCount), total: Double(max(game.total, 1)))
                .tint(.orange)
            Text("\(game.filledCount * 100 / max(game.total, 1))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func palette(_ puzzle: JewelPuzzle) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(puzzle.palette.indices, id: \.self) { index in
                        let left = index < game.remaining.count ? game.remaining[index] : 0
                        Button {
                            game.selected = index
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    Circle()
                                        .fill(puzzle.palette[index].gradient)
                                        .frame(width: 42, height: 42)
                                    if left == 0 {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.footnote.weight(.bold).monospacedDigit())
                                            .foregroundStyle(puzzle.isLight(index) ? Color.black : Color.white)
                                    }
                                }
                                .overlay(Circle().stroke(Color.white, lineWidth: game.selected == index ? 3 : 0))
                                Text(left == 0 ? "完了" : "\(left)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .opacity(left == 0 ? 0.4 : 1)
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: game.selected) { _, index in
                withAnimation(.snappy) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .frame(height: 68)
        .padding(.bottom, 4)
    }

    private func completeBanner(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            Text("完成！")
                .font(.title.weight(.heavy))
            Text("\(game.total) 粒の宝石をはめました")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 12) {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("ジュエル塗り絵", image: Image(uiImage: image))) {
                    Label("保存・共有", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                Button("もう一度") { game.restart() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
    }
}

// MARK: - 遊びの状態

@MainActor
final class JewelGame: ObservableObject {
    @Published private(set) var puzzle: JewelPuzzle?
    @Published private(set) var filledCount = 0
    /// 色ごとの残りのマス数
    @Published private(set) var remaining: [Int] = []
    @Published var selected = 0
    /// 新しい問題になるたびに増える（盤面を作り直す合図）
    @Published private(set) var version = 0
    @Published private(set) var finishedImage: UIImage?

    private(set) var filled: [Bool] = []
    var total: Int { filled.count }
    var isComplete: Bool { total > 0 && filledCount == total }

    func start(with image: UIImage) {
        guard let made = JewelPuzzle(image: image) else { return }
        puzzle = made
        restart()
    }

    func restart() {
        guard let puzzle else { return }
        filled = Array(repeating: false, count: puzzle.targets.count)
        filledCount = 0
        remaining = puzzle.palette.indices.map { color in puzzle.targets.filter { $0 == color }.count }
        selected = 0
        finishedImage = nil
        version += 1
    }

    /// マスに宝石を置く。置けたら true（番号が違う・置いてあるなら false）
    func paint(_ index: Int) -> Bool {
        guard let puzzle, filled.indices.contains(index), !filled[index],
              puzzle.targets[index] == selected else { return false }
        filled[index] = true
        filledCount += 1
        remaining[selected] -= 1
        if remaining[selected] == 0, let next = nextColor(after: selected) {
            selected = next
        }
        if isComplete { finishedImage = JewelBoardView.render(puzzle: puzzle, cell: 16) }
        return true
    }

    private func nextColor(after color: Int) -> Int? {
        let count = remaining.count
        for step in 1..<max(count, 2) {
            let candidate = (color + step) % count
            if remaining[candidate] > 0 { return candidate }
        }
        return nil
    }
}

// MARK: - 盤面（拡大・移動できる）

/// UIScrollView で 2 本指の拡大・移動をし、1 本指のなぞりで宝石を置く
private struct JewelBoard: UIViewRepresentable {
    @ObservedObject var game: JewelGame

    func makeCoordinator() -> Coordinator { Coordinator(game: game) }

    func makeUIView(context: Context) -> FittingScrollView {
        let scroll = FittingScrollView()
        scroll.delegate = context.coordinator
        scroll.backgroundColor = UIColor(white: 0.16, alpha: 1)
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        // 1 本指はなぞって塗るのに使うので、移動は 2 本指にする
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        context.coordinator.scroll = scroll
        return scroll
    }

    func updateUIView(_ scroll: FittingScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let puzzle = game.puzzle else { return }
        if coordinator.version != game.version {
            coordinator.version = game.version
            coordinator.install(puzzle: puzzle, filled: game.filled, in: scroll)
        }
        coordinator.board?.selected = game.selected
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let game: JewelGame
        weak var scroll: FittingScrollView?
        var board: JewelBoardView?
        var version = -1
        private let haptic = UIImpactFeedbackGenerator(style: .light)

        init(game: JewelGame) { self.game = game }

        @MainActor
        func install(puzzle: JewelPuzzle, filled: [Bool], in scroll: FittingScrollView) {
            board?.removeFromSuperview()
            let view = JewelBoardView(puzzle: puzzle, filled: filled)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(paint(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(paint(_:))))
            scroll.addSubview(view)
            scroll.contentSize = view.bounds.size
            scroll.board = view
            board = view
            scroll.needsFit = true
            scroll.setNeedsLayout()
        }

        @MainActor @objc private func paint(_ recognizer: UIGestureRecognizer) {
            guard let board else { return }
            let index = board.index(at: recognizer.location(in: board))
            guard let index, game.paint(index) else { return }
            board.markFilled(index)
            haptic.impactOccurred(intensity: 0.5)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { board }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? FittingScrollView)?.centerContent()
        }
    }
}

/// 盤面が画面に収まる倍率を最小にし、小さいときは真ん中に置くスクロールビュー
final class FittingScrollView: UIScrollView {
    weak var board: UIView?
    var needsFit = false
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let board, bounds.width > 0, bounds.height > 0 else { return }
        if needsFit || bounds.size != lastSize {
            lastSize = bounds.size
            let fit = min(bounds.width / board.bounds.width, bounds.height / board.bounds.height)
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 6, 2)
            if needsFit || zoomScale < fit {
                zoomScale = fit
            }
            needsFit = false
        }
        centerContent()
    }

    func centerContent() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }
}

/// 宝石の盤面。CATiledLayer で、拡大しても宝石がくっきり見えるように描き、
/// 置いたマスだけを描き直す（draw はバックグラウンドで呼ばれるので、置いた状態はロックで守る）
final class JewelBoardView: UIView {
    static let cell: CGFloat = 32

    override class var layerClass: AnyClass { CATiledLayer.self }

    private let puzzle: JewelPuzzle
    private let lock = NSLock()
    private var filled: [Bool]
    private var _selected = 0
    var selected: Int {
        get { lock.lock(); defer { lock.unlock() }; return _selected }
        set {
            lock.lock()
            let changed = _selected != newValue
            _selected = newValue
            lock.unlock()
            if changed { setNeedsDisplay() }
        }
    }

    init(puzzle: JewelPuzzle, filled: [Bool]) {
        self.puzzle = puzzle
        self.filled = filled
        let size = CGSize(width: CGFloat(puzzle.columns) * Self.cell, height: CGFloat(puzzle.rows) * Self.cell)
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = UIColor(white: 0.93, alpha: 1)
        if let tiled = layer as? CATiledLayer {
            tiled.tileSize = CGSize(width: 512, height: 512)
            tiled.levelsOfDetail = 4
            tiled.levelsOfDetailBias = 3
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func index(at point: CGPoint) -> Int? {
        let column = Int(point.x / Self.cell)
        let row = Int(point.y / Self.cell)
        guard point.x >= 0, point.y >= 0, column < puzzle.columns, row < puzzle.rows else { return nil }
        return row * puzzle.columns + column
    }

    func markFilled(_ index: Int) {
        lock.lock()
        filled[index] = true
        lock.unlock()
        setNeedsDisplay(rect(of: index).insetBy(dx: -1, dy: -1))
    }

    private func rect(of index: Int) -> CGRect {
        CGRect(x: CGFloat(index % puzzle.columns) * Self.cell, y: CGFloat(index / puzzle.columns) * Self.cell,
               width: Self.cell, height: Self.cell)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        lock.lock()
        let filled = self.filled
        let selected = _selected
        lock.unlock()
        let c = Self.cell
        let firstColumn = max(0, Int(rect.minX / c))
        let lastColumn = min(puzzle.columns - 1, Int(rect.maxX / c))
        let firstRow = max(0, Int(rect.minY / c))
        let lastRow = min(puzzle.rows - 1, Int(rect.maxY / c))
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return }
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let index = row * puzzle.columns + column
                let cellRect = CGRect(x: CGFloat(column) * c, y: CGFloat(row) * c, width: c, height: c)
                let target = puzzle.targets[index]
                if filled[index] {
                    Self.drawJewel(in: cellRect, color: puzzle.uiColors[target], context: context)
                } else {
                    Self.drawNumber(target + 1, in: cellRect, highlighted: target == selected, context: context)
                }
            }
        }
    }

    /// 番号のマス：薄い灰色に番号。選んでいる色のマスは濃くして目立たせる
    private static func drawNumber(_ number: Int, in rect: CGRect, highlighted: Bool, context: CGContext) {
        context.setFillColor(UIColor(white: highlighted ? 0.72 : 0.92, alpha: 1).cgColor)
        context.fill(rect.insetBy(dx: 0.5, dy: 0.5))
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: rect.width * 0.36, weight: highlighted ? .bold : .medium),
            .foregroundColor: UIColor(white: highlighted ? 0.15 : 0.5, alpha: 1),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                  withAttributes: attributes)
    }

    /// 宝石 1 粒：丸いカットの宝石に、光る面（左上）、影（右下）、きらめき
    static func drawJewel(in rect: CGRect, color: UIColor, context: CGContext) {
        context.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
        context.fill(rect)
        let gem = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        context.saveGState()
        context.addEllipse(in: gem)
        context.clip()
        context.setFillColor(color.cgColor)
        context.fill(gem)
        // 光る面と影の面
        context.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.fill(CGRect(x: gem.minX, y: gem.minY, width: gem.width, height: gem.height * 0.45))
        context.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
        context.fill(CGRect(x: gem.minX, y: gem.midY + gem.height * 0.12, width: gem.width, height: gem.height * 0.4))
        // 真ん中のテーブル面（八角形のカットに見えるよう、少し小さな丸を重ねる）
        let table = gem.insetBy(dx: gem.width * 0.24, dy: gem.height * 0.24)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: table)
        context.setFillColor(UIColor.white.withAlphaComponent(0.12).cgColor)
        context.fillEllipse(in: table)
        context.restoreGState()
        // ふち
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(max(0.5, rect.width * 0.03))
        context.strokeEllipse(in: gem)
        // きらめき
        let spark = CGRect(x: gem.minX + gem.width * 0.2, y: gem.minY + gem.height * 0.18,
                           width: gem.width * 0.18, height: gem.height * 0.18)
        context.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        context.fillEllipse(in: spark)
    }

    /// 完成した宝石の絵を画像にする
    static func render(puzzle: JewelPuzzle, cell: CGFloat) -> UIImage {
        let size = CGSize(width: CGFloat(puzzle.columns) * cell, height: CGFloat(puzzle.rows) * cell)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            for index in puzzle.targets.indices {
                let rect = CGRect(x: CGFloat(index % puzzle.columns) * cell, y: CGFloat(index / puzzle.columns) * cell,
                                  width: cell, height: cell)
                drawJewel(in: rect, color: puzzle.uiColors[puzzle.targets[index]], context: renderer.cgContext)
            }
        }
    }
}
