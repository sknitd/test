import SwiftUI
import MFCore
import MFEngine

/// Animated illustration of a gesture on the mouse surface (or, for fallback chord triggers,
/// the modifier keys plus the click / scroll). Animation pauses when `isAnimating` is false,
/// when animations are disabled in Settings, or when Reduce Motion is on; a representative
/// still frame is shown instead.
@MainActor
public struct GesturePreview: View {
    private let kind: GestureKind
    private let isAnimating: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(kind: GestureKind, isAnimating: Bool = true) {
        self.kind = kind
        self.isAnimating = isAnimating
    }

    public var body: some View {
        let choreography: GestureChoreography = GestureChoreography.make(for: kind)
        let isActive: Bool = isAnimating && model.configuration.settings.animationsEnabled && !reduceMotion
        let edgeFraction: Double = model.configuration.recognizer.edgeZoneFraction
        let cornerFraction: Double = model.configuration.recognizer.cornerZoneFraction
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            GesturePreviewCanvas(
                choreography: choreography,
                phase: isActive ? choreography.phase(at: timeline.date.timeIntervalSinceReferenceDate)
                    : choreography.posterPhase,
                edgeFraction: edgeFraction,
                cornerFraction: cornerFraction
            )
        }
        .aspectRatio(0.66, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Illustration: \(kind.displayName). \(kind.summary)"))
    }
}

/// One still frame of a choreography. Usable without an `AppModel` in the environment.
public struct GesturePreviewCanvas: View {
    private let choreography: GestureChoreography
    private let phase: Double
    private let edgeFraction: Double
    private let cornerFraction: Double

    public init(choreography: GestureChoreography, phase: Double, edgeFraction: Double = 0.16,
                cornerFraction: Double = 0.28) {
        self.choreography = choreography
        self.phase = phase
        self.edgeFraction = edgeFraction
        self.cornerFraction = cornerFraction
    }

    public var body: some View {
        let choreography: GestureChoreography = self.choreography
        let phase: Double = self.phase
        let edgeFraction: Double = self.edgeFraction
        let cornerFraction: Double = self.cornerFraction
        Canvas { context, size in
            GesturePreviewRenderer.draw(choreography, phase: phase, in: &context, size: size,
                                        edgeFraction: edgeFraction, cornerFraction: cornerFraction)
        }
    }
}
