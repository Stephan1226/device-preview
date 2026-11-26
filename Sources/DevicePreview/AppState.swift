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

    /// 화면에 그릴 프레임(정수 pt)과 그 프레임에서 CSS 뷰포트가 정확히 기기 폭이 되는 줌.
    /// WebKit 은 프레임을 정수 pt 로 다루므로 w*scale 을 그대로 쓰면 innerWidth 가 1~2px 모자란다.
    func layout(of device: Device) -> (frame: CGSize, zoom: Double) {
        let css = size(of: device)
        let fw = (css.width * scale).rounded(.up)
        let zoom = Double(fw) / (Double(css.width) + 0.25)
        let fh = ((css.height + 0.25) * zoom).rounded(.up)
        return (CGSize(width: fw, height: fh), zoom)
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
                        NSLog("DP viewport %@ expected=%dx%d actual=%.0fx%.0f", device.id, device.width, device.height, w, h)
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
