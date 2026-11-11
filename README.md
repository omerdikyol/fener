# fener

A keyboard launcher for macOS, in the spirit of Omarchy's menus. Native Swift and AppKit, no
dependencies, configured with plain TOML files. One key opens a panel; type to search apps,
files, windows, clipboard history, emoji, snippets, bookmarks and your own menus, or type a
sum, a unit or currency conversion, or a time zone question and read the answer.

fener stays resident (no Dock icon) and opens with its own shortcut or from the command
line, so any hotkey tool can open it too. On an Apple Silicon Mac the panel is on screen about 30 ms after
the key press.

## Install

Requirements: macOS 14 or later, the Swift toolchain (Xcode or the Command Line Tools:
`xcode-select --install`), and a [Nerd Font](https://www.nerdfonts.com) for the icons (the
default theme uses JetBrainsMono Nerd Font; set another in a theme).

```sh
git clone https://github.com/omerdikyol/fener.git
cd fener
./scripts/install.sh
```

The script builds a release binary, copies it to `~/.local/bin/fener`, and starts it as a
LaunchAgent (`io.github.omerdikyol.fener`), so it runs at login and restarts if it crashes.
Run it again to update. `./scripts/uninstall.sh` stops and removes it and leaves your
config alone.

On its first start fener creates `~/.config/fener/config.toml` with every default. To start
from the example menus, themes and snippets too (existing files are not overwritten):

```sh
mkdir -p ~/.config/fener
rsync -a --ignore-existing extras/menus extras/themes extras/snippets extras/quicklinks.toml ~/.config/fener/
```

Some example menus call tools you may not have (`omniwmctl` for OmniWM, `sketchybar`); they
say so in the menu instead of failing. Without a `menus/menu.toml`, the empty search lists
your apps.

### A key to open it

Set a shortcut in fener Settings › Shortcut (`fener show preferences`) and press the keys you
want, or write it in `config.toml`:

```toml
shortcut = "shift+cmd+space"
```

It needs Command or Control, or an F-key, since Option and Shift alone type characters on
many layouts. fener registers it as a system hotkey, which needs no Input Monitoring or
Accessibility permission. A shortcut another app already uses is reported in the panel.

You can also leave `shortcut` empty and run `~/.local/bin/fener toggle` from any tool that
can run a shell command. With [Karabiner-Elements](https://karabiner-elements.pqrs.org),
`extras/karabiner-rule.json` maps Hyper+Space (Control+Option+Command+Space, for example
Caps Lock remapped to Hyper) to that command. Add it under Complex Modifications, or paste
it into the `rules` array of `~/.config/karabiner/karabiner.json`. skhd, Hammerspoon or
BetterTouchTool work the same way.

## Using it

| Key | Does |
| --- | --- |
| Return | run the selected row |
| Up / Down, Ctrl+N / Ctrl+P, Ctrl+J / Ctrl+K | move |
| Cmd+1 … Cmd+9 | run row 1–9 |
| Cmd+K | more actions for the selected row (Show in Finder, Quick Look, Copy Path, Edit, Quit, …) |
| Cmd+Return | the first of those actions |
| Backspace on an empty search | back to the previous menu |
| Escape | close |

The main search ranks apps, menus, system actions, snippets, System Settings panes, recent
editor projects, generators, browser bookmarks and open windows together. It learns which
row you pick for what you type, so `g` soon means the app you open with `g`. A web search
row is always last.

Start with a prefix to search one thing (change them in `[prefixes]`):

| Prefix | Searches |
| --- | --- |
| `=` | calculator |
| `/` | files (Spotlight, under your home folder) |
| `:` | emoji and symbols |
| `*` | clipboard history |
| `>` | your menus |
| `;` | open windows (OmniWM) |
| `!` | snippets |

Answers appear as you type, with no prefix needed:

```
2 * (3 + 4)^2         10 km to mi          72 f in c          1.5 gib to mb
100 usd to try        €50 in gbp
time in tokyo         15:00 istanbul to london
days until dec 31     today + 30 days      2026-12-24 + 1 month
```

`g fener`, `gh swift toml` and other `<keyword> <text>` searches open in your browser; add
your own in `quicklinks.toml`.

### Command line

```
fener toggle               show or hide the panel
fener show <menu> [text]   open a menu or built-in view, optionally with text typed
fener hide
fener reload               re-read config, menus, themes and apps
fener pick-color           pick a color on screen; copies its hex value
fener query [@view] text   print what a search lists (for scripts and tests)
fener config [defaults]    show the config files, or print every default
fener log [-f]             show (or follow) the log
fener ping                 exit 0 if fener is running
```

Built-in views for `fener show` and for menu entries: `apps`, `files`, `recent`,
`screenshots`, `clipboard`, `emoji`, `snippets`, `windows`, `calc`, `dictionary`,
`system`, `quit`, `settings` (System Settings panes), `audio`, `bookmarks`, `projects`,
`generate`, `processes`, `used` (recently picked) and `preferences` (fener's own settings).

## Configuration

Everything lives in `~/.config/fener/` and applies as soon as you save a file:

```
config.toml             your settings
config.reference.toml   every option with its default and a comment (rewritten on start, never read)
quicklinks.toml         web search keywords and the default engine
themes/<name>.toml      colors, font and layout; select with theme = "<name>"
menus/<name>.toml       your menus
menus/<name>[.sh]       menus generated by a script
snippets/<name>.txt     text snippets
```

Most settings can also be changed from the panel: Setup › fener Settings, or
`fener show preferences`. Those changes are written to `config.toml` with your comments
kept. Mistakes are listed at the top of the empty search and in `fener log`, with the line
number. A wrong value or unknown key is skipped and the rest of the file applies; a file that
is not valid TOML is ignored (built-in defaults are used) until it is fixed.

### Menus

A menu is a TOML file of entries:

```toml
prompt = "Capture…"
width = 320                       # optional panel width

[[entry]]
name = "Screenshot of an area"
icon = "nf-md-crop"               # Nerd Font glyph name, SF Symbol, or an app or image path
command = "screencapture -ic"     # run with /bin/sh -c

[[entry]]
name = "Logs"
command = "tail -f /var/log/system.log"
terminal = true                   # run in a terminal window (terminal_command in config.toml)

[[entry]]
name = "Restart Dock"
command = "killall Dock"
confirm = true                    # ask first

[[entry]]
name = "Themes"
menu = "theme"                    # open another menu or a built-in view
```

A menu can also be an executable file. Run with no arguments, it prints its entries, one per
line, as plain names or JSON objects such as
`{"name": "Dark Mode: On", "value": "dark", "icon": "nf-md-theme_light_dark"}` (or one JSON
array). fener runs it again with the chosen entry's `value` (or name) as `$1`. A line
`{"refresh": 2}` makes fener re-run it every 2 seconds while it is open.
`extras/menus/toggle.sh` is a small example.

### Snippets

One file per snippet in `snippets/`, named after the file. Picking one copies its text with
these filled in: `{clipboard}`, `{uuid}`, `{date}`, `{time}`, `{datetime}` and
`{date:<pattern>}` (a `DateFormatter` pattern such as `{date:EEE d MMM}`). Paste it with
Cmd+V; fener does not type for you, because that needs the Accessibility permission.

### Themes

Copy `extras/themes/tokyo-night.toml` to `themes/<name>.toml`, change what you like
(colors, opacity, font, width, row height, corner radius, how many rows show) and set
`theme = "<name>"`. Catppuccin Mocha is included as a second example.

## Privacy and permissions

- **Network:** none, except one file. When you type a currency conversion and the cached
  rates are over a day old, fener downloads the European Central Bank's public daily
  reference rates. `[currency] enabled = false` turns that off. There is no telemetry and no
  update check. Quicklinks and web search rows open your browser; fener sends nothing itself.
- **Clipboard history** is stored encrypted (AES-GCM) in
  `~/Library/Application Support/fener/clipboard`, with a random key in your login
  Keychain, readable only by your user and excluded from backups. Copies that password
  managers mark as concealed or transient are never recorded, nor anything copied while an
  app in `[clipboard] ignore_apps` is in front. Items older than `keep_days` are deleted.
  `[clipboard] enabled = false` turns it off.
- **Learning** (which row you picked for which text, and the last 10 picks) stays in
  `~/Library/Application Support/fener/learned.json`. System › Forget Search History clears
  it; `learn_queries = false` turns it off. Keystrokes and abandoned searches are never
  recorded.
- **The log** (`~/Library/Logs/fener/fener.log`) records events and errors, never what you
  type or copy.

fener asks for no permissions up front and does not need Accessibility, Input Monitoring or
Screen Recording. macOS may ask once for:

- Keychain access, when the clipboard key is first read. Because the binary is built locally
  and not signed, macOS may ask again after you rebuild; choose Always Allow.
- Automation of System Events or Finder, the first time you use Restart, Shut Down, Log Out
  or Empty Trash.

## Development

```sh
swift build
swift test
swift run fener --show --demo   # a second copy for testing; quit the installed one first
swift run -c release fener --bench   # scan and search timings
```

Sources are in `Sources/Fener`, one file per feature. See `docs/known-issues.md` for known
problems.

## License

MIT, see [LICENSE](LICENSE). fener is written from scratch; it takes ideas from Omarchy and
Walker but no code or theme files. Bundled third-party data (Nerd Font glyph names, the
Tokyo Night and Catppuccin palettes) is listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
