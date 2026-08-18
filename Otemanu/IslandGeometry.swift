import AppKit
import SwiftUI

enum IslandState {
    case closed
    case minimizedBusy
    case open
}

let closedCornerRadiusInsets: (top: CGFloat, bottom: CGFloat) = (top: 6, bottom: 14)

let openCornerRadiusInsets: (top: CGFloat, bottom: CGFloat) = (top: 35, bottom: 35)

let closedPillCornerRadius: CGFloat = 16

let islandShadowPadding: CGFloat = 18
let topScreenBleed: CGFloat = 4
let pillTopOffset: CGFloat = 6
let pillShadowInset: CGFloat = 14

func openIslandSize(screen: NSScreen) -> CGSize {
    let closedHeight = closedIslandSize(screen: screen).height
    let height = max(96, (closedHeight * 3.5).rounded())
    let preferredWidth: CGFloat = screen.safeAreaInsets.top > 0 ? 420 : 340
    return CGSize(width: min(preferredWidth, screen.frame.width - 40), height: height)
}

func closedIslandSize(screen: NSScreen) -> CGSize {
    var height: CGFloat
    var width: CGFloat = 150

    if let topLeftPadding = screen.auxiliaryTopLeftArea?.width,
        let topRightPadding = screen.auxiliaryTopRightArea?.width
    {
        width = screen.frame.width - topLeftPadding - topRightPadding + 4
    }

    if screen.safeAreaInsets.top > 0 {
        height = screen.safeAreaInsets.top
    } else {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        height = menuBarHeight > 0 ? menuBarHeight : 32
    }

    return CGSize(width: width, height: height)
}

func minimizedBusyIslandSize(screen: NSScreen) -> CGSize {
    let closed = closedIslandSize(screen: screen)
    let open = openIslandSize(screen: screen)
    let width =
        usesPillLayout(on: screen)
        ? min(max(closed.width + 40, 190), open.width)
        : min(max(closed.width + 180, 300), open.width)

    return CGSize(width: width, height: closed.height)
}

func usesPillLayout(on screen: NSScreen) -> Bool {
    screen.safeAreaInsets.top <= 0
}

struct IslandCutoutShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat? = nil, bottomCornerRadius: CGFloat? = nil) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

struct IslandPillShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}
