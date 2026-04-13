import SwiftUI

/// Top-of-sidebar banner. Surfaces three things:
/// 1. The optional Microsoft sign-in (only required for Azure SQL discovery)
/// 2. The Azure subscription picker (only when signed in + subs loaded)
/// 3. A persistent "+ New Connection" button that's always available so users
///    can create manual connections without ever signing in
struct AccountBannerView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    @State private var sheetMode: ConnectionSheet.Mode?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if authService.isSignedIn {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text(authService.userEmail)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else {
                    Circle()
                        .fill(.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Button {
                        Task { await authService.signIn() }
                    } label: {
                        Text("Sign in to Microsoft")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Optional — only needed to browse Azure SQL")
                }

                Spacer()

                // + New Connection menu — always visible
                Menu {
                    Button {
                        sheetMode = .azure
                    } label: {
                        Label("Azure SQL Database…", systemImage: "cloud")
                    }
                    .disabled(false)  // sheet itself prompts sign-in if needed

                    Button {
                        sheetMode = .form
                    } label: {
                        Label("SQL Server (Form)…", systemImage: "square.grid.2x2")
                    }

                    Button {
                        sheetMode = .string
                    } label: {
                        Label("From Connection String…", systemImage: "doc.plaintext")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .help("Add a new database connection")

                if authService.isSignedIn {
                    Button {
                        authService.signOut()
                        appState.explorerNodes.removeAll()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Sign out")
                }
            }

            // Subscription picker (signed-in only)
            if authService.isSignedIn && !authService.subscriptions.isEmpty {
                Picker("", selection: Binding(
                    get: { authService.selectedSubscription },
                    set: { sub in
                        authService.selectedSubscription = sub
                        if let sub {
                            authService.saveDefaultSubscriptionId(sub.id)
                            Task {
                                await authService.discoverDatabases(
                                    subscriptionId: sub.id, subscriptionName: sub.name)
                                appState.buildExplorerFromDatabases(authService.databases)
                            }
                        }
                    }
                )) {
                    ForEach(authService.subscriptions) { sub in
                        Text(sub.name).tag(sub as AzureSubscription?)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            if authService.isLoadingSubscriptions || authService.isLoadingDatabases {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(height: 12)
            }

            if let error = authService.errorMessage, !authService.isSignedIn {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(authService.isSignedIn ? Color.green.opacity(0.08) : Color.clear)
        .sheet(item: $sheetMode) { mode in
            ConnectionSheet(authService: authService, initialMode: mode)
                .environmentObject(appState)
        }
    }
}

