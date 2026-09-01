# AVM Drive Index — Windows version

Keeps an automatic catalogue of every external drive (USB sticks, portable
hard drives and SSDs) that gets connected to this PC, so you can see what
lives on which drive — and who used it last — without plugging anything in.

This is the Windows twin of the Mac app. It behaves the same way, looks the
same, and stores the same information; only the plumbing underneath differs.

## Requirements

Windows 10 or Windows 11. **Nothing to install** — it runs on the PowerShell
that already comes with Windows. There is no build step and no compiler: the
app *is* the files in this folder.

## Getting started

1. Copy this whole folder somewhere sensible (your Desktop or Documents).
2. Double-click **`Install Drive Indexer.cmd`** — this turns on the background
   helper that records drives as they're connected. A window appears, prints
   what it did, and waits for a key press.
3. Double-click **`AVM Drive Index.cmd`** to open the app.

Optional: **`Create Desktop Shortcut.cmd`** puts a proper "AVM Drive Index"
icon on your Desktop so you can open it like any other program.

### If Windows or your antivirus warns you

Because these files came from another computer, Windows may show a
**"Windows protected your PC"** SmartScreen box the first time. Click
**More info → Run anyway**. You can avoid this entirely by right-clicking the
downloaded .zip *before* extracting it, choosing **Properties**, ticking
**Unblock**, then extracting.

On a locked-down work PC, script execution is sometimes disabled by company
policy. The launchers already ask Windows to allow just these files
(`-ExecutionPolicy Bypass`), but if policy forbids even that, an IT
administrator has to allow it — there's no way around it from here.

## What you get

Everything is kept in a private folder, out of the way:

```
C:\Users\<you>\AppData\Local\AVM Drive Index\
  Drives Overview.txt        one-glance list: every drive, when it was last
                             connected, and who was signed in
  Drives\
    Project Archive 2026\     one folder per drive you've ever connected
      _DRIVE INFO.txt        size, free space, format, drive letter, last
                             connected, last used by, and full history
      _FILE LIST.txt         every file with its size (up to 20,000 files,
                             6 levels deep) — powers browsing and search
      <folders...>           the drive's folder structure, mirrored as real
                             folders you can browse in File Explorer
                             (folders only — no files — 3 levels deep)
```

You never have to open that folder — the app is the nice way to read it — but
it's plain folders and text files, so nothing is locked inside the app.

## Using the app

- **Sidebar** — every drive ever connected. A **green** indicator and dot mean
  it's plugged in right now; **grey** means it isn't, with a note like
  "2 hours ago" and who used it.
- **Free space** — how much room was left the last time the drive was
  plugged in, shown next to its total size, with a bar showing how full the
  drive is. The bar turns amber past 90% so a nearly-full drive stands out.
- **Contents** — the drive's folders and files with sizes, browsable even when
  the drive is nowhere near you.
- **History** — every connection, with the date and the Windows account that
  was signed in.
- **Search** (or press **Ctrl+F**) — searches the *entire* index: drive names,
  folder names, and file names across every drive ever connected. Click a
  result to jump to its drive; press Esc to clear.
- **Copy Files…** — browse any connected drive as a folder tree and tick whole
  folders or individual files, then copy them into a folder on another drive. A
  file ticked on its own lands straight in the chosen folder; a folder you tick
  is recreated at the destination with its contents inside. The button is in
  the header for anything you offload from — a card, a stick, a recorder — and
  beside the **Contents** and **History** tabs for fixed drives (it is in the
  right-click menu too). Nothing is removed from the source, files already at
  the destination are skipped rather than overwritten, and every copy's size is
  checked.
- **New Project Folder** — creates the standard project folder layout on the drive
  (`01_Project Files` with Davinci Resolve / Premiere / After Effects,
  `02_Footage`, `03_Graphics`, `04_Music`, `05_Docs`, `06_Exports`). Asks for a
  name and a location, then opens the new folder. It never merges into or
  overwrites a folder that is already there.
- **Open Drive / Eject** — shown only while a drive is connected.
- **Rescan** — re-reads whatever is plugged in right now. You rarely need it;
  the background helper does this automatically.

### Organising drives

- **Right-click a drive** for Eject, Move to Folder, Move Up / Move Down, and
  Remove from Index.
- **`+ Index Folder`** in the header creates a folder to group drives into; folders
  appear as labelled sections in the sidebar.
- **Right-click a folder heading** to rename it, move it up or down, or delete
  it (its drives return to the main list — nothing on any real drive is ever
  touched).

Your arrangement is saved in `.drive-organization.json` inside the index
folder, so it survives restarts.

## Staying up to date

The app checks GitHub for a new version once a day and only speaks up when
there is one. To check on the spot, click the **version button** (for example
`v1.7`) in the top-right corner of the window.

Choosing to update downloads the new package, closes the app, copies the new
files over the installed folder and opens it again. Your index and the
background helper's scheduled task are left alone. If the copy fails for any
reason the old version stays exactly where it was and the downloaded files are
shown in Explorer instead.

## "Last used by"

Each time a drive is connected, the indexer records which Windows account was
signed in at that moment. Two things to know:

- It only sees what happens **on this PC**. If someone takes a drive home,
  that won't appear in the history.
- The helper runs per-user. If several people share this PC with **separate
  Windows accounts**, run `Install Drive Indexer.cmd` once while each of them
  is signed in.

## Good to know

- **Memory cards are never catalogued**, as with mounted ISO and VHD images,
  optical drives and network drives — same as the Mac version. A card that is
  plugged in does appear under **Cards** in the sidebar so you can copy off
  it, and disappears again when you remove it.
- **Two different drives with the same name** (or with no name at all) are kept
  apart automatically as "Name" and "Name (2)" — they're told apart by volume
  serial number, not by drive letter, so a drive that comes back as `F:`
  instead of `E:` is still recognised as the same drive.
- **Drives with no label** are listed by their hardware model, or as
  "Removable Disk" if even that is unavailable.
- **Ejected drives stay in the index** — that's the point. The catalogue shows
  every drive ever connected, whether it's plugged in or not.
- **Turning it off:** double-click `Uninstall Drive Indexer.cmd`. Your index is
  left exactly as it is; only future updates stop.
- **Removing a drive from the index** moves its folder to the Recycle Bin, so
  it's recoverable.

## How it works (for the curious)

- `Install Drive Indexer.cmd` registers a **Scheduled Task** ("AVM Drive
  Indexer") that starts `App\Watcher.ps1` when you sign in. If your PC blocks
  task registration, it falls back to a shortcut in your Startup folder — the
  app treats either as "installed".
- `App\Watcher.ps1` subscribes to Windows' `Win32_VolumeChangeEvent` and runs
  the scanner a few seconds after any drive appears or disappears, plus a
  periodic check every 15 minutes in case an event is missed. It logs to
  `Logs\watcher.log` in the index folder.
- `App\DriveIndexer.ps1` finds external drives (by disk bus type, filtering out
  cards and virtual disks), mirrors their folder tree, records the file list,
  and updates the info and overview files.
- `App\DriveIndexApp.ps1` is the window itself — WPF driven from PowerShell.
  It asks Windows directly what's mounted rather than trusting anything
  cached, which is why the "Connected" state is always accurate.

No third-party software, nothing phoning home, and it uses essentially zero
resources while idle.

## Differences from the Mac version

| | Mac | Windows |
|---|---|---|
| Reordering drives | drag and drop | right-click → Move Up / Move Down |
| Drive identity | volume UUID | volume serial number |
| Index location | `~/Library/Application Support` | `%LOCALAPPDATA%` |
| Autostart | LaunchAgent | Scheduled Task (or Startup shortcut) |
| Removed index goes to | Trash | Recycle Bin |

Everything else — the layout, the green/grey connected status, folders,
search, history, the caps on how much gets indexed — is the same.
