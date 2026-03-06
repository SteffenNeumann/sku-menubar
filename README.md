# SKU Budget — macOS Menu Bar App

A lightweight macOS menu bar app that shows your GitHub SKU billing usage in real time.

## Features

- **Live budget bars** — today's usage, monthly spend, remaining budget
- **28-day habit tracker** — contribution-style grid with animated hover labels
- **Glassmorphism UI** — native macOS blur/material background
- **Auto-refresh** — configurable interval (1–30 min)
- **Euro display** — all amounts in €

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ (Xcode Command Line Tools)
- GitHub Fine-grained Personal Access Token
  - User account → Permission: **Plan (read)**
  - Organisation → Permission: **Administration (read)**

## Build & Run

```bash
git clone https://github.com/SteffenNeumann/sku-menubar.git
cd sku-menubar
swift build -c release
cp .build/release/SKUMenuBar ~/Applications/SKUMenuBar
open ~/Applications/SKUMenuBar
```

## Auto-start at Login

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Users/'$(whoami)'/Applications/SKUMenuBar", hidden:false}'
```

## Configuration

Click the **€** icon in the menu bar → open **Einstellungen**:

| Field | Description |
|---|---|
| GitHub Token | Fine-grained PAT |
| Account-Typ | User or Organisation |
| Username / Org | Exact GitHub username |
| Produkt-Filter | All / Actions / Copilot / Packages |
| Monatsbudget | Your monthly spending limit in € |
| Auto-Update | Refresh interval |

Settings are stored in `UserDefaults` (local only, token never leaves your machine).

## Data Source

Uses the [GitHub Enhanced Billing REST API](https://docs.github.com/en/rest/billing/usage):

- `GET /users/{name}/settings/billing/usage` — monthly & daily usage
- Data availability: GitHub processes billing data with a delay of several hours.
