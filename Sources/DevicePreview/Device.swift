import Foundation

struct Device: Identifiable, Hashable {
    enum Kind { case phone, tablet, desktop }

    let id: String
    let name: String
    let group: String
    /// CSS 픽셀 기준 세로 방향 뷰포트 크기 (window.innerWidth / innerHeight)
    let width: Int
    let height: Int
    let kind: Kind
    /// nil 이면 WKWebView 기본(맥 Safari) UA
    let userAgent: String?
}

private enum UA {
    static func samsung(_ model: String, mobile: Bool = true) -> String {
        "Mozilla/5.0 (Linux; Android 14; \(model)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 \(mobile ? "Mobile " : "")Safari/537.36"
    }
    static let iPhone =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"
    // 실제 iPadOS Safari 는 맥 UA 를 쓰고 터치 지원으로 구분되지만,
    // 여기서는 터치를 흉내 낼 수 없으므로 iPad 임을 드러내는 UA 를 쓴다.
    static let iPad =
        "Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"
}

extension Device {
    static let all: [Device] = [
        Device(id: "fold-cover", name: "Galaxy Z Fold (접힘)", group: "Galaxy", width: 344, height: 882, kind: .phone, userAgent: UA.samsung("SM-F956N")),
        Device(id: "fold-open", name: "Galaxy Z Fold (펼침)", group: "Galaxy", width: 690, height: 829, kind: .tablet, userAgent: UA.samsung("SM-F956N")),
        Device(id: "flip", name: "Galaxy Z Flip", group: "Galaxy", width: 360, height: 748, kind: .phone, userAgent: UA.samsung("SM-F741N")),
        Device(id: "gs24", name: "Galaxy S24", group: "Galaxy", width: 360, height: 780, kind: .phone, userAgent: UA.samsung("SM-S921N")),
        Device(id: "gs24u", name: "Galaxy S24 Ultra", group: "Galaxy", width: 384, height: 824, kind: .phone, userAgent: UA.samsung("SM-S928N")),
        Device(id: "ga", name: "Galaxy A 시리즈", group: "Galaxy", width: 412, height: 915, kind: .phone, userAgent: UA.samsung("SM-A556N")),
        Device(id: "tabs9", name: "Galaxy Tab S9", group: "Galaxy", width: 800, height: 1280, kind: .tablet, userAgent: UA.samsung("SM-X716N", mobile: false)),
        Device(id: "ise", name: "iPhone SE", group: "iPhone", width: 375, height: 667, kind: .phone, userAgent: UA.iPhone),
        Device(id: "i16", name: "iPhone 16", group: "iPhone", width: 393, height: 852, kind: .phone, userAgent: UA.iPhone),
        Device(id: "i16pm", name: "iPhone 16 Pro Max", group: "iPhone", width: 440, height: 956, kind: .phone, userAgent: UA.iPhone),
        Device(id: "ipadmini", name: "iPad mini", group: "iPad", width: 744, height: 1133, kind: .tablet, userAgent: UA.iPad),
        Device(id: "ipadair", name: "iPad Air 11\"", group: "iPad", width: 820, height: 1180, kind: .tablet, userAgent: UA.iPad),
        Device(id: "ipadpro", name: "iPad Pro 13\"", group: "iPad", width: 1032, height: 1376, kind: .tablet, userAgent: UA.iPad),
        Device(id: "laptop", name: "노트북 1440", group: "PC", width: 1440, height: 900, kind: .desktop, userAgent: nil),
    ]

    static let defaultEnabled: Set<String> = ["fold-cover", "fold-open", "gs24", "i16", "i16pm", "ipadmini", "ipadair"]

    static let groups: [String] = ["Galaxy", "iPhone", "iPad", "PC"]
}
