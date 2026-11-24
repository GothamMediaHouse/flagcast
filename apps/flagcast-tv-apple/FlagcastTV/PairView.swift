import SwiftUI

/// Not connected yet: the code to type in the Manager (Screens & sponsors → Club TVs → Add a TV).
/// The only screen with the Flagcast logo, because the TV isn't any club's yet.
struct PairView: View {
    let hello: Hello?
    let problem: String?

    var body: some View {
        HStack(spacing: 120) {
            VStack(alignment: .leading, spacing: 36) {
                Image("Wordmark").resizable().scaledToFit().frame(height: 70).accessibilityLabel("Flagcast")
                Text("CONNECT THIS TV TO YOUR CLUB").font(Theme.display(84)).foregroundStyle(Theme.txt).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    Text("1.  Open Flagcast Manager")
                    Text("2.  Go to Screens & sponsors, then Add a TV")
                    Text("3.  Type the code on this TV")
                }
                .font(.system(size: 34)).foregroundStyle(Color(hex: "c9d6cc"))
                Text("You only do this once. After that, this TV shows your club’s tournament on the day, all by itself.")
                    .font(.system(size: 26)).foregroundStyle(Theme.dim).frame(maxWidth: 700, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 34) {
                Text("TV CODE").font(Theme.mono(24)).tracking(4).foregroundStyle(Theme.dim)
                HStack(spacing: 16) {
                    ForEach(Array((hello?.code ?? "······").enumerated()), id: \.offset) { _, c in
                        Text(String(c)).font(Theme.mono(96, .semibold)).foregroundStyle(Theme.flag)
                            .frame(width: 110, height: 150).background(Theme.green, in: .rect(cornerRadius: 18))
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("TV code \(hello?.code.map(String.init).joined(separator: " ") ?? "")")
                if let p = problem { Text(p).font(.system(size: 24)).foregroundStyle(Theme.red).multilineTextAlignment(.center) }
                else if let h = hello {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        let mins = max(0, Int((h.exp / 1000 - Date().timeIntervalSince1970) / 60))
                        Text(mins > 0 ? "New code in \(mins) min" : "New code soon").font(Theme.mono(22)).foregroundStyle(Color(hex: "6f8577"))
                    }
                }
            }
            .padding(.vertical, 70).padding(.horizontal, 60)
            .background(Theme.panel, in: .rect(cornerRadius: 36))
            .overlay(RoundedRectangle(cornerRadius: 36).stroke(Theme.rule, lineWidth: 2))
        }
        .padding(.horizontal, 130)
    }
}
