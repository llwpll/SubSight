# SubSight Design System

SubSight is a calm macOS subscription finance cockpit. The interface should feel local, private, translucent, and precise: one glance for recurring cost, one click to add or inspect.

## Design Principles

- Local-first: make the app feel like a quiet native utility, not a web dashboard.
- Glass foundation: one full-window translucent material surface; cards sit on top as subtle glass panels.
- Financial clarity: numbers, dates, and renewal status are visually stronger than decoration.
- Low-friction editing: every selected subscription should be editable without navigation.
- Empty states teach the next action instead of looking broken.

## Visual Direction

The base screen is a split workspace with two explicit right-pane modes:

- Left rail: brand, summary phrase, a visible Overview entry, upcoming renewal list, empty state when there is no data.
- Main canvas in overview mode: overview title, template/import/export/add actions, metric row, breakdown panels, and a compact workspace summary.
- Main canvas in detail mode: detail title, Back to Overview action, and the selected subscription editor only.
- Modal: compact glass editor with grouped billing/reminder fields.

The window uses macOS traffic lights and a hidden title bar. Do not add a separate custom title bar.

## Tokens

### Material

- Window base: `NSVisualEffectView.Material.hudWindow`, `behindWindow`
- Primary panel: SwiftUI `.regularMaterial`
- Tint wash: cool blue from top-left, warm amber from bottom-right
- Divider: white at 20% opacity
- Panel stroke: white at 32-42% opacity

### Color

- Accent blue: system blue for brand and primary actions
- Success green: active subscriptions and valid status
- Warning amber: yearly spend and renewal attention
- Muted text: `.secondary`
- Avoid large saturated fills; use tint blocks at 8-15% opacity.

### Radius

- Standard card radius: `8`
- Icon well radius: `8`
- Pill radius: capsule only for compact status labels

### Spacing

- Window content inset: `26`
- Sidebar horizontal inset: `22`
- Component gap: `12`
- Section gap: `18`
- Card padding: `14-18`

### Typography

- Screen title: rounded, 30pt, semibold
- Brand title: rounded, 28pt, semibold
- Card value: 20-22pt semibold, monospaced digits for money
- Row title: 14pt semibold
- Captions: caption/callout with secondary color

## Components

### Brand Lockup

Icon well + `SubSight` wordmark + one-line value statement. The wordmark is always visible in the left rail.

### Metric Tile

A reusable panel with:

- 34x34 tinted icon well
- caption label
- monospaced value
- equal-width layout in a metric row

### Insight Panels

Compact glass panels under the metric row show category share, payment-method share, and upcoming renewals. Keep them dense and scannable: up to three breakdown rows and up to four upcoming items.

### Header Icon Buttons

44x44 glass square buttons with SF Symbols for template, import, export, and add. The entire square is the hit target.

### Sidebar Empty State

Glass card explaining that no subscriptions exist and that the plus button adds the first item.

### Subscription Row

Icon well, name, category/cycle, amount, next billing date. Selected state uses a subtle accent wash.

### Editor Modal

Custom glass editor, not system `Form`. Use grouped panels: essentials, billing, reminder, account/cancellation metadata, notes. Every modal must expose a top-right close icon in addition to footer actions.

### Detail Management

The selected subscription detail should expose account hint and cancellation URL as editable fields. If a valid cancellation URL exists, provide an icon-labeled button to open it in the browser.

### Reminder Scheduling

Reminder permission is never requested on launch. The detail reminder panel exposes an explicit button that asks for local notification permission and schedules reminders for the current subscription set.

## Current Screen Mock

```text
+-----------------------------------------------------------------------+
| traffic lights                                                        |
|                                                                       |
|  SubSight rail      |  Overview header              [tpl][↓][↑][+]    |
|  Brand + tagline    |  Metric tile   Metric tile   Metric tile        |
|  Upcoming           |  Category      Payment      Upcoming            |
|  Empty/list card    |                  Empty/detail workspace          |
|                     |                                                 |
+-----------------------------------------------------------------------+
```

When a subscription is selected, replace the overview content entirely:

```text
+-----------------------------------------------------------------------+
|  SubSight rail      |  Detail header                    [Overview]     |
|  Overview entry     |  Hero + editable fields                           |
|  Subscription list  |  Billing / Reminder / Manage / Notes              |
+-----------------------------------------------------------------------+
```

## Feature Roadmap

1. Add flow polish: custom editor modal, auto-select newly added subscriptions.
2. Currency normalization: store original currency, show CNY totals with exchange-rate timestamp.
3. Renewal timeline: next 7 days, next 30 days, overdue.
4. Templates: ChatGPT, iCloud, Netflix, Spotify, Setapp, Adobe, Notion, GitHub.
5. Agent command surface: get, update, pause, resume, import/export.
6. Menu bar companion: monthly total and next renewal.
7. Category budgets and yearly trend.
8. JSON backup/restore UI.
9. iCloud sync as an optional user-controlled setting.
