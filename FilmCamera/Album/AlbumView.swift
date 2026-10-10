import CloudKit
import CoreLocation
import MapKit
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
    /// アプリの最初の画面として使うとき、カメラを開く（右下の大きなボタン）
    var onOpenCamera: (() -> Void)? = nil
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
    /// 長押しで選び始めた直後の「指を離した」タップを無視する
    @State private var justLongPressed = false
    /// まとめて共有する画像（用意できたら共有の画面を出す）
    @State private var sharing: ShareItems?
    @State private var preparingShare = false

    struct ShareItems: Identifiable {
        let id = UUID()
        let images: [UIImage]
    }
    @State private var confirmingDelete = false
    @State private var importItems: [PhotosPickerItem] = []
    @State private var toast: String?
    /// 写真を地図で見る
    @State private var showingMap = false
    @State private var showingExilim = false

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
                    if showingMap { mapSection } else { photoSections }
                }
                .padding(.vertical, 12)
            }
            .background(Deck.body.ignoresSafeArea())
            .overlay {
                if store.isLoading && store.photos.isEmpty {
                    ProgressView("写真を読み込んでいます")
                        .font(.footnote)
                        .padding(.top, 260)
                }
            }
            .overlay(alignment: .bottom) { bottomBar }
            .refreshable { await store.refresh() }
            .navigationTitle(store.selected?.title ?? "共有アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Deck.body, for: .navigationBar)
            .toolbar { toolbar }
            .task {
                AlbumNotifier.shared.requestPermission()
                await store.refresh()
            }
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
            .sheet(item: $sharing) { items in
                ActivityView(items: items.images)
                    .presentationDetents([.medium, .large])
                    .onDisappear { endSelecting() }
            }
            .fullScreenCover(item: $viewing) { start in
                AlbumViewer(store: store, photos: start.photos, index: start.index)
            }
            .fullScreenCover(isPresented: $showingExilim) {
                ExilimView()
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
        VStack(alignment: .leading, spacing: 10) {
            // 右に今日の一枚を大きく出し、数字とメンバーは左に小さくまとめる
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    readout("PHOTOS", "\(store.photos.count)")
                    readout("MEMBERS", "\(max(store.members.count, 1))")
                    readout("LATEST", store.photos.first.map { $0.takenAt.formatted(.dateTime.month().day()) } ?? "—")
                    if !store.members.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(store.members.values.sorted(), id: \.self) { name in
                                    HStack(spacing: 4) {
                                        Text(String(name.prefix(1)))
                                            .font(.caption2.weight(.heavy))
                                            .foregroundStyle(Deck.display)
                                            .frame(width: 16, height: 16)
                                            .background(Circle().fill(Deck.orange))
                                        Text(name)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .lineLimit(1)
                                    }
                                    .padding(.leading, 2)
                                    .padding(.trailing, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(0.1)))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                todayPick
            }
            if store.selected?.isOwner == true { shareRow }
            Toggle(isOn: $store.autoAdd) {
                Label("撮った写真を自動で入れる", systemImage: "bolt.horizontal.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .tint(Deck.orange)
            .controlSize(.mini)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Deck.display))
        .padding(.horizontal, 16)
    }

    /// 今日の一枚：アルバムの写真から日ごとにひとつ選んで右上に出す（押すと開く）
    @ViewBuilder
    private var todayPick: some View {
        if let index = Self.todayIndex(photos: store.photos, album: store.selectedID) {
            let photo = store.photos[index]
            Button {
                viewing = ViewerStart(photos: store.photos, index: index)
            } label: {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("TODAY")
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(Deck.orange)
                    Group {
                        if let image = photo.thumbnail {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: 176, height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.orange, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("今日の一枚（\(photo.takenAt.formatted(.dateTime.year().month().day()))）")
        }
    }

    /// 今日の一枚に選ぶ写真の位置。その日に一度選んだら、写真が増えても同じ写真のまま（日付が変わると選び直す）
    private static func todayIndex(photos: [AlbumPhoto], album: String?) -> Int? {
        guard !photos.isEmpty else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let day = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        let key = "todayPick-\(album ?? "-")"
        let defaults = UserDefaults.standard
        if let saved = defaults.dictionary(forKey: key) as? [String: String], saved["day"] == day,
           let index = photos.firstIndex(where: { $0.id.recordName == saved["photo"] }) {
            return index
        }
        let index = Int.random(in: photos.indices)
        defaults.set(["day": day, "photo": photos[index].id.recordName], forKey: key)
        return index
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(Deck.orange)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
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
                        if selecting {
                            // その日の写真をまとめて選ぶ・外す
                            let ids = Set(section.photos.map(\.id))
                            let all = ids.isSubset(of: picked)
                            Button(all ? "選択を解除" : "すべて選択") {
                                if all { picked.subtract(ids) } else { picked.formUnion(ids) }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Deck.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(section.photos) { photo in
                            thumbnail(photo) {
                                if justLongPressed {
                                    justLongPressed = false
                                } else if selecting {
                                    toggle(photo)
                                } else if let index = all.firstIndex(of: photo) {
                                    viewing = ViewerStart(photos: all, index: index)
                                }
                            }
                            // 長押しで、その写真を選んだ状態で選択を始める
                            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                guard !selecting else { return }
                                justLongPressed = true
                                withAnimation(.snappy) {
                                    selecting = true
                                    picked = [photo.id]
                                }
                            })
                        }
                    }
                }
            }
        }
        .padding(.bottom, selecting ? 90 : (onOpenCamera == nil ? 20 : 110))
    }

    // MARK: - 地図

    /// 撮った場所が記録されている写真を、地図の上に並べる。押すとその写真を開く
    private var mapSection: some View {
        let located = visiblePhotos.filter { $0.location != nil }
        return VStack(alignment: .leading, spacing: 8) {
            if located.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(Deck.print.opacity(0.6))
                    Text("場所の付いた写真がまだありません")
                        .font(.headline)
                        .foregroundStyle(Deck.ink)
                    Text("カメラで撮ると、撮った場所が記録されます（位置情報を許可してください）。写真アプリから入れた写真も、場所の情報があれば地図に出ます。")
                        .font(.footnote)
                        .foregroundStyle(Deck.print)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                Text("\(located.count) 枚に場所が記録されています")
                    .font(.caption)
                    .foregroundStyle(Deck.print)
                Map(initialPosition: .automatic) {
                    ForEach(located) { photo in
                        Annotation("", coordinate: photo.location ?? CLLocationCoordinate2D()) {
                            Button {
                                if let index = located.firstIndex(of: photo) {
                                    viewing = ViewerStart(photos: located, index: index)
                                }
                            } label: {
                                mapPin(photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 480)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, onOpenCamera == nil ? 20 : 110)
    }

    private func mapPin(_ photo: AlbumPhoto) -> some View {
        Group {
            if let image = photo.thumbnail {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Deck.display
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
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
                .overlay(alignment: .bottomTrailing) {
                    // いいねとコメントの数
                    let likes = store.likes(of: photo).count
                    let comments = store.comments(of: photo).count
                    if likes + comments > 0 {
                        HStack(spacing: 5) {
                            if likes > 0 { Label("\(likes)", systemImage: "heart.fill") }
                            if comments > 0 { Label("\(comments)", systemImage: "bubble.right.fill") }
                        }
                        .labelStyle(CompactLabelStyle())
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.5)))
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
            if selecting {
                selectionBar
            } else if let onOpenCamera {
                cameraButton(onOpenCamera)
            }
        }
        .padding(.bottom, 8)
    }

    /// カメラを開く大きなボタン（カメラのシャッターと同じ形）
    private func cameraButton(_ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            ZStack {
                Circle()
                    .fill(Deck.key)
                    .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 3)
                Circle()
                    .fill(Deck.orange)
                    .padding(7)
                Image(systemName: "camera.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("カメラで撮る")
    }

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Text(picked.isEmpty ? "写真を選んでください" : "\(picked.count) 枚")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Spacer()
            // まとめて共有（LINE などに一度に送る）
            Button {
                shareSelected()
            } label: {
                Group {
                    if preparingShare {
                        ProgressView().tint(Deck.orange)
                    } else {
                        Image(systemName: "square.and.arrow.up").font(.headline)
                    }
                }
                .frame(width: 44, height: 40)
            }
            .disabled(picked.isEmpty || preparingShare)
            // ほかのアルバムにまとめて入れる
            let others = store.albums.filter { $0.id != store.selected?.id }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { album in
                        Button(album.title) {
                            let targets = pickedPhotos
                            Task {
                                for photo in targets { _ = await store.copy(photo, to: album) }
                                show("\(targets.count) 枚を「\(album.title)」に追加しています")
                                endSelecting()
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.headline)
                        .frame(width: 44, height: 40)
                }
                .disabled(picked.isEmpty)
            }
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

    /// 選んだ写真を大きい画像で用意して、共有の画面を出す
    private func shareSelected() {
        let targets = pickedPhotos
        preparingShare = true
        Task {
            var images: [UIImage] = []
            for photo in targets {
                if let image = await store.fullImage(of: photo) { images.append(image) }
            }
            preparingShare = false
            if !images.isEmpty { sharing = ShareItems(images: images) }
        }
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
        if selecting || onOpenCamera == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button(selecting ? "完了" : "閉じる") {
                    if selecting { endSelecting() } else { dismiss() }
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if selecting {
                // 表示中の写真をまとめて選ぶ・外す
                let ids = Set(visiblePhotos.map(\.id))
                Button(ids.isSubset(of: picked) && !ids.isEmpty ? "選択を解除" : "すべて選択") {
                    if ids.isSubset(of: picked) { picked = [] } else { picked = ids }
                }
                .fontWeight(.semibold)
            } else {
                Button("選択") {
                    withAnimation(.snappy) { selecting = true }
                }
                .fontWeight(.semibold)
                .disabled(store.photos.isEmpty || showingMap)
            }
            if !selecting {
                Button {
                    withAnimation { showingMap.toggle() }
                } label: {
                    Image(systemName: showingMap ? "square.grid.2x2" : "map")
                }
                .accessibilityLabel(showingMap ? "一覧で見る" : "地図で見る")
                Button {
                    showingExilim = true
                } label: {
                    Image(systemName: "camera.on.rectangle")
                }
                .accessibilityLabel("EXILIM とつなぐ")
                .disabled(store.selected == nil)
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
                    Label("写真をまとめて選ぶ", systemImage: "checkmark.circle")
                }
                .disabled(store.photos.isEmpty)
                Button {
                    showingExilim = true
                } label: {
                    Label("EXILIM（EX-FR100）とつなぐ", systemImage: "camera.on.rectangle")
                }
                .disabled(store.selected == nil)
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

/// 写真を大きく見る。左右にめくり、ピンチ・ダブルタップで拡大。
/// 下のパネルに、入れた人・日時・フィルタ、いいね・絵文字・コメント、共有・保存・このフィルタで撮る・ほかのアルバムへ・削除
private struct AlbumViewer: View {
    @ObservedObject var store: AlbumStore
    let photos: [AlbumPhoto]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var full: [CKRecord.ID: UIImage] = [:]
    @State private var chromeHidden = false
    @State private var confirmingDelete = false
    @State private var showingComments = false
    @State private var heartPop = 0
    @State private var toast: String?
    /// コメントを写真の上に流すか（ニコニコ動画のように）
    @AppStorage("albumDanmaku") private var danmakuOn = true
    /// 落書きする写真
    @State private var doodling: DoodleTarget?
    /// 撮った場所の名前（写真ごと）
    @State private var places: [CKRecord.ID: String] = [:]
    @State private var confirmingRevert = false

    struct DoodleTarget: Identifiable {
        let id = UUID()
        let photo: AlbumPhoto
        let image: UIImage
    }
    @State private var draft = ""

    /// すぐ押せる絵文字
    static let quickEmojis = ["😂", "😍", "🔥", "👏", "😮", "🥹"]

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

            HeartPop(trigger: heartPop)

            if danmakuOn, let photo = current {
                DanmakuLayer(source: store.reactions[photo.id.recordName] ?? [],
                             photoID: photo.id.recordName,
                             isMine: { store.isMine($0) })
                    .id(photo.id.recordName)   // 写真ごとに流し直す
            }

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
        .sensoryFeedback(.impact(weight: .medium), trigger: heartPop)
        .sheet(isPresented: $showingComments) {
            if let photo = current {
                CommentsSheet(store: store, photo: photo)
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(item: $doodling) { target in
            DoodleEditor(image: target.image) { result in
                // 写真に上書き（元の写真は取っておくので、あとで「元に戻す」ができる）
                full[target.photo.id] = result
                flash("落書きを保存しています")
                Task {
                    let ok = await store.applyDoodle(to: target.photo, image: result)
                    flash(ok ? "落書きを保存しました（元に戻せます）" : (store.status ?? "保存できませんでした"))
                    if !ok { full[target.photo.id] = target.image }
                }
            }
        }
        .task(id: index) { await lookUpPlace() }
        .confirmationDialog("落書きを消して、元の写真に戻しますか？", isPresented: $confirmingRevert,
                            titleVisibility: .visible) {
            Button("元に戻す", role: .destructive) {
                guard let photo = current else { return }
                Task {
                    let ok = await store.revertDoodle(photo)
                    if ok { full[photo.id] = await store.fullImage(of: photo) }
                    flash(ok ? "元の写真に戻しました" : (store.status ?? "元に戻せませんでした"))
                }
            }
        } message: {
            Text("アルバムのメンバー全員の画面で、元の写真に戻ります。")
        }
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
                Button {
                    danmakuOn.toggle()
                } label: {
                    Image(systemName: danmakuOn ? "text.bubble.fill" : "text.bubble")
                        .font(.headline)
                        .foregroundStyle(danmakuOn ? Deck.orange : Color.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .accessibilityLabel(danmakuOn ? "流れるコメントを消す" : "流れるコメントを出す")
                Text("\(index + 1) / \(photos.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            Spacer()
            if let photo = current { panel(photo) }
        }
        .transition(.opacity)
    }

    // MARK: 下のパネル

    private func panel(_ photo: AlbumPhoto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(photo)
            emojiBar(photo)
            commentField(photo)
            summary(photo)
            actions(photo)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func header(_ photo: AlbumPhoto) -> some View {
        let name = store.creatorName(of: photo)
        let detail = photo.takenAt.formatted(date: .abbreviated, time: .shortened)
            + (photo.mode.isEmpty ? "" : "・" + photo.mode)
        let liked = store.hasLiked(photo)
        let likeCount = store.likes(of: photo).count
        let commentCount = store.comments(of: photo).count
        return HStack(spacing: 10) {
            Text(String(name.prefix(1)))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Deck.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.65))
                if let place = places[photo.id] {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 4)
            Button {
                like(photo, fromDoubleTap: false)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(liked ? Color.pink : Color.white)
                        .symbolEffect(.bounce, value: liked)
                    if likeCount > 0 {
                        Text("\(likeCount)").font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }
            .accessibilityLabel(liked ? "いいねを外す" : "いいね")
            Button {
                showingComments = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right").font(.title2)
                    if commentCount > 0 {
                        Text("\(commentCount)").font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }
            .padding(.leading, 6)
            .accessibilityLabel("コメント")
        }
    }

    /// 絵文字の反応。押すと付く・外れる。付いている数も出す
    private func emojiBar(_ photo: AlbumPhoto) -> some View {
        let counts = Dictionary(uniqueKeysWithValues: store.emojis(of: photo).map { ($0.emoji, $0.people.count) })
        let extra = store.emojis(of: photo).map(\.emoji).filter { !Self.quickEmojis.contains($0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.quickEmojis + extra, id: \.self) { emoji in
                    let mine = store.hasReacted(photo, with: emoji)
                    Button {
                        Task { await store.toggleEmoji(emoji, on: photo) }
                    } label: {
                        HStack(spacing: 3) {
                            Text(emoji).font(.title3)
                            if let count = counts[emoji] {
                                Text("\(count)").font(.caption.weight(.bold).monospacedDigit())
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(mine ? Deck.orange.opacity(0.85) : .white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: mine)
                }
            }
        }
    }

    /// コメントを書いて、すぐ写真の上に流す
    private func commentField(_ photo: AlbumPhoto) -> some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("コメントを流す").foregroundStyle(.white.opacity(0.5)))
                .font(.subheadline)
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit { send(photo) }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.12)))
            Button {
                send(photo)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.headline)
                    .foregroundStyle(Deck.orange)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send(_ photo: AlbumPhoto) {
        let text = draft
        draft = ""
        danmakuOn = true
        Task { await store.comment(on: photo, text: text) }
    }

    /// だれがいいねしたか、いちばん新しいコメント
    @ViewBuilder
    private func summary(_ photo: AlbumPhoto) -> some View {
        let likes = store.likes(of: photo)
        let comments = store.comments(of: photo)
        if !likes.isEmpty || !comments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !likes.isEmpty {
                    let names = likes.map { store.name(of: $0.creator) }
                    Text(names.prefix(3).joined(separator: "、")
                         + (names.count > 3 ? " ほか\(names.count - 3)人" : "") + " がいいね")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let last = comments.last {
                    Button {
                        showingComments = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(store.name(of: last.creator) + "  ").font(.caption.weight(.bold))
                             + Text(last.text).font(.caption))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if comments.count > 1 {
                                Text("コメント \(comments.count) 件をすべて見る")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actions(_ photo: AlbumPhoto) -> some View {
        let canShootLikeThis = LookMode.allCases.contains { $0.title == photo.mode }
        let others = store.albums.filter { $0.id != store.selected?.id }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                if let image = full[photo.id] {
                    Button {
                        doodling = DoodleTarget(photo: photo, image: image)
                    } label: {
                        actionKey("落書き", systemImage: "pencil.tip.crop.circle")
                    }
                }
                if store.isEdited(photo.id) {
                    Button {
                        confirmingRevert = true
                    } label: {
                        actionKey("元に戻す", systemImage: "arrow.uturn.backward.circle")
                    }
                }
                if canShootLikeThis {
                    Button {
                        store.requestedMode = photo.mode
                        dismiss()
                    } label: {
                        actionKey("このフィルタで撮る", systemImage: "camera.filters")
                    }
                }
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { album in
                            Button(album.title) {
                                Task {
                                    let ok = await store.copy(photo, to: album)
                                    flash(ok ? "「\(album.title)」に追加しています" : "追加できませんでした")
                                }
                            }
                        }
                    } label: {
                        actionKey("ほかのアルバムへ", systemImage: "rectangle.stack.badge.plus")
                    }
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
    }

    private func actionKey(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.headline)
            Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 64)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.12)))
    }

    /// いいね。ダブルタップのときは付けるだけ（外さない）で、大きなハートを出す
    private func like(_ photo: AlbumPhoto, fromDoubleTap: Bool) {
        if fromDoubleTap {
            heartPop += 1
            guard !store.hasLiked(photo) else { return }
        } else if !store.hasLiked(photo) {
            heartPop += 1
        }
        Task { await store.toggleLike(photo) }
    }

    /// 開いている写真の撮った場所を、地名にする（例：東京都渋谷区）
    private func lookUpPlace() async {
        guard let photo = current, places[photo.id] == nil, let coordinate = photo.location else { return }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        let name = [mark.administrativeArea, mark.locality, mark.subLocality]
            .compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined()
        places[photo.id] = name.isEmpty ? (mark.name ?? "") : name
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

/// ニコニコ動画のように、写真の上をコメントと絵文字が右から左へ流れる。
/// 開いたときは今までの反応を順に流し、流れ終わったらまた最初から。新しい反応はすぐ流す
private struct DanmakuLayer: View {
    let source: [AlbumReaction]
    let photoID: String
    let isMine: (String?) -> Bool

    private struct Item {
        let text: String
        let big: Bool
        let mine: Bool
    }

    private struct Flight: Identifiable {
        let id = UUID()
        let item: Item
        let lane: Int
        let start: Date
        let width: CGFloat
    }

    @State private var flights: [Flight] = []
    @State private var queue: [Item] = []
    @State private var laneFree: [Int: Date] = [:]
    @State private var size: CGSize = .zero

    /// 画面の端から端まで流れる秒数
    private static let duration: Double = 5.5
    private static let laneHeight: CGFloat = 38
    private static let top: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, canvasSize in
                    for flight in flights {
                        let elapsed = timeline.date.timeIntervalSince(flight.start)
                        guard elapsed >= 0 else { continue }
                        let speed = (canvasSize.width + flight.width) / Self.duration
                        let x = canvasSize.width - CGFloat(elapsed) * speed
                        let y = Self.top + (CGFloat(flight.lane) + 0.5) * Self.laneHeight
                        draw(flight.item, at: CGPoint(x: x, y: y), in: &context)
                    }
                }
            }
            .onAppear { size = geo.size }
            .onChange(of: geo.size) { _, new in size = new }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task { await run() }
        .onChange(of: source) { old, new in
            // 新しく付いた反応は、すぐ流す
            let known = Set(old.map(\.id))
            for reaction in new where !known.contains(reaction.id) {
                launch(item(for: reaction))
            }
        }
    }

    private func draw(_ item: Item, at point: CGPoint, in context: inout GraphicsContext) {
        let font: Font = item.big ? .system(size: 32) : .title3.weight(.bold)
        let fill = context.resolve(Text(item.text).font(font).foregroundColor(.white))
        let edge = context.resolve(Text(item.text).font(font).foregroundColor(.black.opacity(0.75)))
        // 黒いふちどりで、どんな写真の上でも読めるように
        for (dx, dy) in [(-1.5, 0.0), (1.5, 0), (0, -1.5), (0, 1.5), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
            context.draw(edge, at: CGPoint(x: point.x + dx, y: point.y + dy), anchor: .leading)
        }
        context.draw(fill, at: point, anchor: .leading)
        if item.mine {
            // 自分のコメントは、ニコニコ動画のように枠で囲む
            let width = fill.measure(in: CGSize(width: 2000, height: 100)).width
            let box = CGRect(x: point.x - 6, y: point.y - Self.laneHeight / 2 + 3,
                             width: width + 12, height: Self.laneHeight - 6)
            context.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(Deck.orange), lineWidth: 1.5)
        }
    }

    private func item(for reaction: AlbumReaction) -> Item {
        switch reaction.kind {
        case .like: return Item(text: "❤️", big: true, mine: isMine(reaction.creator))
        case .emoji: return Item(text: reaction.text, big: true, mine: isMine(reaction.creator))
        case .comment: return Item(text: reaction.text, big: false, mine: isMine(reaction.creator))
        }
    }

    /// 今までの反応を少しずつ流し続ける（全部流れたら最初から）
    private func run() async {
        flights = []
        queue = []
        laneFree = [:]
        try? await Task.sleep(for: .milliseconds(400))
        while !Task.isCancelled {
            if queue.isEmpty {
                queue = source.map(item(for:))
                if queue.isEmpty {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                if !flights.isEmpty {
                    // ひと回りしたら少し間をあける
                    try? await Task.sleep(for: .seconds(Self.duration))
                }
            }
            launch(queue.removeFirst())
            flights.removeAll { Date().timeIntervalSince($0.start) > Self.duration + 0.5 }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 450...900)))
        }
    }

    /// 空いている段を選んで流す（空きがなければ、いちばん早く空く段）
    private func launch(_ item: Item) {
        guard size.width > 0 else { return }
        let lanes = max(3, Int((size.height * 0.5) / Self.laneHeight))
        let now = Date()
        let lane = (0..<lanes).first { (laneFree[$0] ?? .distantPast) <= now }
            ?? (0..<lanes).min { (laneFree[$0] ?? now) < (laneFree[$1] ?? now) } ?? 0
        let width = CGFloat(item.text.count) * (item.big ? 36 : 21)
        let speed = (size.width + width) / Self.duration
        // 前のコメントの後ろが、少し離れるまで同じ段は使わない
        laneFree[lane] = now.addingTimeInterval(Double((width + 50) / speed))
        flights.append(Flight(item: item, lane: lane, start: now, width: width))
    }
}

/// いいねしたときに真ん中に出る大きなハート
private struct HeartPop: View {
    let trigger: Int
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 110))
            .foregroundStyle(.pink)
            .shadow(color: .black.opacity(0.3), radius: 10)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                scale = 0.3
                opacity = 1
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { scale = 1 }
                withAnimation(.easeIn(duration: 0.3).delay(0.55)) {
                    opacity = 0
                    scale = 1.3
                }
            }
    }
}

/// コメントの一覧と入力
private struct CommentsSheet: View {
    @ObservedObject var store: AlbumStore
    let photo: AlbumPhoto
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let comments = store.comments(of: photo)
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty {
                    ContentUnavailableView("まだコメントはありません", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("最初のコメントを書いてみましょう"))
                } else {
                    List {
                        ForEach(comments) { comment in
                            row(comment)
                                .swipeActions {
                                    if store.canDelete(comment) {
                                        Button("削除", role: .destructive) {
                                            Task { await store.removeReaction(comment) }
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
                if let status = store.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                HStack(spacing: 10) {
                    TextField("コメントを書く", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                    Button {
                        let text = draft
                        draft = ""
                        Task { await store.comment(on: photo, text: text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(Deck.orange)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
            }
            .navigationTitle("コメント")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ comment: AlbumReaction) -> some View {
        let name = store.name(of: comment.creator)
        return HStack(alignment: .top, spacing: 10) {
            Text(String(name.prefix(1)))
                .font(.caption.weight(.heavy))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(store.isMine(comment.creator) ? Deck.orange : Color(.systemGray4)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.subheadline.weight(.bold))
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(comment.text).font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }
}

/// ピンチで拡大できる画像。拡大中だけドラッグで動かせる（それ以外は左右にめくれる）。
/// ダブルタップは、拡大中なら元に戻し、そうでなければタップした所を中心に 2.5 倍に拡大
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
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > 1 {
                        reset()
                    } else {
                        // タップした所が画面の同じ位置に残るように、拡大してずらす
                        let zoom: CGFloat = 2.5
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        scale = zoom
                        lastScale = zoom
                        offset = CGSize(width: (center.x - location.x) * (zoom - 1),
                                        height: (center.y - location.y) * (zoom - 1))
                        lastOffset = offset
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

/// アイコンと数字を詰めて並べる
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

/// iOS の共有の画面（複数の写真をまとめて LINE などに送る）
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
