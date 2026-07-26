import SwiftUI

// MARK: - GF badge

struct GFBadge: View {
    var gf: Bool
    var body: some View {
        if gf {
            Text("GF")
                .font(Typography.mono(12, weight: .semibold))
                .foregroundStyle(Theme.primaryDeep)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.primary.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(Theme.primary.opacity(0.35), lineWidth: 1))
                .accessibilityLabel("Gluten free")
        }
    }
}

// MARK: - Category eyebrow

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(Typography.mono(12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - Section header (small caps divider)

struct SectionHeaderLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(Typography.mono(12, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.faint)
            .padding(.top, 4)
    }
}

// MARK: - Mono quantity with accent flash

struct MonoQuantity: View {
    var text: String
    var flashing: Bool
    var size: CGFloat = 17

    var body: some View {
        Text(text)
            .font(Typography.mono(size, weight: .semibold))
            .foregroundStyle(flashing ? Theme.accent : Theme.primaryDeep)
            .animation(.easeOut(duration: 0.45), value: flashing)
            .monospacedDigit()
    }
}

// MARK: - Chip / pill

struct Chip: View {
    var text: String
    var selected: Bool = false
    var body: some View {
        Text(text)
            .font(Typography.mono(13, weight: .medium))
            .foregroundStyle(selected ? Theme.offWhite : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Theme.primaryDeep : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
    }
}

// MARK: - Primary / secondary buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body(16, weight: .semibold))
            .foregroundStyle(Theme.offWhite)
            .padding(.horizontal, 18)
            .frame(minHeight: Theme.minTouch)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Theme.primary : Theme.primaryDeep, in: Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body(16, weight: .semibold))
            .foregroundStyle(Theme.primaryDeep)
            .padding(.horizontal, 18)
            .frame(minHeight: Theme.minTouch)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Card surface

struct CardSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Theme.Space.l)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

// MARK: - Scale stepper

struct ScaleStepper: View {
    @Binding var value: Int
    var unitWord: String
    var minValue: Int
    var maxValue: Int
    var baseValue: Int
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            stepButton(system: "minus", enabled: value > minValue) {
                value = max(minValue, value - 1); onChange()
            }

            VStack(spacing: 2) {
                Text("\(value) \(unitWord)")
                    .font(Typography.mono(20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if value != baseValue {
                    Button {
                        value = baseValue; onChange()
                    } label: {
                        Text("base \(baseValue)")
                            .font(Typography.mono(12))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .frame(minWidth: 120)

            stepButton(system: "plus", enabled: value < maxValue) {
                value = min(maxValue, value + 1); onChange()
            }
        }
    }

    private func stepButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.offWhite)
                .frame(width: Theme.minTouch, height: Theme.minTouch)
                .background(enabled ? Theme.primaryDeep : Theme.faint.opacity(0.4), in: Circle())
        }
        .disabled(!enabled)
    }
}

// MARK: - Async content states

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.primary)
            Text("Loading…").font(Typography.mono(13)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    var message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(Typography.body(15))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry).buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 200)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
