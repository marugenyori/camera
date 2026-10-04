import CloudKit
import PhotosUI
import SwiftUI

/// アルバムの画面の色（カメラの画面と同じ、teenage engineering 風の灰色の筐体とオレンジ）
private enum Deck {
    static let body = Color(red: 0.867, green: 0.863, blue: 0.843)
    static let key = Color(red: 0.961, green: 0.957, blue: 0.941)
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let print = Color(red: 0.463, green: 0.459, blue: 0.435)
    static let display = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let orange = Color.accentColor
}

/// 共有アルバムの画面：アルバムの切り替え、メンバーと招待、入れた人で絞り込み、日付ごとの写真、まとめて保存・削除
struct AlbumView: View {
    @ObservedObject var store: AlbumStore
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: ViewerStart?
    @State private var showingNewAlbum = false
    @State private var showingRename = false
    @State private var nameField = ""
    @State private var confirmingRemove = false
    /// 入れた人で絞り込む（nil = みんな、"me" = 自分）
    @State private var personFilter: String?
    @State private var selecting = false
    @State private var picked: Set<CKRecord.ID> = []
    @State private var confirmingDelete = false
    @State private var importItems: [PhotosPickerItem] = []
    @State private var toast: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    struct ViewerStart: Identifiable {
        let id = UUID()
        let photos: [AlbumPhoto]
        let index: Int
    }

    private struct Person: Identifiable {
        let id: String
        let name: String
    }

    private struct DaySection: Identifiable {
        let id: Date
        let photos: [AlbumPhoto]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    albumStrip
                    infoPanel
                    if !people.isEmpty { personChips }
                    messages
                    photoSections
                }
                .padding(.vertical, 12)
            }
            .background(Deck.body.ignoresSafeArea())
            .overlay {
                if store.isLoading && store.photos.isEmpty { ProgressView() }
            }
            .overlay(alignment: .bottom) { bottomBar }
            .refreshable { await store.refresh() }
            .navigationTitle(store.selected?.title ?? "共有アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Deck.body, for: .navigationBar)
            .toolbar { toolbar }
            .task { await store.refresh() }
            .onChange(of: store.selectedID) { _, _ in
                personFilter = nil
                endSelecting()
            }
            .onChange(of: importItems) { _, items in
                guard !items.isEmpty else { return }
                importItems = []
                Task {
                    var files: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { files.append(data) }
                    }
                    store.importPhotos(files)
                    show("\(files.count) 枚を追加しています")
                }
            }
            .alert("新しいアルバム", isPresented: $showingNewAlbum) {
                TextField("名前（例：家族、サークル）", text: $nameField)
                Button("作る") {
                    let name = nameField
                    Task { await store.createAlbum(named: name) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("グループごとにアルバムを作ると、それぞれ別の友だちを招待できます。")
            }
            .alert("アルバムの名前", isPresented: $showingRename) {
                TextField("名前", text: $nameField)
                Button("変更") {
                    let name = nameField
                    Task { await store.renameSelectedAlbum(to: name) }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .confirmationDialog(store.selected?.isOwner == true
                                ? "このアルバムを削除しますか？" : "このアルバムから抜けますか？",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button(store.selected?.isOwner == true ? "削除する" : "抜ける", role: .destructive) {
                    Task { await store.removeSelectedAlbum() }
                }
            } message: {
                Text(store.selected?.isOwner == true
                     ? "アルバムの写真はすべて消え、招待した人も見られなくなります。"
                     : "このアルバムが一覧から消えます。もう一度入るには招待のリンクが必要です。")
            }
            .confirmationDialog("\(pickedPhotos.count) 枚を削除しますか？", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    let targets = pickedPhotos
                    Task {
                        await store.delete(targets)
                        endSelecting()
                    }
                }
            } message: {
                Text("アルバムのメンバー全員から見えなくなります。")
            }
            .fullScreenCover(item: $viewing) { start in
                AlbumViewer(store: store, photos: start.photos, index: start.index)
            }
        }
    }

    // MARK: - アルバムの切り替え

    private var albumStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.albums) { album in
                    albumCard(album)
                }
                Button {
                    nameField = ""
                    showingNewAlbum = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                        Text("新しい\nアルバム")
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Deck.print)
                    .frame(width: 92, height: 124)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Deck.print.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func albumCard(_ album: AlbumRef) -> some View {
        let isSelected = album.id == store.selected?.id
        return Button {
            store.selectedID = album.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Deck.display
                    if let cover = store.covers[album.id] {
                        Image(uiImage: cover).resizable().scaledToFill()
                    } else {
                        Image(systemName: album.isOwner ? "photo.stack" : "person.2")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(album.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(Deck.ink)
                HStack(spacing: 4) {
                    Circle()
                        .fill(isSelected ? Deck.orange : Deck.print.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(store.counts[album.id].map { "\($0)枚" } ?? (album.isOwner ? "自分" : "友だち"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Deck.print)
                }
            }
            .padding(6)
            .frame(width: 92, height: 124, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Deck.key)
                .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: isSelected ? 0 : 2))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Deck.orange, lineWidth: isSelected ? 2.5 : 0))
            .offset(y: isSelected ? 2 : 0)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isSelected)
    }

    // MARK: - アルバムの情報（黒い表示窓）

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                readout("PHOTOS", "\(store.photos.count)")
                readout("MEMBERS", "\(max(store.members.count, 1))")
                readout("LATEST", store.photos.first.map { $0.takenAt.formatted(.dateTime.month().day()) } ?? "—")
                Spacer()
            }
            if !store.members.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.members.values.sorted(), id: \.self) { name in
                            HStack(spacing: 5) {
                                Text(String(name.prefix(1)))
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Deck.display)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Deck.orange))
                                Text(name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .padding(.leading, 3)
                            .padding(.trailing, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.1)))
                        }
                    }
                }
            }
            if store.selected?.isOwner == true { shareRow }
            Divider().overlay(.white.opacity(0.15))
            Toggle(isOn: $store.autoAdd) {
                Label("撮った写真を自動でこのアルバムに入れる", systemImage: "bolt.horizontal.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .tint(Deck.orange)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Deck.display))
        .padding(.horizontal, 16)
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(Deck.orange)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.trailing, 18)
    }

    /// 招待の状態と、招待を作る・送るボタン
    private var shareRow: some View {
        HStack(spacing: 10) {
            Text(store.share == nil
                 ? "まだ誰とも共有していません"
                 : store.participantNames.isEmpty ? "招待の準備ができています。リンクを送ってください" : "共有中")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            if let url = store.share?.url {
                ShareLink(item: url,
                          subject: Text("フィルムカメラの共有アルバム"),
                          message: Text("フィルムカメラの共有アルバムに招待します。リンクを開くと参加できます。")) {
                    pill("招待を送る", systemImage: "paperplane.fill")
                }
            } else if store.isPreparingShare {
                ProgressView().tint(.white)
            } else {
                Button {
                    Task { await store.makeShare() }
                } label: {
                    pill("友だちを招待", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
    }

    private func pill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Deck.orange))
    }

    // MARK: - 入れた人で絞り込み

    private func personKey(_ photo: AlbumPhoto) -> String {
        store.isMine(photo) ? "me" : (photo.creator ?? "?")
    }

    /// 写真を入れた人（写真にいる人だけ。2 人以上いるときだけ絞り込みを出す）
    private var people: [Person] {
        var seen: [String: String] = [:]
        for photo in store.photos {
            seen[personKey(photo)] = store.creatorName(of: photo)
        }
        guard seen.count > 1 else { return [] }
        return seen.map { Person(id: $0.key, name: $0.value) }
            .sorted { a, b in a.id == "me" || (b.id != "me" && a.name < b.name) }
    }

    private var personChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("みんな", isOn: personFilter == nil) { personFilter = nil }
                ForEach(people) { person in
                    chip(person.name, isOn: personFilter == person.id) { personFilter = person.id }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(isOn ? Color.white : Deck.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? Deck.orange : Deck.key)
                    .shadow(color: .black.opacity(isOn ? 0 : 0.15), radius: 0, x: 0, y: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 写真

    private var visiblePhotos: [AlbumPhoto] {
        guard let personFilter else { return store.photos }
        return store.photos.filter { personKey($0) == personFilter }
    }

    /// 撮った日ごとにまとめる（新しい日が上）
    private var sections: [DaySection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visiblePhotos) { calendar.startOfDay(for: $0.takenAt) }
        return groups.map { DaySection(id: $0.key, photos: $0.value) }.sorted { $0.id > $1.id }
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = store.status {
                Label(status, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Deck.ink)
            }
            if store.uploading > 0 {
                Label("\(store.uploading) 枚を送っています", systemImage: "icloud.and.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(Deck.print)
            }
            if store.photos.isEmpty && !store.isLoading && store.status == nil {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(Deck.print.opacity(0.6))
                    Text("まだ写真がありません")
                        .font(.headline)
                        .foregroundStyle(Deck.ink)
                    Text("撮った写真を開いて「共有アルバムに追加」、上の自動の設定、または右上の ＋ から写真アプリの写真を入れられます。")
                        .font(.footnote)
                        .foregroundStyle(Deck.print)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(.horizontal, 16)
    }

    private var photoSections: some View {
        let all = visiblePhotos
        return LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.id.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Deck.ink)
                        Text("\(section.photos.count)枚")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Deck.print)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(section.photos) { photo in
                            thumbnail(photo) {
                                if selecting {
                                    toggle(photo)
                                } else if let index = all.firstIndex(of: photo) {
                                    viewing = ViewerStart(photos: all, index: index)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, selecting ? 90 : 20)
    }

    private func thumbnail(_ photo: AlbumPhoto, action: @escaping () -> Void) -> some View {
        let isPicked = picked.contains(photo.id)
        let mine = store.isMine(photo)
        return Button(action: action) {
            Color.black.opacity(0.08)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = photo.thumbnail {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    // 共有しているアルバムでは、入れた人の頭文字を小さく出す
                    if !store.members.isEmpty && personFilter == nil {
                        Text(String(store.creatorName(of: photo).prefix(1)))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(mine ? Deck.orange : Deck.display.opacity(0.7)))
                            .padding(4)
                    }
                }
                .overlay {
                    if selecting && isPicked { Color.white.opacity(0.35) }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isPicked ? Deck.orange : Color.white)
                            .shadow(radius: 2)
                            .padding(5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 選んでまとめて

    private var pickedPhotos: [AlbumPhoto] { store.photos.filter { picked.contains($0.id) } }

    private func toggle(_ photo: AlbumPhoto) {
        if picked.contains(photo.id) { picked.remove(photo.id) } else { picked.insert(photo.id) }
    }

    private func endSelecting() {
        selecting = false
        picked = []
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Deck.display))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if selecting { selectionBar }
        }
        .padding(.bottom, 8)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text(picked.isEmpty ? "写真を選んでください" : "\(picked.count) 枚を選択中")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                let targets = pickedPhotos
                Task {
                    let saved = await store.saveToLibrary(targets)
                    show("\(saved) 枚を写真アプリに保存しました")
                    endSelecting()
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.headline)
                    .frame(width: 44, height: 40)
            }
            .disabled(picked.isEmpty)
            if pickedPhotos.contains(where: { store.canDelete($0) }) {
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 40)
                }
            }
        }
        .foregroundStyle(Deck.orange)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Deck.display))
        .padding(.horizontal, 16)
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    // MARK: - 上のボタン

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(selecting ? "完了" : "閉じる") {
                if selecting { endSelecting() } else { dismiss() }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if !selecting {
                PhotosPicker(selection: $importItems, maxSelectionCount: 30, matching: .images) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("写真アプリから追加")
                .disabled(store.selected == nil)
            }
            Menu {
                Button {
                    selecting = true
                } label: {
                    Label("写真を選ぶ（保存・削除）", systemImage: "checkmark.circle")
                }
                .disabled(store.photos.isEmpty)
                Button {
                    nameField = ""
                    showingNewAlbum = true
                } label: {
                    Label("新しいアルバム（グループ）", systemImage: "plus.rectangle.on.rectangle")
                }
                if let album = store.selected, album.isOwner {
                    Button {
                        nameField = album.title
                        showingRename = true
                    } label: {
                        Label("名前を変える", systemImage: "pencil")
                    }
                }
                if let album = store.selected,
                   !album.isOwner || album.zoneID.zoneName != AlbumStore.ownZoneID.zoneName {
                    Button(role: .destructive) {
                        confirmingRemove = true
                    } label: {
                        Label(album.isOwner ? "このアルバムを削除" : "このアルバムから抜ける",
                              systemImage: album.isOwner ? "trash" : "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("アルバムの操作")
        }
    }
}

// MARK: - 1 枚ずつ大きく見る

/// 写真を大きく見る。左右にめくり、ピンチやダブルタップで拡大。入れた人・モード・日時を表示し、共有・保存・削除ができる
private struct AlbumViewer: View {
    @ObservedObject var store: AlbumStore
    let photos: [AlbumPhoto]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var full: [CKRecord.ID: UIImage] = [:]
    @State private var chromeHidden = false
    @State private var confirmingDelete = false
    @State private var toast: String?

    init(store: AlbumStore, photos: [AlbumPhoto], index: Int) {
        self.store = store
        self.photos = photos
        _index = State(initialValue: index)
    }

    private var current: AlbumPhoto? { photos.indices.contains(index) ? photos[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(photos.indices, id: \.self) { offset in
                    let photo = photos[offset]
                    ZoomableImage(image: full[photo.id] ?? photo.thumbnail)
                        .overlay {
                            if full[photo.id] == nil { ProgressView().tint(.white) }
                        }
                        .tag(offset)
                        .task { await load(photo) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } }

            if !chromeHidden { chrome }
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white))
                    .transition(.opacity)
            }
        }
        .statusBarHidden(chromeHidden)
        .confirmationDialog("この写真を削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                guard let photo = current else { return }
                Task {
                    await store.delete([photo])
                    dismiss()
                }
            }
        } message: {
            Text("アルバムのメンバー全員から見えなくなります。")
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                Spacer()
                Text("\(index + 1) / \(photos.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            Spacer()
            if let photo = current { infoCard(photo) }
        }
        .transition(.opacity)
    }

    private func infoCard(_ photo: AlbumPhoto) -> some View {
        let name = store.creatorName(of: photo)
        let detail = photo.takenAt.formatted(date: .abbreviated, time: .shortened)
            + (photo.mode.isEmpty ? "" : "・" + photo.mode)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(String(name.prefix(1)))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Deck.orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
            }
            HStack(spacing: 10) {
                if let image = full[photo.id] {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("写真", image: Image(uiImage: image))) {
                        actionKey("共有", systemImage: "square.and.arrow.up")
                    }
                } else {
                    actionKey("共有", systemImage: "square.and.arrow.up").opacity(0.4)
                }
                Button {
                    Task {
                        let saved = await store.saveToLibrary([photo])
                        flash(saved > 0 ? "写真アプリに保存しました" : (store.status ?? "保存できませんでした"))
                    }
                } label: {
                    actionKey("保存", systemImage: "square.and.arrow.down")
                }
                if store.canDelete(photo) {
                    Button {
                        confirmingDelete = true
                    } label: {
                        actionKey("削除", systemImage: "trash")
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.55)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func actionKey(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.headline)
            Text(title).font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.12)))
    }

    private func load(_ photo: AlbumPhoto) async {
        guard full[photo.id] == nil, let image = await store.fullImage(of: photo) else { return }
        full[photo.id] = image
    }

    private func flash(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

/// ピンチとダブルタップで拡大できる画像。拡大中だけドラッグで動かせる（それ以外は左右にめくれる）
private struct ZoomableImage: View {
    let image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(5, max(1, lastScale * value.magnification)) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.01 { reset() }
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: scale > 1 ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
