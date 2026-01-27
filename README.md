# Spook

> *"The Spook Who Sat By the Port"*

A lightweight macOS menu bar app that monitors network traffic in real-time.

The name is a play on Sam Greenlee's 1969 novel *"The Spook Who Sat By the Door"* — because this app sits quietly by your network ports, watching the data flow.

## Features

### Menu Bar Display
- Live upload/download speeds: `↓ 1.2 MB/s ↑ 340 KB/s`
- Updates every second
- Click to open detail window, right-click for menu

### Detail Window
- **Per-app traffic breakdown** — see which apps are using your network
- **Connection details** — expand any app to see remote IPs, ports, and resolved hostnames
- **Traffic graphs** — visualize usage over 1 hour, 24 hours, or 7 days
- **Direction filters** — focus on download-only or upload-only traffic
- **Search** — quickly find specific apps
- **Freeze/Resume** — pause list reordering to interact with rapidly changing entries
- **Pin mode** — keep the window visible while you work

### History & Preferences
- Historical data stored locally (SQLite)
- Daily/weekly usage tracking
- Optional launch at login (off by default)
- Data retained for 30 days, auto-pruned

## Screenshots

*Coming soon*

## Requirements

- macOS 14.0 (Sonoma) or later
- No special permissions required

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/qaid/spook.git
cd spook

# Build
swift build -c release

# Deploy to ~/Applications
./deploy.sh
```

### Pre-built Binary

*Coming soon*

## How It Works

Spook uses built-in macOS tools to gather network statistics:

| Tool | Purpose |
|------|---------|
| `netstat` | Total network interface byte counts |
| `nettop` | Per-process network traffic |
| `lsof` | Active connection details |

No kernel extensions, network filters, or elevated privileges required.

## Privacy

- All data stays on your Mac
- No telemetry or analytics
- No network requests from the app itself
- See [SECURITY.md](SECURITY.md) for details

## Build System

This project uses Swift Package Manager and can be built without Xcode:

```bash
swift build              # Debug build
swift build -c release   # Release build
./deploy.sh              # Create .app bundle
```

See [deploy.sh](deploy.sh) for bundle assembly details.

## Project Status

### Completed
- Menu bar indicator with live speeds
- Floating detail window with per-app breakdown
- Connection details with DNS resolution
- Historical data storage and graphs
- Preferences window
- Direction filtering (download/upload)
- Search and freeze functionality

### Phase 4: Refinement (Not Yet Started)
- [ ] Performance optimization
- [ ] Memory profiling
- [ ] Edge case handling
- [ ] Accessibility audit

## Contributing

Contributions welcome! Please read the security considerations in [SECURITY.md](SECURITY.md) before submitting code changes.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [Little Snitch](https://www.obdev.at/products/littlesnitch) and other network monitoring tools
- Built with Swift, SwiftUI, and determination
