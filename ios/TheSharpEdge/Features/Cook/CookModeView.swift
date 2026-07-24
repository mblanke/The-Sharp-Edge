import SwiftUI

/// Full-screen, one-step-per-screen cook mode. Keeps the screen awake, shows scaled
/// amounts for the active step, runs inline timers, and persists position per recipe.
struct CookModeView: View {
    let recipe: RecipeFull
    let target: Int
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int = 0
    @State private var showIngredients = false

    private var steps: [Step] { recipe.currentVersion.steps }
    private var factor: Double { Double(target) / Double(max(1, recipe.baseYield)) }
    private var scaledRows: [ScaledRow] {
        ScalingEngine.scale(recipe.currentVersion.ingredients, baseYield: recipe.baseYield, targetYield: target)
    }
    private var posKey: String { "sharpedge.cookpos.\(recipe.slug)" }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                TabView(selection: $index) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        stepPage(idx: idx, step: step).tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .bottom) { pageDots }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let saved = UserDefaults.standard.integer(forKey: posKey)
            if saved > 0 && saved < steps.count { index = saved }
        }
        .onChange(of: index) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: posKey)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showIngredients) { ingredientSheet }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
            }
            Spacer()
            Text("\(index + 1) / \(steps.count)")
                .font(Typography.mono(15, weight: .semibold)).foregroundStyle(Theme.faint)
            Spacer()
            Button { showIngredients = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private func stepPage(idx: Int, step: Step) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Spacer(minLength: 0)
            Text("Step \(idx + 1)")
                .font(Typography.mono(16, weight: .semibold)).foregroundStyle(Theme.copper)
            Text(StepText.attributed(step.text))
                .font(Typography.display(30, weight: .regular))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let t = step.timerSeconds {
                CookTimerView(seconds: t)
            }
            Spacer(minLength: 0)
            navButtons(idx: idx)
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func navButtons(idx: Int) -> some View {
        HStack(spacing: Theme.Space.l) {
            Button {
                withAnimation { index = max(0, idx - 1) }
            } label: { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(idx == 0)
                .opacity(idx == 0 ? 0.4 : 1)

            Button {
                withAnimation { index = min(steps.count - 1, idx + 1) }
            } label: { Label(idx == steps.count - 1 ? "Done" : "Next",
                             systemImage: idx == steps.count - 1 ? "checkmark" : "chevron.right") }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps.count, id: \.self) { i in
                Circle().fill(i == index ? Theme.green : Theme.line)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 10)
    }

    private var ingredientSheet: some View {
        NavigationStack {
            List {
                ForEach(Grouping.sections(scaledRows)) { section in
                    Section(section.name ?? "Ingredients") {
                        ForEach(section.rows) { row in
                            HStack {
                                Text(row.display).font(Typography.mono(15, weight: .semibold))
                                    .foregroundStyle(Theme.greenDeep).frame(minWidth: 70, alignment: .leading)
                                Text(row.name).font(Typography.body(15))
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(target) \(recipe.yieldWord)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showIngredients = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
