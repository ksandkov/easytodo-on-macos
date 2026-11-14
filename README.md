<div align="center">
  <img src="logo/logo.png" alt="EasyTODO logo" width="96" />
  <h1>EasyTODO for macOS</h1>
  <p>A lightweight desktop task list with configurable categories and a compact window.</p>
  <p>macOS 14+ · SwiftUI · SwiftData · Local storage · MIT</p>
</div>

This is a fork of [ArabelaTso/easytodo-on-macos](https://github.com/ArabelaTso/easytodo-on-macos), maintained by [ksandkov](https://github.com/ksandkov). It focuses on reliable macOS 14 behavior, a clean desktop card, and named task categories while preserving the original app's local-first approach.

## Download

**[Download EasyTODO v1.1.0 for Apple Silicon](https://github.com/ksandkov/easytodo-on-macos/releases/download/v1.1.0/EasyTODO-1.1.0-macOS-arm64.dmg)** · [All release files](https://github.com/ksandkov/easytodo-on-macos/releases/latest)

Requires **macOS 14 or later** and an **Apple Silicon Mac**. Open the DMG and drag EasyTODO into Applications, or use the ZIP. Quit an older EasyTODO build before replacing it. These builds are ad-hoc signed, **not notarized**; if macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** only if you trust this download. SHA-256 checksums are included with the release.

Upstream releases do not include this fork's changes. The original app and this fork share task data and preferences, so back up both before switching builds.

## What's Different

- **Reliable startup on macOS 14:** menu bar setup waits until AppKit finishes launching.
- **Inline editing:** double-click a task title; Return saves and Escape cancels.
- **Configurable categories:** add categories, rename them, and choose their colors in **Settings → Categories**. Defaults are **Work**, **Important**, and **Home**.
- **Visible category selection:** click a task's color strip to open a named palette. Every task input has a category circle, including calendar, menu bar, and global Quick Add.
- **Clean desktop card:** larger task text, subtle checkboxes, visible trash buttons with confirmation, and a separate bottom **+ Add Task** section.
- **One compact window:** double-click the header to collapse or expand; no separate widget window. Calendar, settings, progress, and add controls remain in the header.
- **Persistent geometry:** window size, position, and compact state survive relaunch. Expanded height can be reduced to 180 points; tasks scroll when space is limited.
- **Independent visibility:** Dock and menu bar icons can each be hidden without forcing the other to remain visible. The window gear and context menu still provide settings access.

Calendar planning, task reordering, date moves, repeat scheduling, completion feedback, transparency, and launch-at-login settings are retained from the original app.

## Requirements

- macOS 14 or later.
- Xcode 15.4 / Swift 5.10, or a compatible newer toolchain.
- No third-party package dependencies.

## Build and Run

```sh
git clone https://github.com/ksandkov/easytodo-on-macos.git
cd easytodo-on-macos
swift build
swift run EasyTODO
```

Run only one EasyTODO build at a time. If an older source build is running, quit it normally before launching another.

### Backed-up Local Preview

```sh
bash scripts/preview_app.sh
```

The script builds and tests the app, asks an existing EasyTODO process to quit normally, backs up task data and preferences to `dist/data-backup-*`, packages a debug app, and opens `dist/EasyTODO.app`. It does **not** replace `/Applications/EasyTODO.app`. Build output is saved to `dist/preview-build.log`.

**The preview and original app share the bundle identifier `com.easytodo.EasyTODO`, task store, and preferences. They are not independent installations.** Keep the backup before switching builds. This fork does not change the SwiftData task schema.

## Everyday Use

- Add a task with the header **+**, bottom **+ Add Task**, or global Quick Add. Choose a category using the input's colored circle before pressing Return.
- Click an existing task's left color strip to change its category, or choose **No category** for neutral gray.
- Open **Settings → Categories** to add, rename, recolor, or delete categories. Category changes update linked tasks; deleting a category never deletes its tasks.
- Existing tasks are not automatically assigned to the new categories. Categories do not change task ordering; legacy priority values are preserved internally.
- Generated repeat occurrences inherit the source task's category. Undoing task deletion restores its category if that category still exists.
- Check a task to complete it, drag to reorder it, double-click its title to edit it, and use the trash button to delete with confirmation.
- Double-click the header to toggle compact mode. Drag the window and resize it normally; its geometry is remembered.
- Use the calendar button for planning. Right-click tasks for edit, category, delete, move-date, and repeat actions where available.
- Open Settings with the gear, the window context menu, or the menu bar context menu. General settings and category management have separate panes to keep the window compact.

An unchanged older default category set is translated to English while preserving category identities and task assignments. Customized category catalogs are left untouched.

### Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Command + +` | Global Quick Add |
| `Option + Command + N` | Fallback global Quick Add |
| `Command + N` | Focus a new task input |
| `Control + Z` | Undo the last task deletion in the main window |
| `Command + ,` | Open Settings when the app menu is available |
| `Return` | Save a task input, title edit, or category name edit |
| `Esc` | Cancel a title edit or dismiss quick input |

### General Settings

- Launch at Login and Always on Top.
- **Hide Menu Bar Icon** and **Hide Dock Icon**, independently. Turning either setting on hides that icon.
- Window transparency: 100%, 80%, or 50%.
- Light or dark theme.

Both icons can be hidden. If the main window is also hidden, reopen the same app build to restore it. Quit remains available in the main window's context menu. Third-party menu bar utilities may hide or relocate the status item independently of these settings.

## Data and Backups

Tasks use SwiftData in the user's Application Support directory. Category definitions and task assignments are stored separately in application preferences, together with window and display settings.

**Back up preferences together with the task store.** Copying only the task database does not include category assignments. The local preview script backs up both, including legacy store locations and SQLite sidecars when present. Backups may contain personal task data; do not commit or publish `dist/`.

The app does not require an account or cloud service.

## Verification

```sh
swift build
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -q
bash -n scripts/*.sh
git diff --check
```

Run tests on macOS; native window tests require a desktop session. Coverage includes task creation and persistence, category migration and assignment, recurrence, deletion undo, native text input, palette selection, compact windows, saved geometry, and menu bar lifecycle.

## Packaging

```sh
bash scripts/package_app.sh
bash scripts/package_dmg.sh
```

These produce local app, ZIP, and DMG artifacts in `dist/`. Set `VERSION` and `BUILD_NUMBER` when preparing a release. Packaging uses the current machine's architecture. Builds are ad-hoc signed, not notarized; macOS may require an explicit first-launch confirmation. Packaging alone does not install the app or publish a release.

The release workflow runs only for a version tag or a manual dispatch. Do not treat an upstream release as a release of this fork.

## Project Structure

```text
Sources/EasyTODO/
├── App/           # App entry and shared settings
├── Components/    # Task controls, category palette, input, and effects
├── Managers/      # Windows, menu bar, shortcuts, and category preferences
├── Models/        # SwiftData task model, categories, ordering, and scheduling
├── Persistence/   # Model container and existing store handling
├── Resources/     # App logo
└── Views/         # Task list, calendar, quick add, and settings
Tests/EasyTODOTests/
scripts/           # Preview, packaging, and script tests
```

## Release Notes

### v1.1.0 — Desktop and Category Customization

- Fix macOS 14 startup and borderless-window keyboard focus.
- Add named, configurable categories and category selection in every task input.
- Preserve category identity through rename, recolor, recurrence, deletion undo, and the English-default migration.
- Replace the separate widget with one persistent, collapsible desktop window.
- Refine the card layout, restore visible trash buttons, and separate the bottom add section.
- Keep Dock and menu bar visibility independent; retain settings access with both hidden.
- Add a backed-up preview workflow and regression coverage without changing the task-store schema.
- Package Apple Silicon DMG and ZIP downloads with the original MIT license included in the app bundle.
- Set release and preview packaging defaults to version 1.1.0.
- Keep resource lookup relocatable without embedding a developer-specific build path.
- Isolate native window test preferences so repeated test runs do not inherit earlier window geometry.

For the original release history, see the [upstream releases](https://github.com/ArabelaTso/easytodo-on-macos/releases).

## Credits and License

Original EasyTODO app, branding, and bundled assets by [ArabelaTso](https://github.com/ArabelaTso). This fork retains the upstream copyright and [MIT license](LICENSE).
