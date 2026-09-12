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
            ProductRootView()

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
                    SecureField("Nessie API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Customer ID", text: $customerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Nessie sandbox")
                } footer: {
                    Text("Credentials stay on the device for this session and are never committed to the repository.")
                }

                Section("Status") {
                    switch bankStore.phase {
                    case .idle:
                        Label("No linked bank loaded", systemImage: "link")
                    case .loadingCache:
                        Label("Loading saved bank history", systemImage: "externaldrive")
                    case .connecting:
                        HStack {
                            ProgressView()
                            Text("Connecting and syncing…")
                        }
                    case .connected:
                        Label("Bank data connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if bankStore.isLinked {
                    Section {
                        Button("Refresh linked accounts") {
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
