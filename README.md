# Amiga → PS3 Package Builder

This is a macOS SwiftUI front end based on the workflow in `Create Amiga PKG Tutorial` created by [@Empardopo](https://www.youtube.com/@empardopo) from [ArcadeSpain](https://t.me/arcadespain).
It automates the repeatable parts of the process:

- add an ADF, HDF, or LHA input;
- infer the initial title from the filename;
- generate `PARAM.SFO`;
- copy the Amiga emulator template and ROMs;
- generate `UAE.CFG` with PS3 paths;
- select `ICON0.PNG`, `PIC1.PNG`, music, and a video frame;
- write `package.conf`;
- optionally invoke a package builder.

The app deliberately separates “prepare the package directory” from “produce a
signed/installable PKG”. A directory with the right filenames is not itself a
valid PS3 package.

## Disclaimer

We do not support piracy.

You must supply your own ADF, HDF, or LHA files, music, and any other assets, and those files must be ones you legally own or otherwise have the right to use. That includes game images, box art, icons, background music, and Kickstart ROMs. This project only packages files you already have. It does not download them, and nothing here is a licence to copy or share commercial Amiga software.

Git ignores those files on purpose. [What git does not track](#what-git-does-not-track) lists each pattern and where the replacement comes from.

## What git does not track

A clone is the Swift sources, the scripts, and the app icon. Local media, build products, and third-party runtimes are listed in `.gitignore` and are absent after `git clone`. You create or supply them on the machine where you build.

**Game disks, archives, and ROMs.** `*.adf`, `*.hdf`, `*.lha`, and `*.rom` are ignored in every directory. `assets-example/` is ignored as well, so the tree has no sample title, box art, or music. Choose an ADF, HDF, or LHA you legally own in the app. An LHA has to contain an ADF or HDF, and `lha`, `unar`, `7z`, or `bsdtar` has to be on `PATH` to unpack it. The Kickstart file (`USRDIR/kick31.rom`, or `kick13.rom` / `kick12.rom`) has to already sit in the CLIKAK500 template. The app copies that ROM into the package. It never downloads one.

The tutorial folder is not in this repository either. `./scripts/build-app.sh` looks for `Create Amiga PKG Tutorial/CLIKAK500/USRDIR/EBOOT.BIN` in the repo root, then in `~/Downloads/Create Amiga PKG Tutorial`, `~/projects/amiga-to-ps3/Create Amiga PKG Tutorial`, and a previously installed app bundle. That folder is also where `makepkg.rar` and TrueAncestor live. Without `EBOOT.BIN`, the app-bundle build stops.

**Packages you produce.** `*.pkg` files and directories whose names end in `_staging` are output from **Prepare files** and **Build .PKG**. They stay next to your working copy.

**Build folders.** `.build/` is created by `swift run` and `swift build`. `dist/` is created by `./scripts/build-app.sh` and holds `AmigaPS3Builder.app`. Delete either directory and run the same command again.

**`vendor/`.** The scripts park third-party tools here. The directory is ignored because it is large, and some of it is not ours to publish. `./scripts/build-app.sh` fills in what it can:

- `vendor/atracdenc` is built from [atracdenc-rs](https://github.com/liangchunn/atracdenc-rs) `v0.1.0` when `cargo` and rustc 1.88 or newer are installed. The script clones the sources into `vendor/atracdenc-src` and compiles. Point `ATRACDENC_DIR` at a tree you already built. Skip the tool with `AMIGA_SKIP_ATRACDENC=1 AMIGA_REQUIRE_ATRACDENC=0`.
- `vendor/at3emu` is the [at3emu](https://github.com/liangchunn/at3emu) `v0.1.0` release, downloaded when `./scripts/build-app.sh` runs (`AMIGA_ALLOW_AT3EMU_FETCH=1`). Archives land in `vendor/at3emu-cache/` and are checked against `scripts/at3emu.manifest`. Sony’s `at3tool` and `libatrac.so` are not fetched. Background music is encoded with `atracdenc`. `at3emu` is only the optional wrapper, and it does not encode on its own.
- `vendor/wine-runtime` is an x86_64 WineHQ build. If `/Applications/Wine Stable.app` is installed, the script copies it. Otherwise the download stays off until you opt in. The tarball is cached in `vendor/wine-cache/` and checked against `scripts/wine-runtime.manifest`.

```sh
# Copy from an installed Wine Stable.app
WINE_RUNTIME_DIR="/Applications/Wine Stable.app" ./scripts/stage-wine-runtime.sh

# Or download the pinned build
AMIGA_ALLOW_WINE_FETCH=1 ./scripts/stage-wine-runtime.sh
```

On Apple Silicon that Wine binary runs under Rosetta 2. To build the UI without bundling Wine:

```sh
AMIGA_SKIP_WINE=1 AMIGA_REQUIRE_WINE=0 ./scripts/build-app.sh
```

`.DS_Store` is ignored too. Nothing to restore.

## Testing in RPCS3 (macOS)

The `.pkg` from this pipeline targets **real PS3 hardware** (or a fully working
PS3 OS environment). RPCS3 on Apple Silicon is useful for smoke tests, but it
is not a supported end-user platform for this homebrew stack.

What you may see in RPCS3:

- **Turrican (or other) box art** on the boot screen is only `PIC1.PNG` /
  `ICON0.PNG`. It does not change which ADF is in `USRDIR` (check `UAE.CFG` and
  the installed folder under `dev_hdd0/game/<TITLE_ID>/`).
- **“Preloading cached shaders… / Compiling pipeline object 1 of 1”** is RPCS3’s
  RSX overlay during PS3 boot. It can sit on top of the game’s boot animation
  for 30–90 seconds even when the title is running.
- RPCS3’s log may show **MoltenVK warnings** (no double-precision shaders, MSAA
  disabled). The CLIKAK500-based emulator uses RSX; graphics may stay black or
  appear frozen on Mac even though the log shows `UAE.CFG`, kickstart, and ADF
  files being opened.

If RPCS3 looks stuck: wait at least two minutes once, try **Remove Shader Cache**
for the title, or switch GPU renderer (e.g. KosmicKrisp vs MoltenVK if offered).
For a definitive test, install the Content-ID-named `.pkg` on a PS3 with a
compatible CFW.

## Run on macOS

`.build/`, `dist/`, and `vendor/` are empty after a clone. [What git does not track](#what-git-does-not-track) covers how they get filled, and which disks and ROMs you still provide yourself.

Xcode command-line tools and Swift 5.9 or newer are required:

```sh
swift run
```

For a release binary:

```sh
swift build -c release
.build/release/AmigaPS3Builder
```

To create a launchable macOS application bundle:

```sh
./scripts/build-app.sh
open dist/AmigaPS3Builder.app
```

Release builds bundle these inside `AmigaPS3Builder.app`:

- `Contents/Resources/Packager` — extracted from `Create Amiga PKG Tutorial/makepkg.rar`
- `Contents/Resources/Tutorial` — `CLIKAK500`, TrueAncestor, and sample artwork
- `Contents/Resources/Tools/atracdenc` — ATRAC3 encoder for `SND0.AT3`
- `Contents/Resources/Wine` — WineHQ macOS **x86_64** runtime (optional but required for **Build .PKG**)

`./scripts/build-app.sh` stages `atracdenc` and `at3emu` when they are missing. Wine is copied from Wine Stable.app, or downloaded only after you opt in. The commands are in [What git does not track](#what-git-does-not-track). After a successful build:

```sh
./scripts/verify-bundle.sh
```

On Apple Silicon, the bundled Wine runs through **Rosetta 2** with an isolated
`WINEPREFIX` under `~/Library/Application Support/AmigaPS3Builder/wine-prefix`.
Third-party notices live in `scripts/third-party-notices.txt` and inside the app bundle.

Launched from the `.app`, the UI uses the tutorial copied into the bundle. `swift run` searches the same places as the build script: a `Create Amiga PKG Tutorial` folder beside the working directory, under `~/Downloads`, or at `~/projects/amiga-to-ps3/`. A template folder must contain:

```text
USRDIR/EBOOT.BIN
USRDIR/UAE.CFG       (optional; sensible defaults are generated if absent)
USRDIR/kick31.rom    (or another Kickstart ROM referenced by the config)
ICON0.PNG             (or select an icon in the UI)
```

## Inputs and artwork

- `.adf` is copied as the floppy image and assigned to `floppy0`.
- Multiple ADF inputs are assigned to successive floppy slots (up to four);
  with one ADF, the template `savedisk.adf` remains the second slot.
- `.hdf` is copied as the hardfile and assigned to `hardfile`; floppy slots are
  cleared for this mode, matching the tutorial’s correction.
- `.lha` is extracted with the first available `lha`, `unar`, `7z`, or
  `bsdtar`; the archive must contain an ADF or HDF. A generic LHA archive
  cannot be booted directly by the supplied UAE configuration.
- PNG files are copied directly. Other images and video inputs are converted
  with `ffmpeg` if you still use those CLI paths.
- A video input becomes the first frame in `PIC1.PNG`. The original package
  layout has a static XMB background slot, not a standard video-background
  slot.
- Music is converted to `SND0.AT3` (ATRAC3 in a RIFF WAVE) with the bundled
  `atracdenc`. PCM conversion uses macOS `afconvert`, so Homebrew `ffmpeg` is
  not required for MP3/M4A/WAV input.

Install optional helpers with your preferred macOS package manager. An LHA
extractor is needed for LHA input.

## Building the final PKG

The supplied `makepkg.rar` contains the Windows x86 `make_pkg.exe` front-end,
`kit/psn_package_npdrm.exe`, Cygwin DLLs, and PS3 packaging data. The release
app pre-fills those paths and the bundled Wine binary; you can still override
them in section 5 of the UI.

Click **Build .PKG** after **Prepare files**. The app invokes the Windows
builder with `-C <output-folder>` and the staging directory as its arguments.
Native macOS packagers (if you provide one) receive only the staging directory.
The generated staging directory contains a
`package.conf` using the configuration
keys exposed by the supplied tool:

```text
contentid=...
drmtype=Free
klicensee=00000000000000000000000000000000
contenttype=GameExec
packageversion=01.00
titleid=...
```

Do not add `installdirectory` for automated builds: under Wine,
`psn_package_npdrm.exe` fails its InstallDirectory check when that key is
present, even with a correct path. The tool derives the install path from
`PARAM.SFO` (`TITLE_ID`) instead.

If the builder uses a different command-line contract, use **Prepare files**
and adapt the final packaging command separately. The app reports an error
instead of calling a Windows binary directly on macOS or presenting an
unpackaged directory as a `.pkg`.

## EBOOT patching and NPDRM

The tutorial’s `EBOOT` workflow is now represented in the UI:

1. Start from `trueancestor 1.80/EBOOT.ELF`.
2. Replace every `MAGICS500` occurrence with the nine-character Title ID.
3. Run TrueAncestor’s interactive option 3 through Wine with the configured
   Content ID.
4. Copy the generated `EBOOT.BIN` into `USRDIR`.

The supplied ELF contains two `MAGICS500` occurrences, which the builder
validates before patching. The default Content ID follows the tutorial:
`JP9000-TITLEID_00-0000000000000000`; it is editable in the UI and is written
to both the resigner flow and `package.conf`.

Enable **Patch EBOOT.ELF and invoke TrueAncestor option 3** to use this path.
Without it, the original template EBOOT is retained. The app does not
implement or distribute PS3 private-key cryptography: TrueAncestor and its local
keys remain in the tutorial bundle; Wine is bundled only when you stage it with
`scripts/stage-wine-runtime.sh`.

## What the supplied Windows software does

The repository is a bundle of separate tools rather than one application:

- `PS3SFOEdit.exe` is an x86 .NET/Visual Basic WinForms editor. REA found
  `PARAM.SFO` load/save members and editable title/category controls.
- `psn_package_npdrm.exe` is an x86 native package builder. REA observed
  configuration fields such as `contentid`, `contenttype`, `packageversion`,
  `titleid`, and `installdirectory`, plus validation for `PARAM.SFO`, ICON0,
  SELF/EDATA/ELF content, and package format.
- `scetool.exe`, `make_fself*.exe`, `unfself.exe`, and `FixELF.exe` are
  native PS3 SELF/ELF helpers. The supplied `scetool.exe` is packed, so its
  REA entry point primarily shows an unpack/decompression stub; that is not
  treated as proof of a complete reimplementation.
- `klicencebruteforce.exe` is a separate key/license utility, not a normal
  Amiga-image conversion step.
- `EBOOT.BIN` is an SCE/SELF payload and the decrypted `EBOOT.ELF` is a
  PowerPC64 ELF. The Mac app does not decompile it; it performs the tutorial’s
  exact fixed-width identifier replacement and delegates signing to
  TrueAncestor.

The app replaces the Windows GUI/manual file editing with one macOS UI while
keeping the platform-specific PS3 package/signing step explicit.
