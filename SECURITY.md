# Security Considerations

## Overview

Spook is a network traffic monitor that displays per-application network activity. This document describes the security model, data handling, and potential concerns.

## System Access

### External Commands

Spook uses three system utilities to gather network data:

| Command | Path | Purpose |
|---------|------|---------|
| `netstat` | `/usr/sbin/netstat` | Total network interface statistics |
| `nettop` | `/usr/bin/nettop` | Per-process network traffic |
| `lsof` | `/usr/sbin/lsof` | Active network connections |

**Security notes:**
- All executable paths are hardcoded (no PATH lookup)
- No user input is passed to these commands
- Commands run with the same privileges as the app (user-level, no root required)

### No Elevated Privileges

Spook does not require:
- Administrator/root access
- System Integrity Protection (SIP) modifications
- Kernel extensions
- Network extensions or content filters

## Data Collection

### What is collected

| Data Type | Purpose | Storage |
|-----------|---------|---------|
| Process names | Display in app list | Memory only (not persisted) |
| Process IDs | Match traffic to apps | Memory only |
| Remote IP addresses | Show connection details | Memory only |
| DNS-resolved hostnames | Show friendly names | In-memory cache (5 min TTL) |
| Byte counts (total/per-app) | Historical graphs | SQLite database |
| Daily/hourly aggregates | Usage trends | SQLite database |

### What is NOT collected

- Packet contents or payloads
- URLs or HTTP request data
- Authentication credentials
- Personal identifiable information
- Any data transmitted off-device

### Data Storage

Historical data is stored in:
```
~/Library/Application Support/Spook/history.sqlite
```

- Data is stored locally only
- No cloud sync or network transmission
- Automatic pruning after 30 days
- User can clear all history via Settings

## Privacy

### No Telemetry

Spook does not:
- Phone home or check for updates
- Collect analytics or usage metrics
- Transmit any data over the network
- Include any third-party analytics SDKs

### Local-Only Operation

All monitoring data stays on your Mac. The app has no network communication of its own.

## Potential Concerns

### Information Exposure

The app displays:
- Which applications are using the network
- Remote IP addresses and ports
- Resolved hostnames

This information could be sensitive in shared environments. Consider:
- Closing the detail window when screen sharing
- Not pinning the window when others can see your screen

### Process Name Parsing

Process names come from system tools and are displayed as-is. While this is safe for display, the code uses parameterized SQL queries to prevent any injection if process names contain special characters.

## Code Signing

For distribution, the app should be properly code signed:

```bash
# Ad-hoc signing (current)
codesign --force --sign - Spook.app

# For distribution, use a Developer ID
codesign --force --sign "Developer ID Application: Your Name" Spook.app
```

## Reporting Security Issues

If you discover a security vulnerability, please:

1. Do not open a public issue
2. Email the maintainer directly with details
3. Allow reasonable time for a fix before disclosure

## Audit History

| Date | Auditor | Findings |
|------|---------|----------|
| Jan 2026 | Initial development | SQL injection in pruneOldData (fixed) |
