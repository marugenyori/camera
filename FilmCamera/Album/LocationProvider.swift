import CoreLocation
import ImageIO

/// 撮った場所を記録するための位置情報。カメラを開いている間だけ受け取る（電池のため）。
/// 共有アルバムの地図と、写真の「どこで撮ったか」に使う
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var latest: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// カメラを開いたとき（初回は許可をたずねる）
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// 10 分以内に受け取った場所（古すぎるものは使わない）
    var recent: CLLocation? {
        guard let latest, abs(latest.timestamp.timeIntervalSinceNow) < 600 else { return nil }
        return latest
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latest = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// 写真のファイルに入っている GPS の情報（写真アプリから入れた写真など）
    static func location(inImage data: Data) -> CLLocation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              var longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { longitude = -longitude }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}
