import AppKit
import SwiftUI

struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    private var isOpen: Bool { viewModel.state == .open }
    private var isMinimizedBusy: Bool { viewModel.state == .minimizedBusy }
    private var isPill: Bool { usesPillLayout(on: viewModel.screen) }
    private var surfaceSize: CGSize {
        switch viewModel.state {
        case .closed:
            closedIslandSize(screen: viewModel.screen)
        case .minimizedBusy:
            minimizedBusyIslandSize(screen: viewModel.screen)
        case .open:
            openIslandSize(screen: viewModel.screen)
        }
    }

    private var cornerInsets:
        (
            opened: (top: CGFloat, bottom: CGFloat),
            closed: (top: CGFloat, bottom: CGFloat)
        )
    {
        (opened: openCornerRadiusInsets, closed: closedCornerRadiusInsets)
    }

    private var cutoutShape: IslandCutoutShape {
        IslandCutoutShape(
            topCornerRadius: isOpen ? cornerInsets.opened.top : cornerInsets.closed.top,
            bottomCornerRadius: isOpen ? cornerInsets.opened.bottom : cornerInsets.closed.bottom
        )
    }

    private var pillShape: IslandPillShape {
        IslandPillShape(
            cornerRadius: isOpen
                ? openCornerRadiusInsets.top
                : max(surfaceSize.height / 2, closedPillCornerRadius)
        )
    }

    private var resolvedShape: AnyShape {
        isPill ? AnyShape(pillShape) : AnyShape(cutoutShape)
    }

    var body: some View {
        VStack(spacing: 0) {
            surface
                .padding(.top, isPill ? pillTopOffset : topScreenBleed)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var surface: some View {
        ZStack(alignment: .top) {
            Color.black

            if isOpen {
                JupyterMonitorView(
                    topInset: isPill ? 8 : closedIslandSize(screen: viewModel.screen).height,
                    horizontalInset: isPill ? 22 : openCornerRadiusInsets.top + 12
                )
                .transition(.opacity.combined(with: .scale(scale: 0.965, anchor: .top)))
            } else if isMinimizedBusy {
                JupyterBusyCompactView()
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
        .clipShape(resolvedShape)
        .compositingGroup()
        .shadow(
            color: (viewModel.state != .closed || isHovering) ? .black.opacity(0.6) : .clear,
            radius: 10
        )
        .padding(.horizontal, isPill ? pillShadowInset : 0)
        .contentShape(resolvedShape)
        .animation(.bouncy.speed(1.2), value: isHovering)
        .animation(
            isOpen
                ? .spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0)
                : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0),
            value: viewModel.state
        )
        .onHover(perform: handleHover)
        .onTapGesture {
            viewModel.toggle()
        }
        .contextMenu {
            Button("Settings") {
                SettingsWindowController.shared.showWindow()
            }

            Divider()

            Button("Quit Otemanu", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        withAnimation(.bouncy.speed(1.2)) {
            isHovering = hovering
        }

        if hovering {
            guard viewModel.state == .closed else { return }
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard isHovering, viewModel.state == .closed else { return }
                    viewModel.open()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !isHovering, viewModel.state == .open else { return }
                    viewModel.close()
                }
            }
        }
    }
}
