# SubSight

[简体中文](README.md) | [English](README.en.md)

SubSight is a local-first macOS app for tracking recurring payments. It helps you see upcoming renewals, monthly and yearly cost, categories, payment methods, cancellation links, and notes without sending subscription data to a server.

The project also ships a command-line tool, `subsightctl`, for agents, scripts, and power users.

## Features

- Native macOS app built with SwiftUI
- Local JSON storage under Application Support
- Add, edit, pause, resume, and delete subscriptions
- Track amount, currency, billing cycle, next billing date, category, payment method, account hint, cancellation URL, notes, payment limits, and end dates
- Overview for active subscriptions, monthly cost, yearly cost, category breakdown, payment breakdown, and upcoming renewals
- Menu bar item for quick access to upcoming charges
- Privacy mode for hiding sensitive names and amounts on screen
- CSV and JSON import/export
- `subsightctl` CLI for list, get, add, update, pause, resume, delete, summary, breakdown, rates, templates, import, and export

## Requirements

- macOS 15 or later
- Swift 6.1 or later

## Build the App

For local development:

```sh
swift test
Scripts/build-app.sh
open .build/SubSight.app
```

For a release build:

```sh
CONFIGURATION=release Scripts/build-app.sh
open .build/SubSight.app
```

## Build the CLI

From source:

```sh
swift build -c release --product subsightctl
```

Install it somewhere on your `PATH`:

```sh
cp .build/release/subsightctl /usr/local/bin/subsightctl
```

Or install from a GitHub Release artifact:

```sh
tar -xzf subsightctl-<version>-macos-<arch>.tar.gz
chmod +x subsightctl
sudo mv subsightctl /usr/local/bin/subsightctl
```

Verify the install:

```sh
subsightctl help
subsightctl list --json
```

Or run it through SwiftPM during development:

```sh
swift run subsightctl list --status all
```

## CLI Examples

```sh
subsightctl list --json
subsightctl list --query chat --status active
subsightctl get --id <UUID> --json
subsightctl due --days 30 --json
subsightctl templates --json
```

Add and edit records:

```sh
subsightctl add \
  --name "iCloud+" \
  --amount 6 \
  --currency CNY \
  --cycle monthly \
  --next 2026-08-01 \
  --category Cloud \
  --payment "App Store"

subsightctl update --id <UUID> --amount 12 --next 2026-09-01
subsightctl pause --id <UUID>
subsightctl resume --id <UUID>
subsightctl delete --id <UUID>
```

Analyze and exchange data:

```sh
subsightctl summary --base CNY --json
subsightctl breakdown --dimension category --base CNY --json
subsightctl breakdown --dimension payment --base CNY --json
subsightctl export-csv --output ~/Desktop/subsight.csv
subsightctl import-csv --input ~/Desktop/subsight.csv --replace
subsightctl export-json --output ~/Desktop/subsight.json
subsightctl import-json --input ~/Desktop/subsight.json --replace
subsightctl rates --base USD --quotes CNY,EUR,HKD
```

## Agent Usage

Codex, OpenClaw, shell scripts, and other local agents can record subscriptions by calling `subsightctl`. No special integration is required as long as the CLI is on `PATH`.

Suggested instruction for an agent:

```text
Use the `subsightctl` CLI to read and update my SubSight subscriptions.
Do not edit `subscriptions.json` directly.
Before making changes, run `subsightctl list --json`.
After adding or updating a subscription, run `subsightctl get --id <UUID> --json` or `subsightctl list --json` to verify it.
```

Example agent commands:

```sh
subsightctl add \
  --name "GitHub Copilot" \
  --amount 10 \
  --currency USD \
  --cycle monthly \
  --next 2026-08-01 \
  --category AI \
  --payment "Credit Card" \
  --account "work account" \
  --notes "Added by Codex via subsightctl"

subsightctl due --days 30 --json
subsightctl summary --base CNY --json
subsightctl list --query github --json
```

For demos or isolated agent runs, point the CLI at a separate data file:

```sh
SUBSIGHT_DATA_FILE=/tmp/subsight-agent-demo.json subsightctl add \
  --name "Demo Service" \
  --amount 20 \
  --currency USD \
  --cycle monthly \
  --next 2026-08-01
```

## Data Location

By default, the app and CLI share this file:

```text
~/Library/Application Support/SubSight/subscriptions.json
```

For tests, demos, or agent sandboxes, point the CLI/app at a different file:

```sh
SUBSIGHT_DATA_FILE=/tmp/subsight-demo.json subsightctl list --json
```

Do not commit personal `subscriptions.json` files to the repository.

## Privacy Notes

SubSight stores subscription records locally and does not upload subscription names, amounts, account hints, notes, or cancellation links. Exchange-rate lookups use `https://api.frankfurter.dev/v2/rates` and send only currency codes such as `USD` and `CNY`.

## Release Artifacts

Create GitHub Release-ready artifacts:

```sh
Scripts/package-release.sh
```

The script writes artifacts to:

```text
.build/release-artifacts/SubSight-<version>/
```

It produces:

- `SubSight-<version>-macos-app.zip`
- `subsightctl-<version>-macos-<arch>.tar.gz`
- `SHA256SUMS.txt`

Upload those files to a GitHub Release.

After pushing to GitHub, tags that start with `v` will trigger the release workflow:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow will run tests, package the app and CLI, and create a GitHub Release.

## GitHub Setup

Initialize and push a new repository:

```sh
git init
git add .
git commit -m "Initial release"
git branch -M main
git remote add origin git@github.com:<your-name>/SubSight.git
git push -u origin main
```

Before committing, configure public Git author information so a private email address does not appear in commit metadata:

```sh
git config user.name "<your GitHub username or display name>"
git config user.email "<your GitHub noreply email>"
```

## Design

- [SubSight Design System](docs/SubSight-Design-System.md)

## License

MIT. See [LICENSE](LICENSE).
