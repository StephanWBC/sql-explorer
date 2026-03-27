# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## MANDATORY: Commit and Push After Every Change

**Every change you make MUST be committed and pushed to main immediately.** This is not optional.

After completing any code change:
1. `dotnet build SqlStudio.slnx` — verify it compiles
2. `git add -A && git commit -m "<descriptive message>"` — commit
3. `git push origin main` — push (this auto-triggers build + release pipeline)

The CI/CD pipeline automatically creates a new versioned release (v1.0.N) with downloadable macOS DMG and Windows ZIP installers on every push to main. There is no manual tagging step. Every push = new release.

## Build & Run Commands

```bash
# Run the desktop app
dotnet run --project src/SqlStudio.App

# Build entire solution
dotnet build SqlStudio.slnx

# Run all tests
dotnet test

# Run a single test project
dotnet test tests/SqlStudio.Core.Tests

# Build macOS .dmg installer locally (version arg required)
bash build/build-mac.sh 1.0.0

# Build Windows portable zip locally
bash build/build-windows.sh 1.0.0
```

## Architecture

**SQL Explorer** is a cross-platform SQL Server Management Studio alternative. Three projects with a clear dependency chain:

```
SqlStudio.App (Avalonia UI, MVVM ViewModels)
  → SqlStudio.Core (services, models, data access — no UI dependency)
  → SqlStudio.LanguageServices (IntelliSense, syntax highlighting — depends on Core for models)
```

### SqlStudio.Core

All business logic lives here. Key patterns:
- **Interfaces/** define service contracts (`IConnectionManager`, `IQueryExecutionService`, `IObjectExplorerService`, `IScriptGenerationService`, `IImportExportService`)
- **Services/** implement them using constructor-injected dependencies
- **DataAccess/SqlConnectionFactory** handles all 3 auth types: SQL Auth, Entra ID Interactive, Entra ID Default (via `Azure.Identity`)
- **DataAccess/SystemTableQueries** contains all `sys.*` catalog queries as string constants
- **Models/** are plain data classes, no Entity Framework — raw ADO.NET with `Microsoft.Data.SqlClient`

### SqlStudio.App

Avalonia desktop app using **CommunityToolkit.Mvvm** with source-generated `[ObservableProperty]` and `[RelayCommand]` attributes.

- DI is configured in `App.axaml.cs` → `ConfigureServices()`. Singletons for connection/settings/cache, transient for query/object services.
- `MainWindowViewModel` orchestrates everything: Object Explorer tree, query tabs, toolbar commands, theme toggle
- `ObjectExplorerNodeViewModel` uses lazy-loading — children load on tree node expand via `OnIsExpandedChanged`
- `QueryTabViewModel` manages per-tab SQL text, execution, results (as `DataTable`), and cancellation
- `ConnectionDialogViewModel` handles all auth flows, Entra ID browser sign-in, database listing, and saved connection management
- Views are AXAML with `x:DataType` for compiled bindings

### SqlStudio.LanguageServices

- `SqlTokenizer` determines cursor context (after FROM → suggest tables, after SELECT → suggest columns, etc.)
- `SchemaCacheService` caches table/view/column names per connection+database pair for fast IntelliSense
- `SqlCompletionProvider` combines keyword completions with schema-aware completions
- `Resources/TSql.xshd` is the AvaloniaEdit XML syntax highlighting definition

## Authentication Flow

Three auth methods supported via `ConnectionAuthType` enum:
- **SqlAuthentication** — standard username/password, works with local/Docker/Azure
- **EntraIdInteractive** — opens default browser for Microsoft sign-in with MFA support
- **EntraIdDefault** — uses `DefaultAzureCredential` (az login, managed identity, env vars)

Entra ID flow in `ConnectionDialogViewModel`:
1. User clicks "Sign in with Microsoft" → `InteractiveBrowserCredential` opens browser
2. JWT token decoded to extract user email (`upn`/`email`/`preferred_username` claims)
3. Token cached permanently by Azure.Identity's `TokenCachePersistenceOptions`
4. Email persisted to `~/.sqlexplorer/entra-credential.json` for next app launch
5. After sign-in, automatically queries `sys.databases` on the server to list accessible databases
6. User selects a database from the list and clicks Connect

## Key Conventions

- .NET 10.0 target, nullable enabled, implicit usings (set in `Directory.Build.props`)
- Central package management via `Directory.Packages.props` — add versions there, not in individual csproj files
- Async-first with `CancellationToken` on all service methods
- `ConnectionManager` owns connection lifetime — services get connections via `IConnectionManager.GetConnectionAsync()`, never create their own
- Persistent user data stored in `~/.sqlexplorer/`:
  - `connections.json` — saved server connections
  - `settings.json` — user preferences (theme, font, timeout)
  - `entra-credential.json` — cached Entra sign-in email/tenant

## CI/CD

GitHub Actions (`.github/workflows/release.yml`):
- **Every push to main** automatically: builds macOS DMG + Windows ZIP, auto-tags as `v1.0.<commit-count>`, creates a GitHub Release with downloadable installers
- No manual tagging required — the pipeline is fully automated
- Version is deterministic: `1.0.<total-commit-count-on-main>`
- macOS build includes ad-hoc code signing to avoid Gatekeeper errors
- Windows MSI uses WiX Toolset (continues on error); ZIP is always created as fallback
- DMG uses consistent app bundle name (`SQL Explorer.app`) so dragging to Applications always replaces the previous version

## Logo & Icons

- Source SVG: `src/SqlStudio.App/Assets/logo.svg`
- Pre-rendered PNGs at all sizes: `logo-16.png` through `logo-1024.png`
- macOS .icns generated by `build/build-mac.sh` using `iconutil`
- Toolbar uses `logo.png` (512px) via `<Image Source="/Assets/logo.png"/>`
