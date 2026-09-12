import SwiftUI

@main
struct Finanzas2026App: App {
    @StateObject private var bankStore = BankAccountStore()

    var body: some Scene {
        WindowGroup {
            V2AppHost()
                .environmentObject(bankStore)
        }
    }
}

private struct V2AppHost: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var showingBankLink = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ContentView()

            Button {
                showingBankLink = true
            } label: {
                Image(systemName: bankStore.isLinked ? "building.columns.fill" : "link.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.16), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bankStore.isLinked ? "Bank connection" : "Connect bank")
            .padding(.top, 10)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showingBankLink) {
            NessieConnectionSheet()
                .environmentObject(bankStore)
        }
    }
}

private struct NessieConnectionSheet: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var customerID = ""

    private var isConnecting: Bool {
        if case .connecting = bankStore.phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Bank access key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Test customer", text: $customerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Connect your bank")
                } footer: {
                    Text("For the hackathon demo, use the test-bank credentials provided for this account. They stay on this device for the current session.")
                }

                Section("Status") {
                    switch bankStore.phase {
                    case .idle:
                        Label("No bank connected", systemImage: "link")
                    case .loadingCache:
                        Label("Loading saved bank activity", systemImage: "externaldrive")
                    case .connecting:
                        HStack {
                            ProgressView()
                            Text("Connecting and refreshing…")
                        }
                    case .connected:
                        Label("Bank connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Label("The last refresh needs attention", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if bankStore.isLinked {
                    Section {
                        Button("Refresh bank data") {
                            Task { await bankStore.refreshLinkedAccounts() }
                        }
                        .disabled(isConnecting)
                    }
                }
            }
            .navigationTitle("Bank connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task {
                            await bankStore.linkNessieAccount(
                                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                customerID: customerID.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            if bankStore.isLinked { dismiss() }
                        }
                    }
                    .disabled(
                        isConnecting ||
                        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        customerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}
