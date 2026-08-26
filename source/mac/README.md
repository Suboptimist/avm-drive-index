# Drive Indexer

Keeps an automatic catalogue of external storage drives (USB drives and
hard drives) that get connected to this Mac, so you can see what lives on
which drive — and who used it last — without plugging anything in. Memory
cards and mounted disk images are never catalogued, though a card that is
plugged in shows up so you can copy files off it.

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

## Copying off a card

Insert a memory card and it appears under **Cards** in the sidebar — not
catalogued (cards get reformatted too often to be worth a permanent record),
just there for as long as it is plugged in. Its folders and files are read
fresh each time.

**Copy Files…** sits at the top for anything you offload from — a memory card,
a USB stick, a field recorder, a mic — that is, any volume the system reports
as *removable media*. A fixed archive drive keeps it in the right-click menu
instead, out of the way of the job you usually came to do.

You browse the card as a folder tree: open a folder to tick individual files,
or tick the folder itself to take everything in it. What you tick decides where
things land — **a file ticked on its own goes straight into the folder you
chose, and a folder you tick is recreated at the destination with its contents
inside**. So ticking `100MSDCF` puts a `100MSDCF` folder in your project, while
ticking three clips inside it drops just those three clips in.

It is deliberately careful:

- nothing is ever removed from the card,
- a file already at the destination is skipped and listed, never overwritten,
- every copy's size is checked, and a short copy is deleted rather than left
  looking valid.

Point it at a project's `02_Footage` and that is exactly where the clips end
up.

## New Project

With a drive connected, **New Project** (next to Open Drive) creates the
standard project layout on it:

```
<Project name>/
  01_Project Files/
    01_Davinci Resolve/
    02_Premiere/
    03_After Effects/
  02_Footage/
  03_Graphics/
  04_Music/
  05_Docs/
  06_Exports/
```

Give it a name, pick where it goes (the drive's top level to start with), and
it makes the folders and opens the result in Finder. An existing folder of the
same name is never merged into or overwritten — you get told the name is taken
instead. This replaces the old "AVM Folder Structure" applet.

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

- **Cards are never catalogued** — they appear while plugged in and vanish
  when removed, so the drive list stays a list of real drives.
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
