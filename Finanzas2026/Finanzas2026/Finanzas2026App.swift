import SwiftUI

@main
struct Finanzas2026App: App {
    @StateObject private var bankStore = BankAccountStore()

    var body: some Scene {
        WindowGroup {
            // Accounts and the bank connection live behind the profile button in
            // ContentView's top bar. There used to be a second floating button for
            // the same thing stacked on top of the screen, which made both hard to hit.
            ContentView()
                .environmentObject(bankStore)
        }
    }
}
