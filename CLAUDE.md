# CLAUDE.md

## MANDATORY: Commit and Push After Every Change

Every change MUST be committed and pushed to main immediately. The CI/CD pipeline automatically creates a new versioned release with a downloadable macOS DMG on every push to main.

## Build & Run

```bash
# Build
swift build

# Run
swift run SQLExplorer

# Run tests
swift test

# Build release
swift build -c release

# Create DMG (run from repo root)
bash build/build-mac.sh
```

## Architecture

**SQL Explorer** is a native macOS SQL Server management app built with Swift + SwiftUI.

```
SQLExplorer/          (main app target)
├── App/              @main entry point, AppState (global ObservableObject)
├── Models/           Codable data models (ConnectionInfo, QueryResult, etc.)
├── Services/         Business logic (ConnectionManager, AuthService, ConnectionStore)
├── Views/            SwiftUI views (MainView, ConnectionSheet, QueryEditor, Results)
├── Editor/           SQL syntax highlighting (NSTextView + NSLayoutManager)
├── Utilities/        FreeTDS bridge, Keychain helper
└── Resources/        SQL keywords, Assets

Sources/CFreeTDS/     System library module for FreeTDS headers
Sources/CFreeTDSShim/ C shim exposing FreeTDS macros to Swift
```

## Tech Stack

- **UI**: SwiftUI + AppKit bridging (NSTextView for editor, NSOutlineView for tree)
- **SQL Server**: FreeTDS via db-lib (installed via Homebrew, linked via SPM)
- **Authentication**: MSAL.Swift — native ASWebAuthenticationSession (Keychain-cached tokens)
- **Persistence**: Codable JSON at `~/.sqlexplorer/connections.json`
- **Credentials**: macOS Keychain via Security framework

## Key Services

- `ConnectionManager` — FreeTDS connection pool on dedicated serial DispatchQueue
- `AuthService` — MSAL.Swift for Entra ID (Azure CLI client ID, silent + interactive flows)
- `ConnectionStore` — JSON persistence, backwards-compatible with old .NET format
- `QueryExecutionService` — Execute SQL via FreeTDS, return QueryResult
- `ObjectExplorerService` — Query sys.* tables for schema tree

## Dependencies (SPM)

- `microsoft-authentication-library-for-objc` (MSAL.Swift) — Entra ID auth
- `CFreeTDS` (system library) — FreeTDS headers from Homebrew
- `CFreeTDSShim` (C target) — Exposes FreeTDS C macros as Swift-callable functions

## Prerequisites

```bash
brew install freetds
```

## User Data

Stored at `~/.sqlexplorer/`:
- `connections.json` — saved connections and groups
- Keychain entries under `com.sqlexplorer.app` service

## CI/CD

GitHub Actions (`.github/workflows/release.yml`):
- Every push to main → builds with `swift build -c release` → creates .app bundle → DMG → GitHub Release
- macOS only, no Windows
