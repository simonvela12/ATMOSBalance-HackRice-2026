import SwiftUI

@main
struct Finanzas2026App: App {
    @StateObject private var bankStore = BankAccountStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bankStore)
        }
    }
}
