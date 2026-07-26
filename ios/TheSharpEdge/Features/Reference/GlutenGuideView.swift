import SwiftUI

struct GlutenGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Eyebrow(text: "Reference")
                    Text("Hidden-gluten guide")
                        .font(Typography.display(32)).foregroundStyle(Theme.ink)
                    Text("The traps that catch a celiac household. Check these every cook.")
                        .font(Typography.body(15)).foregroundStyle(Theme.faint)
                }

                ForEach(SampleData.glutenGuide) { section in
                    CardSurface {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            Text(section.h).font(Typography.display(20)).foregroundStyle(Theme.inkAccent)
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.shield")
                                        .foregroundStyle(Theme.primary)
                                        .font(.system(size: 15))
                                    Text(item).font(Typography.body(15)).foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Gluten guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
