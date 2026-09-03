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

Safari uses its `Personal`, `Development`, and `Work` profiles in workspaces 2,
3, and 9. Chrome normally belongs to ChatGPT in workspace 4. Brave belongs to
Shopping in workspace 5. Move a rare Capital One Shopping Chrome window to
workspace 5 manually after login.

## After login

A one-shot recovery waits for restored windows to settle. It then reapplies a
workspace rule only when one managed rule clearly matches the window. Unknown,
titleless, and ambiguous windows remain where they are. Recovery does not keep
running during normal work.

Use this read-only command to inspect proposed repairs:

```text
recover-omniwm-workspaces --check
```

Use this command to run the same recovery again. It can move uniquely matched
windows:

```text
recover-omniwm-workspaces
```

## Daily navigation

| Shortcut | Action |
| --- | --- |
| `⌥1` through `⌥0` | Go directly to a workspace |
| `⌃⌥Tab` | Return to the previous workspace |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | Focus a window in that direction |
| `⌥Tab` | Focus the previously used window |
| `⌘Tab` | Switch applications or inspect apps that need attention |
| `⌘\`` | Switch windows in the current application |
| `⌥⇧O` | Show all workspaces and windows in the OmniWM overview |
| `⌃⌥Space` | Search windows and application menu actions |
| `⌃⌥M` | Open the active application's menu near the pointer |
| Hold `⌃⌥` for 200 ms | Temporarily show the workspace bar |

Prefer direct workspace keys when you know the destination. Use the overview
when you lose track of a window. Use the command palette when you know a name or
action but not its location. Keep using `⌘Tab` for brief app changes and
notifications.

The workspace bar stays hidden and does not reserve screen space. Hold `⌃⌥` for
200 ms when you need the bar. Release the keys to hide it. A quick directional
shortcut does not show the bar.

## Move and arrange windows

| Shortcut | Action |
| --- | --- |
| `⌥⇧1` through `⌥⇧0` | Move the focused window to a workspace |
| `⌃⌥⇧←` `⌃⌥⇧→` `⌃⌥⇧↑` `⌃⌥⇧↓` | Move the focused window in that direction |
| `⌥Return` | Toggle full-screen tiling for the focused window |
| `⌥,` / `⌥.` | Cycle the focused column through useful widths |
| `⌥-` / `⌥=` | Decrease or increase the focused column width |
| `⌥⇧B` | Balance window sizes |
| `⌥T` | Toggle tabs for a column that contains multiple windows |
| `⌥⇧F` | Toggle full-width display for the focused column |

Keep one window large most of the time. For a temporary side-by-side layout,
focus the second window, move it beside the first window, and adjust the width.
Use `⌥Return` when you want to return one window to a large view.

### Use tabbed columns

`⌥T` changes how one column displays its windows. It does not combine separate
columns. First use `⌃⌥⇧←` or `⌃⌥⇧→` to move a window into the neighboring
column. Then use `⌥T` to show one window at a time. Use `⌃⌥↑` and `⌃⌥↓` to
change the active window in that column.

### Temporarily use the full width

`⌥⇧F` makes the focused column use the full primary span of the display. Press
it again to restore the column's saved width. The first press has no visible
effect when the column's normal width already fills the display. This does not
replace `⌥Return`, which toggles OmniWM's full-screen tiling mode.

### Understand floating windows

A floating window leaves the tiling columns. It keeps its own size and position
and can overlap tiled windows. It still belongs to one workspace. A scratchpad
adds summon-and-hide behavior to floating windows, which makes it available from
other workspaces.

The Downloads Finder shortcut uses scratchpad behavior. Photos uses a separate
summon-and-return workflow. Broad floating rules for Finder or Photos would
affect every matching window, so they are intentionally not configured.

## Windows available from any workspace

| Shortcut | Action |
| --- | --- |
| `⌃⌥D` | Show or hide the Downloads Finder window |
| `⌃⌥P` | Bring Photos to the current workspace or return it to Parking |
| `⌃⌥H` | Show or hide this cheat sheet in a floating panel |

Press `Escape` or `⌃⌥H` to hide the cheat-sheet panel.

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
