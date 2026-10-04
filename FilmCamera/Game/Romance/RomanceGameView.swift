import SwiftUI

/// 隠しゲーム「放課後メモリーズ」：2000 年代のギャルゲー風の恋愛アドベンチャー。
/// タイトル → 日付の札 → 朝の場面 → 放課後に行く場所を選ぶ → その子との場面 → 次の日……
/// 5 日すごしたら土曜の桜まつりでエンディング。毎朝、自動でセーブする（「つづきから」はその日の朝から）
struct RomanceGameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var game = RomanceGame()
    @State private var showingLog = false
    @State private var confirmingTitle = false
    @State private var viewingCG: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch game.phase {
            case .title:
                titleScreen
            case .gallery:
                gallery
            case .dayCard(let title):
                DayCard(title: title)
            case .scene, .map:
                scene
            case .theEnd(let title):
                theEnd(title)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { GameAudio.shared.playMusic(.school) }
        .onDisappear { GameAudio.shared.stop() }
        .sheet(isPresented: $showingLog) { logSheet }
        .fullScreenCover(item: Binding(get: { viewingCG.map(CGName.init) }, set: { viewingCG = $0?.id })) { item in
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = RomanceImages.cg(item.id) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .onTapGesture { viewingCG = nil }
        }
        .confirmationDialog("タイトルに戻りますか？", isPresented: $confirmingTitle, titleVisibility: .visible) {
            Button("タイトルへ") { game.toTitle() }
        } message: {
            Text("今日の朝から、「つづきから」で再開できます。")
        }
    }

    // MARK: - タイトル

    private var titleScreen: some View {
        let keyVisual = RomanceImages.image("title")
        return ZStack {
            BackdropView(backdrop: .sakuraHill)
            if keyVisual == nil {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: -40) {
                        HeroinePortrait(heroine: .shizuku, face: .smile).frame(height: 220)
                        HeroinePortrait(heroine: .hinata, face: .laugh).frame(height: 250)
                        HeroinePortrait(heroine: .rin, face: .smile).frame(height: 220)
                    }
                    .opacity(0.9)
                }
                .ignoresSafeArea()
            }
            VStack(spacing: 22) {
                Spacer().frame(height: keyVisual == nil ? 50 : 20)
                if let keyVisual {
                    // タイトルの一枚絵（横長なので、画面の幅いっぱいに出す）
                    Image(uiImage: keyVisual)
                        .resizable()
                        .scaledToFit()
                        .overlay(Rectangle().stroke(.white.opacity(0.9), lineWidth: 2))
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 2) {
                                OutlinedText(text: RomanceScript.title, size: 34, fill: Color(red: 1, green: 0.55, blue: 0.7))
                                OutlinedText(text: RomanceScript.subtitle, size: 17, fill: .white)
                            }
                            .offset(y: 34)
                        }
                        .padding(.bottom, 30)
                } else {
                    VStack(spacing: 6) {
                        OutlinedText(text: RomanceScript.title, size: 40, fill: Color(red: 1, green: 0.55, blue: 0.7))
                        OutlinedText(text: RomanceScript.subtitle, size: 20, fill: .white)
                    }
                }
                VStack(spacing: 12) {
                    menuButton("はじめから") { game.newGame() }
                    menuButton("つづきから") { game.continueGame() }
                        .disabled(!game.hasSave)
                        .opacity(game.hasSave ? 1 : 0.45)
                    menuButton("おもいで") { game.phase = .gallery }
                    menuButton("ゲームをえらぶ") { dismiss() }
                }
                .padding(.horizontal, 60)
                Spacer()
                Text("© 2026 FILM CAMERA SOFT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)
            }
        }
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .serif).weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(
                    LinearGradient(colors: [Color(red: 0.95, green: 0.5, blue: 0.7).opacity(0.85),
                                            Color(red: 0.55, green: 0.35, blue: 0.8).opacity(0.85)],
                                   startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.9), lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - おもいで

    private var gallery: some View {
        ZStack {
            BackdropView(backdrop: .library)
            Color.black.opacity(0.45).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OutlinedText(text: "おもいで", size: 30, fill: Color(red: 1, green: 0.6, blue: 0.75))
                        .frame(maxWidth: .infinity)
                    ForEach(Heroine.allCases, id: \.self) { heroine in
                        HStack(spacing: 12) {
                            HeroinePortrait(heroine: heroine, face: .smile)
                                .frame(width: 90, height: 120)
                                .background(RoundedRectangle(cornerRadius: 12).fill(heroine.color.opacity(0.35)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(heroine.fullName).font(.headline)
                                Text(profile(heroine)).font(.caption).foregroundStyle(.white.opacity(0.8))
                                let title = RomanceScript.ending(heroine).title
                                Label(game.endingsSeen.contains(title) ? title : "？？？",
                                      systemImage: game.endingsSeen.contains(title) ? "heart.fill" : "lock.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(game.endingsSeen.contains(title) ? heroine.color : .white.opacity(0.5))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4)))
                    }
                    let cgs = RomanceGame.allCGs.filter { RomanceImages.cg($0) != nil }
                    if !cgs.isEmpty {
                        Text("CG モード").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(cgs, id: \.self) { name in
                                let seen = game.cgsSeen.contains(name)
                                Button {
                                    if seen { viewingCG = name }
                                } label: {
                                    ZStack {
                                        Color.black.opacity(0.5)
                                        if seen, let image = RomanceImages.cg(name) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else {
                                            Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                    .frame(height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    let normal = RomanceScript.ending(nil).title
                    Label(game.endingsSeen.contains(normal) ? normal : "？？？", systemImage: "sparkles")
                        .font(.footnote.weight(.bold))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4)))
                    menuButton("タイトルへ") { game.phase = .title }
                        .padding(.horizontal, 60)
                        .padding(.top, 8)
                }
                .padding(20)
            }
        }
    }

    private func profile(_ heroine: Heroine) -> String {
        switch heroine {
        case .hinata: return "隣の家に住む幼なじみ。明るくて世話焼き。料理が得意。"
        case .shizuku: return "物静かな図書委員。本と星が好き。めったに笑わない。"
        case .rin: return "写真部の一年生。おじいちゃんのフィルムカメラを持ち歩く。素直じゃない。"
        }
    }

    // MARK: - 場面

    private var scene: some View {
        GeometryReader { geo in
            ZStack {
                BackdropView(backdrop: game.backdrop)
                    .id(game.backdrop)
                    .transition(.opacity)
                if let heroine = game.heroine {
                    HeroinePortrait(heroine: heroine, face: game.face)
                        .frame(height: geo.size.height * 0.78)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: geo.size.height * 0.06)
                        .id(heroine)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                if let name = game.cg, let image = RomanceImages.cg(name) {
                    // イベント CG は画面いっぱいに（立ち絵の上に重ねる）
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                FlashView(trigger: game.flash)
                if game.phase == .scene {
                    VStack(spacing: 0) {
                        topButtons
                        Spacer()
                        textBox
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    if let choices = game.choices {
                        choiceMenu(choices)
                    }
                } else {
                    mapMenu
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if game.phase == .scene { game.tap() } }
            .animation(.easeInOut(duration: 0.4), value: game.backdrop)
            .animation(.easeOut(duration: 0.25), value: game.heroine)
            .animation(.easeInOut(duration: 0.6), value: game.cg)
        }
    }

    private var topButtons: some View {
        HStack(spacing: 8) {
            Spacer()
            smallButton("LOG", lit: false) { showingLog = true }
            smallButton("AUTO", lit: game.auto) { game.toggleAuto() }
            smallButton("SKIP", lit: game.skipping) { game.toggleSkip() }
            smallButton("MENU", lit: false) { confirmingTitle = true }
        }
        .padding(.top, 6)
    }

    private func smallButton(_ title: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.heavy).monospaced())
                .foregroundStyle(lit ? Color.black : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(lit ? Color(red: 1, green: 0.8, blue: 0.4) : .black.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var speakerName: String? {
        switch game.speaker {
        case .narration: return nil
        case .me: return RomanceScript.heroName
        case .heroine(let heroine): return heroine.name
        }
    }

    private var speakerColor: Color {
        if case .heroine(let heroine) = game.speaker { return heroine.color }
        return Color(red: 0.35, green: 0.55, blue: 0.9)
    }

    /// 2000 年代風のメッセージウィンドウ（半透明の紺、白いふち、名前の札）
    private var textBox: some View {
        let done = game.shown >= game.text.count
        return VStack(alignment: .leading, spacing: 6) {
            if let name = speakerName {
                Text(name)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(speakerColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1.5))
            }
            Text(String(game.text.prefix(game.shown)))
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            HStack {
                Spacer()
                if done && game.choices == nil {
                    BlinkingTriangle()
                }
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.15, blue: 0.4).opacity(0.82),
                                              Color(red: 0.2, green: 0.3, blue: 0.6).opacity(0.78)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.85), lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1).padding(4))
    }

    private func choiceMenu(_ options: [Option]) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ForEach(options.indices, id: \.self) { index in
                    Button {
                        game.choose(options[index])
                    } label: {
                        Text(options[index].text)
                            .font(.system(.body, design: .serif).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(
                                LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.65).opacity(0.9),
                                                        Color(red: 0.6, green: 0.3, blue: 0.75).opacity(0.9)],
                                               startPoint: .leading, endPoint: .trailing)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
        }
    }

    /// 放課後、どこへ行くか
    private var mapMenu: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(RomanceScript.dayTitle(game.day) + "　放課後")
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                OutlinedText(text: "どこへ行こう？", size: 28, fill: Color(red: 1, green: 0.85, blue: 0.5))
                ForEach(RomanceScript.spots(game.day)) { spot in
                    Button {
                        game.go(to: spot)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: spot.systemImage)
                                .font(.title3)
                                .frame(width: 36)
                            Text(spot.name)
                                .font(.system(.headline, design: .serif).weight(.bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.15, green: 0.22, blue: 0.5).opacity(0.85)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.85), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                Button("まっすぐ帰る") { game.go(to: nil) }
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 30)
        }
    }

    // MARK: - おわり

    private func theEnd(_ title: String) -> some View {
        ZStack {
            BackdropView(backdrop: .sakuraHill)
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 20) {
                OutlinedText(text: "THE END", size: 44, fill: .white)
                OutlinedText(text: title, size: 22, fill: Color(red: 1, green: 0.7, blue: 0.8))
                Text("おもいでに追加されました")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                menuButton("タイトルへ") { game.toTitle() }
                    .padding(.horizontal, 70)
                    .padding(.top, 20)
            }
        }
    }

    private var logSheet: some View {
        NavigationStack {
            List(game.log) { line in
                VStack(alignment: .leading, spacing: 3) {
                    if let name = line.name {
                        Text(name).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Text(line.text).font(.subheadline)
                }
            }
            .listStyle(.plain)
            .navigationTitle("これまでの会話")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 部品

/// ふちどりのある文字（ゲームのロゴ風）
private struct OutlinedText: View {
    let text: String
    let size: CGFloat
    let fill: Color

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                Text(text)
                    .foregroundStyle(Color(red: 0.25, green: 0.1, blue: 0.3))
                    .offset(x: cos(angle) * 2.5, y: sin(angle) * 2.5)
            }
            Text(text).foregroundStyle(fill)
        }
        .font(.system(size: size, weight: .heavy, design: .serif))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }
}

/// 日付の札（黒い画面に日付がふわっと出る）
private struct DayCard: View {
    let title: String
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("— \(RomanceScript.title) —")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
        }
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.6)) { shown = true } }
    }
}

/// 文章を読み終わったときの、点滅する ▼
private struct BlinkingTriangle: View {
    @State private var on = false

    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .opacity(on ? 1 : 0.2)
            .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { on = true } }
    }
}

/// ぶつかったときなどの白い光
private struct FlashView: View {
    let trigger: Int
    @State private var opacity = 0.0

    var body: some View {
        Color.white
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                opacity = 1
                withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
            }
    }
}

// MARK: - 進行

@MainActor
final class RomanceGame: ObservableObject {
    /// シナリオに出てくるイベント CG の名前（cg_〇〇.png）
    static let allCGs = ["bump", "hinata_sunset", "shizuku_stars", "rin_photo", "hinata_end", "shizuku_end", "rin_end"]

    enum Phase: Equatable {
        case title, gallery, dayCard(String), scene, map, theEnd(String)
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let name: String?
        let text: String
    }

    private struct Frame {
        let steps: [Step]
        var index: Int
    }

    @Published var phase: Phase = .title
    @Published private(set) var backdrop: Backdrop = .black
    @Published private(set) var heroine: Heroine?
    @Published private(set) var face: Face = .normal
    @Published private(set) var speaker: Speaker = .narration
    @Published private(set) var text = ""
    @Published private(set) var shown = 0
    @Published private(set) var choices: [Option]?
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var auto = false
    @Published private(set) var skipping = false
    @Published private(set) var flash = 0
    /// 表示中のイベント CG（画像があるときだけ）
    @Published private(set) var cg: String?
    /// 見たイベント CG（おもいでの CG モードに出す）
    @Published private(set) var cgsSeen: Set<String>
    @Published private(set) var day = 1
    @Published private(set) var endingsSeen: Set<String>
    private var love: [Heroine: Int] = [:]

    private var frames: [Frame] = []
    private var completion: (() -> Void)?
    private var typing: Task<Void, Never>?
    private var waiter: Task<Void, Never>?

    init() {
        endingsSeen = Set(UserDefaults.standard.stringArray(forKey: "romanceEndings") ?? [])
        cgsSeen = Set(UserDefaults.standard.stringArray(forKey: "romanceCGs") ?? [])
    }

    var hasSave: Bool { UserDefaults.standard.integer(forKey: "romanceDay") > 0 }

    // MARK: 始める・続ける

    func newGame() {
        day = 1
        love = [:]
        log = []
        startDay()
    }

    func continueGame() {
        let defaults = UserDefaults.standard
        day = max(1, defaults.integer(forKey: "romanceDay"))
        let saved = defaults.dictionary(forKey: "romanceLove") as? [String: Int] ?? [:]
        love = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in
            Heroine(rawValue: key).map { ($0, value) }
        })
        log = []
        startDay()
    }

    func toTitle() {
        stopTimers()
        frames = []
        completion = nil
        choices = nil
        heroine = nil
        cg = nil
        auto = false
        skipping = false
        phase = .title
        GameAudio.shared.playMusic(.school)
    }

    /// 毎朝セーブして、日付の札を出してから朝の場面へ（6 日目はエンディング）
    private func startDay() {
        let defaults = UserDefaults.standard
        defaults.set(day, forKey: "romanceDay")
        defaults.set(Dictionary(uniqueKeysWithValues: love.map { ($0.key.rawValue, $0.value) }), forKey: "romanceLove")
        stopTimers()
        heroine = nil
        choices = nil
        cg = nil
        GameAudio.shared.stopMusic()
        let title = RomanceScript.dayTitle(day)
        phase = .dayCard(title)
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard phase == .dayCard(title) else { return }
            if day > RomanceScript.days {
                runEnding()
            } else {
                run(RomanceScript.morning(day)) { [weak self] in self?.phase = .map }
            }
        }
    }

    /// 放課後に行く場所を決める（nil = まっすぐ帰る）
    func go(to spot: Spot?) {
        GameAudio.shared.play(.place)
        let steps = spot.map { RomanceScript.event($0.heroine, day: day) } ?? RomanceScript.goHome(day)
        run(steps) { [weak self] in
            guard let self else { return }
            day += 1
            startDay()
        }
    }

    /// いちばん好感度の高い子のエンディング（足りなければノーマルエンド）
    private func runEnding() {
        let best = Heroine.allCases
            .map { ($0, love[$0] ?? 0) }
            .max { $0.1 < $1.1 }
        let chosen = best.flatMap { $0.1 >= RomanceScript.endingLove ? $0.0 : nil }
        let ending = RomanceScript.ending(chosen)
        run(ending.steps) { [weak self] in
            guard let self else { return }
            endingsSeen.insert(ending.title)
            UserDefaults.standard.set(Array(endingsSeen), forKey: "romanceEndings")
            UserDefaults.standard.removeObject(forKey: "romanceDay")
            UserDefaults.standard.removeObject(forKey: "romanceLove")
            auto = false
            skipping = false
            GameAudio.shared.play(.complete)
            phase = .theEnd(ending.title)
        }
    }

    // MARK: シナリオを進める

    private func run(_ steps: [Step], then: @escaping () -> Void) {
        phase = .scene
        frames = [Frame(steps: steps, index: 0)]
        completion = then
        advance()
    }

    /// 次のセリフか選択肢まで進める
    private func advance() {
        stopTimers()
        choices = nil
        while let frame = frames.last {
            if frame.index >= frame.steps.count {
                frames.removeLast()
                continue
            }
            let step = frame.steps[frame.index]
            frames[frames.count - 1].index += 1
            switch step {
            case .bg(let backdrop):
                self.backdrop = backdrop
            case .show(let heroine, let face):
                self.heroine = heroine
                self.face = face
            case .hide:
                heroine = nil
            case .love(let heroine, let amount):
                love[heroine, default: 0] += amount
            case .music(let song):
                GameAudio.shared.playMusic(song)
            case .flash:
                flash += 1
                GameAudio.shared.play(.invalid)
            case .cg(let name):
                if let name, RomanceImages.cg(name) != nil {
                    cg = name
                    if !cgsSeen.contains(name) {
                        cgsSeen.insert(name)
                        UserDefaults.standard.set(Array(cgsSeen), forKey: "romanceCGs")
                    }
                } else {
                    cg = nil
                }
            case .line(let speaker, let face, let text):
                if case .heroine(let heroine) = speaker {
                    self.heroine = heroine
                    if let face { self.face = face }
                }
                self.speaker = speaker
                self.text = text
                let name: String?
                switch speaker {
                case .narration: name = nil
                case .me: name = RomanceScript.heroName
                case .heroine(let heroine): name = heroine.name
                }
                log.append(LogLine(name: name, text: text))
                startTyping()
                return
            case .choice(let options):
                skipping = false
                choices = options
                return
            }
        }
        let next = completion
        completion = nil
        next?()
    }

    func choose(_ option: Option) {
        GameAudio.shared.play(.place)
        log.append(LogLine(name: "▶", text: option.text))
        frames.append(Frame(steps: option.steps, index: 0))
        advance()
    }

    /// 画面をタップ：文字を出し切っていなければ全部出し、出し切っていれば次へ
    func tap() {
        guard choices == nil else { return }
        if skipping {
            skipping = false
            return
        }
        if shown < text.count {
            typing?.cancel()
            shown = text.count
            scheduleAuto()
        } else {
            GameAudio.shared.tick()
            advance()
        }
    }

    func toggleAuto() {
        auto.toggle()
        if auto && shown >= text.count && choices == nil { scheduleAuto() }
    }

    func toggleSkip() {
        skipping.toggle()
        if skipping && choices == nil { advance() }
    }

    private func startTyping() {
        shown = 0
        if skipping {
            shown = text.count
            waiter = Task {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                advance()
            }
            return
        }
        typing = Task {
            while shown < text.count {
                try? await Task.sleep(for: .milliseconds(32))
                guard !Task.isCancelled else { return }
                shown += 1
            }
            scheduleAuto()
        }
    }

    private func scheduleAuto() {
        guard auto, phase == .scene else { return }
        waiter?.cancel()
        let wait = 1.2 + Double(text.count) * 0.04
        waiter = Task {
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, choices == nil else { return }
            advance()
        }
    }

    private func stopTimers() {
        typing?.cancel()
        waiter?.cancel()
        typing = nil
        waiter = nil
    }
}

private struct CGName: Identifiable {
    let id: String
}
