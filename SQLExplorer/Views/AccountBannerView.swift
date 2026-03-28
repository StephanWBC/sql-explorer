import SwiftUI

struct AccountBannerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.authService.isSignedIn {
                // Signed in state
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.authService.userEmail)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                        if appState.authService.isLoadingSubscriptions {
                            Text("Loading subscriptions...")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(appState.authService.subscriptions.count) subscription(s)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        appState.authService.signOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Sign out")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.08))
            } else {
                // Not signed in
                VStack(spacing: 6) {
                    Button {
                        Task { await appState.authService.signIn() }
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

                    if let error = appState.authService.errorMessage {
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
