import SwiftUI
import WebKit

@main
struct DevicePreviewApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // 메인 창은 AppDelegate 가 AppKit 으로 직접 만든다.
        // (SwiftUI Window/WindowGroup 은 실행 방식에 따라 첫 창을 띄우지 않는 경우가 있었다)
        Settings {
            SettingsView().environmentObject(appDelegate.state)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("미리보기") {
                Button("주소창으로 이동") { appDelegate.state.focusURLToken += 1 }.keyboardShortcut("l")
                Button("전체 새로고침") { appDelegate.state.reloadAll() }.keyboardShortcut("r")
                Button("전체 뒤로") { appDelegate.state.goBackAll() }.keyboardShortcut("[")
                Button("전체 앞으로") { appDelegate.state.goForwardAll() }.keyboardShortcut("]")
                Divider()
                Button("개별 조작 / 미러 조작 전환") {
                    let s = appDelegate.state
                    s.mode = s.mode == .mirror ? .independent : .mirror
                }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("전체 회전") { appDelegate.state.toggleRotateAll() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("확대") { appDelegate.state.scale = min(1, appDelegate.state.scale + 0.05) }.keyboardShortcut("=")
                Button("축소") { appDelegate.state.scale = max(0.25, appDelegate.state.scale - 0.05) }.keyboardShortcut("-")
            }
            CommandGroup(after: .windowArrangement) {
                Button("Device Preview 창 보기") { appDelegate.showMainWindow() }.keyboardShortcut("0")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Device Preview"
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 900, height: 560)
            w.contentView = NSHostingView(rootView: ContentView().environmentObject(state))
            w.center()
            w.setFrameAutosaveName("DevicePreviewMain")
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - 메인 화면

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()

            if state.mode == .mirror {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle")
                    Text("미러 조작: 아무 기기에서나 클릭·입력·스크롤하면 나머지 기기에도 똑같이 반영됩니다. 같은 요소를 못 찾은 기기에는 ⚠ 가 잠깐 표시됩니다.")
                        .lineLimit(2)
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.12))
            }

            if state.enabledDevices.isEmpty {
                ContentUnavailable()
            } else {
                ScrollView([.vertical, .horizontal]) {
                    FlowLayout(spacing: 28) {
                        ForEach(state.enabledDevices) { device in
                            DeviceCard(model: state.model(for: device), device: device)
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .onChange(of: state.focusURLToken) { _ in urlFocused = true }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button { state.goBackAll() } label: { Image(systemName: "chevron.left") }.help("전체 뒤로 (⌘[)")
                Button { state.goForwardAll() } label: { Image(systemName: "chevron.right") }.help("전체 앞으로 (⌘])")
                Button { state.reloadAll() } label: { Image(systemName: "arrow.clockwise") }.help("전체 새로고침 (⌘R)")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14))

            TextField("http://localhost:5173", text: $state.urlString)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, maxWidth: 520)
                .focused($urlFocused)
                .onSubmit { state.loadAll() }
                .help("주소를 입력하고 Enter 를 누르면 모든 기기가 이동합니다 (⌘L)")

            Spacer(minLength: 8)

            Picker("", selection: $state.mode) {
                ForEach(AppState.Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("미러 조작: 한 기기에서 한 조작을 모든 기기에 반영 (⇧⌘M)")

            Menu {
                ForEach(Device.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(Device.all.filter { $0.group == group }) { d in
                            Toggle("\(d.name)  \(d.width)×\(d.height)", isOn: Binding(
                                get: { state.enabledIDs.contains(d.id) },
                                set: { state.setEnabled(d.id, $0) }))
                        }
                    }
                }
                Divider()
                Button("기본 구성으로") { state.enabledIDs = Device.defaultEnabled }
                Button("모두 켜기") { state.enabledIDs = Set(Device.all.map(\.id)) }
            } label: {
                Label("기기 \(state.enabledIDs.count)", systemImage: "iphone.gen3")
            }
            .fixedSize()
            .help("보여줄 기기 선택")

            Button { state.toggleRotateAll() } label: { Image(systemName: "rotate.right") }
                .buttonStyle(.borderless)
                .help("전체 가로/세로 회전 (⇧⌘O)")

            HStack(spacing: 4) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $state.scale, in: 0.25...1).frame(width: 110)
                Text("\(Int((state.scale * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
            .help("배율 (⌘- / ⌘=)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ContentUnavailable: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("툴바의 「기기」 메뉴에서 볼 기기를 고르세요.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 기기 카드

private let badgeColors: [Color] = [.pink, .orange, .blue, .green, .purple, .teal]

struct DeviceCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: DeviceModel
    let device: Device

    @State private var showMiss = false

    var body: some View {
        let size = state.size(of: device)
        let frame = state.layout(of: device).frame
        let w = frame.width, h = frame.height
        let isActive = state.mode == .mirror && state.activeID == device.id
        let bezel: CGFloat = device.kind == .phone ? 8 : 10

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if isActive {
                    Text("조작 중").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor)).foregroundStyle(.white)
                }
                if showMiss {
                    Text("⚠ 요소 못 찾음").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                Button { state.toggleRotate(device.id) } label: { Image(systemName: "rotate.right") }
                    .help("가로/세로 회전")
                Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("이 기기만 새로고침")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 6) {
                Text("\(Int(size.width)) × \(Int(size.height))").monospacedDigit()
                if model.viewport != .zero && Int(model.viewport.width) != Int(size.width) {
                    Text("(실제 \(Int(model.viewport.width)))").foregroundStyle(.orange)
                        .help("페이지가 보고 있는 window.innerWidth")
                }
                if let (label, idx) = state.breakpointBadge(width: Int(size.width)) {
                    Text(label).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(badgeColors[idx % badgeColors.count]))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 4)
                Text(model.path).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            ZStack {
                WebViewHost(webView: model.webView)
                if let err = model.errorText {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(err).multilineTextAlignment(.center)
                        Text("dev 서버가 켜져 있는지 확인하세요").foregroundStyle(.secondary)
                    }
                    .font(.caption).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: device.kind == .phone ? 14 : 8))
            .padding(bezel)
            .background(RoundedRectangle(cornerRadius: device.kind == .phone ? 22 : 16).fill(Color.black))
            .overlay(
                RoundedRectangle(cornerRadius: device.kind == .phone ? 22 : 16)
                    .strokeBorder(Color.accentColor, lineWidth: isActive ? 3 : 0)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .frame(width: max(w + bezel * 2, 200))
        .onChange(of: model.missAt) { _ in
            showMiss = true
            Task { try? await Task.sleep(nanoseconds: 1_800_000_000); showMiss = false }
        }
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - 줄바꿈 배치

struct FlowLayout: Layout {
    var spacing: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? s.width : rows[rows.count - 1].width + spacing + s.width
            if needed > maxWidth && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? s.width : row.width + spacing + s.width
            row.height = max(row.height, s.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - 설정

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                TextField("예: 519, 800, 1400", text: $state.breakpointsText)
                Text("프로젝트의 CSS 미디어쿼리 max-width 값을 쉼표로 적으면, 기기마다 어느 구간에 걸리는지 배지로 보여줍니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("브레이크포인트 (px)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }
}
