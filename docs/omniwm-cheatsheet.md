# OmniWM Cheat Sheet

Use workspaces for sustained activities. Use app switching for short interruptions.

## Workspace map

| Key | Workspace | Main windows |
| --- | --- | --- |
| `⌥1` | Todoist | Todoist |
| `⌥2` | Personal | Personal Safari, Brave, personal Chrome |
| `⌥3` | Terminal | Ghostty and its dedicated Safari window |
| `⌥4` | ChatGPT | ChatGPT app and ChatGPT Chrome window |
| `⌥5` | Shopping | Shopping, CardPointers, parental controls |
| `⌥6` | Messages | Messages |
| `⌥7` | Home | Home Assistant |
| `⌥8` | Calendar | Calendar |
| `⌥9` | Work | Work Safari and Slack |
| `⌥0` | Parking | Bitwarden, Snagit, Backblaze, Phone, and rarely used windows |

## Daily navigation

| Shortcut | Action |
| --- | --- |
| `⌥1` through `⌥0` | Go directly to a workspace |
| `⌃⌥Tab` | Return to the previous workspace |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | Focus a window in that direction |
| `⌥Tab` | Focus the previously used window |
| `⌘Tab` | Switch applications or inspect apps that need attention |
| `⌘\`` | Switch windows in the current application |
| `⌃⌥Space` | Search for a window |
| `⌥⇧O` | Show the OmniWM overview |

Prefer direct workspace keys when you know the destination. Use directional focus
inside a workspace. Keep using `⌘Tab` for brief app changes and notifications.

## Move and arrange windows

| Shortcut | Action |
| --- | --- |
| `⌥⇧1` through `⌥⇧0` | Move the focused window to a workspace |
| `⌃⌥⇧←` `⌃⌥⇧→` `⌃⌥⇧↑` `⌃⌥⇧↓` | Move the focused window in that direction |
| `⌥Return` | Toggle full-screen tiling for the focused window |
| `⌥,` / `⌥.` | Cycle the focused column through useful widths |
| `⌥-` / `⌥=` | Decrease or increase the focused column width |
| `⌥⇧B` | Balance window sizes |
| `⌥T` | Toggle tabs for the focused column |

Keep one window large most of the time. For a temporary side-by-side layout,
focus the second window, move it beside the first window, and adjust the width.
Use `⌥Return` when you want to return one window to a large view.

## Windows available from any workspace

| Shortcut | Action |
| --- | --- |
| `⌃⌥D` | Show or hide the Downloads Finder window |
| `⌃⌥P` | Bring Photos to the current workspace or return it to Parking |

Finder is the OmniWM scratchpad. Only its managed Downloads window uses this
behavior. Photos uses its own summon-and-return workflow.

## Common workflows

### Open a link from Ghostty

Click the link normally. The managed URL handler opens it in the dedicated
Safari window used with workspace 3.

### Enter a two-factor authentication code

1. Leave the website open.
2. Use `⌘Tab` to open the email or authentication app briefly.
3. Copy the code.
4. Use `⌘Tab` to return to the website.
5. Paste the code.

Do not change workspaces for a short interruption unless the needed window is
already easier to reach with its direct workspace key.

### Work with two windows for a short time

1. Bring both windows to the same workspace.
2. Use `⌃⌥Arrow` to focus each window.
3. Use `⌃⌥⇧Arrow` to put them side by side.
4. Use `⌥,`, `⌥.`, `⌥-`, or `⌥=` to adjust their widths.
5. Move the temporary window home when finished.

## Shortcuts that remain standard macOS behavior

| Shortcut | Action |
| --- | --- |
| `⌥←` / `⌥→` | Move by one word in text |
| `⌥⇧←` / `⌥⇧→` | Select text by word |
| `⌘⇧[` / `⌘⇧]` | Change Ghostty tabs |

OmniWM must not claim these shortcuts.
