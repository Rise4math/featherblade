import SwiftUI
import SceneKit
import UIKit

@main
struct ShuttleApp: App {
    var body: some Scene {
        WindowGroup { ClubView().preferredColorScheme(.dark) }
    }
}

private let ink = Color(red: 0.035, green: 0.064, blue: 0.089)
private let cream = Color(red: 0.95, green: 0.95, blue: 0.87)
private let mint = Color(red: 0.61, green: 0.97, blue: 0.78)
private let coral = Color(red: 1, green: 0.43, blue: 0.32)

private func caption(_ text: String, size: CGFloat = 10) -> some View {
    Text(text).font(.system(size: size, weight: .bold, design: .monospaced)).tracking(1.2)
}

struct ClubView: View {
    @State private var match = false
    @State private var help = false
    @AppStorage("bestRally") private var best = 0
    var body: some View {
        ZStack {
            if match {
                CourtScreen { match = false }
            } else {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        ink.ignoresSafeArea()
                        GeometryReader { canvas in
                            Image("KeyArt").resizable().scaledToFill()
                                .frame(width: canvas.size.width, height: canvas.size.height, alignment: .trailing)
                                .clipped()
                            LinearGradient(stops: [.init(color: ink.opacity(0.74), location: 0.0), .init(color: ink.opacity(0.30), location: 0.44), .init(color: ink.opacity(0), location: 0.65)], startPoint: .leading, endPoint: .trailing)
                        }.ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 9) {
                                ClubMark().frame(width: 25, height: 25).foregroundStyle(mint)
                                caption("FEATHERBLADE   /   BADMINTON CLUB")
                            }.foregroundStyle(cream)
                            Spacer(minLength: 8)
                            HStack(spacing: 8) { Rectangle().fill(coral).frame(width: 24, height: 3); caption("SINGLES   ·   NIGHT SESSION").foregroundStyle(mint) }
                            Text("羽刃").italic().font(.system(size: min(83, g.size.height * 0.23), weight: .black)).foregroundStyle(cream)
                                .lineLimit(1).padding(.vertical, -4)
                            Text("夜场单打").font(.system(size: 23, weight: .bold)).foregroundStyle(cream)
                            Text("十一分制   /   球馆 A").font(.system(size: 13)).foregroundStyle(cream.opacity(0.68)).padding(.top, 5)
                            Spacer(minLength: 10)
                            HStack(spacing: 12) {
                                Button { match = true } label: {
                                    HStack(spacing: 18) { Text("进入球场"); Image(systemName: "arrow.up.right") }
                                        .font(.headline).foregroundStyle(ink).padding(.horizontal, 20).frame(height: 48).background(mint)
                                }
                                Button { help = true } label: {
                                    Text("操作指南").font(.subheadline.bold()).foregroundStyle(cream).padding(.horizontal, 14).frame(height: 48)
                                        .overlay(Rectangle().strokeBorder(cream.opacity(0.35)))
                                }
                            }
                            if best > 0 { Text("个人最长回合  ·  \(best) 拍").font(.caption.monospacedDigit()).foregroundStyle(mint).padding(.top, 7) }
                        }.padding(.leading, 20).padding(.vertical, max(10, g.size.height * 0.046))
                    }
                }
            }
            if help { HelpCard { help = false } }
        }.buttonStyle(.plain).statusBarHidden(true)
    }
}

private struct ClubMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let x = CGFloat(i) * 0.27
            p.move(to: CGPoint(x: rect.width*x, y: rect.height*0.78))
            p.addLine(to: CGPoint(x: rect.width*(x+0.23), y: rect.height*0.14))
            p.addLine(to: CGPoint(x: rect.width*(x+0.40), y: rect.height*0.14))
            p.addLine(to: CGPoint(x: rect.width*(x+0.14), y: rect.height*0.86))
            p.closeSubpath()
        }
        return p
    }
}

private struct HelpCard: View {
    var close: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.83).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { caption("COURTSIDE   /   PLAYBOOK").foregroundStyle(mint); Spacer(); Button(action: close) { Image(systemName: "xmark").padding(12) }.accessibilityLabel("关闭指南") }
                    Text("操作指南").font(.title.bold())
                    Text("球员会自动追球。拖动左下方向盘微调脚步，点右侧按钮挥拍。沿击球按钮向左或向右滑动再松手，可以控制落点方向。")
                    Divider()
                    ForEach([["高远","把对手压到底线，争取回位时间。"],["吊球","对手留在后场时，轻吊网前。"],["扣杀","抢到高点时下压进攻。"]], id: \.first) { row in
                        HStack { Text(row[0]).bold().foregroundStyle(mint).frame(width: 46, alignment: .leading); Text(row[1]) }
                    }
                    Text("每球得分，先得 11 分且领先 2 分胜。14 平后下一球决胜。").font(.footnote).foregroundStyle(cream.opacity(0.7))
                }.font(.subheadline).foregroundStyle(cream).padding(20)
            }.frame(maxWidth: 480, maxHeight: 320).background(ink)
        }
    }
}

@MainActor
private final class CourtSession: ObservableObject {
    let game = MatchScene()
    let sound = CourtSound()
    @Published var status: MatchScene.Status?
    @Published var paused = false
    var running = false
    func begin() {
        game.onUpdate = { [weak self] value in
            self?.status = value
            if value.rally > UserDefaults.standard.integer(forKey: "bestRally") { UserDefaults.standard.set(value.rally, forKey: "bestRally") }
        }
        game.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .strike(let player, let shot): self.sound.hit(power: shot == .smash, haptic: player)
            case .serve(let player): self.sound.hit(power: false, haptic: player)
            case .point(let player): self.sound.point(won: player)
            case .fault: break
            }
        }
        running = true
        game.start()
    }
    func pause(_ value: Bool) {
        game.setMovement(0, depth: 0)
        game.setPaused(value)
        paused = value
    }
}

private struct CourtRenderer: UIViewRepresentable {
    let session: CourtSession
    let paused: Bool
    @MainActor final class Driver: NSObject {
        let session: CourtSession
        weak var surface: SCNView?
        var clock: CADisplayLink?
        var last = 0.0
        var size = CGSize.zero
        init(_ session: CourtSession) { self.session = session }
        @objc func frame(_ link: CADisplayLink) {
            guard let surface else { return }
            if surface.bounds.size != size && surface.bounds.height > 0 {
                size = surface.bounds.size
                session.game.resize(aspect: Float(size.width / size.height))
            }
            if last > 0 && session.running && !session.paused {
                session.game.tick(min(link.timestamp - last, 0.05))
            }
            last = link.timestamp
        }
    }
    func makeCoordinator() -> Driver { Driver(session) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.035, green: 0.064, blue: 0.089, alpha: 1)
        view.scene = session.game.scene
        view.pointOfView = session.game.camera
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        let driver = context.coordinator
        driver.surface = view
        let link = CADisplayLink(target: driver, selector: #selector(Driver.frame(_:)))
        link.preferredFramesPerSecond = 60
        driver.clock = link
        link.add(to: .main, forMode: .common)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        view.isPlaying = !paused
        view.rendersContinuously = !paused
        let driver = context.coordinator
        if driver.clock?.isPaused != paused {
            driver.last = 0
            driver.clock?.isPaused = paused
        }
    }
    static func dismantleUIView(_ uiView: SCNView, coordinator: Driver) { coordinator.clock?.invalidate(); coordinator.clock = nil; uiView.scene = nil }
}

private struct CourtScreen: View {
    @StateObject private var session = CourtSession()
    @Environment(\.scenePhase) private var lifecycle
    let leave: () -> Void
    var body: some View {
        ZStack {
            CourtRenderer(session: session, paused: session.paused).ignoresSafeArea()
            if let s = session.status {
                VStack {
                    HStack(alignment: .top) {
                        HStack(spacing: 12) {
                            score("我方", s.playerScore, mint, s.playerServing)
                            Rectangle().fill(cream.opacity(0.3)).frame(width: 1, height: 26)
                            score("对手", s.opponentScore, coral, !s.playerServing)
                        }.padding(.horizontal, 14).padding(.vertical, 6).background(ink.opacity(0.9))
                        Spacer()
                        if s.rally > 0 { Text("\(s.rally) 拍").font(.subheadline.monospacedDigit().bold()).padding(9).background(ink.opacity(0.85)) }
                        Button { session.pause(true) } label: { Image(systemName: "pause.fill").frame(width: 44,height: 44).background(ink.opacity(0.85)) }.accessibilityLabel("暂停")
                    }
                    Spacer()
                    if s.phase == .rally {
                        HStack(alignment: .bottom) {
                            FootPad { x, z in session.game.setMovement(x, depth: z) }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(s.message).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 4).background(ink.opacity(0.82))
                                HStack(spacing: 8) {
                                    shot("高远", .clear, s.canHit)
                                    shot("吊球", .drop, s.canHit)
                                    shot("扣杀", .smash, s.canHit)
                                }
                            }
                        }
                    } else if s.phase != .finished {
                        Button { session.game.serve() } label: {
                            HStack(spacing: 12) {
                                Text(s.message)
                                Image(systemName: "chevron.right")
                            }.font(.headline).foregroundStyle(ink).padding(.horizontal, 20).frame(height: 46).background(mint)
                        }
                    }
                }.padding(.horizontal, 8).padding(.vertical, 6).foregroundStyle(cream)
                if s.phase == .finished {
                    overlay(title: s.playerWon == true ? "赢下比赛" : "比赛结束", detail: "\(s.playerScore)   :   \(s.opponentScore)", primary: "再打一场", action: { session.game.start() })
                }
            }
            if session.paused { overlay(title: "比赛暂停", detail: "羽刃   /   夜场单打", primary: "继续比赛", action: { session.pause(false) }) }
        }.onAppear { session.begin() }.onDisappear { session.running = false; session.sound.stop() }
            .onChange(of: lifecycle) { phase in if phase != .active && session.running { session.pause(true) } }
    }
    private func shot(_ title: String, _ stroke: MatchScene.Stroke, _ active: Bool) -> some View {
        StrokePad(title: title, tint: stroke == .smash ? coral : mint, active: active) { aim in
            session.game.strike(stroke, aim: aim)
        }
    }
    private func score(_ name: String, _ number: Int, _ color: Color, _ serve: Bool) -> some View {
        HStack(spacing: 5) {
            VStack(spacing: 2) {
                Text(name).font(.caption2.bold())
                Capsule().fill(serve ? color : .clear).frame(width: 14, height: 2)
            }
            Text(String(format: "%02d", number)).font(.system(size: 25, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(color)
        }
    }
    private func overlay(title: String, detail: String, primary: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.70).ignoresSafeArea()
            VStack(spacing: 12) {
                caption("FEATHERBLADE   /   CLUB COURT").foregroundStyle(mint)
                Text(title).font(.largeTitle.bold()).foregroundStyle(cream)
                Text(detail).font(.title2.monospacedDigit()).foregroundStyle(cream)
                HStack(spacing: 12) {
                    Button("返回主场", action: leave).foregroundStyle(cream).padding(12)
                    Button(primary, action: action).bold().foregroundStyle(ink).padding(12).background(mint)
                }
            }.padding(22).background(ink)
        }
    }
}

private struct StrokePad: View {
    let title: String
    let tint: Color
    let active: Bool
    let strike: (Float) -> Void
    @GestureState private var drag: CGFloat? = nil

    var body: some View {
        let offset = drag ?? 0
        let illuminated = active || drag != nil
        return Text(abs(offset) > 10 ? (offset < 0 ? "↖ 左线" : "右线 ↗") : title)
            .font(.system(size: abs(offset) > 10 ? 13 : 17, weight: .bold))
            .foregroundStyle(illuminated ? ink : cream)
            .frame(width: 58, height: 46).background(illuminated ? tint : ink.opacity(0.85))
            .overlay(Rectangle().strokeBorder(tint.opacity(0.8)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($drag) { value, state, _ in state = value.translation.width }
                .onEnded { value in strike(Float(max(-1, min(1, value.translation.width / 46)))) })
            .accessibilityLabel(title).accessibilityAddTraits(.isButton)
            .accessibilityAction { strike(0) }
    }
}

private struct FootPad: View {
    var move: (Float, Float) -> Void
    @State private var offset = CGSize.zero
    var body: some View {
        ZStack {
            Circle().fill(ink.opacity(0.7)).overlay(Circle().strokeBorder(cream.opacity(0.45)))
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").foregroundStyle(cream.opacity(0.6))
            Circle().fill(mint.opacity(0.7)).frame(width: 23,height: 23).offset(offset)
        }.frame(width: 78, height: 78).contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = value.location.x - 39, y = value.location.y - 39
                let factor = max(1, hypot(x, y) / 26)
                offset = CGSize(width: x / factor, height: y / factor)
                move(Float(offset.width / 26), -Float(offset.height / 26))
            }.onEnded { _ in offset = .zero; move(0, 0) })
            .onDisappear { move(0, 0) }.accessibilityLabel("移动方向盘")
    }
}
