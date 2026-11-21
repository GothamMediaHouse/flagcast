import SwiftUI

/// The green bar over the map pages: the section, its big title, and its buttons.
struct MapHeader<Actions: View>: View {
    var title: String
    var sub: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            Text(title).font(FC.display(34)).foregroundStyle(.white)
            Text(sub).font(.system(size: 13)).foregroundStyle(FC.onGreenMuted).lineLimit(1)
            Spacer()
            HStack(spacing: 10) { actions }.alignmentGuide(.lastTextBaseline) { d in d[VerticalAlignment.center] + 6 }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        .background(FC.green)
        .contentShape(Rectangle()).gesture(WindowDragGesture())
    }
}
