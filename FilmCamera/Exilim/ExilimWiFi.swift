import Foundation
import NetworkExtension
import Security
import UIKit

/// カメラの Wi-Fi に、アプリから自分でつなぐ（iPhone の「設定」を開かなくていい）。
/// 名前（SSID）とパスワードは最初の 1 回だけ入れてもらい、名前は UserDefaults、パスワードはキーチェーンに置く。
/// joinOnce で入るので、アプリを閉じたり画面を閉じたりすると、いつもの Wi-Fi に戻る。
/// 使うには entitlements の Hotspot Configuration と、Apple Developer の App ID の「Hotspot」が必要
enum ExilimWiFi {
    private static let ssidKey = "exilimSSID"
    private static let service = "exilim-wifi"

    static var ssid: String? {
        let value = UserDefaults.standard.string(forKey: ssidKey)
        return value?.isEmpty == false ? value : nil
    }

    static var password: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(ssid: String, password: String) {
        UserDefaults.standard.set(ssid, forKey: ssidKey)
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData] = Data(password.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// カメラの Wi-Fi につなぐ（はじめての Wi-Fi のときは iOS が「接続」をたずねる）
    /// EX-FR100 の Wi-Fi の名前は「FR100-」＋英数字 6 桁、パスワードの初期値は 00000000（取扱説明書 68 ページ）。
    /// 名前を登録していなければ、この頭の文字と初期のパスワードで探してつなぐ
    static let defaultPrefix = "FR100-"
    static let defaultPassword = "00000000"

    static func join() async -> String? {
        let configuration: NEHotspotConfiguration
        if let ssid {
            let pass = password ?? ""
            configuration = pass.isEmpty
                ? NEHotspotConfiguration(ssid: ssid)
                : NEHotspotConfiguration(ssid: ssid, passphrase: pass, isWEP: false)
        } else {
            configuration = NEHotspotConfiguration(ssidPrefix: defaultPrefix, passphrase: defaultPassword, isWEP: false)
        }
        configuration.joinOnce = true
        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
            return nil
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain {
            switch NEHotspotConfigurationError(rawValue: error.code) {
            case .alreadyAssociated: return nil
            case .userDenied: return "Wi-Fi への接続が許可されませんでした"
            case .invalidWPAPassphrase, .invalidSSID: return "Wi-Fi の名前かパスワードが正しくありません"
            default: return "カメラの Wi-Fi につなげませんでした（カメラの Wi-Fi が出ているか確かめてください）"
            }
        } catch {
            return "カメラの Wi-Fi につなげませんでした"
        }
    }

    /// いま iPhone が入っている Wi-Fi の名前（アプリが NEHotspotConfiguration で入れた Wi-Fi なら読める）
    static func currentSSID() async -> String? {
        await NEHotspotNetwork.fetchCurrent()?.ssid
    }

    /// いまカメラの Wi-Fi に本当に入っているか（apply の「成功」は入り始めただけのことがある）。
    /// iOS が今の Wi-Fi を教えてくれないときは nil（分からないので、入り直したりしない）
    static func isOnCameraWiFi() async -> Bool? {
        guard let current = await currentSSID() else { return nil }
        if let ssid { return current == ssid }
        return current.hasPrefix(defaultPrefix)
    }

    /// カメラの Wi-Fi から離れて、いつもの Wi-Fi に戻る
    static func leave() {
        if let ssid { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid) }
        // 名前の頭で探してつないだときの設定も消す
        NEHotspotConfigurationManager.shared.getConfiguredSSIDs { list in
            for name in list where name.hasPrefix(defaultPrefix) {
                NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: name)
            }
        }
    }
}

/// カメラから受け取った写真の置き場。カメラの Wi-Fi はインターネットにつながらないので、
/// 受け取った写真はいったん端末に置き、いつもの回線に戻ってから共有アルバムに送る。
/// 送れなかった分は残しておき、次に開いたときにまた送る
enum ExilimPending {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExilimPending", isDirectory: true)
    }

    static func keep(_ data: Data, mode: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // ファイル名に機種名を入れておく（送るときのモード表示に使う）
        let safe = mode.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))_\(String(safe)).jpg"
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    static var count: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasSuffix(".jpg") }.count ?? 0
    }

    @MainActor private static var sending = false

    /// 置いてある写真を共有アルバムに送る（送れたものだけ消す）。送れた枚数を返す
    @MainActor
    @discardableResult
    static func flush() async -> Int {
        guard !sending else { return 0 }
        sending = true
        defer { sending = false }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var sent = 0
        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let mode = name.split(separator: "_", maxSplits: 1).last.map(String.init) ?? "EXILIM"
            let thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 800, height: 800))
            let ok = await AlbumStore.shared.upload(data: data, type: "public.jpeg", thumbnail: thumbnail, mode: mode,
                                                    location: LocationProvider.location(inImage: data))
            if ok {
                try? FileManager.default.removeItem(at: url)
                sent += 1
            } else {
                // 1 枚失敗したら、回線がまだ戻っていないとみて、残りは次の機会に
                break
            }
        }
        return sent
    }
}
