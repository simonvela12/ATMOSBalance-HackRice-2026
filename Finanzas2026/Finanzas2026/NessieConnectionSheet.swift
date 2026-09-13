import SwiftUI

struct NessieConnectionSheet: View {
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
                    Text("The API key is stored securely in the device Keychain. Imported account data is cached on this device.")
                }

                Section("Status") {
                    switch bankStore.phase {
                    case .idle:
                        Label("No Nessie account connected", systemImage: "link")
                    case .loadingCache:
                        Label("Loading saved bank history", systemImage: "externaldrive")
                    case .cached:
                        Label("Saved Nessie data loaded", systemImage: "externaldrive.badge.checkmark")
                    case .connecting:
                        HStack {
                            ProgressView()
                            Text("Connecting and syncing…")
                        }
                    case .connected:
                        Label("Nessie is connected and refreshing", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if bankStore.isLinked {
                    Section("Linked data") {
                        LabeledContent("Accounts", value: "\(bankStore.accounts.count)")
                        LabeledContent("Transactions", value: "\(bankStore.transactions.count)")
                        LabeledContent("Available balance") {
                            Text(bankStore.totalAvailableCash, format: .currency(code: "USD"))
                                .monospacedDigit()
                        }
                    }
                }

                if let result = bankStore.lastSyncResult {
                    Section("Latest sync") {
                        LabeledContent("Fetched", value: "\(result.transactionsFetched)")
                        LabeledContent("New", value: "\(result.transactionsInserted)")
                        LabeledContent("Updated", value: "\(result.transactionsUpdated)")
                        LabeledContent("Finished") {
                            Text(result.finishedAt, format: .dateTime.hour().minute().second())
                        }
                    }
                }

                if bankStore.canRefresh {
                    Section {
                        Label("Automatic refresh runs every 10 seconds", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(.secondary)
                        Button("Refresh now") {
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
