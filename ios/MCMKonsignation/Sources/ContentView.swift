import SwiftUI

struct ContentView: View {
    @StateObject private var soll = SollStore()
    @StateObject private var scan = ScanStore()
    @Environment(\.scenePhase) private var phase
    @State private var incoming: URL?

    var body: some View {
        TabView {
            SollListeView(store: soll, incoming: $incoming)
                .tabItem { Label("Soll-Liste", systemImage: "list.bullet.rectangle") }
            ScanView(store: scan)
                .tabItem { Label("Scannen", systemImage: "barcode.viewfinder") }
            ResultView(soll: soll, scan: scan)
                .tabItem { Label("Ergebnis", systemImage: "checkmark.seal") }
        }
        .onAppear { incoming = Inbox.takeNext() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active, incoming == nil {
                incoming = Inbox.takeNext()
            }
        }
    }
}

#Preview {
    ContentView()
}
