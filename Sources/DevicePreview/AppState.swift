import AppKit
import SwiftUI
import WebKit

@MainActor
final class AppState: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case independent, mirror
        var id: String { rawValue }
        var label: String { self == .independent ? "개별 조작" : "미러 조작" }
    }

    private let defaults = UserDefaults.standard

    @Published var urlString: String
    @Published var enabledIDs: Set<String> { didSet { defaults.set(Array(enabledIDs), forKey: "enabled") } }
    @Published var rotatedIDs: Set<String> {
        didSet {
            defaults.set(Array(rotatedIDs), forKey: "rotated")
            models.values.forEach(applyZoom)
        }
    }
    @Published var scale: Double {
        didSet {
            defaults.set(scale, forKey: "scale")
            models.values.forEach(applyZoom)
        }
    }
    @Published var mode: Mode {
        didSet {
            defaults.set(mode.rawValue, forKey: "mode")
            activeID = nil
        }
    }
    /// 기기 안 브라우저 확대(Chrome/Safari 의 페이지 확대와 같음). 1 이면 100%.
    /// 확대하면 같은 화면 안에서 CSS 뷰포트가 좁아진다 (예: 344px 에서 125% → 275px)
    @Published var browserZoom: Double {
        didSet {
            defaults.set(browserZoom, forKey: "browserZoom")
            models.values.forEach(applyZoom)
        }
    }
    /// 기기별 브라우저 확대. 없으면 browserZoom 을 따른다
    @Published var zoomByID: [String: Double] {
        didSet {
            defaults.set(zoomByID, forKey: "zoomByID")
            models.values.forEach(applyZoom)
        }
    }
    static let zoomLevels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2]
    static let scaleRange: ClosedRange<Double> = 0.25...1.5

    @Published var activeID: String?
    @Published var breakpointsText: String { didSet { defaults.set(breakpointsText, forKey: "breakpoints") } }
    /// ⌘L 로 주소창에 포커스를 주기 위한 신호
    @Published var focusURLToken = 0

    private(set) var models: [String: DeviceModel] = [:]
    private var lastInputAt = Date.distantPast

    init() {
        let argURL = CommandLine.arguments.dropFirst().first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        urlString = argURL ?? defaults.string(forKey: "url") ?? "http://localhost:5173"
        enabledIDs = Set(defaults.stringArray(forKey: "enabled") ?? Array(Device.defaultEnabled))
        rotatedIDs = Set(defaults.stringArray(forKey: "rotated") ?? [])
        let s = defaults.double(forKey: "scale")
        scale = s == 0 ? 0.6 : s
        let z = defaults.double(forKey: "browserZoom")
        browserZoom = z == 0 ? 1 : z
        zoomByID = defaults.dictionary(forKey: "zoomByID") as? [String: Double] ?? [:]
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .independent
        breakpointsText = defaults.string(forKey: "breakpoints") ?? ""
    }

    var enabledDevices: [Device] { Device.all.filter { enabledIDs.contains($0.id) } }

    func model(for device: Device) -> DeviceModel {
        if let m = models[device.id] { return m }
        let m = DeviceModel(device: device, state: self)
        models[device.id] = m
        applyZoom(m)
        if let url = normalizedURL { m.webView.load(URLRequest(url: url)) }
        return m
    }

    func size(of device: Device) -> CGSize {
        rotatedIDs.contains(device.id)
            ? CGSize(width: device.height, height: device.width)
            : CGSize(width: device.width, height: device.height)
    }

    func browserZoom(of device: Device) -> Double { zoomByID[device.id] ?? browserZoom }

    /// 페이지가 보게 될 CSS 뷰포트. 브라우저 확대가 100% 가 아니면 기기 크기보다 좁아진다
    func viewport(of device: Device) -> CGSize {
        let css = size(of: device), z = browserZoom(of: device)
        return CGSize(width: (css.width / z).rounded(), height: (css.height / z).rounded())
    }

    /// 화면에 그릴 프레임(정수 pt)과 WKWebView 에 줄 pageZoom.
    /// - 프레임 크기는 「보기 배율」만 따른다 (기기 크기 × scale)
    /// - pageZoom = 보기 배율 × 브라우저 확대 → 프레임 안의 CSS 뷰포트가 viewport(of:) 가 된다
    /// WebKit 은 프레임을 정수 pt 로 다루므로 w*scale 을 그대로 쓰면 innerWidth 가 1~2px 모자란다.
    func layout(of device: Device) -> (frame: CGSize, zoom: Double) {
        let css = size(of: device), vp = viewport(of: device)
        let fw = (css.width * scale).rounded(.up)
        let zoom = Double(fw) / (Double(vp.width) + 0.25)
        let fh = ((vp.height + 0.25) * zoom).rounded(.up)
        return (CGSize(width: fw, height: fh), zoom)
    }

    func setBrowserZoom(_ z: Double?, for id: String) {
        if let z, z != browserZoom { zoomByID[id] = z } else { zoomByID.removeValue(forKey: id) }
    }

    func stepBrowserZoom(_ dir: Int) {
        let levels = Self.zoomLevels
        if dir == 0 { browserZoom = 1; zoomByID = [:]; return }
        let i = levels.firstIndex { $0 >= browserZoom - 0.001 } ?? levels.count - 1
        let cur = abs(levels[i] - browserZoom) < 0.001 ? i : (dir > 0 ? i - 1 : i)
        browserZoom = levels[min(max(cur + dir, 0), levels.count - 1)]
    }

    func stepScale(_ dir: Int) {
        scale = min(max(((scale + 0.05 * Double(dir)) * 20).rounded() / 20, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    private func applyZoom(_ m: DeviceModel) {
        m.webView.pageZoom = layout(of: m.device).zoom
    }

    // MARK: - 브레이크포인트

    var breakpoints: [Int] {
        breakpointsText
            .split(whereSeparator: { ",; ".contains($0) })
            .compactMap { Int($0) }
            .sorted()
    }

    /// (라벨, 구간 번호). 브레이크포인트가 없으면 nil
    func breakpointBadge(width: Int) -> (String, Int)? {
        let bps = breakpoints
        guard !bps.isEmpty else { return nil }
        if let i = bps.firstIndex(where: { width <= $0 }) { return ("≤\(bps[i])", i) }
        return ("> \(bps.last!)", bps.count)
    }

    // MARK: - 전체 조작

    var normalizedURL: URL? {
        var s = urlString.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = (s.hasPrefix("localhost") || s.hasPrefix("127.") ? "http://" : "https://") + s }
        return URL(string: s)
    }

    func loadAll() {
        guard let url = normalizedURL else { return }
        urlString = url.absoluteString
        defaults.set(urlString, forKey: "url")
        activeID = nil
        for d in enabledDevices { model(for: d).webView.load(URLRequest(url: url)) }
    }

    func reloadAll() { enabledModels.forEach { $0.webView.reload() } }
    func goBackAll() { activeID = nil; enabledModels.forEach { if $0.webView.canGoBack { $0.webView.goBack() } } }
    func goForwardAll() { activeID = nil; enabledModels.forEach { if $0.webView.canGoForward { $0.webView.goForward() } } }

    func toggleRotateAll() {
        let ids = enabledDevices.map(\.id)
        if ids.allSatisfy(rotatedIDs.contains) { rotatedIDs.subtract(ids) } else { rotatedIDs.formUnion(ids) }
    }

    func toggleRotate(_ id: String) {
        if rotatedIDs.contains(id) { rotatedIDs.remove(id) } else { rotatedIDs.insert(id) }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        if on { enabledIDs.insert(id) } else { enabledIDs.remove(id) }
    }

    private var enabledModels: [DeviceModel] { enabledDevices.compactMap { models[$0.id] } }

    // MARK: - 미러 중계

    func markActive(_ id: String) {
        lastInputAt = Date()
        if activeID != id { activeID = id }
    }

    func relay(_ body: [String: Any], from id: String) {
        guard mode == .mirror, id == activeID,
              let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.__mirror && window.__mirror.apply(\(json))"
        for m in enabledModels where m.device.id != id {
            m.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// 조작 중인 기기에서 SPA 가 아닌 전체 페이지 이동이 일어나면 나머지도 같은 주소로 보낸다
    func didCommitNavigation(_ url: URL, from id: String) {
        guard mode == .mirror, id == activeID, Date().timeIntervalSince(lastInputAt) < 2 else { return }
        for m in enabledModels where m.device.id != id && m.webView.url != url {
            m.webView.load(URLRequest(url: url))
        }
    }
}

@MainActor
final class DeviceModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let device: Device
    let webView: WKWebView
    weak var state: AppState?

    @Published var path = ""
    @Published var viewport: CGSize = .zero
    @Published var missAt: Date?
    @Published var errorText: String?

    private var urlObservation: NSKeyValueObservation?

    init(device: Device, state: AppState) {
        self.device = device
        self.state = state

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // 모든 기기가 쿠키·localStorage(로그인 상태)를 공유
        let ucc = WKUserContentController()
        if device.kind != .desktop {
            ucc.addUserScript(WKUserScript(source: MirrorScript.touchSpoof, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        ucc.addUserScript(WKUserScript(source: MirrorScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // 우클릭 → 요소 검사

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        ucc.add(WeakMessageHandler(self), name: "mirror")
        webView.customUserAgent = device.userAgent
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { webView.isInspectable = true }

        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
            let url = wv.url
            Task { @MainActor in self?.updatePath(url) }
        }
    }

    private func updatePath(_ url: URL?) {
        guard let url else { path = ""; return }
        var p = url.path.isEmpty ? "/" : url.path
        if let q = url.query { p += "?" + q }
        if let f = url.fragment { p += "#" + f }
        path = p
    }

    nonisolated func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit 은 이 콜백을 메인 스레드에서 부른다
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            let w = body["w"] as? Double, h = body["h"] as? Double
            switch type {
            case "active":
                state?.markActive(device.id)
            case "viewport":
                if let w, let h {
                    viewport = CGSize(width: w, height: h)
                    if ProcessInfo.processInfo.environment["DP_DEBUG"] != nil {
                        let e = state?.viewport(of: device) ?? .zero
                        NSLog("DP viewport %@ expected=%.0fx%.0f actual=%.0fx%.0f", device.id, e.width, e.height, w, h)
                    }
                }
            case "miss":
                missAt = Date()
            default:
                state?.relay(body, from: device.id)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        MainActor.assumeIsolated { errorText = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            if let url = webView.url { state?.didCommitNavigation(url, from: device.id) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        MainActor.assumeIsolated { errorText = text }
    }
}

/// WKUserContentController 가 핸들러를 강하게 잡아서 생기는 순환 참조를 끊는다
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}
