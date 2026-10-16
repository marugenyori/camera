import SceneKit
import SwiftUI

/// 「まちかどマート」の 3D（SceneKit）。お店の床・壁・棚・人・お金を立体で作り、毎コマ MartGame の様子に合わせて動かす。
/// 座標：床の x → SceneKit の x、床の y → SceneKit の z、高さは y。カメラは右手前ななめ上から（平行投影）店員を追う。
/// 光は真上寄りの太陽（やわらかい影）と、全体を明るくする環境光
@MainActor
final class MartScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let sun = SCNNode()
    private let world = SCNNode()
    private let shell = SCNNode()
    private var shellDepth: CGFloat = 0
    private var target = SCNVector3(9, 0, 13.5)

    private var shelfNodes: [Int: SCNNode] = [:]
    private var shelfItems: [Int: [SCNNode]] = [:]
    private var supplyNodes: [Int: SCNNode] = [:]
    private var ghostNodes: [Int: SCNNode] = [:]
    private var playerNodes: [CharacterNode] = []
    private var customerNodes: [UUID: CharacterNode] = [:]
    private var helperNodes: [CharacterNode] = []
    private var cashierNode: CharacterNode?
    private var cashBills: [SCNNode] = []
    private var padNodes: [Int: PadNode] = [:]
    private var arrow = SCNNode()
    private var maxLabel = SCNNode()
    private var servingRing = SCNNode()
    private var standBasketNodes: [SCNNode] = []
    private var lastCarry: [[MartProduct]] = []
    private var returnBasketNodes: [SCNNode] = []

    /// 画面に映す広さ（大きいほど引く。2 本指で変えられる）
    var zoom: CGFloat = CGFloat(UserDefaults.standard.object(forKey: "martZoom") as? Double ?? 7.2) {
        didSet {
            zoom = min(max(zoom, 4.5), 11)
            cameraNode.camera?.orthographicScale = Double(zoom)
            sun.light?.orthographicScale = zoom * 2.1
        }
    }

    func saveZoom() { UserDefaults.standard.set(Double(zoom), forKey: "martZoom") }

    private var leavingCustomers: Set<UUID> = []
    private var doorPanels: [(SCNNode, Float)] = []
    private var doorOpen: Float = 0
    private var dustTimer: Double = 0
    /// 飛んでいる途中の商品（着くまで棚に出さない）
    private var flying: Set<ObjectIdentifier> = []
    private var lastStock: [Int] = []
    private var lastMoney = 0
    private var lastCash = 0
    private var lastDone: Set<Int> = []
    private var billTimer: Double = 0
    private var built = false

    init() {
        scene.background.contents = UIColor(red: 0.7, green: 0.83, blue: 0.62, alpha: 1)
        scene.rootNode.addChildNode(world)
        world.addChildNode(shell)
        buildShell(depth: MartGame.floor.height)
        setupCamera()
        setupLights()
        buildWorld()
    }

    // MARK: - 材料

    private static var materials: [String: SCNMaterial] = [:]

    static func material(_ color: UIColor, emission: Bool = false) -> SCNMaterial {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = String(format: "%.3f-%.3f-%.3f-%.2f-%d", r, g, b, a, emission ? 1 : 0)
        if let cached = materials[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = color
        if emission { material.emission.contents = color }
        if a < 1 {
            material.transparency = a
            material.blendMode = .alpha
        }
        materials[key] = material
        return material
    }

    static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ color: UIColor, chamfer: CGFloat = 0.03) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: l, chamferRadius: min(chamfer, min(w, h, l) / 2))
        geometry.materials = [material(color)]
        return SCNNode(geometry: geometry)
    }

    static func cylinder(_ r: CGFloat, _ h: CGFloat, _ color: UIColor) -> SCNNode {
        let geometry = SCNCylinder(radius: r, height: h)
        geometry.radialSegmentCount = 20
        geometry.materials = [material(color)]
        return SCNNode(geometry: geometry)
    }

    static func sphere(_ r: CGFloat, _ color: UIColor) -> SCNNode {
        let geometry = SCNSphere(radius: r)
        geometry.segmentCount = 20
        geometry.materials = [material(color)]
        return SCNNode(geometry: geometry)
    }

    static func capsule(_ r: CGFloat, _ h: CGFloat, _ color: UIColor) -> SCNNode {
        let geometry = SCNCapsule(capRadius: r, height: h)
        geometry.radialSegmentCount = 18
        geometry.materials = [material(color)]
        return SCNNode(geometry: geometry)
    }

    static func at(_ node: SCNNode, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNNode {
        node.position = SCNVector3(Float(x), Float(y), Float(z))
        return node
    }

    /// 文字や絵を貼った板（いつもカメラを向く）
    static func billboard(_ image: UIImage, width: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: width * image.size.height / max(image.size.width, 1))
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.constraints = [SCNBillboardConstraint()]
        node.renderingOrder = 100
        return node
    }

    /// 床に寝かせた板
    static func decal(_ image: UIImage, width: CGFloat, length: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: length)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 5
        return node
    }

    // MARK: - 絵（文字・ふきだし）

    private static var imageCache: [String: UIImage] = [:]

    static func label(_ text: String, size: CGFloat = 44, color: UIColor = .white, background: UIColor? = nil) -> UIImage {
        let key = "label|\(text)|\(size)|\(color)|\(background?.description ?? "")"
        if let cached = imageCache[key] { return cached }
        let font = UIFont.systemFont(ofSize: size, weight: .heavy).rounded()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color,
            .strokeColor: UIColor(white: 0, alpha: background == nil ? 0.35 : 0), .strokeWidth: background == nil ? -3 : 0,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pad: CGFloat = background == nil ? 6 : size * 0.45
        let canvas = CGSize(width: ceil(textSize.width + pad * 2), height: ceil(textSize.height + pad * 1.2))
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            if let background {
                background.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: canvas.height / 2).fill()
            }
            (text as NSString).draw(at: CGPoint(x: pad, y: (canvas.height - textSize.height) / 2), withAttributes: attributes)
        }
        imageCache[key] = image
        return image
    }

    /// お客さんのふきだし（ほしい商品と数、またはお会計）
    static func bubble(product: MartProduct?, count: Int) -> UIImage {
        let key = "bubble|\(product?.rawValue ?? -1)|\(count)"
        if let cached = imageCache[key] { return cached }
        let size = CGSize(width: 150, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(x: 4, y: 4, width: 142, height: 92)
            UIColor(white: 0, alpha: 0.15).setFill()
            UIBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: 4), cornerRadius: 28).fill()
            UIColor.white.setFill()
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: 28)
            shape.move(to: CGPoint(x: 62, y: 95))
            shape.addLine(to: CGPoint(x: 75, y: 116))
            shape.addLine(to: CGPoint(x: 88, y: 95))
            shape.fill()
            if let product {
                // 商品のアイコン
                (product.icon as NSString).draw(at: CGPoint(x: 16, y: 18), withAttributes: [.font: UIFont.systemFont(ofSize: 52)])
                let text = "\(count)" as NSString
                let font = UIFont.systemFont(ofSize: 50, weight: .black).rounded()
                text.draw(at: CGPoint(x: 86, y: 18), withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.15, alpha: 1)])
            } else {
                let text = "💵" as NSString
                text.draw(at: CGPoint(x: 42, y: 14), withAttributes: [.font: UIFont.systemFont(ofSize: 56)])
            }
            _ = context
        }
        imageCache[key] = image
        return image
    }

    /// 持っている商品の札（「● ジュース ×3　● おかし ×2」）
    static func carryImage(_ carry: [MartProduct]) -> UIImage {
        var counts: [(MartProduct, Int)] = []
        for product in carry {
            if let index = counts.firstIndex(where: { $0.0 == product }) { counts[index].1 += 1 } else { counts.append((product, 1)) }
        }
        let key = "carry|" + counts.map { "\($0.0.rawValue)x\($0.1)" }.joined(separator: ",")
        if let cached = imageCache[key] { return cached }
        let font = UIFont.systemFont(ofSize: 34, weight: .bold).rounded()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.15, alpha: 1)]
        let parts = counts.map { "\($0.0.icon)×\($0.1)" }
        let widths = parts.map { ($0 as NSString).size(withAttributes: attributes).width }
        let height: CGFloat = 60
        let width = widths.reduce(0, +) + CGFloat(parts.count) * 8 + CGFloat(max(parts.count - 1, 0)) * 14 + 20
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height + 8)).image { _ in
            UIColor(white: 0, alpha: 0.12).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 6, width: width, height: height), cornerRadius: height / 2).fill()
            UIColor(white: 1, alpha: 0.97).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: height / 2).fill()
            var x: CGFloat = 16
            for (index, part) in parts.enumerated() {
                (part as NSString).draw(at: CGPoint(x: x, y: height / 2 - font.lineHeight / 2), withAttributes: attributes)
                x += widths[index] + 22
            }
        }
        imageCache[key] = image
        return image
    }

    /// 解放マーク（点線の枠・絵・名前・残りの値段）
    static func padImage(_ step: MartStep, remaining: Int, pixels: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: pixels).image { _ in
            let rect = CGRect(origin: .zero, size: pixels).insetBy(dx: 10, dy: 10)
            UIColor(white: 1, alpha: 0.28).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 26).fill()
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 26)
            border.lineWidth = 9
            border.setLineDash([26, 16], count: 2, phase: 0)
            UIColor.white.setStroke()
            border.stroke()
            // 文字は出さず、アイコンだけ（棚は商品の絵文字）
            let side = min(pixels.width, pixels.height)
            if case .shelf(let k) = step.kind, let product = MartProduct(rawValue: k) {
                let icon = product.icon as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: side * 0.3)]
                let iconSize = icon.size(withAttributes: attributes)
                icon.draw(at: CGPoint(x: pixels.width / 2 - iconSize.width / 2, y: pixels.height * 0.42 - iconSize.height / 2),
                          withAttributes: attributes)
            } else {
                let config = UIImage.SymbolConfiguration(pointSize: side * 0.26, weight: .bold)
                if let symbol = UIImage(systemName: step.symbol, withConfiguration: config)?
                    .withTintColor(UIColor(white: 1, alpha: 0.95), renderingMode: .alwaysOriginal) {
                    symbol.draw(at: CGPoint(x: pixels.width / 2 - symbol.size.width / 2, y: pixels.height * 0.42 - symbol.size.height / 2))
                }
            }
            let price = MartYen.text(remaining) as NSString
            let priceAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(pixels.width, pixels.height) * 0.16, weight: .black).rounded(),
                .foregroundColor: UIColor(red: 0.2, green: 0.55, blue: 0.2, alpha: 1),
            ]
            let priceSize = price.size(withAttributes: priceAttributes)
            let chip = CGRect(x: pixels.width / 2 - priceSize.width / 2 - 14, y: pixels.height * 0.66,
                              width: priceSize.width + 28, height: priceSize.height + 6)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: chip, cornerRadius: chip.height / 2).fill()
            price.draw(at: CGPoint(x: chip.minX + 14, y: chip.minY + 3), withAttributes: priceAttributes)
        }
    }

    // MARK: - カメラと光

    private func setupCamera() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(zoom)
        // 物のすき間や足もとに、うすい陰（空間の奥行きが出る）
        camera.screenSpaceAmbientOcclusionIntensity = 0.55
        camera.screenSpaceAmbientOcclusionRadius = 0.45
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.25
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 4.2, Float.pi / 4, 0)
        scene.rootNode.addChildNode(cameraNode)
        moveCamera(to: target, immediately: true)
    }

    private func moveCamera(to point: SCNVector3, immediately: Bool = false) {
        let offset = SCNVector3(9, 12.5, 9)
        cameraNode.position = SCNVector3(point.x + offset.x, point.y + offset.y, point.z + offset.z)
        sun.position = SCNVector3(point.x + 3, 12, point.z + 6)
    }

    private func setupLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 620
        ambient.light?.color = UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let light = SCNLight()
        light.type = .directional
        light.intensity = 780
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowColor = UIColor(white: 0, alpha: 0.28)
        light.shadowRadius = 3
        light.shadowSampleCount = 8
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.orthographicScale = zoom * 2.1
        light.zNear = 1
        light.zFar = 40
        sun.light = light
        sun.eulerAngles = SCNVector3(-Float.pi / 2.6, Float.pi / 7, 0)
        scene.rootNode.addChildNode(sun)
    }

    // MARK: - 動かないもの

    private func buildWorld() {
        let floor = MartGame.floor
        // 外の地面と道
        let ground = SCNNode(geometry: SCNPlane(width: 80, height: 80))
        ground.geometry?.materials = [Self.material(UIColor(red: 0.7, green: 0.83, blue: 0.62, alpha: 1))]
        ground.eulerAngles.x = -.pi / 2
        ground.position = SCNVector3(11, -0.21, 8)
        world.addChildNode(ground)
        world.addChildNode(Self.at(Self.box(4, 0.1, 40, UIColor(red: 0.82, green: 0.82, blue: 0.8, alpha: 1), chamfer: 0), 24.3, -0.17, 8))
        world.addChildNode(Self.at(Self.box(5, 0.08, 40, UIColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1), chamfer: 0), 28.8, -0.18, 8))
        for k in 0..<10 {
            world.addChildNode(Self.at(Self.box(0.15, 0.02, 1.2, .white, chamfer: 0), 28.8, -0.13, -8 + CGFloat(k) * 4))
        }

        // 奥の壁 2 枚と、手前の低い縁
        let wall = UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1)
        let trim = UIColor(red: 0.36, green: 0.4, blue: 0.46, alpha: 1)
        world.addChildNode(Self.at(Self.box(floor.width + 0.3, 2.6, 0.3, wall, chamfer: 0.02), floor.midX - 0.15, 1.3, -0.15))
        world.addChildNode(Self.at(Self.box(floor.width + 0.4, 0.2, 0.4, trim, chamfer: 0.03), floor.midX - 0.15, 2.6, -0.15))
        world.addChildNode(Self.at(Self.box(0.15, 0.3, 13.2, trim), floor.maxX + 0.07, 0.15, 6.6))
        // 看板
        let sign = Self.decalStanding(Self.label("MACHIKADO MART", size: 80, color: UIColor(red: 0.3, green: 0.33, blue: 0.38, alpha: 1)),
                                      width: 8)
        sign.position = SCNVector3(Float(floor.midX), 1.75, 0.02)
        world.addChildNode(sign)
        // 入口の自動ドア
        let frame = UIColor(white: 0.35, alpha: 1)
        world.addChildNode(Self.at(Self.box(0.25, 2.2, 0.25, frame), floor.maxX + 0.05, 1.1, MartGame.door.y - 1.3))
        world.addChildNode(Self.at(Self.box(0.25, 0.3, 2.6, frame), floor.maxX + 0.05, 2.2, MartGame.door.y))
        world.addChildNode(Self.at(Self.box(0.25, 2.2, 0.25, frame), floor.maxX + 0.05, 1.1, MartGame.door.y + 1.3))
        let glass = UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.4)
        for z in [MartGame.door.y - 0.65, MartGame.door.y + 0.65] {
            let panel = Self.box(0.08, 2.0, 1.25, glass, chamfer: 0.01)
            panel.addChildNode(Self.at(Self.box(0.1, 2.0, 0.06, UIColor(white: 0.4, alpha: 1), chamfer: 0), 0, 0, z < MartGame.door.y ? -0.6 : 0.6))
            panel.position = SCNVector3(Float(floor.maxX + 0.05), 1.0, Float(z))
            world.addChildNode(panel)
            doorPanels.append((panel, Float(z)))
        }
        // レジ台
        let counter = MartGame.counter
        let counterNode = SCNNode()
        counterNode.addChildNode(Self.at(Self.box(counter.width, 0.9, counter.height, UIColor(red: 0.36, green: 0.4, blue: 0.46, alpha: 1)),
                                         0, 0.45, 0))
        counterNode.addChildNode(Self.at(Self.box(counter.width + 0.1, 0.08, counter.height + 0.1, UIColor(white: 0.97, alpha: 1)),
                                         0, 0.93, 0))
        counterNode.addChildNode(Self.at(Self.box(0.5, 0.3, 0.55, UIColor(white: 0.25, alpha: 1)), 0.05, 1.12, -0.4))
        let screen = Self.box(0.06, 0.28, 0.4, UIColor(red: 0.3, green: 0.9, blue: 0.55, alpha: 1), chamfer: 0.01)
        screen.geometry?.materials = [Self.material(UIColor(red: 0.3, green: 0.9, blue: 0.55, alpha: 1), emission: true)]
        counterNode.addChildNode(Self.at(screen, 0.25, 1.4, -0.4))
        counterNode.addChildNode(Self.at(Self.box(0.8, 0.04, 0.9, UIColor(white: 0.2, alpha: 1)), 0, 0.98, 0.5))
        counterNode.position = SCNVector3(Float(counter.midX), 0, Float(counter.midY))
        world.addChildNode(counterNode)
        // レジの立つ場所
        let spot = Self.decal(Self.spotImage(), width: 1.5, length: 1.5)
        spot.position = SCNVector3(Float(MartGame.cashierSpot.x), 0.015, Float(MartGame.cashierSpot.y))
        world.addChildNode(spot)
        // お金の置き場（マット）
        world.addChildNode(Self.at(Self.box(1.4, 0.04, 0.9, UIColor(red: 0.85, green: 0.92, blue: 0.85, alpha: 1)),
                                   MartGame.cashSpot.x, 0.02, MartGame.cashSpot.y))
        buildDecorations()
        buildBaskets()
        // 外のトラックと木
        buildTruck()
        for (x, z, r) in [(26.3, 1.0, 0.6), (23.4, -1.5, 0.8)]
            as [(CGFloat, CGFloat, CGFloat)] {
            let tree = SCNNode()
            tree.addChildNode(Self.at(Self.cylinder(0.12, 0.6, UIColor(red: 0.55, green: 0.38, blue: 0.25, alpha: 1)), 0, 0.3, 0))
            tree.addChildNode(Self.at(Self.sphere(r, UIColor(red: 0.35, green: 0.7, blue: 0.35, alpha: 1)), 0, 0.6 + r * 0.8, 0))
            tree.addChildNode(Self.at(Self.sphere(r * 0.7, UIColor(red: 0.45, green: 0.78, blue: 0.4, alpha: 1)), r * 0.35, 0.8 + r, r * 0.3))
            tree.position = SCNVector3(Float(x), -0.2, Float(z))
            world.addChildNode(tree)
        }
        // 案内の矢印
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.28, height: 0.45)
        cone.materials = [Self.material(UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1))]
        let tip = SCNNode(geometry: cone)
        tip.eulerAngles.x = .pi
        arrow.addChildNode(tip)
        arrow.addChildNode(Self.at(Self.cylinder(0.11, 0.4, UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1)), 0, 0.4, 0))
        arrow.isHidden = true
        world.addChildNode(arrow)
        arrow.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.35, z: 0, duration: 0.45),
                                                  .moveBy(x: 0, y: -0.35, z: 0, duration: 0.45)])))
        // MAX の文字
        maxLabel = Self.billboard(Self.label("MAX", size: 60, color: UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1)), width: 0.9)
        maxLabel.isHidden = true
        world.addChildNode(maxLabel)
        // 会計の輪
        servingRing = Self.billboard(Self.label("💵", size: 60), width: 0.6)
        servingRing.isHidden = true
        world.addChildNode(servingRing)
        // お金の山：帯の付いた札束を 3×2 の山に積む（はじめに作っておき、たまった額で出し入れする）
        for index in 0..<36 {
            let bundle = Self.bundleNode(kind: index % 5 == 4 ? 1 : 0)
            let pile = index % 6, level = index / 6
            bundle.position = SCNVector3(Float(MartGame.cashSpot.x - 0.5 + CGFloat(pile % 3) * 0.5),
                                         Float(0.1 + CGFloat(level) * 0.105),
                                         Float(MartGame.cashSpot.y - 0.16 + CGFloat(pile / 3) * 0.32))
            bundle.eulerAngles.y = Float.random(in: -0.12...0.12)
            bundle.isHidden = true
            world.addChildNode(bundle)
            cashBills.append(bundle)
        }
    }

    /// 床・左の壁・手前の縁・入口から手前の右の壁・花だん・手前の木（お店を広げると作り直す）
    private func buildShell(depth: CGFloat) {
        shell.childNodes.forEach { $0.removeFromParentNode() }
        shellDepth = depth
        let floor = CGRect(x: 0, y: 0, width: MartGame.floor.width, height: depth)
        // 床（市松模様）
        let floorNode = Self.box(floor.width, 0.2, floor.height, .white, chamfer: 0)
        let unit: CGFloat = 64
        let tiles = UIGraphicsImageRenderer(size: CGSize(width: floor.width * unit, height: floor.height * unit)).image { context in
            // 目地（タイルのすき間）の色を全体に塗ってから、タイルを少しずつ色を変えて置く
            UIColor(red: 0.84, green: 0.83, blue: 0.81, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: floor.width * unit, height: floor.height * unit))
            for x in 0..<Int(floor.width.rounded(.up)) {
                for y in 0..<Int(floor.height) {
                    let checker = (x + y) % 2 == 0
                    let jitter = CGFloat((x * 37 + y * 17) % 7) * 0.004
                    UIColor(red: (checker ? 0.965 : 0.93) - jitter, green: (checker ? 0.957 : 0.92) - jitter,
                            blue: (checker ? 0.94 : 0.9) - jitter, alpha: 1).setFill()
                    let tile = CGRect(x: CGFloat(x) * unit + 2, y: CGFloat(y) * unit + 2, width: unit - 4, height: unit - 4)
                    UIBezierPath(roundedRect: tile, cornerRadius: 4).fill()
                    // ほんのり光る角
                    UIColor(white: 1, alpha: 0.18).setFill()
                    UIBezierPath(roundedRect: CGRect(x: tile.minX + 4, y: tile.minY + 4, width: tile.width * 0.45, height: 5), cornerRadius: 2).fill()
                }
            }
        }
        let floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .lambert
        floorMaterial.diffuse.contents = tiles
        let sideMaterial = Self.material(UIColor(red: 0.8, green: 0.72, blue: 0.62, alpha: 1))
        floorNode.geometry?.materials = [sideMaterial, sideMaterial, sideMaterial, sideMaterial, floorMaterial, sideMaterial]
        floorNode.position = SCNVector3(Float(floor.midX), -0.1, Float(floor.midY))
        shell.addChildNode(floorNode)

        let wall = UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1)
        let trim = UIColor(red: 0.36, green: 0.4, blue: 0.46, alpha: 1)
        shell.addChildNode(Self.at(Self.box(0.3, 2.6, floor.height, wall, chamfer: 0.02), -0.15, 1.3, floor.midY))
        shell.addChildNode(Self.at(Self.box(0.4, 0.2, floor.height + 0.3, trim, chamfer: 0.03), -0.15, 2.6, floor.midY - 0.15))
        shell.addChildNode(Self.at(Self.box(floor.width - 0.3, 0.3, 0.15, trim), floor.midX - 0.15, 0.15, floor.maxY + 0.07))
        let lower = MartGame.door.y + 1.3
        shell.addChildNode(Self.at(Self.box(0.15, 0.3, floor.maxY - lower, trim), floor.maxX + 0.07, 0.15, (lower + floor.maxY) / 2))
        // 外：花だん（手前）
        for k in 0..<11 {
            let x = 1.0 + CGFloat(k) * 1.95
            shell.addChildNode(Self.at(Self.box(1.5, 0.25, 0.5, UIColor(red: 0.75, green: 0.55, blue: 0.4, alpha: 1)), x, -0.08, floor.maxY + 0.6))
            for f in 0..<4 {
                let colors: [UIColor] = [.systemPink, .systemYellow, .white, .systemOrange]
                shell.addChildNode(Self.at(Self.sphere(0.1, colors[(k + f) % colors.count]),
                                           x - 0.5 + CGFloat(f) * 0.33, 0.12, floor.maxY + 0.6))
            }
            shell.addChildNode(Self.at(Self.box(1.4, 0.12, 0.42, UIColor(red: 0.35, green: 0.65, blue: 0.35, alpha: 1)),
                                       x, 0.06, floor.maxY + 0.6))
        }
        for (x, dz, r) in [(25.0, 2.6, 0.7), (3, 2.2, 0.6), (9, 2.6, 0.7), (15, 2.2, 0.55), (20.5, 2.5, 0.65)] as [(CGFloat, CGFloat, CGFloat)] {
            let tree = SCNNode()
            tree.addChildNode(Self.at(Self.cylinder(0.12, 0.6, UIColor(red: 0.55, green: 0.38, blue: 0.25, alpha: 1)), 0, 0.3, 0))
            tree.addChildNode(Self.at(Self.sphere(r, UIColor(red: 0.35, green: 0.7, blue: 0.35, alpha: 1)), 0, 0.6 + r * 0.8, 0))
            tree.addChildNode(Self.at(Self.sphere(r * 0.7, UIColor(red: 0.45, green: 0.78, blue: 0.4, alpha: 1)), r * 0.35, 0.8 + r, r * 0.3))
            tree.position = SCNVector3(Float(x), -0.2, Float(floor.maxY + dz))
            shell.addChildNode(tree)
        }
    }

    // MARK: - お金の絵

    /// お札の模様（kind 0 = 一万円ふう、1 = 千円ふう）。本物にまねない、ゲーム用のデザイン
    static func billImage(kind: Int) -> UIImage {
        let key = "bill|\(kind)"
        if let cached = imageCache[key] { return cached }
        let base = kind == 0 ? UIColor(red: 0.9, green: 0.85, blue: 0.74, alpha: 1) : UIColor(red: 0.8, green: 0.86, blue: 0.9, alpha: 1)
        let ink = kind == 0 ? UIColor(red: 0.5, green: 0.36, blue: 0.24, alpha: 1) : UIColor(red: 0.25, green: 0.36, blue: 0.52, alpha: 1)
        let size = CGSize(width: 512, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            base.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // 細かい地紋（波線）
            ink.withAlphaComponent(0.12).setStroke()
            for row in stride(from: CGFloat(0), to: size.height, by: 9) {
                let wave = UIBezierPath()
                wave.move(to: CGPoint(x: 0, y: row))
                for x in stride(from: CGFloat(0), through: size.width, by: 16) {
                    wave.addQuadCurve(to: CGPoint(x: x + 16, y: row), controlPoint: CGPoint(x: x + 8, y: row + 5))
                }
                wave.lineWidth = 1.2
                wave.stroke()
            }
            // 枠
            let outer = UIBezierPath(roundedRect: CGRect(x: 12, y: 12, width: 488, height: 232), cornerRadius: 10)
            outer.lineWidth = 7
            ink.withAlphaComponent(0.85).setStroke()
            outer.stroke()
            let inner = UIBezierPath(roundedRect: CGRect(x: 26, y: 26, width: 460, height: 204), cornerRadius: 6)
            inner.lineWidth = 2
            inner.stroke()
            // 左のロゼット（花のような丸い模様）
            let center = CGPoint(x: 120, y: 128)
            for k in 0..<14 {
                let angle = CGFloat(k) / 14 * .pi * 2
                let petal = UIBezierPath(ovalIn: CGRect(x: -44, y: -14, width: 88, height: 28))
                petal.apply(CGAffineTransform(rotationAngle: angle))
                petal.apply(CGAffineTransform(translationX: center.x, y: center.y))
                petal.lineWidth = 1.6
                ink.withAlphaComponent(0.45).setStroke()
                petal.stroke()
            }
            ink.withAlphaComponent(0.8).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)).fill()
            // 右のすかしの楕円
            UIColor(white: 1, alpha: 0.35).setFill()
            UIBezierPath(ovalIn: CGRect(x: 360, y: 58, width: 96, height: 132)).fill()
            ink.withAlphaComponent(0.25).setStroke()
            let watermark = UIBezierPath(ovalIn: CGRect(x: 360, y: 58, width: 96, height: 132))
            watermark.lineWidth = 2
            watermark.stroke()
            // 金額
            let amount = (kind == 0 ? "10000" : "1000") as NSString
            let amountFont = UIFont.systemFont(ofSize: 64, weight: .heavy).rounded()
            amount.draw(at: CGPoint(x: 196, y: 120), withAttributes: [.font: amountFont, .foregroundColor: ink])
            ("MART BANK" as NSString).draw(at: CGPoint(x: 200, y: 44),
                                           withAttributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold).rounded(),
                                                            .foregroundColor: ink.withAlphaComponent(0.8)])
            ("円" as NSString).draw(at: CGPoint(x: 410, y: 186),
                                   withAttributes: [.font: UIFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: ink])
        }
        imageCache[key] = image
        return image
    }

    private static var billMaterials: [Int: [SCNMaterial]] = [:]

    /// 1 枚のお札（上と下にお札の絵、ふちは紙の色）
    static func billNode(kind: Int) -> SCNNode {
        let geometry = SCNBox(width: 0.5, height: 0.014, length: 0.25, chamferRadius: 0.004)
        if billMaterials[kind] == nil {
            let face = SCNMaterial()
            face.lightingModel = .lambert
            face.diffuse.contents = billImage(kind: kind)
            let edge = material(kind == 0 ? UIColor(red: 0.86, green: 0.8, blue: 0.68, alpha: 1) : UIColor(red: 0.76, green: 0.82, blue: 0.86, alpha: 1))
            billMaterials[kind] = [edge, edge, edge, edge, face, face]
        }
        geometry.materials = billMaterials[kind] ?? []
        return SCNNode(geometry: geometry)
    }

    private static var bundleMaterials: [Int: [SCNMaterial]] = [:]

    /// 帯の付いた札束（横から見ると紙が重なったしま）
    static func bundleNode(kind: Int) -> SCNNode {
        let geometry = SCNBox(width: 0.5, height: 0.1, length: 0.25, chamferRadius: 0.008)
        if bundleMaterials[kind] == nil {
            let face = SCNMaterial()
            face.lightingModel = .lambert
            face.diffuse.contents = billImage(kind: kind)
            let paper = kind == 0 ? UIColor(red: 0.88, green: 0.83, blue: 0.72, alpha: 1) : UIColor(red: 0.78, green: 0.84, blue: 0.88, alpha: 1)
            let layers = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 32)).image { context in
                paper.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 128, height: 32))
                paper.darker(0.12).setFill()
                for y in stride(from: 1, to: 32, by: 3) { context.fill(CGRect(x: 0, y: y, width: 128, height: 1)) }
            }
            let side = SCNMaterial()
            side.lightingModel = .lambert
            side.diffuse.contents = layers
            bundleMaterials[kind] = [side, side, side, side, face, face]
        }
        geometry.materials = bundleMaterials[kind] ?? []
        let node = SCNNode(geometry: geometry)
        // 帯
        node.addChildNode(at(box(0.09, 0.104, 0.254, UIColor(white: 0.98, alpha: 1), chamfer: 0.004), -0.06, 0, 0))
        return node
    }

    static func coinNode() -> SCNNode {
        let coin = cylinder(0.075, 0.022, UIColor(red: 0.95, green: 0.78, blue: 0.32, alpha: 1))
        coin.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.3, green: 0.2, blue: 0.0, alpha: 1)
        coin.addChildNode(at(cylinder(0.05, 0.024, UIColor(red: 0.98, green: 0.86, blue: 0.45, alpha: 1)), 0, 0, 0))
        return coin
    }

    /// 飾り：窓・ポスター・時計・観葉植物・入口のマット・外の花だん・街灯・ベンチ・駐車場
    private func buildDecorations() {
        let floor = MartGame.floor
        // 奥の壁の窓（看板の両側）
        let glass = UIColor(red: 0.72, green: 0.9, blue: 1, alpha: 1)
        let frame = UIColor(white: 0.98, alpha: 1)
        for x in [4.0, 18.0] as [CGFloat] {
            world.addChildNode(Self.at(Self.box(2.0, 1.2, 0.06, frame, chamfer: 0.02), x, 1.5, 0.02))
            world.addChildNode(Self.at(Self.box(1.8, 1.0, 0.07, glass, chamfer: 0), x, 1.5, 0.03))
            world.addChildNode(Self.at(Self.box(0.06, 1.0, 0.08, frame, chamfer: 0), x, 1.5, 0.04))
            world.addChildNode(Self.at(Self.box(1.8, 0.06, 0.08, frame, chamfer: 0), x, 1.5, 0.04))
            // 窓の下のひさし
            world.addChildNode(Self.at(Self.box(2.2, 0.06, 0.25, UIColor(red: 0.36, green: 0.4, blue: 0.46, alpha: 1)), x, 0.86, 0.12))
        }
        // 左の壁のポスターと時計
        let posterColors: [UIColor] = [UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 1),
                                       UIColor(red: 1, green: 0.55, blue: 0.6, alpha: 1)]
        for (index, z) in ([0.9, 13.5, 14.9] as [CGFloat]).enumerated() {
            let poster = Self.box(0.04, 0.9, 0.7, posterColors[index], chamfer: 0.01)
            poster.addChildNode(Self.at(Self.box(0.05, 0.3, 0.5, .white, chamfer: 0.01), 0, 0.15, 0))
            poster.addChildNode(Self.at(Self.box(0.05, 0.08, 0.5, UIColor(white: 1, alpha: 0.7), chamfer: 0), 0, -0.2, 0))
            world.addChildNode(Self.at(poster, 0.03, 1.55, z))
        }
        let clock = Self.cylinder(0.32, 0.05, .white)
        clock.eulerAngles.x = .pi / 2
        clock.addChildNode(Self.at(Self.cylinder(0.28, 0.06, UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)), 0, 0.005, 0))
        clock.addChildNode(Self.at(Self.box(0.03, 0.07, 0.2, UIColor(white: 0.2, alpha: 1), chamfer: 0), 0, 0.04, -0.08))
        clock.addChildNode(Self.at(Self.box(0.15, 0.07, 0.03, UIColor(white: 0.2, alpha: 1), chamfer: 0), 0.06, 0.04, 0))
        world.addChildNode(Self.at(clock, 14.5, 2.1, 0.05))
        // 観葉植物（すみ）
        for (x, z) in [(0.6, 0.6), (21.4, 0.6), (21.4, 11.6)] as [(CGFloat, CGFloat)] {
            let plant = SCNNode()
            plant.addChildNode(Self.at(SCNNode(geometry: {
                let pot = SCNCone(topRadius: 0.24, bottomRadius: 0.17, height: 0.4)
                pot.materials = [Self.material(UIColor(red: 0.85, green: 0.5, blue: 0.35, alpha: 1))]
                return pot
            }()), 0, 0.2, 0))
            for (dx, dy, dz, r) in [(0.0, 0.62, 0.0, 0.26), (0.12, 0.85, 0.06, 0.18), (-0.1, 0.8, -0.08, 0.17)]
                as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                plant.addChildNode(Self.at(Self.sphere(r, UIColor(red: 0.3, green: 0.68, blue: 0.35, alpha: 1)), dx, dy, dz))
            }
            world.addChildNode(Self.at(plant, x, 0, z))
        }
        // 入口のマット
        let mat = Self.decal(Self.label("WELCOME", size: 50, color: .white,
                                         background: UIColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1)), width: 1.0, length: 2.2)
        mat.eulerAngles.y = .pi / 2
        mat.position = SCNVector3(Float(floor.maxX - 0.7), 0.012, Float(MartGame.door.y))
        world.addChildNode(mat)
        // 外：街灯とベンチと駐車場の線
        for z in [1.0, 9.0] as [CGFloat] {
            let lamp = SCNNode()
            lamp.addChildNode(Self.at(Self.cylinder(0.06, 2.6, UIColor(white: 0.3, alpha: 1)), 0, 1.3, 0))
            lamp.addChildNode(Self.at(Self.sphere(0.2, UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1)), 0, 2.7, 0))
            world.addChildNode(Self.at(lamp, floor.maxX + 0.7, -0.15, z))
        }
        let bench = SCNNode()
        bench.addChildNode(Self.at(Self.box(0.5, 0.08, 1.5, UIColor(red: 0.7, green: 0.48, blue: 0.3, alpha: 1)), 0, 0.45, 0))
        bench.addChildNode(Self.at(Self.box(0.08, 0.45, 1.5, UIColor(red: 0.7, green: 0.48, blue: 0.3, alpha: 1)), -0.22, 0.72, 0))
        for dz in [-0.6, 0.6] as [CGFloat] {
            bench.addChildNode(Self.at(Self.box(0.45, 0.45, 0.08, UIColor(white: 0.3, alpha: 1)), 0, 0.22, dz))
        }
        world.addChildNode(Self.at(bench, floor.maxX + 0.9, -0.15, 17.0))
        for k in 0..<5 {
            world.addChildNode(Self.at(Self.box(2.4, 0.02, 0.1, .white, chamfer: 0), 27.0, -0.12, -2 + CGFloat(k) * 2.6))
        }
    }

    /// かご置き場・使い終わったかごの山・アップグレードの場所
    private func buildBaskets() {
        // かご置き場（入口のそば）：台と看板。かごは重ねて置く
        let stand = SCNNode()
        stand.addChildNode(Self.at(Self.box(0.6, 0.1, 0.45, UIColor(white: 0.35, alpha: 1)), 0, 0.05, 0))
        stand.addChildNode(Self.at(Self.cylinder(0.025, 1.3, UIColor(white: 0.55, alpha: 1)), 0.28, 0.65, -0.2))
        let sign = Self.decalStanding(Self.label("🧺", size: 60, color: .white, background: UIColor(red: 0.9, green: 0.22, blue: 0.25, alpha: 1)),
                                      width: 0.5)
        sign.position = SCNVector3(0.28, 1.35, -0.18)
        stand.addChildNode(sign)
        for index in 0..<MartGame.basketStandMax {
            let basket = Self.basketModel()
            basket.position = SCNVector3(0, 0.1 + Float(index) * 0.06, 0)
            basket.isHidden = true
            stand.addChildNode(basket)
            standBasketNodes.append(basket)
        }
        stand.position = SCNVector3(Float(MartGame.basketStand.x), 0, Float(MartGame.basketStand.y))
        world.addChildNode(stand)
        let standZone = Self.decal(Self.zoneImage(color: UIColor(red: 0.9, green: 0.22, blue: 0.25, alpha: 1), icon: "🧺"),
                                   width: 1.6, length: 1.6)
        standZone.position = SCNVector3(Float(MartGame.basketStand.x), 0.014, Float(MartGame.basketStand.y))
        world.addChildNode(standZone)
        // 使い終わったかごがたまる場所（棚とレジのあいだ）
        let returnZone = Self.decal(Self.zoneImage(color: UIColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1), icon: "↩️"),
                                    width: 1.6, length: 1.6)
        returnZone.position = SCNVector3(Float(MartGame.basketReturn.x), 0.014, Float(MartGame.basketReturn.y))
        world.addChildNode(returnZone)
        for index in 0..<12 {
            let basket = Self.basketModel()
            basket.position = SCNVector3(Float(MartGame.basketReturn.x) + Float(index % 2) * 0.1 - 0.05,
                                         0.02 + Float(index) * 0.06, Float(MartGame.basketReturn.y))
            basket.eulerAngles.y = Float(index % 3) * 0.2 - 0.2
            basket.isHidden = true
            world.addChildNode(basket)
            returnBasketNodes.append(basket)
        }
        // ゴミ箱
        let trash = SCNNode()
        let bin = SCNNode(geometry: SCNCone(topRadius: 0.3, bottomRadius: 0.24, height: 0.75))
        bin.geometry?.materials = [Self.material(UIColor(red: 0.45, green: 0.52, blue: 0.6, alpha: 1))]
        trash.addChildNode(Self.at(bin, 0, 0.375, 0))
        trash.addChildNode(Self.at(Self.cylinder(0.32, 0.06, UIColor(red: 0.32, green: 0.38, blue: 0.45, alpha: 1)), 0, 0.78, 0))
        trash.addChildNode(Self.at(Self.box(0.32, 0.03, 0.1, UIColor(white: 0.12, alpha: 1), chamfer: 0.01), 0, 0.815, 0))
        let trashIcon = Self.billboard(Self.label("🗑️", size: 60, background: .white), width: 0.55)
        trashIcon.position = SCNVector3(0, 1.35, 0)
        trash.addChildNode(trashIcon)
        trash.position = SCNVector3(Float(MartGame.trashSpot.x), 0, Float(MartGame.trashSpot.y))
        world.addChildNode(trash)
        let trashZone = Self.decal(Self.zoneImage(color: UIColor(white: 0.45, alpha: 1), icon: ""), width: 1.7, length: 1.7)
        trashZone.position = SCNVector3(Float(MartGame.trashSpot.x), 0.014, Float(MartGame.trashSpot.y))
        world.addChildNode(trashZone)
        // アップグレードの場所（左下）
        let zone = MartGame.upgradeZone
        let upgrade = Self.decal(Self.upgradeImage(), width: zone.width, length: zone.height)
        upgrade.position = SCNVector3(Float(zone.midX), 0.014, Float(zone.midY))
        world.addChildNode(upgrade)
        let mark = Self.billboard(Self.label("⬆️", size: 60, color: .white,
                                             background: UIColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1)), width: 0.7)
        mark.position = SCNVector3(Float(zone.midX), 1.3, Float(zone.midY))
        mark.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.15, z: 0, duration: 0.8), .moveBy(x: 0, y: -0.15, z: 0, duration: 0.8)])))
        world.addChildNode(mark)
    }

    private static func zoneImage(color: UIColor, icon: String) -> UIImage {
        let key = "zone-icon|\(icon)"
        if let cached = imageCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { _ in
            let rect = CGRect(x: 12, y: 12, width: 176, height: 176)
            color.withAlphaComponent(0.25).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 30).fill()
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 30)
            border.lineWidth = 8
            border.setLineDash([22, 12], count: 2, phase: 0)
            color.withAlphaComponent(0.85).setStroke()
            border.stroke()
            (icon as NSString).draw(at: CGPoint(x: 62, y: 56), withAttributes: [.font: UIFont.systemFont(ofSize: 66)])
        }
        imageCache[key] = image
        return image
    }

    private static func upgradeImage() -> UIImage {
        let key = "upgrade-zone"
        if let cached = imageCache[key] { return cached }
        let size = CGSize(width: 416, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(x: 10, y: 10, width: 396, height: 236)
            let purple = UIColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1)
            purple.withAlphaComponent(0.3).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 36).fill()
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 36)
            border.lineWidth = 10
            purple.setStroke()
            border.stroke()
            ("💰" as NSString).draw(at: CGPoint(x: 96, y: 68), withAttributes: [.font: UIFont.systemFont(ofSize: 100)])
            ("⬆️" as NSString).draw(at: CGPoint(x: 216, y: 68), withAttributes: [.font: UIFont.systemFont(ofSize: 100)])
        }
        imageCache[key] = image
        return image
    }

    static func decalStanding(_ image: UIImage, width: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: width * image.size.height / max(image.size.width, 1))
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        plane.materials = [material]
        return SCNNode(geometry: plane)
    }

    private static func spotImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { _ in
            let rect = CGRect(x: 12, y: 12, width: 176, height: 176)
            UIColor(red: 0.35, green: 0.8, blue: 0.4, alpha: 0.5).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 30).fill()
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 30)
            border.lineWidth = 10
            UIColor(red: 0.3, green: 0.7, blue: 0.35, alpha: 1).setStroke()
            border.stroke()
            ("💰" as NSString).draw(at: CGPoint(x: 62, y: 52), withAttributes: [.font: UIFont.systemFont(ofSize: 70)])
        }
    }

    private func buildTruck() {
        let truck = SCNNode()
        let body = UIColor(white: 0.97, alpha: 1)
        truck.addChildNode(Self.at(Self.box(1.6, 1.7, 3.2, body, chamfer: 0.08), 0, 1.2, 0))
        truck.addChildNode(Self.at(Self.box(1.6, 1.2, 1.2, UIColor(red: 0.9, green: 0.25, blue: 0.25, alpha: 1), chamfer: 0.12), 0, 0.95, -2.3))
        truck.addChildNode(Self.at(Self.box(1.5, 0.5, 0.05, UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1), chamfer: 0), 0, 1.25, -2.92))
        truck.addChildNode(Self.at(Self.box(1.62, 0.35, 3.0, UIColor(red: 0.9, green: 0.25, blue: 0.25, alpha: 1), chamfer: 0.02), 0, 1.0, 0))
        for (x, z) in [(-0.8, -2.2), (0.8, -2.2), (-0.8, 0.9), (0.8, 0.9)] as [(CGFloat, CGFloat)] {
            let wheel = Self.cylinder(0.32, 0.25, UIColor(white: 0.15, alpha: 1))
            wheel.eulerAngles.z = .pi / 2
            truck.addChildNode(Self.at(wheel, x, 0.32, z))
        }
        truck.position = SCNVector3(25.6, -0.15, -18)
        world.addChildNode(truck)
        // 商品を届けに来て、また走っていく
        let arrive = SCNAction.move(to: SCNVector3(25.6, -0.15, 6.5), duration: 3.2)
        arrive.timingMode = .easeOut
        let leave = SCNAction.move(to: SCNVector3(25.6, -0.15, 34), duration: 3.0)
        leave.timingMode = .easeIn
        truck.runAction(.repeatForever(.sequence([
            arrive,
            .sequence([.moveBy(x: 0, y: 0.04, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.04, z: 0, duration: 0.12)]),
            .wait(duration: 9),
            leave,
            .wait(duration: 8),
            .move(to: SCNVector3(25.6, -0.15, -18), duration: 0),
        ])))
    }

    // MARK: - 棚・倉庫の台

    /// 売り場：低い陳列台。前の列と、一段高い奥の列に 4 個ずつ並べ、並んだ数がそのまま残りの数になる
    private func makeShelf(_ k: Int) -> SCNNode {
        let rect = MartGame.shelfRect(k)
        let node = SCNNode()
        guard let product = MartProduct(rawValue: k) else { return node }
        let white = UIColor(white: 0.98, alpha: 1)
        let height: CGFloat = 0.42
        let riser: CGFloat = 0.16
        // 商品の色の腰板と白い天板、奥のひな段
        node.addChildNode(Self.at(Self.box(rect.width - 0.08, height - 0.03, rect.height - 0.08, product.accent, chamfer: 0.04),
                                  0, (height - 0.03) / 2, 0))
        node.addChildNode(Self.at(Self.box(rect.width, 0.06, rect.height, white, chamfer: 0.025), 0, height, 0))
        node.addChildNode(Self.at(Self.box(rect.width - 0.04, riser, rect.height / 2 - 0.02, white, chamfer: 0.025),
                                  0, height + riser / 2, -rect.height / 4))
        // 腰板の値札
        let price = Self.decalStanding(Self.label(MartYen.text(product.price), size: 40, color: UIColor(white: 0.12, alpha: 1),
                                                  background: UIColor(red: 1, green: 0.88, blue: 0.25, alpha: 1)), width: 0.45)
        price.position = SCNVector3(0, Float(height * 0.5), Float(rect.height / 2 - 0.035))
        node.addChildNode(price)
        // 上に、売り場のアイコン
        let badge = Self.billboard(Self.label(product.icon, size: 64, background: .white), width: 0.55)
        badge.position = SCNVector3(0, 1.45, 0)
        node.addChildNode(badge)
        badge.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.08, z: 0, duration: 0.9), .moveBy(x: 0, y: -0.08, z: 0, duration: 0.9)])))
        // 商品（8 個ぶんの場所を作っておく）
        var items: [SCNNode] = []
        for index in 0..<MartGame.shelfCapacity {
            let back = index >= 4
            let column = CGFloat(index % 4)
            let item = Self.productModel(product)
            item.position = SCNVector3(Float(-rect.width / 2 + 0.3 + column * (rect.width - 0.6) / 3),
                                       Float(height + 0.03 + (back ? riser : 0)),
                                       Float(back ? -rect.height / 4 : rect.height / 4))
            item.eulerAngles.y = -0.35
            item.isHidden = true
            node.addChildNode(item)
            items.append(item)
        }
        shelfItems[k] = items
        node.position = SCNVector3(Float(rect.midX), 0, Float(rect.midY))
        return node
    }

    /// 棚に並ぶ商品の形（包装の絵を貼った、缶・ペットボトル・袋・カップ・サンド・果物・くま）
    static func productModel(_ product: MartProduct) -> SCNNode {
        let outer = SCNNode()
        let node = SCNNode()
        node.scale = SCNVector3(1.2, 1.2, 1.2)
        outer.addChildNode(node)
        let silver = UIColor(white: 0.86, alpha: 1)
        switch product {
        case .soda:
            // 缶（絵を巻いた胴と銀のふた）
            let can = SCNCylinder(radius: 0.065, height: 0.24)
            can.radialSegmentCount = 20
            can.materials = [textured(packageImage(product)), material(silver), material(silver)]
            let canNode = SCNNode(geometry: can)
            canNode.addChildNode(at(cylinder(0.058, 0.02, silver), 0, 0.125, 0))
            canNode.eulerAngles.y = -0.6
            node.addChildNode(at(canNode, -0.08, 0.12, 0))
            // ペットボトル（すけた緑の胴・ラベル・首・キャップ）
            let bottle = cylinder(0.06, 0.24, UIColor(red: 0.55, green: 0.85, blue: 0.6, alpha: 0.75))
            let band = SCNCylinder(radius: 0.063, height: 0.09)
            band.radialSegmentCount = 20
            band.materials = [textured(packageImage(product, alt: true)), material(product.accent), material(product.accent)]
            let bandNode = SCNNode(geometry: band)
            bandNode.eulerAngles.y = -0.6
            bottle.addChildNode(at(bandNode, 0, 0.0, 0))
            let neck = SCNNode(geometry: SCNCone(topRadius: 0.025, bottomRadius: 0.06, height: 0.07))
            neck.geometry?.materials = [material(UIColor(red: 0.55, green: 0.85, blue: 0.6, alpha: 0.75))]
            bottle.addChildNode(at(neck, 0, 0.155, 0))
            bottle.addChildNode(at(cylinder(0.028, 0.035, .white), 0, 0.205, 0))
            node.addChildNode(at(bottle, 0.08, 0.12, 0))
        case .snack:
            // ふくらんだ袋：表と裏に絵、上下はギザギザの閉じ口
            let bag = SCNBox(width: 0.3, height: 0.34, length: 0.11, chamferRadius: 0.05)
            let print = textured(packageImage(product))
            let side = material(product.color.darker(0.08))
            bag.materials = [print, side, print, side, side, side]
            let bagNode = SCNNode(geometry: bag)
            for y in [-0.17, 0.17] as [CGFloat] {
                bagNode.addChildNode(at(box(0.3, 0.04, 0.03, product.accent.darker(0.05), chamfer: 0.008), 0, y, 0))
            }
            bagNode.eulerAngles.x = -0.12
            node.addChildNode(at(bagNode, 0, 0.19, 0))
        case .noodle:
            // カップ（絵を巻いた胴）と、紙のふた
            let cup = SCNCone(topRadius: 0.125, bottomRadius: 0.09, height: 0.22)
            cup.radialSegmentCount = 24
            cup.materials = [textured(packageImage(product)), material(product.color), material(product.color)]
            let cupNode = SCNNode(geometry: cup)
            cupNode.eulerAngles.y = -0.5
            cupNode.addChildNode(at(cylinder(0.13, 0.018, UIColor(white: 0.93, alpha: 1)), 0, 0.115, 0))
            cupNode.addChildNode(at(cylinder(0.08, 0.02, product.accent), 0, 0.12, 0))
            node.addChildNode(at(cupNode, 0, 0.11, 0))
        case .sandwich:
            // 三角のサンド 2 切れ（断面にレタス・たまご・ハム）
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: -0.15, y: 0))
            triangle.addLine(to: CGPoint(x: 0.15, y: 0))
            triangle.addLine(to: CGPoint(x: 0, y: 0.22))
            triangle.close()
            let shape = SCNShape(path: triangle, extrusionDepth: 0.07)
            shape.chamferRadius = 0.012
            let cut = textured(sandwichImage())
            let crust = material(UIColor(red: 0.86, green: 0.62, blue: 0.36, alpha: 1))
            shape.materials = [cut, cut, crust, crust, crust]
            for (dz, turn) in [(0.045, 0.0), (-0.045, Double.pi)] as [(CGFloat, Double)] {
                let piece = SCNNode(geometry: shape)
                piece.eulerAngles.y = Float(turn)
                node.addChildNode(at(piece, 0, 0.0, dz))
            }
            // 包みのシール
            node.addChildNode(at(box(0.1, 0.05, 0.2, product.accent, chamfer: 0.01), 0, 0.2, 0))
        case .fruit:
            // りんご・オレンジ・ぶどう
            let apple = sphere(0.085, UIColor(red: 0.88, green: 0.16, blue: 0.2, alpha: 1))
            apple.scale = SCNVector3(1, 0.92, 1)
            apple.addChildNode(at(cylinder(0.008, 0.05, UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1)), 0, 0.09, 0))
            let leaf = sphere(0.03, UIColor(red: 0.35, green: 0.7, blue: 0.3, alpha: 1))
            leaf.scale = SCNVector3(1.4, 0.3, 0.7)
            apple.addChildNode(at(leaf, 0.03, 0.1, 0))
            node.addChildNode(at(apple, -0.09, 0.085, 0.02))
            let orange = sphere(0.08, UIColor(red: 1, green: 0.6, blue: 0.12, alpha: 1))
            orange.addChildNode(at(sphere(0.015, UIColor(red: 0.35, green: 0.6, blue: 0.25, alpha: 1)), 0, 0.078, 0))
            node.addChildNode(at(orange, 0.08, 0.08, 0.04))
            let grape = UIColor(red: 0.5, green: 0.22, blue: 0.6, alpha: 1)
            for (x, y, z) in [(-0.03, 0.2, -0.05), (0.03, 0.2, -0.05), (0.0, 0.2, -0.0), (-0.015, 0.15, -0.04), (0.02, 0.15, -0.03),
                              (0.0, 0.1, -0.04)] as [(CGFloat, CGFloat, CGFloat)] {
                node.addChildNode(at(sphere(0.035, grape), x, y, z))
            }
        case .toy:
            // くまのぬいぐるみ（首にリボン）
            // ほかの商品とまぎれない、うすむらさきのくま
            let fur = UIColor(red: 0.74, green: 0.58, blue: 0.95, alpha: 1)
            let light = UIColor(red: 0.97, green: 0.9, blue: 1, alpha: 1)
            let dark = UIColor(white: 0.12, alpha: 1)
            let body = sphere(0.11, fur)
            body.scale = SCNVector3(1, 1.05, 0.9)
            body.addChildNode(at(sphere(0.06, light), 0, -0.01, 0.07))
            node.addChildNode(at(body, 0, 0.12, 0))
            for x in [-0.07, 0.07] as [CGFloat] {
                node.addChildNode(at(sphere(0.045, fur), x * 1.35, 0.15, 0.03))
                node.addChildNode(at(sphere(0.05, fur), x, 0.04, 0.07))
            }
            let head = sphere(0.09, fur)
            head.addChildNode(at(sphere(0.04, light), 0, -0.02, 0.07))
            head.addChildNode(at(sphere(0.014, dark), 0, -0.005, 0.105))
            for x in [-0.035, 0.035] as [CGFloat] {
                head.addChildNode(at(sphere(0.012, dark), x, 0.025, 0.08))
            }
            for x in [-0.065, 0.065] as [CGFloat] {
                let ear = sphere(0.035, fur)
                ear.addChildNode(at(sphere(0.02, light), 0, 0, 0.018))
                head.addChildNode(at(ear, x, 0.07, 0))
            }
            node.addChildNode(at(head, 0, 0.3, 0))
            for x in [-0.03, 0.03] as [CGFloat] {
                node.addChildNode(at(sphere(0.028, UIColor(red: 1, green: 0.4, blue: 0.55, alpha: 1)), x, 0.215, 0.05))
            }
        case .bread:
            // 山型の食パン（焼き色の上と、切り込み）
            let crust = UIColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1)
            let loaf = box(0.3, 0.14, 0.18, UIColor(red: 0.98, green: 0.88, blue: 0.68, alpha: 1), chamfer: 0.04)
            node.addChildNode(at(loaf, 0, 0.07, 0))
            for x in [-0.075, 0.075] as [CGFloat] {
                let dome = sphere(0.085, crust)
                dome.scale = SCNVector3(0.95, 0.8, 1.05)
                node.addChildNode(at(dome, x, 0.15, 0))
            }
            let bag = box(0.08, 0.06, 0.2, UIColor(red: 0.3, green: 0.55, blue: 0.9, alpha: 1), chamfer: 0.01)
            node.addChildNode(at(bag, 0.17, 0.1, 0))
        case .milk:
            // 牛乳パック（三角の屋根、青い帯）
            let carton = box(0.16, 0.24, 0.16, .white, chamfer: 0.01)
            carton.addChildNode(at(box(0.165, 0.08, 0.165, product.accent, chamfer: 0.005), 0, -0.02, 0))
            node.addChildNode(at(carton, 0, 0.12, 0))
            let roof = SCNNode(geometry: SCNPyramid(width: 0.16, height: 0.07, length: 0.16))
            roof.geometry?.materials = [material(.white)]
            node.addChildNode(at(roof, 0, 0.24, 0))
            node.addChildNode(at(box(0.16, 0.04, 0.02, .white, chamfer: 0.005), 0, 0.32, 0))
        case .iceCream:
            // コーンに 2 段のアイスとさくらんぼ
            let cone = SCNNode(geometry: SCNCone(topRadius: 0.075, bottomRadius: 0.012, height: 0.2))
            cone.geometry?.materials = [material(product.accent)]
            node.addChildNode(at(cone, 0, 0.1, 0))
            node.addChildNode(at(sphere(0.085, product.color), 0, 0.23, 0))
            node.addChildNode(at(sphere(0.075, UIColor(red: 0.6, green: 0.92, blue: 0.78, alpha: 1)), 0, 0.33, 0))
            node.addChildNode(at(sphere(0.028, UIColor(red: 0.92, green: 0.1, blue: 0.2, alpha: 1)), 0, 0.42, 0))
        case .flower:
            // 紙で包んだ花束
            let wrap = SCNNode(geometry: SCNCone(topRadius: 0.13, bottomRadius: 0.03, height: 0.24))
            wrap.geometry?.materials = [material(UIColor(red: 0.97, green: 0.93, blue: 0.85, alpha: 1))]
            node.addChildNode(at(wrap, 0, 0.12, 0))
            let colors = [product.color, UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1), UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1),
                          UIColor(red: 0.75, green: 0.55, blue: 0.95, alpha: 1), .white]
            for (index, (x, z)) in ([(0.0, 0.0), (-0.07, 0.03), (0.07, 0.03), (-0.04, -0.06), (0.05, -0.05)] as [(CGFloat, CGFloat)]).enumerated() {
                node.addChildNode(at(sphere(0.055, colors[index]), x, 0.28 + (index == 0 ? 0.04 : 0), z))
            }
            let leaf = sphere(0.05, product.accent)
            leaf.scale = SCNVector3(1.6, 0.4, 0.8)
            node.addChildNode(at(leaf, 0.1, 0.24, 0.05))
        case .cake:
            // 白いホールケーキに、いちごとろうそく
            let base = cylinder(0.14, 0.14, product.color)
            base.addChildNode(at(cylinder(0.142, 0.025, UIColor(red: 1, green: 0.75, blue: 0.82, alpha: 1)), 0, 0.0, 0))
            node.addChildNode(at(base, 0, 0.07, 0))
            for index in 0..<6 {
                let angle = CGFloat(index) / 6 * 2 * .pi
                node.addChildNode(at(sphere(0.03, product.accent), cos(angle) * 0.1, 0.155, sin(angle) * 0.1))
            }
            node.addChildNode(at(cylinder(0.012, 0.09, UIColor(red: 0.5, green: 0.75, blue: 1, alpha: 1)), 0, 0.19, 0))
            let flame = sphere(0.018, UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1))
            flame.geometry?.materials = [material(UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1), emission: true)]
            node.addChildNode(at(flame, 0, 0.25, 0))
        case .game:
            // ゲームのコントローラー（こちらに傾けて立てる）
            let pad = SCNNode()
            pad.addChildNode(box(0.26, 0.07, 0.12, product.color, chamfer: 0.035))
            for x in [-0.11, 0.11] as [CGFloat] {
                pad.addChildNode(at(sphere(0.06, product.color), x, -0.005, 0.03))
            }
            pad.addChildNode(at(box(0.06, 0.02, 0.018, .white, chamfer: 0.004), -0.07, 0.04, 0))
            pad.addChildNode(at(box(0.018, 0.02, 0.06, .white, chamfer: 0.004), -0.07, 0.04, 0))
            for (index, (x, z)) in ([(0.06, 0.0), (0.09, -0.025), (0.09, 0.025), (0.12, 0.0)] as [(CGFloat, CGFloat)]).enumerated() {
                let colors = [UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1), product.accent,
                              UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1), UIColor(red: 0.4, green: 0.85, blue: 0.4, alpha: 1)]
                pad.addChildNode(at(sphere(0.014, colors[index]), x, 0.04, z))
            }
            pad.eulerAngles.x = 0.9
            node.addChildNode(at(pad, 0, 0.12, 0))
        }
        return outer
    }

    /// 絵を貼る材料（同じ絵は使いまわす）
    static func textured(_ image: UIImage) -> SCNMaterial {
        let key = "image-\(ObjectIdentifier(image).hashValue)"
        if let cached = materials[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = image
        materials[key] = material
        return material
    }

    /// 商品の包装の絵
    static func packageImage(_ product: MartProduct, alt: Bool = false) -> UIImage {
        let key = "package|\(product.rawValue)|\(alt)"
        if let cached = imageCache[key] { return cached }
        let size = CGSize(width: 256, height: 256)
        func text(_ string: String, y: CGFloat, size: CGFloat, color: UIColor, width: CGFloat = 256) {
            let font = UIFont.systemFont(ofSize: size, weight: .black).rounded()
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let textSize = (string as NSString).size(withAttributes: attributes)
            (string as NSString).draw(at: CGPoint(x: (width - textSize.width) / 2, y: y), withAttributes: attributes)
        }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let all = CGRect(origin: .zero, size: size)
            switch product {
            case .soda where alt:
                // ペットボトルのラベル
                UIColor(red: 0.98, green: 0.97, blue: 0.9, alpha: 1).setFill()
                context.fill(all)
                product.accent.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 256, height: 40))
                context.fill(CGRect(x: 0, y: 216, width: 256, height: 40))
                text("TEA", y: 70, size: 90, color: UIColor(red: 0.25, green: 0.55, blue: 0.3, alpha: 1))
            case .soda:
                // 缶：赤地に白い波とロゴ
                product.color.setFill()
                context.fill(all)
                let wave = UIBezierPath()
                wave.move(to: CGPoint(x: 0, y: 170))
                wave.addCurve(to: CGPoint(x: 256, y: 150), controlPoint1: CGPoint(x: 90, y: 110), controlPoint2: CGPoint(x: 170, y: 210))
                wave.addLine(to: CGPoint(x: 256, y: 182))
                wave.addCurve(to: CGPoint(x: 0, y: 200), controlPoint1: CGPoint(x: 170, y: 240), controlPoint2: CGPoint(x: 90, y: 140))
                wave.close()
                UIColor.white.setFill()
                wave.fill()
                text("COLA", y: 50, size: 70, color: .white)
                for k in 0..<6 {
                    UIColor(white: 1, alpha: 0.35).setFill()
                    UIBezierPath(ovalIn: CGRect(x: 20 + CGFloat(k) * 40, y: 22 + CGFloat(k % 2) * 8, width: 10, height: 10)).fill()
                }
            case .snack:
                // 袋：黄色地、上に赤い帯、まんなかにロゴ、下にポテトの絵
                product.color.setFill()
                context.fill(all)
                product.accent.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 256, height: 46))
                UIBezierPath(ovalIn: CGRect(x: 24, y: 58, width: 208, height: 100)).fill()
                text("CHIPS", y: 72, size: 60, color: .white)
                text("うすしお", y: 6, size: 30, color: .white)
                for (x, y) in [(40, 175), (95, 190), (150, 172), (196, 192), (120, 215)] as [(CGFloat, CGFloat)] {
                    UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 1).setFill()
                    let chip = UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 46, height: 32))
                    chip.fill()
                    UIColor(red: 0.85, green: 0.62, blue: 0.25, alpha: 1).setStroke()
                    chip.lineWidth = 3
                    chip.stroke()
                }
            case .noodle:
                // カップ：白地に赤い帯とロゴ、どんぶりの絵
                product.color.setFill()
                context.fill(all)
                product.accent.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 256, height: 70))
                context.fill(CGRect(x: 0, y: 236, width: 256, height: 20))
                text("NOODLE", y: 12, size: 44, color: .white)
                UIColor(red: 0.98, green: 0.85, blue: 0.45, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 60, y: 110, width: 136, height: 60)).fill()
                UIColor(red: 0.3, green: 0.35, blue: 0.45, alpha: 1).setFill()
                let bowl = UIBezierPath()
                bowl.move(to: CGPoint(x: 52, y: 140))
                bowl.addQuadCurve(to: CGPoint(x: 204, y: 140), controlPoint: CGPoint(x: 128, y: 250))
                bowl.close()
                bowl.fill()
                UIColor(red: 0.95, green: 0.4, blue: 0.5, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 100, y: 112, width: 30, height: 18)).fill()
                UIColor(red: 0.4, green: 0.7, blue: 0.3, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 140, y: 118, width: 22, height: 12)).fill()
            default:
                product.color.setFill()
                context.fill(all)
            }
        }
        imageCache[key] = image
        return image
    }

    /// 店員の足もとの輪（自分・仲間・係を見分ける）
    static func ringImage(_ color: UIColor) -> UIImage {
        let key = "ring|\(color)"
        if let cached = imageCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { _ in
            let circle = CGRect(x: 12, y: 12, width: 136, height: 136)
            color.withAlphaComponent(0.25).setFill()
            UIBezierPath(ovalIn: circle).fill()
            let ring = UIBezierPath(ovalIn: circle)
            ring.lineWidth = 12
            color.setStroke()
            ring.stroke()
        }
        imageCache[key] = image
        return image
    }

    /// サンドの断面（パン・レタス・たまご・ハム）
    static func sandwichImage() -> UIImage {
        let key = "sandwich-cut"
        if let cached = imageCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { context in
            UIColor(red: 0.99, green: 0.95, blue: 0.84, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            let layers: [(CGFloat, CGFloat, UIColor)] = [
                (52, 10, UIColor(red: 0.45, green: 0.78, blue: 0.3, alpha: 1)),
                (62, 14, UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)),
                (76, 9, UIColor(red: 0.98, green: 0.55, blue: 0.6, alpha: 1)),
            ]
            for (y, h, color) in layers {
                color.setFill()
                context.fill(CGRect(x: 0, y: y, width: 128, height: h))
            }
        }
        imageCache[key] = image
        return image
    }

    /// 買い物かご（赤いプラスチック、取っ手つき）
    static func basketModel(_ color: UIColor = UIColor(red: 0.9, green: 0.22, blue: 0.25, alpha: 1)) -> SCNNode {
        let node = SCNNode()
        let w: CGFloat = 0.44, l: CGFloat = 0.32, h: CGFloat = 0.2
        node.addChildNode(at(box(w - 0.04, 0.02, l - 0.04, color.darker(0.1), chamfer: 0.005), 0, 0.01, 0))
        let wall = textured(basketWallImage(color))
        for (x, z, width, length) in [(0, l / 2, w, 0.015), (0, -l / 2, w, 0.015), (w / 2, 0, 0.015, l), (-w / 2, 0, 0.015, l)]
            as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let geometry = SCNBox(width: width, height: h, length: length, chamferRadius: 0.004)
            geometry.materials = [wall]
            node.addChildNode(at(SCNNode(geometry: geometry), x, h / 2, z))
        }
        // ふち
        for (x, z, width, length) in [(0, l / 2, w + 0.02, 0.03), (0, -l / 2, w + 0.02, 0.03), (w / 2, 0, 0.03, l), (-w / 2, 0, 0.03, l)]
            as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            node.addChildNode(at(box(width, 0.025, length, color, chamfer: 0.008), x, h, z))
        }
        // 取っ手（ねかせてある）
        let handleColor = UIColor(white: 0.25, alpha: 1)
        for z in [-l / 2 + 0.02, l / 2 - 0.02] {
            node.addChildNode(at(box(w * 0.6, 0.02, 0.025, handleColor, chamfer: 0.008), 0, h + 0.03, z))
        }
        return node
    }

    /// かごの側面（四角い穴の並び）
    private static func basketWallImage(_ color: UIColor) -> UIImage {
        let key = "basket-wall|\(color)"
        if let cached = imageCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
            color.darker(0.25).setFill()
            for row in 0..<2 {
                for column in 0..<6 {
                    UIBezierPath(roundedRect: CGRect(x: 6 + CGFloat(column) * 20, y: 12 + CGFloat(row) * 22, width: 14, height: 14),
                                 cornerRadius: 3).fill()
                }
            }
        }
        imageCache[key] = image
        return image
    }

    /// しま模様（果物売り場のひさし）
    private static func stripeImage(_ color: UIColor) -> UIImage {
        let key = "stripe|\(color)"
        if let cached = imageCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 64)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 64))
            color.setFill()
            for k in 0..<8 where k % 2 == 0 {
                context.fill(CGRect(x: CGFloat(k) * 32, y: 0, width: 32, height: 64))
            }
            // すそのなみなみ
            UIColor.white.setFill()
            for k in 0..<8 {
                UIBezierPath(ovalIn: CGRect(x: CGFloat(k) * 32, y: 54, width: 32, height: 20)).fill()
            }
        }
        imageCache[key] = image
        return image
    }

    /// 運ぶときの箱（商品の色の包み）
    static func packModel(_ product: MartProduct) -> SCNNode {
        let pack = box(0.4, 0.17, 0.3, product.color, chamfer: 0.03)
        pack.addChildNode(at(box(0.41, 0.06, 0.31, product.accent, chamfer: 0.01), 0, 0, 0))
        return pack
    }

    private func makeSupply(_ product: MartProduct) -> SCNNode {
        let node = SCNNode()
        let spot = MartGame.supplySpot(product.rawValue)
        node.addChildNode(Self.at(Self.box(1.0, 0.12, 1.0, UIColor(red: 0.78, green: 0.58, blue: 0.38, alpha: 1)), 0, 0.06, 0))
        // 商品そのものを山に積む（3×3 を、奥ほど高く）。動かないので 1 つにまとめて軽くする
        let pile = SCNNode()
        let layer = CGFloat(CharacterNode.height(product))
        for row in 0..<3 {
            for column in 0..<3 {
                let levels = row == 0 ? 3 : row == 1 ? 2 : 1
                for level in 0..<levels {
                    let item = Self.productModel(product)
                    item.position = SCNVector3(Float(-0.32 + CGFloat(column) * 0.32), Float(0.12 + CGFloat(level) * layer),
                                               Float(-0.32 + CGFloat(row) * 0.32))
                    item.eulerAngles.y = Float((row * 3 + column + level) % 4) * 0.35 - 0.5
                    pile.addChildNode(item)
                }
            }
        }
        node.addChildNode(pile.flattenedClone())
        // 床の受け取る場所
        let zone = Self.decal(Self.zoneImage(product), width: 1.7, length: 1.7)
        zone.position = SCNVector3(0.75, 0.015, 0)
        node.addChildNode(zone)
        let sign = Self.billboard(Self.label(product.icon, size: 60, color: .white, background: product.accent), width: 0.6)
        sign.position = SCNVector3(0, 1.75, 0)
        node.addChildNode(sign)
        node.position = SCNVector3(Float(spot.x - 0.75), 0, Float(spot.y))
        return node
    }

    private static func zoneImage(_ product: MartProduct) -> UIImage {
        let key = "zone|\(product.rawValue)"
        if let cached = imageCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { _ in
            let rect = CGRect(x: 14, y: 14, width: 172, height: 172)
            product.accent.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 30).fill()
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 30)
            border.lineWidth = 8
            product.accent.withAlphaComponent(0.8).setStroke()
            border.stroke()
        }
        imageCache[key] = image
        return image
    }

    // MARK: - 毎コマ

    func sync(_ game: MartGame, dt: Double) {
        let smooth = 1 - Float(exp(-12 * dt))
        if game.floorRect.height != shellDepth {
            buildShell(depth: game.floorRect.height)
            if built {
                burst(at: SCNVector3(Float(game.floorRect.midX), 0.8, Float(MartGame.floor.maxY + 2)))
            }
        }
        // 棚と倉庫の台
        for product in game.unlockedProducts where shelfNodes[product.rawValue] == nil {
            let shelf = makeShelf(product.rawValue)
            let supply = makeSupply(product)
            world.addChildNode(shelf)
            world.addChildNode(supply)
            shelfNodes[product.rawValue] = shelf
            supplyNodes[product.rawValue] = supply
            if built {
                // 解放したばかり：ぽんと出す
                for node in [shelf, supply] {
                    node.scale = SCNVector3(0.01, 0.01, 0.01)
                    let grow = SCNAction.scale(to: 1, duration: 0.45)
                    grow.timingFunction = { t in
                        let s: Float = 1.70158 * 1.4
                        let u = t - 1
                        return u * u * ((s + 1) * u + s) + 1
                    }
                    node.runAction(grow)
                }
                burst(at: SCNVector3(Float(MartGame.shelfRect(product.rawValue).midX), 0.8,
                                     Float(MartGame.shelfRect(product.rawValue).midY)))
            }
        }
        // 棚の商品：増えたら店員の手から飛んでいき、減ったらお客さんの手へ飛ぶ
        var staffHands: [SCNVector3] = playerNodes.map(\.handPosition) + helperNodes.map(\.handPosition)
        if staffHands.isEmpty { staffHands = [SCNVector3(9, 1, 13.5)] }
        for (k, items) in shelfItems {
            let stock = game.stock.indices.contains(k) ? game.stock[k] : 0
            guard let product = MartProduct(rawValue: k) else { continue }
            for (index, item) in items.enumerated() {
                let id = ObjectIdentifier(item)
                let show = index < stock
                if show, item.isHidden, !flying.contains(id) {
                    if built {
                        let slot = item.worldPosition
                        let from = staffHands.min { Self.distance($0, slot) < Self.distance($1, slot) } ?? slot
                        flying.insert(id)
                        flyClone(Self.productModel(product), from: from, to: slot, duration: 0.22) { [weak self] in
                            guard let self else { return }
                            self.flying.remove(id)
                            let current = self.lastStock.indices.contains(k) ? self.lastStock[k] : 0
                            guard index < current else { return }
                            item.isHidden = false
                            item.scale = SCNVector3(0.5, 0.5, 0.5)
                            item.runAction(.scale(to: 1, duration: 0.12))
                        }
                    } else {
                        item.isHidden = false
                    }
                } else if !show, !item.isHidden {
                    item.isHidden = true
                    // お客さんが取った
                    let slot = item.worldPosition
                    let buyer = game.customers.filter { $0.phase == .shopping && $0.product == product }
                        .map { SCNVector3(Float($0.walker.pos.x), 0.9, Float($0.walker.pos.y)) }
                        .min { Self.distance($0, slot) < Self.distance($1, slot) }
                    if let buyer {
                        flyClone(Self.productModel(product), from: slot, to: buyer, duration: 0.25, shrink: true)
                    }
                }
            }
        }
        lastStock = game.stock
        syncPads(game)
        // かご
        for (index, basket) in standBasketNodes.enumerated() where basket.isHidden != (index >= game.standBaskets) {
            basket.isHidden = index >= game.standBaskets
        }
        for (index, basket) in returnBasketNodes.enumerated() where basket.isHidden != (index >= game.returnedBaskets) {
            basket.isHidden = index >= game.returnedBaskets
            if !basket.isHidden, built {
                basket.scale = SCNVector3(0.6, 0.6, 0.6)
                basket.runAction(.scale(to: 1, duration: 0.15))
            }
        }
        // 人
        while playerNodes.count < game.players.count {
            let index = playerNodes.count
            let node = CharacterNode(style: .staff(cap: index == 0 ? UIColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1)
                                                         : UIColor(red: 0.92, green: 0.3, blue: 0.3, alpha: 1)))
            world.addChildNode(node.root)
            playerNodes.append(node)
        }
        while playerNodes.count > game.players.count { playerNodes.removeLast().root.removeFromParentNode() }
        for (index, walker) in game.players.enumerated() {
            let before = lastCarry.indices.contains(index) ? lastCarry[index] : []
            let hand = playerNodes[index].handPosition
            let added = playerNodes[index].update(walker, smooth: index == game.me ? 1 : smooth, dt: dt)
            flyFromSupply(added, carry: walker.carry)
            // ゴミ箱に捨てた商品が、箱へ飛んでいく
            if built, walker.carry.count < before.count, let thrown = before.last,
               hypot(walker.pos.x - MartGame.trashSpot.x, walker.pos.y - MartGame.trashSpot.y) < 1.2 {
                flyClone(Self.productModel(thrown), from: hand,
                         to: SCNVector3(Float(MartGame.trashSpot.x), 0.8, Float(MartGame.trashSpot.y)), duration: 0.22, shrink: true)
            }
        }
        lastCarry = game.players.map(\.carry)
        var seen = Set<UUID>()
        for customer in game.customers {
            seen.insert(customer.id)
            let node: CharacterNode
            if let existing = customerNodes[customer.id] {
                node = existing
            } else {
                node = CharacterNode(style: .customer(customer.shirt))
                node.root.position = SCNVector3(Float(customer.walker.pos.x), 0, Float(customer.walker.pos.y))
                world.addChildNode(node.root)
                customerNodes[customer.id] = node
            }
            node.update(customer.walker, smooth: smooth, dt: dt)
            let stock = game.stock[customer.product.rawValue]
            node.setBasket(customer.basket && customer.phase != .leaving ? customer.got : nil, product: customer.product)
            switch customer.phase {
            case .toBasket:
                node.setBubble(customer.waited > 0.5 ? Self.label("🧺?", size: 56, color: UIColor(white: 0.2, alpha: 1), background: .white)
                               : Self.bubble(product: customer.product, count: customer.want))
            case .toShelf:
                node.setBubble(Self.bubble(product: customer.product, count: customer.want))
            case .shopping:
                node.setBubble(stock == 0 || customer.got < customer.want
                               ? Self.bubble(product: customer.product, count: customer.want - customer.got) : nil)
            case .toQueue, .queued:
                node.setBubble(Self.bubble(product: nil, count: 0))
            case .leaving:
                node.setBubble(nil)
                if !customer.angry { node.setBag(customer.product) }
                if !leavingCustomers.contains(customer.id) {
                    leavingCustomers.insert(customer.id)
                    // 買えてうれしい・待たされて怒った
                    let face = customer.angry ? "😡" : ["😊", "😍", "🥰", "👍"][customer.shirt % 4]
                    floatText(face, at: SCNVector3(node.root.position.x, 2.0, node.root.position.z))
                }
            }
        }
        for (id, node) in customerNodes where !seen.contains(id) {
            node.root.removeFromParentNode()
            customerNodes[id] = nil
            leavingCustomers.remove(id)
        }
        while helperNodes.count < game.helpers.count {
            let node = CharacterNode(style: .helper)
            world.addChildNode(node.root)
            helperNodes.append(node)
        }
        for (index, helper) in game.helpers.enumerated() {
            let added = helperNodes[index].update(helper.walker, smooth: smooth, dt: dt)
            flyFromSupply(added, carry: helper.walker.carry)
        }
        // 歩くと足もとに土ぼこり
        dustTimer -= dt
        if dustTimer <= 0 {
            dustTimer = 0.11
            for (index, walker) in game.players.enumerated() where walker.moving && playerNodes.indices.contains(index) {
                puff(at: playerNodes[index].root.position)
            }
        }
        // 自動ドア：人が近づくと開く
        let door = MartGame.door
        let near = (game.players.map(\.pos) + game.customers.map(\.walker.pos)).contains { hypot($0.x - door.x - 0.4, $0.y - door.y) < 1.9 }
        doorOpen += ((near ? 1 : 0) - doorOpen) * Float(min(1, dt * 8))
        for (panel, z) in doorPanels {
            panel.position.z = z + (z < Float(MartGame.door.y) ? -1 : 1) * doorOpen * 1.05
        }
        if game.hasCashier, cashierNode == nil {
            let node = CharacterNode(style: .helper)
            world.addChildNode(node.root)
            cashierNode = node
        }
        cashierNode?.update(MartWalker(pos: MartGame.cashierSpot, heading: .pi), smooth: 1)

        // お金
        // たまった額に合わせて札束を出す（¥1,500 で 1 束）
        let bundles = game.cash > 0 ? min(game.cash / 1_500 + 1, cashBills.count) : 0
        for (index, bundle) in cashBills.enumerated() where bundle.isHidden != (index >= bundles) {
            bundle.isHidden = index >= bundles
            if !bundle.isHidden, built {
                bundle.scale = SCNVector3(1.3, 0.4, 1.3)
                bundle.runAction(.scale(to: 1, duration: 0.18))
            }
        }
        if game.cash > lastCash {
            let earned = game.cash - lastCash
            floatText("+" + MartYen.text(earned), at: SCNVector3(Float(MartGame.counter.midX), 1.6, Float(MartGame.counter.midY)))
            // お客さんの払ったお金（硬貨とお札）が、レジ横の山へ飛ぶ
            let from = SCNVector3(Float(MartGame.serveSpot.x), 1.0, Float(MartGame.serveSpot.y))
            let to = SCNVector3(Float(MartGame.cashSpot.x), 0.5, Float(MartGame.cashSpot.y))
            for k in 0..<min(2 + earned / 300, 6) {
                let delay = Double(k) * 0.05
                let node = k % 3 == 2 ? Self.billNode(kind: 1) : Self.coinNode()
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.flyClone(node, from: from, to: Self.jitter(to, 0.3), duration: 0.32)
                }
            }
        }
        billTimer -= dt
        let mePos = game.players.indices.contains(game.me) ? game.players[game.me].pos : .zero
        if game.money > lastMoney, billTimer <= 0 {
            // 拾ったお金が店員に飛んでくる
            flyBill(from: Self.jitter(SCNVector3(Float(MartGame.cashSpot.x), 0.5, Float(MartGame.cashSpot.y)), 0.35),
                    to: SCNVector3(Float(mePos.x), 1.1, Float(mePos.y)), bundle: game.money - lastMoney >= 600)
            billTimer = 0.022
        } else if game.money < lastMoney, billTimer <= 0, let pad = game.visibleSteps.first(where: {
            hypot($0.1.pos.x - mePos.x, $0.1.pos.y - mePos.y) < 0.9
        }) {
            // 払ったお金がマークに飛んでいく
            flyBill(from: SCNVector3(Float(mePos.x), 1.0, Float(mePos.y)),
                    to: SCNVector3(Float(pad.1.pos.x), 0.1, Float(pad.1.pos.y)))
            billTimer = 0.04
        }
        lastMoney = game.money
        lastCash = game.cash
        // 解放したとき
        if built, game.done != lastDone {
            for index in game.done.subtracting(lastDone) where MartGame.steps.indices.contains(index) {
                let pos = MartGame.steps[index].pos
                burst(at: SCNVector3(Float(pos.x), 0.5, Float(pos.y)))
            }
        }
        lastDone = game.done
        // 会計の合図
        if game.serving > 0 {
            servingRing.isHidden = false
            servingRing.position = SCNVector3(Float(MartGame.serveSpot.x), 2.2 + Float(game.serving) * 0.3, Float(MartGame.serveSpot.y))
            servingRing.opacity = CGFloat(0.4 + game.serving * 0.6)
        } else {
            servingRing.isHidden = true
        }
        // MAX
        if game.players.indices.contains(game.me), game.players[game.me].carry.count >= game.capacity {
            maxLabel.isHidden = false
            let p = playerNodes[game.me].root.position
            maxLabel.position = SCNVector3(p.x, 1.6 + Float(game.capacity) * 0.18 + 0.5, p.z)
        } else {
            maxLabel.isHidden = true
        }
        updateArrow(game)
        // カメラは自分の店員を追う
        if let mine = playerNodes.indices.contains(game.me) ? playerNodes[game.me] : nil {
            let p = mine.root.position
            let follow = 1 - Float(exp(-6 * dt))
            target.x += (p.x - target.x) * follow
            target.z += (p.z - target.z) * follow
            moveCamera(to: target)
        }
        built = true
    }

    private func syncPads(_ game: MartGame) {
        let visible = Dictionary(uniqueKeysWithValues: game.visibleSteps.map { ($0.0, $0.1) })
        for (index, pad) in padNodes where visible[index] == nil {
            pad.root.removeFromParentNode()
            padNodes[index] = nil
            ghostNodes[index]?.removeFromParentNode()
            ghostNodes[index] = nil
        }
        for (index, step) in visible {
            let pad: PadNode
            if let existing = padNodes[index] {
                pad = existing
            } else {
                pad = PadNode(step: step)
                world.addChildNode(pad.root)
                padNodes[index] = pad
                if case .shelf(let k) = step.kind {
                    // これから建つ棚の、うすい影
                    let ghost = makeGhost(k)
                    world.addChildNode(ghost)
                    ghostNodes[index] = ghost
                }
            }
            pad.update(paid: game.paidAmount(index))
        }
    }

    private func makeGhost(_ k: Int) -> SCNNode {
        let rect = MartGame.shelfRect(k)
        let node = Self.box(rect.width, 0.5, rect.height, UIColor(white: 1, alpha: 0.25), chamfer: 0.04)
        node.position = SCNVector3(Float(rect.midX), 0.25, Float(rect.midY))
        node.castsShadow = false
        return node
    }

    /// 次にすることの上に矢印を出す（はじめのうちだけ）
    private func updateArrow(_ game: MartGame) {
        guard game.players.indices.contains(game.me) else {
            arrow.isHidden = true
            return
        }
        let me = game.players[game.me]
        var point: CGPoint?
        // かごが足りないときは、いつでも案内する
        if me.baskets > 0 {
            point = MartGame.basketStand
        } else if game.standBaskets == 0, game.returnedBaskets > 0, me.carry.isEmpty {
            point = MartGame.basketReturn
        } else if game.level >= 4 {
            point = nil
        } else if game.cash >= 10 {
            point = MartGame.cashSpot
        } else if let pad = game.visibleSteps.first, game.money >= pad.1.cost - game.paidAmount(pad.0) {
            point = pad.1.pos
        } else if !me.carry.isEmpty, let product = me.carry.last,
                  game.stock[product.rawValue] < MartGame.shelfCapacity {
            point = MartGame.shelfFront(product.rawValue)
        } else if game.customers.contains(where: { $0.phase == .queued }) && !game.hasCashier {
            point = MartGame.cashierSpot
        } else if me.carry.isEmpty, let product = game.unlockedProducts.min(by: { game.stock[$0.rawValue] < game.stock[$1.rawValue] }),
                  game.stock[product.rawValue] < MartGame.shelfCapacity {
            point = MartGame.supplySpot(product.rawValue)
        }
        guard let point, hypot(point.x - me.pos.x, point.y - me.pos.y) > 1.0 else {
            arrow.isHidden = true
            return
        }
        arrow.isHidden = false
        arrow.position.x = Float(point.x)
        arrow.position.z = Float(point.y)
        if arrow.position.y < 1.5 || arrow.position.y > 3 { arrow.position.y = 2.2 }
    }

    // MARK: - 演出

    static func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// 受け取った商品が、倉庫の台から手の上へ飛んでくる
    private func flyFromSupply(_ added: [SCNNode], carry: [MartProduct]) {
        guard built else {
            added.forEach { $0.isHidden = false }
            return
        }
        for pack in added {
            let index = Int(pack.name ?? "") ?? 0
            guard carry.indices.contains(index) else {
                pack.isHidden = false
                continue
            }
            let product = carry[index]
            let spot = MartGame.supplySpot(product.rawValue)
            let from = SCNVector3(Float(spot.x - 0.75), 0.9, Float(spot.y))
            flyClone(Self.productModel(product), from: from, to: pack.worldPosition, duration: 0.2) {
                pack.isHidden = false
                pack.scale = SCNVector3(1.2, 0.8, 1.2)
                pack.runAction(.scale(to: 1, duration: 0.1))
            }
        }
    }

    /// 物を放物線で飛ばす（着いたら消して completion）
    private func flyClone(_ node: SCNNode, from start: SCNVector3, to end: SCNVector3, duration: Double, shrink: Bool = false,
                          completion: (() -> Void)? = nil) {
        node.position = start
        node.castsShadow = false
        world.addChildNode(node)
        let mid = SCNVector3((start.x + end.x) / 2, max(start.y, end.y) + 0.9, (start.z + end.z) / 2)
        let up = SCNAction.move(to: mid, duration: duration / 2)
        up.timingMode = .easeOut
        let down = SCNAction.move(to: end, duration: duration / 2)
        down.timingMode = .easeIn
        var actions: [SCNAction] = [.sequence([up, down]), .rotateBy(x: 0, y: 2.5, z: 0, duration: duration)]
        if shrink { actions.append(.scale(to: 0.3, duration: duration)) }
        node.runAction(.group(actions)) {
            node.removeFromParentNode()
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    /// 足もとの土ぼこり
    private func puff(at position: SCNVector3) {
        let dust = Self.sphere(0.09, UIColor(white: 1, alpha: 0.85))
        dust.castsShadow = false
        dust.position = SCNVector3(position.x + Float.random(in: -0.08...0.08), 0.06, position.z + Float.random(in: -0.08...0.08))
        world.addChildNode(dust)
        dust.runAction(.sequence([.group([.scale(to: 2.2, duration: 0.4), .fadeOut(duration: 0.4),
                                          .moveBy(x: 0, y: 0.15, z: 0, duration: 0.4)]), .removeFromParentNode()]))
    }

    static func jitter(_ point: SCNVector3, _ amount: Float) -> SCNVector3 {
        SCNVector3(point.x + Float.random(in: -amount...amount), point.y, point.z + Float.random(in: -amount...amount))
    }

    /// お札（または札束）が放物線で飛ぶ。くるくる回りながら
    private func flyBill(from start: SCNVector3, to end: SCNVector3, bundle: Bool = false) {
        let bill = bundle ? Self.bundleNode(kind: Int.random(in: 0...1)) : Self.billNode(kind: Int.random(in: 0...3) == 0 ? 1 : 0)
        bill.position = start
        bill.castsShadow = false
        bill.eulerAngles.y = Float.random(in: 0...(2 * .pi))
        world.addChildNode(bill)
        let mid = SCNVector3((start.x + end.x) / 2, max(start.y, end.y) + 1.3, (start.z + end.z) / 2)
        let up = SCNAction.move(to: mid, duration: 0.17)
        up.timingMode = .easeOut
        let down = SCNAction.move(to: end, duration: 0.17)
        down.timingMode = .easeIn
        bill.runAction(.group([.sequence([up, down]), .rotateBy(x: CGFloat.random(in: -2...2), y: 4, z: CGFloat.random(in: -1...1), duration: 0.34),
                               .sequence([.wait(duration: 0.26), .scale(to: 0.4, duration: 0.08)])])) {
            bill.removeFromParentNode()
        }
    }

    private func floatText(_ text: String, at position: SCNVector3) {
        let node = Self.billboard(Self.label(text, size: 60, color: UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1)),
                                  width: text.hasPrefix("+") ? 1.4 : 0.9)
        node.position = position
        world.addChildNode(node)
        node.runAction(.group([.moveBy(x: 0, y: 1.0, z: 0, duration: 0.9), .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.4)])])) {
            node.removeFromParentNode()
        }
    }

    /// 紙吹雪
    private func burst(at position: SCNVector3) {
        let particles = SCNParticleSystem()
        particles.birthRate = 600
        particles.emissionDuration = 0.12
        particles.loops = false
        particles.particleLifeSpan = 1.4
        particles.particleVelocity = 6
        particles.particleVelocityVariation = 3
        particles.emittingDirection = SCNVector3(0, 1, 0)
        particles.spreadingAngle = 50
        particles.acceleration = SCNVector3(0, -9, 0)
        particles.particleSize = 0.08
        particles.particleSizeVariation = 0.04
        particles.particleColor = UIColor(red: 1, green: 0.7, blue: 0.2, alpha: 1)
        particles.particleColorVariation = SCNVector4(1, 0.4, 0.3, 0)
        particles.particleAngularVelocity = 400
        particles.particleAngularVelocityVariation = 300
        particles.isLightingEnabled = false
        let node = SCNNode()
        node.position = position
        node.addParticleSystem(particles)
        world.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 2), .removeFromParentNode()]))
    }
}

// MARK: - 人

/// 人の 3D：すらっとした体、歩くと足と腕が振れて体が少し前に傾く。
/// 運ぶ商品は、商品そのもの（缶・袋・カップ…）をお盆にのせて積み、上に「ジュース ×3」の札を出す
@MainActor
final class CharacterNode {
    enum Style {
        case staff(cap: UIColor)
        case helper
        case customer(Int)
    }

    let root = SCNNode()
    private let pivot = SCNNode()
    private let lean = SCNNode()
    private let body: SCNNode
    private let leftLeg = SCNNode()
    private let rightLeg = SCNNode()
    private let leftArm = SCNNode()
    private let rightArm = SCNNode()
    private let stack = SCNNode()
    private let tray: SCNNode
    private var stackKey: [MartProduct] = []
    private var stackTop: Float = 0
    private var carryLabel: SCNNode?
    private var bubbleNode: SCNNode?
    private var bubbleImage: UIImage?
    private var bag: SCNNode?
    private var heldBasket: SCNNode?
    private var heldKey = -1
    private let basketStack = SCNNode()
    private var basketCount = 0
    private var stride: Float = 0
    private let showsLabel: Bool

    /// 係（品出し・レジ）の制服の色
    static let helperColor = UIColor(red: 0.18, green: 0.7, blue: 0.45, alpha: 1)

    /// お客さんの服：店員の青・赤・緑とまぎれない、落ち着いた私服の色
    private static let customerColors: [UIColor] = [
        UIColor(red: 0.93, green: 0.86, blue: 0.72, alpha: 1), UIColor(red: 0.95, green: 0.72, blue: 0.78, alpha: 1),
        UIColor(red: 0.74, green: 0.66, blue: 0.88, alpha: 1), UIColor(red: 0.98, green: 0.84, blue: 0.45, alpha: 1),
        UIColor(red: 0.6, green: 0.48, blue: 0.4, alpha: 1), UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1),
        UIColor(red: 0.98, green: 0.66, blue: 0.5, alpha: 1), UIColor(red: 0.55, green: 0.56, blue: 0.6, alpha: 1),
    ]

    /// 積むときの、商品 1 つぶんの高さ
    static func height(_ product: MartProduct) -> Float {
        switch product {
        case .soda: return 0.43
        case .snack: return 0.43
        case .noodle: return 0.3
        case .sandwich: return 0.27
        case .fruit: return 0.28
        case .toy: return 0.48
        case .bread: return 0.27
        case .milk: return 0.42
        case .iceCream: return 0.53
        case .flower: return 0.42
        case .cake: return 0.3
        case .game: return 0.3
        }
    }

    init(style: Style) {
        let skin = UIColor(red: 0.97, green: 0.84, blue: 0.72, alpha: 1)
        let shirt: UIColor
        let pants: UIColor
        switch style {
        case .staff(let cap):
            // 店員は帽子と同じ色のはっきりした制服
            shirt = cap
            pants = UIColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
        case .helper:
            shirt = Self.helperColor
            pants = UIColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
        case .customer(let index):
            shirt = Self.customerColors[index % Self.customerColors.count]
            pants = [UIColor(red: 0.27, green: 0.31, blue: 0.42, alpha: 1), UIColor(red: 0.4, green: 0.36, blue: 0.33, alpha: 1),
                     UIColor(white: 0.32, alpha: 1)][index % 3]
        }
        showsLabel = { if case .customer = style { return false } else { return true } }()
        body = MartScene.capsule(0.165, 0.64, shirt)
        tray = MartScene.box(0.44, 0.03, 0.34, UIColor(white: 0.97, alpha: 1), chamfer: 0.012)
        root.addChildNode(pivot)
        pivot.addChildNode(lean)
        // 足（腰を軸に振る）
        for (leg, z) in [(leftLeg, Float(-0.075)), (rightLeg, Float(0.075))] {
            leg.position = SCNVector3(0, 0.44, z)
            let shape = MartScene.capsule(0.06, 0.44, pants)
            shape.position = SCNVector3(0, -0.22, 0)
            leg.addChildNode(shape)
            let shoe = MartScene.box(0.17, 0.06, 0.1, UIColor(white: 0.16, alpha: 1), chamfer: 0.03)
            shoe.position = SCNVector3(0.035, -0.42, 0)
            leg.addChildNode(shoe)
            pivot.addChildNode(leg)
        }
        // 体と頭
        body.position = SCNVector3(0, 0.76, 0)
        lean.addChildNode(body)
        let neck = MartScene.cylinder(0.05, 0.08, skin)
        neck.position = SCNVector3(0, 0.33, 0)
        body.addChildNode(neck)
        let head = MartScene.sphere(0.155, skin)
        head.position = SCNVector3(0, 0.46, 0)
        body.addChildNode(head)
        // 腕（肩を軸に振る。運ぶときは前に出す）
        for (arm, z) in [(leftArm, Float(-0.2)), (rightArm, Float(0.2))] {
            arm.position = SCNVector3(0, 0.2, z)
            let shape = MartScene.capsule(0.048, 0.36, shirt)
            shape.position = SCNVector3(0, -0.17, 0)
            shape.addChildNode(MartScene.at(MartScene.sphere(0.05, skin), 0, -0.19, 0))
            arm.addChildNode(shape)
            body.addChildNode(arm)
        }
        switch style {
        case .staff(let cap):
            let crown = MartScene.sphere(0.162, cap)
            crown.scale = SCNVector3(1, 0.6, 1)
            crown.position = SCNVector3(0, 0.53, 0)
            body.addChildNode(crown)
            let brim = MartScene.cylinder(0.11, 0.025, cap)
            brim.scale = SCNVector3(1.5, 1, 1.1)
            brim.position = SCNVector3(0.14, 0.5, 0)
            body.addChildNode(brim)
            let apron = MartScene.box(0.04, 0.42, 0.26, UIColor(white: 0.97, alpha: 1), chamfer: 0.015)
            apron.position = SCNVector3(0.155, -0.08, 0)
            body.addChildNode(apron)
            // 足もとの輪（自分・仲間を見分ける）
            let ring = MartScene.decal(MartScene.ringImage(cap), width: 0.95, length: 0.95)
            ring.position = SCNVector3(0, 0.03, 0)
            root.addChildNode(ring)
            ring.runAction(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.6), .scale(to: 1, duration: 0.6)])))
        case .helper:
            let crown = MartScene.sphere(0.162, Self.helperColor.darker(0.08))
            crown.scale = SCNVector3(1, 0.6, 1)
            crown.position = SCNVector3(0, 0.53, 0)
            body.addChildNode(crown)
            let brim = MartScene.cylinder(0.11, 0.025, Self.helperColor.darker(0.08))
            brim.scale = SCNVector3(1.5, 1, 1.1)
            brim.position = SCNVector3(0.14, 0.5, 0)
            body.addChildNode(brim)
            let apron = MartScene.box(0.04, 0.42, 0.26, UIColor(white: 0.97, alpha: 1), chamfer: 0.015)
            apron.position = SCNVector3(0.155, -0.08, 0)
            body.addChildNode(apron)
            let ring = MartScene.decal(MartScene.ringImage(Self.helperColor), width: 0.8, length: 0.8)
            ring.position = SCNVector3(0, 0.03, 0)
            root.addChildNode(ring)
        case .customer(let index):
            let hairColors: [UIColor] = [UIColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1), UIColor(red: 0.1, green: 0.09, blue: 0.09, alpha: 1),
                                         UIColor(red: 0.8, green: 0.62, blue: 0.32, alpha: 1), UIColor(red: 0.5, green: 0.28, blue: 0.17, alpha: 1)]
            let hair = MartScene.sphere(0.164, hairColors[index % hairColors.count])
            hair.scale = SCNVector3(1, 0.68, 1)
            hair.position = SCNVector3(-0.025, 0.53, 0)
            body.addChildNode(hair)
            if index % 3 == 1 {
                let back = MartScene.box(0.09, 0.26, 0.27, hairColors[index % hairColors.count], chamfer: 0.045)
                back.position = SCNVector3(-0.12, 0.4, 0)
                body.addChildNode(back)
            }
        }
        // 運ぶ商品をのせるお盆
        tray.isHidden = true
        stack.addChildNode(tray)
        stack.position = SCNVector3(0.38, 0.9, 0)
        pivot.addChildNode(stack)
        stack.addChildNode(basketStack)
    }

    /// 動かす。smooth は位置を追いかける割合、dt はコマの長さ。増えた商品（隠してある）を返す
    @discardableResult
    func update(_ walker: MartWalker, smooth: Float, dt: Double = 1.0 / 60) -> [SCNNode] {
        let target = SCNVector3(Float(walker.pos.x), 0, Float(walker.pos.y))
        root.position.x += (target.x - root.position.x) * smooth
        root.position.z += (target.z - root.position.z) * smooth
        // 向き（なめらかに回す）
        let want = -Float(walker.heading)
        var diff = want - pivot.eulerAngles.y
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        pivot.eulerAngles.y += diff * (1 - Float(exp(-14 * dt)))
        // 歩く動き（止まるときもすっと収める）
        stride += ((walker.moving ? 1 : 0) - stride) * (1 - Float(exp(-10 * dt)))
        let phase = Float(walker.step) * 7.5
        let swing = sin(phase) * 0.55 * stride
        leftLeg.eulerAngles.z = swing
        rightLeg.eulerAngles.z = -swing
        body.position.y = 0.76 + abs(sin(phase)) * 0.035 * stride
        lean.eulerAngles.z = -0.08 * stride
        let carrying = !walker.carry.isEmpty || walker.baskets > 0
        if walker.baskets != basketCount {
            // 返しに行くかごを、重ねて抱える
            basketCount = walker.baskets
            basketStack.childNodes.forEach { $0.removeFromParentNode() }
            for index in 0..<min(basketCount, 12) {
                let basket = MartScene.basketModel()
                basket.eulerAngles.y = .pi / 2
                basket.position = SCNVector3(0, Float(index) * 0.06, 0)
                basketStack.addChildNode(basket)
            }
        }
        let armTarget: Float = carrying ? -1.35 : 0
        for (arm, sign) in [(leftArm, Float(-1)), (rightArm, Float(1))] {
            let walkSwing = carrying ? 0 : sin(phase) * 0.5 * stride * sign
            arm.eulerAngles.z += (armTarget + walkSwing - arm.eulerAngles.z) * (1 - Float(exp(-16 * dt)))
        }
        // 運んでいる商品
        var added: [SCNNode] = []
        if walker.carry != stackKey {
            if walker.carry.count > stackKey.count, Array(walker.carry.prefix(stackKey.count)) == stackKey {
                for index in stackKey.count..<walker.carry.count {
                    let item = MartScene.productModel(walker.carry[index])
                    item.position = SCNVector3(0, 0.02 + stackTop, 0)
                    stackTop += Self.height(walker.carry[index])
                    item.name = "\(index)"
                    item.isHidden = true
                    stack.addChildNode(item)
                    added.append(item)
                }
            } else {
                stack.childNodes.filter { $0 !== tray && $0 !== basketStack }.forEach { $0.removeFromParentNode() }
                stackTop = 0
                for (index, product) in walker.carry.enumerated() {
                    let item = MartScene.productModel(product)
                    item.position = SCNVector3(0, 0.02 + stackTop, 0)
                    stackTop += Self.height(product)
                    item.name = "\(index)"
                    stack.addChildNode(item)
                }
            }
            stackKey = walker.carry
            tray.isHidden = walker.carry.isEmpty
            // 何を持っているかの札
            carryLabel?.removeFromParentNode()
            carryLabel = nil
            if showsLabel, !walker.carry.isEmpty {
                let label = MartScene.billboard(MartScene.carryImage(walker.carry), width: 1.1)
                label.position = SCNVector3(0, stackTop + 0.35, 0)
                stack.addChildNode(label)
                carryLabel = label
            }
        }
        // 歩くと積んだ商品が少しゆれる
        stack.eulerAngles.x = sin(phase * 0.5) * 0.04 * stride
        return added
    }

    /// 手の上（積んだ商品のいちばん上）の場所
    var handPosition: SCNVector3 {
        stack.convertPosition(SCNVector3(0, stackTop, 0), to: nil)
    }

    func setBubble(_ image: UIImage?) {
        guard image !== bubbleImage else { return }
        bubbleImage = image
        bubbleNode?.removeFromParentNode()
        bubbleNode = nil
        guard let image else { return }
        let node = MartScene.billboard(image, width: 0.72)
        node.position = SCNVector3(0, 1.85, 0)
        root.addChildNode(node)
        bubbleNode = node
        node.scale = SCNVector3(0.4, 0.4, 0.4)
        node.runAction(.scale(to: 1, duration: 0.15))
    }

    /// お客さんが手に下げるかご（nil で消す）。中に買った商品が入る
    func setBasket(_ count: Int?, product: MartProduct) {
        let key = count ?? -1
        guard key != heldKey else { return }
        heldKey = key
        heldBasket?.removeFromParentNode()
        heldBasket = nil
        guard let count else { return }
        let basket = MartScene.basketModel()
        basket.scale = SCNVector3(0.8, 0.8, 0.8)
        for index in 0..<min(count, 4) {
            let item = MartScene.productModel(product)
            item.scale = SCNVector3(0.6, 0.6, 0.6)
            item.position = SCNVector3(Float(index % 2) * 0.18 - 0.09, 0.03 + Float(index / 2) * 0.1, Float(index % 2) * 0.04 - 0.02)
            basket.addChildNode(item)
        }
        basket.position = SCNVector3(0.02, 0.36, 0.3)
        basket.eulerAngles.y = .pi / 2
        pivot.addChildNode(basket)
        heldBasket = basket
    }

    func setBag(_ product: MartProduct) {
        guard bag == nil else { return }
        let node = MartScene.box(0.28, 0.32, 0.12, UIColor(white: 0.97, alpha: 1), chamfer: 0.035)
        node.addChildNode(MartScene.at(MartScene.productModel(product), 0, 0.1, 0))
        node.position = SCNVector3(0.05, 0.6, 0.27)
        pivot.addChildNode(node)
        bag = node
    }
}

/// 解放マーク：床の点線の板と、払った分だけ伸びる緑の帯
@MainActor
final class PadNode {
    let root = SCNNode()
    private let step: MartStep
    private let board: SCNNode
    private let fill: SCNNode
    private var shownRemaining = -1
    private let size: CGSize

    init(step: MartStep) {
        self.step = step
        if case .shelf(let k) = step.kind {
            let rect = MartGame.shelfRect(k)
            size = CGSize(width: rect.width + 0.5, height: rect.height + 0.9)
            root.position = SCNVector3(Float(rect.midX), 0.02, Float(rect.midY + 0.2))
        } else {
            size = CGSize(width: 2.0, height: 2.0)
            root.position = SCNVector3(Float(step.pos.x), 0.02, Float(step.pos.y))
        }
        let fillPlane = SCNPlane(width: size.width - 0.12, height: size.height - 0.12)
        fillPlane.cornerRadius = 0.12
        fillPlane.materials = [MartScene.material(UIColor(red: 0.35, green: 0.82, blue: 0.4, alpha: 0.75))]
        fill = SCNNode(geometry: fillPlane)
        fill.eulerAngles.x = -.pi / 2
        fill.renderingOrder = 4
        fill.scale = SCNVector3(1, 0.001, 1)
        root.addChildNode(fill)
        board = SCNNode()
        root.addChildNode(board)
        root.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.75, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)])))
    }

    func update(paid: Int) {
        let remaining = step.cost - paid
        guard remaining != shownRemaining else { return }
        shownRemaining = remaining
        let image = MartScene.padImage(step, remaining: remaining,
                                       pixels: CGSize(width: size.width * 160, height: size.height * 160))
        board.childNodes.forEach { $0.removeFromParentNode() }
        board.addChildNode(MartScene.decal(image, width: size.width, length: size.height))
        // 手前から奥へ、払った分だけ緑にする
        let fraction = max(Float(paid) / Float(step.cost), 0.001)
        fill.scale = SCNVector3(1, fraction, 1)
        fill.position = SCNVector3(0, 0.005, Float(size.height - 0.12) * (1 - fraction) / 2)
    }
}

private extension UIColor {
    func darker(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(r - amount, 0), green: max(g - amount, 0), blue: max(b - amount, 0), alpha: a)
    }
}

private extension UIFont {
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
