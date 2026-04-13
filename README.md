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
</p>

---

## Features

### Query & Results
- **Multi-tab query editor** with SQL syntax highlighting, autocomplete, and keyword suggestions
- **Results grid** — NSTableView-backed, Excel-style cell selection, click-to-copy, context menus, export
- **Query history** — automatically saved, searchable, re-runnable
- **Error panel** — categorized errors, pre-validation, fix suggestions
- **Keyboard shortcuts** — `Cmd+Enter` execute, `Cmd+T` new tab, `Cmd+W` close

### Object Explorer
- Expandable schema tree (databases, schemas, tables, columns, views, stored procedures)
- Schema filter chips + search in the sidebar
- Auto-focus query editor when a new tab opens

### Database Diagrams (ERD)
- Visual entity-relationship diagrams with FK lines and drag-to-arrange tables
- Hierarchical auto-arrange layout
- Save and load named diagrams per database
- Related-table suggestions in sidebar and on canvas
- Schema filter + grouped-by-schema table list

### Azure SQL Integration
- **Entra ID sign-in** via MSAL — silent refresh, webview fallback, Keychain-cached tokens
- **Cross-subscription** Groups and Favorites with a badge for members in a different subscription
- **Browse** all Azure SQL databases across every subscription you have access to
- **Auto-trigger sign-in** when connecting to a saved Entra member
- **Manual connections** — either fill the form or paste a connection string

### Performance Monitor (Azure SQL)
Open from Object Explorer, Groups, or Favorites. Pulls Azure Monitor metrics
(CPU, DTU, Data IO, Log IO, Storage, Workers, Sessions, deadlocks, connection
successes/failures, firewall blocks) with:
- **Hover ruler** — dashed line + dot snap to the nearest sampled point with a
  full-precision timestamp tooltip, so spikes can be pinpointed on 24h / 7d windows
- **Stats strip** — Min / Avg / P95 / Max for every chart
- **Trend delta** — direction arrow + change vs. the start of the window
- **Threshold coloring** — amber above 75%, red above 90% for percentage metrics
- **Expand** — double-click a chart to open a focused view with peak callout and CSV export
- **Pin** — right-click to pin a metric to the top of the grid (persisted)
- **Auto-refresh** every 60 s, configurable time range (1h / 6h / 24h / 7d)

### Connections
- Save, group, and organize server connections with environment labels
- Favorites & Groups for quick access
- SQL, Windows, and Entra ID authentication

## Installation

Download the latest `.dmg` from [**Releases**](https://github.com/StephanWBC/sql-explorer/releases/latest), open it, and drag **SQL Explorer** to your Applications folder.

## Requirements

- macOS 14.0 (Sonoma) or later

## License

This project is proprietary software. All rights reserved.
