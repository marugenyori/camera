import SwiftUI

/// 「ふたりの文明」の入口：名前と遊び方（ひとり・近く・離れて）を選ぶ
struct CivGameView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("civName") private var name = ""
    @ObservedObject private var albums = AlbumStore.shared
    @State private var albumID: String?
    @State private var session: CivSession?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ふたりの文明")
                            .font(.largeTitle.weight(.heavy))
                        Text("2 人で 1 つの文明を育てる、交代制の街づくり。都市を作り、土地を耕し、技術を研究して、宇宙船を打ち上げたら 2 人の勝ち。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    TextField("あなたの名前", text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button {
                        open(.nearbyHost)
                    } label: {
                        Label("文明を作って、相手を待つ", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Button {
                        open(.nearbyJoin)
                    } label: {
                        Label("近くの文明に参加する", systemImage: "person.2.wave.2")
                    }
                } header: {
                    Text("近くで遊ぶ")
                } footer: {
                    Text("同じ場所にいる 2 台の iPhone を Wi-Fi・Bluetooth で直接つなぎます。1 人が「作って待つ」、もう 1 人が「参加する」を押します。はじめてのときは「ローカルネットワーク」の許可をたずねられます。")
                }
                Section {
                    if albums.albums.isEmpty {
                        Text("共有アルバムがまだありません。アルバムの画面で友だちを招待してください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("共有アルバム", selection: Binding(get: { albumID ?? albums.albums.first?.id },
                                                              set: { albumID = $0 })) {
                            ForEach(albums.albums) { album in
                                Text(album.title).tag(Optional(album.id))
                            }
                        }
                        Button {
                            if let album = albums.albums.first(where: { $0.id == (albumID ?? albums.albums.first?.id) }) {
                                open(.cloud(album))
                            }
                        } label: {
                            Label("このアルバムの仲間と遊ぶ", systemImage: "icloud")
                        }
                    }
                } header: {
                    Text("離れて遊ぶ")
                } footer: {
                    Text("同じ共有アルバムに入っている友だちと、iCloud で交代に遊びます。相手の番が終わると通知が届きます。アルバムごとに 1 つの文明があります。")
                }
                Section {
                    Button {
                        open(.solo)
                    } label: {
                        Label("ひとりで試す", systemImage: "person")
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: Binding(get: { session.map(SessionBox.init) }, set: { if $0 == nil { session = nil } })) { box in
            CivPlayView(session: box.session)
        }
    }

    private struct SessionBox: Identifiable {
        let session: CivSession
        var id: ObjectIdentifier { ObjectIdentifier(session) }
    }

    private func open(_ mode: CivSession.Mode) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        session = CivSession(mode: mode, name: trimmed.isEmpty ? "プレイヤー" : String(trimmed.prefix(12)))
    }
}

// MARK: - 遊ぶ画面

struct CivPlayView: View {
    @ObservedObject var session: CivSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: (Int, Int)?
    @State private var zoom: CGFloat = 1.3
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var showingTech = false
    @State private var showingLog = false
    @State private var confirmingRestart = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let state = session.state {
                    TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                        Canvas { context, size in
                            CivRenderer.draw(&context, size: size, state: state, zoom: zoom, pan: pan,
                                             selected: selected, time: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                    .ignoresSafeArea()
                    .onTapGesture(coordinateSpace: .local) { location in
                        let hit = CivRenderer.cell(at: location, size: geo.size, state: state, zoom: zoom, pan: pan)
                        if let hit, let current = selected, current == hit {
                            selected = nil
                        } else {
                            selected = hit
                        }
                        GameAudio.shared.tick()
                    }
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture)
                    VStack(spacing: 8) {
                        hud(state)
                        Spacer()
                        if let text = session.message {
                            banner(text)
                        }
                        panel(state)
                    }
                    if state.won { victory(state) }
                } else {
                    waiting
                }
            }
        }
        .task { await session.start() }
        .onDisappear { session.stop() }
        .sheet(isPresented: $showingTech) {
            if let state = session.state { CivTechSheet(session: session, state: state) }
        }
        .sheet(isPresented: $showingLog) {
            if let state = session.state { CivLogSheet(state: state) }
        }
        .confirmationDialog("最初から作り直しますか？", isPresented: $confirmingRestart, titleVisibility: .visible) {
            Button("作り直す", role: .destructive) { session.restart() }
        } message: {
            Text("いまの文明は消えます（相手の画面も新しい文明になります）。")
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if panStart == nil { panStart = pan }
                if let start = panStart {
                    pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                }
            }
            .onEnded { _ in panStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = zoom }
                if let start = zoomStart { zoom = min(max(start * value.magnification, 0.7), 4) }
            }
            .onEnded { _ in zoomStart = nil }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(session.status)
                .font(.callout)
                .multilineTextAlignment(.center)
            if let text = session.message {
                Text(text).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button("もどる") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(32)
    }

    // MARK: 上の表示

    private func hud(_ state: CivState) -> some View {
        let income = state.income
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("閉じる")
                VStack(alignment: .leading, spacing: 1) {
                    Text("ターン \(state.turn)・\(state.era)")
                        .font(.subheadline.weight(.heavy))
                    Text(session.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button {
                        showingLog = true
                    } label: {
                        Label("できごと", systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        withAnimation { zoom = 1.3; pan = .zero }
                    } label: {
                        Label("真ん中に戻す", systemImage: "scope")
                    }
                    if session.mode != .nearbyJoin {
                        Button(role: .destructive) {
                            confirmingRestart = true
                        } label: {
                            Label("最初から作り直す", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            HStack(spacing: 10) {
                stat("🔨", "\(state.production)", "+\(income.prod)")
                Button {
                    showingTech = true
                } label: {
                    stat("📖", state.research.map { "\($0.name) \(min(state.progress, $0.cost))/\($0.cost)" } ?? "研究を選ぶ",
                         "+\(income.sci)")
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                players(state)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func stat(_ icon: String, _ value: String, _ plus: String) -> some View {
        HStack(spacing: 3) {
            Text(icon)
            Text(value).font(.caption.weight(.bold).monospacedDigit())
            Text(plus).font(.caption2.weight(.semibold)).foregroundStyle(.green)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.5)))
    }

    private func players(_ state: CivState) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(state.players.enumerated()), id: \.offset) { index, player in
                let active = index == state.current
                Text(player.name)
                    .font(.caption2.weight(active ? .heavy : .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .foregroundStyle(active ? .white : .primary)
                    .background(Capsule().fill(active ? CivRenderer.color(of: player.color) : Color.white.opacity(0.4)))
            }
            if state.players.count < 2 && session.mode != .solo {
                Text("相手を待っています")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .onTapGesture { session.message = nil }
    }

    // MARK: 下のパネル

    private func panel(_ state: CivState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let spot = selected, let tile = state.tile(spot.0, spot.1) {
                tilePanel(state, x: spot.0, y: spot.1, tile: tile)
            } else {
                Text(session.isMyTurn ? "マスをタップして、何をするか選びます" : "\(session.currentName)さんの番です。地図を見ながら待ちましょう")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<CivState.actionsPerTurn, id: \.self) { k in
                        Circle()
                            .fill(k < state.actions && session.isMyTurn ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                }
                .accessibilityLabel("残りの行動 \(state.actions)")
                Text(session.isMyTurn ? "あなたの番" : "\(session.currentName)さんの番")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button {
                    selected = nil
                    session.endTurn()
                } label: {
                    Label("番を終える", systemImage: "hourglass")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!session.isMyTurn || state.won)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func tilePanel(_ state: CivState, x: Int, y: Int, tile: CivTile) -> some View {
        if !tile.revealed {
            Text("霧の向こう").font(.headline)
            actionButton(state, "探検する", systemImage: "binoculars.fill", cost: nil, .explore(x, y))
        } else if let cityIndex = state.city(at: x, y) {
            cityPanel(state, cityIndex)
        } else {
            let yield = state.yield(of: x, y)
            HStack {
                Text(tile.terrain.name + (tile.improvement.map { "・\($0.name)" } ?? ""))
                    .font(.headline)
                Spacer()
                Text("🍞\(yield.food) 🔨\(yield.prod) 📖\(yield.sci)")
                    .font(.caption.monospacedDigit())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if tile.ruin {
                        actionButton(state, "遺跡を調べる", systemImage: "questionmark.circle.fill", cost: nil, .explore(x, y))
                    }
                    if tile.terrain.isLand && tile.terrain != .mountain {
                        actionButton(state, "都市を作る", systemImage: "house.fill", cost: CivState.cityCost, .foundCity(x, y))
                    }
                    ForEach(CivImprovement.allCases.filter { $0.allowed(on: tile.terrain) }, id: \.self) { kind in
                        actionButton(state, kind.name + "を作る", systemImage: kind == .farm ? "leaf.fill" : kind == .mine ? "hammer.fill" : "sailboat.fill",
                                     cost: kind.cost, .improve(x, y, kind))
                    }
                }
            }
        }
    }

    private func cityPanel(_ state: CivState, _ cityIndex: Int) -> some View {
        let city = state.cities[cityIndex]
        let yield = state.cityYield(cityIndex)
        let buildable = CivBuilding.allCases.filter { state.techs.contains($0.tech) && !city.buildings.contains($0) }
        let wonders = CivWonder.allCases.filter { state.techs.contains($0.tech) && !state.wonders.contains($0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(CivRenderer.color(of: city.founder)).frame(width: 10, height: 10)
                Text(city.name).font(.headline)
                Text("人口 \(city.pop)").font(.caption.weight(.bold))
                Spacer()
                Text("🍞\(yield.food) 🔨\(yield.prod) 📖\(yield.sci)")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: Double(min(city.food, city.growThreshold)), total: Double(city.growThreshold)) {
                Text("食料 \(city.food)/\(city.growThreshold)（いっぱいで人口 +1、1 人で 🍞2 食べる）")
                    .font(.caption2)
            }
            .tint(.green)
            if !city.buildings.isEmpty {
                Text(city.buildings.map(\.name).joined(separator: "・"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(buildable) { building in
                        actionButton(state, building.name, systemImage: building.symbol, cost: building.cost,
                                     .build(cityIndex, building), detail: building.effect)
                    }
                    ForEach(wonders) { wonder in
                        actionButton(state, wonder.name, systemImage: wonder == .spaceship ? "airplane.departure" : "sparkles",
                                     cost: wonder.cost, .wonder(cityIndex, wonder), detail: wonder.effect, special: true)
                    }
                    if buildable.isEmpty && wonders.isEmpty {
                        Text("研究すると、建てられるものが増えます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func actionButton(_ state: CivState, _ title: String, systemImage: String, cost: Int?,
                              _ action: CivState.Action, detail: String? = nil, special: Bool = false) -> some View {
        let problem = session.isMyTurn ? state.problem(action) : "\(session.currentName)さんの番です"
        return Button {
            session.act(action)
            if case .foundCity = action { selected = nil }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.bold))
                Text([cost.map { "🔨\($0)" }, "行動 1", detail].compactMap { $0 }.joined(separator: "・"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(minWidth: 120, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(special ? Color.yellow.opacity(0.25) : Color.white.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .disabled(problem != nil)
        .opacity(problem == nil ? 1 : 0.6)
    }

    private func victory(_ state: CivState) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 12) {
                Text("🚀").font(.system(size: 64))
                Text("宇宙船が打ち上がりました！")
                    .font(.title2.weight(.heavy))
                Text("\(state.turn) ターンで、\(state.players.map(\.name).joined(separator: " と ")) の文明の勝ち")
                    .multilineTextAlignment(.center)
                Text("都市 \(state.cities.count)・人口 \(state.cities.map(\.pop).reduce(0, +))・技術 \(state.techs.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if session.mode != .nearbyJoin {
                    Button("新しい文明を始める") { session.restart() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                Button("閉じる") { dismiss() }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(30)
        }
    }
}

// MARK: - 研究

private struct CivTechSheet: View {
    @ObservedObject var session: CivSession
    let state: CivState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CivTech.allCases.filter { state.canResearch($0) }) { tech in
                        Button {
                            session.act(.research(tech))
                            dismiss()
                        } label: {
                            row(tech, status: state.research == tech ? "研究中 \(min(state.progress, tech.cost))/\(tech.cost)" : "📖\(tech.cost)")
                        }
                        .disabled(!session.isMyTurn)
                    }
                } header: {
                    Text("研究できる技術")
                } footer: {
                    Text(session.isMyTurn ? "選ぶのに行動は使いません。番を終えるたびに 📖 がたまります。" : "研究を選べるのは自分の番だけです。")
                }
                Section("まだ研究できない") {
                    ForEach(CivTech.allCases.filter { !state.techs.contains($0) && !state.canResearch($0) }) { tech in
                        row(tech, status: "必要：" + tech.requires.map(\.name).joined(separator: "・"))
                            .opacity(0.6)
                    }
                }
                Section("研究ずみ") {
                    ForEach(state.techs) { tech in
                        row(tech, status: "✓")
                    }
                }
            }
            .navigationTitle("技術")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func row(_ tech: CivTech, status: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tech.symbol)
                .frame(width: 28)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(tech.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(tech.unlocks).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - できごと

private struct CivLogSheet: View {
    let state: CivState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(state.log.enumerated().reversed()), id: \.offset) { _, entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text("T\(entry.turn)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.orange)
                            .frame(width: 34, alignment: .leading)
                        Text(entry.text).font(.callout)
                    }
                }
            }
            .navigationTitle("できごと")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
