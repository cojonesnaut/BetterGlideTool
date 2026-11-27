import SwiftUI

// ─────────────────────────────────────────────
// MARK: - Material pill
// ─────────────────────────────────────────────

private struct MaterialPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps the view in a frosted capsule — good for version tags and status chips.
    func materialPill() -> some View { modifier(MaterialPill()) }
}

// ─────────────────────────────────────────────
// MARK: - Squiggle divider
//
// A small hand-drawn-looking sine divider. Drawn as a Path so it needs no
// bundled asset.
// ─────────────────────────────────────────────

struct SquiggleDivider: View {
    var color: Color = .primary
    var width: CGFloat = 51
    var height: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height / 2
            let amplitude = size.height / 2
            let waves: CGFloat = 3
            path.move(to: CGPoint(x: 0, y: midY))
            let steps = 60
            for i in 1 ... steps {
                let x = size.width * CGFloat(i) / CGFloat(steps)
                let phase = CGFloat(i) / CGFloat(steps) * waves * 2 * .pi
                path.addLine(to: CGPoint(x: x, y: midY - sin(phase) * amplitude))
            }
            context.stroke(path, with: .color(color.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}

// ─────────────────────────────────────────────
// MARK: - Shimmer
//
// Sweeping highlight for "look here" chips (e.g. an available update). A moving
// linear gradient masked to the content — no dependency on the fluid gradient.
// ─────────────────────────────────────────────

private struct Shimmer: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.6)
                    .offset(x: phase * w * 1.6)
                    .blendMode(.plusLighter)
                }
                .mask(content)
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
        }
    }
}

extension View {
    /// Sweeps a soft highlight across the view while `active` is true.
    func shimmer(active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

// ─────────────────────────────────────────────
// MARK: - Liquid Glass selection
//
// Settings marks the chosen item with a clear Liquid Glass shape instead of an
// accent-coloured fill. macOS 26 draws real glass; older systems fall back to a
// frosted material so the selection still reads.
// ─────────────────────────────────────────────

struct GlassSurface<S: Shape>: View {
    var shape: S
    var interactive = false
    /// Colours the glass, as the system does for tinted icons.
    var tint: Color? = nil

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(glass, in: shape)
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(tint ?? .clear))
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return interactive ? glass.interactive() : glass
    }
}

extension View {
    /// Puts a Liquid Glass shape behind the view when `isOn`, nothing otherwise.
    func glassSelection<S: Shape>(_ isOn: Bool, in shape: S) -> some View {
        background { if isOn { GlassSurface(shape: shape) } }
    }
}

/// A segmented control whose chosen segment is a Liquid Glass capsule rather
/// than the accent-filled bezel of `.pickerStyle(.segmented)`.
struct GlassSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    /// Stretch the segments across the available width, like a page picker.
    var fillsWidth = false

    @Namespace private var namespace

    init(_ title: String, selection: Binding<Value>,
         options: [(value: Value, label: String)], fillsWidth: Bool = false) {
        self.title = title
        self._selection = selection
        self.options = options
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button {
                    // No `withAnimation` here: it would also animate whatever
                    // the selection drives (the gesture list cross-faded and
                    // overlapped). Only the capsule below slides.
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 26, maxWidth: fillsWidth ? .infinity : nil, minHeight: 22)
                        .background {
                            if isOn {
                                GlassSurface(shape: Capsule(style: .continuous), interactive: true)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: selection)
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
