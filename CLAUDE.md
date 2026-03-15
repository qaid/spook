# Spook - macOS Network Traffic Monitor

## Overview
Spook is a lightweight macOS menu bar app that monitors network traffic in real-time. It shows per-app traffic breakdown, connection details with DNS resolution, and traffic history graphs.

## Build
```bash
swift build
```

## Deploy (build + bundle .app)
```bash
./deploy.sh
```

## Tech Stack
- **Language**: Swift 5.9
- **UI**: SwiftUI + AppKit (NSPanel, NSStatusItem)
- **Build**: Swift Package Manager (no external dependencies)
- **Data**: SQLite (via direct C API) for traffic history
- **Target**: macOS 14.0+ (Sonoma)

## Architecture
- **App layer** (`Sources/Spook/App/`): AppDelegate manages menu bar status item and floating NSPanel
- **Views** (`Sources/Spook/Views/`): SwiftUI views with design system tokens from `DesignSystem.swift`
- **Services** (`Sources/Spook/Services/`): NetworkMonitor (@Observable, @MainActor), DNSResolver (Actor), HistoryStore (Actor)
- **Models** (`Sources/Spook/Models/`): AppTraffic and Connection data types

## Key Patterns
- Menu bar app using `LSUIElement: true` with optional dock visibility
- Floating `NSPanel` with HUD material for detail view
- `@Observable` for reactive state, Actor isolation for thread-safe services
- System commands (`netstat`, `nettop`, `lsof`) for network monitoring
- Design system in `DesignSystem.swift` — use `Spacing.*`, `SpookFont.*`, `Color.spook*`, `CornerRadius.*` tokens

## Conventions
- No external dependencies — uses only system frameworks
- Colors: blue for download, green for upload (via `Color.spookDownload`/`.spookUpload`)
- Use capsule-shaped controls for toggles and badges
- Hover states on interactive elements using `.hoverHighlight()` or `@State isHovered`
