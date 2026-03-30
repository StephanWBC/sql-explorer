import SwiftUI

struct AccountBannerView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if authService.isSignedIn {
                VStack(spacing: 6) {
                    // Email + sign out
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(authService.userEmail)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                        Spacer()
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

                    // Subscription picker
                    if !authService.subscriptions.isEmpty {
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.08))
            } else {
                VStack(spacing: 6) {
                    Button {
                        Task { await authService.signIn() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 12))
                            Text("Sign in with Microsoft")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}
