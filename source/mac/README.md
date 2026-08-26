# Drive Indexer

Keeps an automatic catalogue of external storage drives (USB drives and
hard drives) that get connected to this Mac, so you can see what lives on
which drive — and who used it last — without plugging anything in. SD cards
and mounted app-installer disk images are ignored.

It comes in two parts that work together:

1. **A background helper** that quietly updates the index every time a
   drive is connected or ejected — even when no app is open.
2. **AVM Drive Index.app** — a normal Mac app (it lives in the Drive
   Index folder) for browsing everything: the list of drives in a
   sidebar (green = connected right now, gray = not), each drive's
   folders *and files* with sizes, how much room is left (with a bar
   showing how full the drive is), who used it last, and the full
   connection history. It can search the entire index (⌘F) — drive
   names, folders, and files across every drive ever connected — and
   lets you reorder drives and group them into folders in the sidebar.

The app is the nice way to look at the index, but everything is also
plain folders and text files you can browse in Finder — nothing is
locked inside the app.

## Rebuilding the app after changing the code

Double-click **`Build App.command`** in this folder (needs Apple's free
Command Line Tools — a small, free download from Apple). It compiles the
Swift code in `Sources/` and puts a fresh `AVM Drive Index.app` in the
Drive Index folder.

## What you get

The app can live wherever you keep applications. Its private index is stored
in `~/Library/Application Support/AVM Drive Index`:

```
~/Library/Application Support/AVM Drive Index/
  Drives Overview.txt        one-glance list: every drive, when it was
                             last connected, and who was logged in
  Drives/
    Project Archive 2026/     one folder per drive you've ever connected
      _DRIVE INFO.txt        size, free space, format, last connected,
                             last used by, and a full connection history
      _FILE LIST.txt         every file on the drive with its size
                             (up to 20,000 files, 6 levels deep) — the
                             app uses this for browsing and search
      <folders...>           the drive's own folder structure, mirrored
                             as real folders you can browse in Finder
                             (folders only — no files — 3 levels deep)
    Untitled/
      ...
```

The mirrored folders are recreated fresh every time a drive is
connected, so they always match reality. Don't store your own files
inside them — anything you add there gets cleaned away on the next
connection. Notes are safe as files directly in the drive's folder
(files are never deleted, only folders are rebuilt).

## Turning it on (once)

Double-click **`Install Drive Indexer.command`**.

If macOS shows a warning about an unidentified developer, right-click
the file → **Open** → **Open**.

If macOS later asks whether the indexer may **access files on a
removable volume**, click **Allow** — it only reads folder names, never
file contents.

That's it. From then on it runs silently in the background: connect a
drive, and a second or two later the index is updated.

## "Last used by"

Each time a drive is connected, the indexer records which macOS user
account was logged in at that moment. That's what shows up as
**LAST USED BY**, and every connection is kept in the history inside
`_DRIVE INFO.txt`.

Two things to know:

- It can only see what happens **on this Mac**. If someone takes a drive
  home and uses it there, that won't appear in the history.
- The background helper is per-user. If several people share this Mac
  with **separate macOS accounts**, run the installer once while logged
  in as each of them (they can all share the same Drive Index folder —
  the installer figures the path out on its own as long as this folder
  is somewhere all accounts can reach).

## Good to know

- **Two different drives with the same name** (e.g. two cards both
  called "Untitled") are kept apart automatically as "Untitled" and
  "Untitled (2)" — the indexer tells them apart by their volume ID.
- **Moving the Drive Index folder:** if you move or rename it, just
  double-click the installer again so the helper learns the new
  location.
- **Ejected drives stay in the index** — that's the point! The catalogue
  shows every drive ever connected, whether it's plugged in or not.
  Drives currently connected are marked in `Drives Overview.txt`.
- **Turning it off:** double-click `Uninstall Drive Indexer.command`.
  The index itself is never deleted.
- **Running a scan by hand:** you never need to, but running
  `drive_indexer.sh` (or reinstalling) re-scans whatever is currently
  connected and updates the private index.
- **If a drive's folders and files come up empty**, macOS has not granted the
  app access to external drives yet. Open the app with the drive connected and
  press **Rescan** — approve the prompt, or switch on **AVM Drive Index**
  under System Settings → Privacy & Security → Files and Folders (Removable
  Volumes). Everything else about the drive is recorded either way.

## How it works (for the curious)

`Install Drive Indexer.command` creates a standard macOS LaunchAgent
(`~/Library/LaunchAgents/com.avm.drive-indexer.plist`) that watches the
system's `/Volumes` folder. Whenever a drive appears or disappears, macOS
launches the app with `--scan`, which runs one pass of `drive_indexer.sh` and
exits without opening a window. The script uses `diskutil` to spot external
storage volumes, skips SD cards and mounted disk images, mirrors their folder
tree, and updates the info files.

Scanning goes through the app rather than running the script straight from
bash for a specific reason: macOS grants file access per identifiable
application. The app can be given access to external drives in **System
Settings → Privacy & Security**; a bare shell cannot, which used to leave
folder and file listings empty ("could not read this drive's contents") even
though size, free space and history worked.

The scanner is copied into the index folder so background scanning survives
the app being moved, and the app refreshes that copy whenever they differ, so
an update reaches background scans too.

No third-party software, nothing phoning home, and it uses essentially zero
resources while idle.
