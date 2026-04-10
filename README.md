<p align="center">
  <img src="SQLExplorer/Resources/logo-256.png" width="128" alt="SQL Explorer logo">
</p>

<h1 align="center">SQL Explorer</h1>

<p align="center">
  A native macOS SQL Server management app built with Swift and SwiftUI.<br>
  Fast, lightweight, and designed for developers who work with SQL Server on Mac.
</p>

<p align="center">
  <a href="https://github.com/StephanWBC/sql-explorer/releases/latest"><img src="https://img.shields.io/github/v/release/StephanWBC/sql-explorer?style=flat-square&label=latest%20release" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift 6.0">
  <a href="https://github.com/StephanWBC/sql-explorer/actions"><img src="https://img.shields.io/github/actions/workflow/status/StephanWBC/sql-explorer/release.yml?style=flat-square&label=build" alt="Build Status"></a>
</p>

---

## Features

- **Multi-tab query editor** with SQL syntax highlighting, autocomplete, and keyword suggestions
- **Object Explorer** sidebar with expandable schema tree (databases, tables, columns, views, stored procedures)
- **Database Diagrams** — visual entity-relationship diagrams with FK lines, drag-to-arrange tables
- **Connection management** — save, group, and organize server connections with environment labels
- **Azure AD / Entra ID authentication** via MSAL (interactive + silent token flows)
- **SQL & Windows authentication** support
- **Query history** — automatically saved, searchable, re-runnable
- **Results grid** with copy, export, and row count
- **Error panel** with categorized errors, pre-validation, and fix suggestions
- **Favorites & Groups** for organizing connections
- **Keyboard shortcuts** — `Cmd+Enter` to execute, `Cmd+T` for new tab, `Cmd+W` to close

## Installation

### Download

Grab the latest `.dmg` from [**Releases**](https://github.com/StephanWBC/sql-explorer/releases/latest), open it, and drag **SQL Explorer** to your Applications folder.

### Prerequisites

SQL Explorer uses [FreeTDS](https://www.freetds.org/) to connect to SQL Server:

```bash
brew install freetds
```

### Build from source

```bash
git clone https://github.com/StephanWBC/sql-explorer.git
cd sql-explorer
swift build -c release
```

## Architecture

```
SQLExplorer/
├── App/              @main entry point, AppState (global state)
├── Models/           Codable data models (ConnectionInfo, QueryResult, ERDModel, etc.)
├── Services/         Business logic (ConnectionManager, AuthService, ConnectionStore)
├── Views/            SwiftUI views (MainView, QueryEditor, Results, ERD, etc.)
├── Editor/           SQL syntax highlighting (NSTextView + NSLayoutManager)
├── Utilities/        FreeTDS bridge, Keychain helper
└── Resources/        SQL keywords, app icon

Sources/CFreeTDS/     System library module for FreeTDS headers
Sources/CFreeTDSShim/ C shim exposing FreeTDS macros to Swift
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI + AppKit bridging |
| SQL Server | FreeTDS (db-lib) via SPM system library |
| Auth | MSAL.Swift — Entra ID with ASWebAuthenticationSession |
| Persistence | Codable JSON (`~/.sqlexplorer/connections.json`) |
| Credentials | macOS Keychain via Security framework |
| CI/CD | GitHub Actions — auto-release DMG on every push to main |

## Requirements

- macOS 14.0 (Sonoma) or later
- [FreeTDS](https://www.freetds.org/) (`brew install freetds`)

## License

This project is proprietary software. All rights reserved.
