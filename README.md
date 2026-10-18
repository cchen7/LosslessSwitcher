<p align="center">
  <img width="550" alt="header image with app icon" src="https://user-images.githubusercontent.com/23420208/164895903-1c95fe89-6198-433a-9100-8d9af32ca24f.png">

</p>

#  

LosslessSwitcher switches your current audio device's sample rate to match the currently playing lossless song on your Apple Music app, automatically.

Let's say if the next song that you are playing, is a Hi-Res Lossless track with a sample rate of 192kHz, LosslessSwitcher will switch your device to that sample rate as soon as possible. 

The opposite happens, when the next track happens to have a lower sample rate. 

## macOS 27 / Apple Silicon fork

This fork targets Apple Silicon Macs, including M4 Max, running macOS 27. It builds on upstream version 2.0 and [PR #225](https://github.com/vincentneo/LosslessSwitcher/pull/225), retaining the original author's attribution. It is a compatibility preview, not an official upstream release.

### Current development milestone: 2.2.0

The development branch adds separate **Source** and **Output** format readouts and
recovery when the app starts during an already-playing Music stream. This is not
the upstream v3 rewrite. The published 2.1.0 releases do not contain these changes.

If no fresh decoder format is available, the app can read the current track's
reported sample rate from Music. Automatic attempts never request new
permissions. Choose **Read Current Track from Music...** in the menu to grant
Music Automation access when needed; later startups can reuse that authorization.
The request targets the already-running Music process, runs off the main thread,
uses a shared three-second event budget after permission, and rejects results
from changed tracks, paused playback or obsolete detection generations.

Music metadata does **not** establish source codec or bit depth. Metadata-only
recovery therefore displays unknown fields, changes only the sample rate, and
keeps the existing output bit depth even if Bit Depth Switching is enabled.
Fresh ALAC decoder data still provides the full rate/depth pair. No system
logging privacy profile is required.

The menu displays the actual hardware bit depth even when switching is disabled
and warns when the detected source format is reduced at the output. This is
format visibility, not a bit-perfect guarantee.

Later backlog, outside this development milestone:

- Real mixed-rate natural-queue coverage, physical USB reconnect and sleep/wake checks.
- Local operation timing to investigate intermittent output-switch delays.
- A privacy-preserving streaming log-source experiment and workload-matched performance comparison.
- Redacted diagnostics export, login controls and an update entry.
- Unsigned build/offline regression CI; signing credentials remain in the local Keychain.

**兼容性改造说明（2026-10-18）：** 本版本由 cchen7 基于 Vincent Neo 和其他贡献者的原项目进行 macOS 27 / Apple Silicon 兼容性改造，不是原项目的官方发布，也不代表重新原创了整个应用。继续遵循 GPLv3，保留原作者与贡献者的署名和许可证。

**欢迎测试与反馈：** 欢迎使用不同 Mac、macOS 版本和 DAC 进行测试，并到[本 fork 的 Issues](https://github.com/cchen7/LosslessSwitcher/issues) 提交问题。请附上应用版本、Mac 型号、macOS 版本及 build、DAC 型号、复现步骤、预期与实际采样率；分享日志或截图前请移除个人信息。已知限制见下文。

**Compatibility work, not an official upstream release:** cchen7 maintains these macOS 27 / Apple Silicon compatibility changes; credit for the original application remains with Vincent Neo and the upstream contributors. Please test this preview and [report issues in this fork](https://github.com/cchen7/LosslessSwitcher/issues), including your app/macOS versions, Mac and DAC models, reproduction steps, and expected/actual sample rates. GPLv3 and upstream attribution are retained.

- Uses one playback listener and one audio-device controller.
- Detects formats at track changes, resume and actual seeks, rather than every metadata update. Repeated MediaRemote position timestamps do not count as seeks.
- Rejects stale detection work and out-of-window preloads, restores the detected format on output-device changes, and displays the hardware's actual rate.
- Supports physical format rate ranges and remembers device selection and the bit-depth preference.

### Install this fork

Download the ARM64 ZIP from [this fork's releases](https://github.com/cchen7/LosslessSwitcher/releases), extract it, quit any other LosslessSwitcher instance, and drag `LosslessSwitcher.app` into Applications. Enable Lossless Audio in Music; disable Dolby Atmos when you want the lossless stereo stream. Bit Depth Switching is optional and is off by default.

Starting with **Preview 3 / build 27**, the app is signed with the maintainer's **Developer ID Application** certificate, with Hardened Runtime and a secure timestamp. Check the individual release page for its **Apple notarization status**; signing and notarization are separate steps. Earlier Preview 1 and 2 builds were ad-hoc signed.

For a GitHub download, macOS may require **System Settings > Privacy & Security > Open Anyway** after the first launch attempt. Do not disable Gatekeeper or SIP. The fork uses its own bundle identifier, so configure its preferences and login item separately from the upstream app.

### Build from source

With Xcode selected:

```sh
bash scripts/build-release.sh
bash Tests/Regression/run.sh
```

The application is in `.build/Build/Products/Release/LosslessSwitcher.app`; the installable ARM64 ZIP and SHA-256 checksum are in `dist/`. All dependencies use the committed package lockfile. Distribution includes the GPL license and dependency notices.

### Sign with your own Apple Developer account

Install your **Developer ID Application** certificate and private key in your local Keychain. Use `security find-identity -v -p codesigning` to find the certificate name, then build:

```sh
SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
bash scripts/build-release.sh
```

This enables Hardened Runtime and secure timestamps and signs the embedded framework before the app with the same identity, without `--deep`. The 2.2.0 metadata recovery feature needs exactly one Apple Events Automation entitlement, with an explicit Music-access usage description; it does not request library-validation or debugging exceptions. Permission is prompted only by the explicit menu/script action. Earlier build 27 did not have this entitlement. The default ad-hoc local build disables Hardened Runtime for that app to avoid Team ID library-validation failures; it does not change any system security setting.

For notarization, add `NOTARY_PROFILE="YOUR_EXISTING_PROFILE"` to the build command above, using an existing notarytool Keychain profile for the same Apple team. A team profile can be reused across apps; this script does not create one or request account passwords. It submits the ZIP with a 30-minute wait, requires an accepted result, staples and validates the ticket, checks Gatekeeper, and repackages the stapled app. Keep signing identities, team/profile values, private keys and account credentials out of the repository; supply local values through environment variables.

### Real-device QA

On 2026-10-18, short device tests used an M4 Max, macOS 27.0.1 and a **YULONG Audio DSD DAC OT**, with actual Apple Music subscription streams. Music's track sample rate, ALAC decoder logs, CoreAudio hardware format and the running app's scripting readback were checked independently.

The tested streams automatically switched between 44.1, 96 and 192 kHz. Pause/resume, seeks, a same-rate natural track transition, rapid next-track commands and return from the built-in output to a cached 192 kHz DAC format passed. With Bit Depth Switching enabled, 16-bit and 24-bit sources selected the corresponding physical DAC formats. With it disabled, the existing hardware bit depth is intentionally retained.

Device QA found and fixed a stale display when another application changed the hardware sample rate. `Tests/DeviceQA.swift` covers that regression on real hardware. One scripting-response timeout during output switching was not reproduced in four subsequent output-return checks; long-run stability is not established.

In the published 2.1.0 preview, launching during an already-playing stream requires a new decoder event. The 2.2.0 development candidate recovered a real 192 kHz stream on YULong without changing tracks when Music access was already authorized, and correctly left unknown source bit depth unfilled. Source/output differences, explicit mixed-rate track changes, resume and decoder-controlled 16/24-bit output were checked on the same DAC. Different-rate natural queue transitions, long-duration preloading, physical USB unplug/replug and bit-perfect output remain unverified.

**Limits:** Music's decoder logs do not provide a reliable public track identifier. Selection within a -1.5/+2 second playback-event window is still a heuristic, not a guarantee of bit-perfect playback. A preloaded format inside that window can remain ambiguous. Without a matching decoder event or an authorized, identity-matched Music metadata result, the app leaves the device rate unchanged and shows a status message. External DACs, AirPlay and Bluetooth have their own supported-rate limits.

The installation notes and device reports below refer to the upstream releases.

## Installation

### For macOS Big Sur 11.4 to macOS Sonoma 14.x
Please use releases of version 1.x, such as versions 1.0, 1.1 or [1.1.1 betas](https://github.com/vincentneo/LosslessSwitcher/releases/tag/1.1.1-beta2).
Version 1.x also works up to macOS Sequoia 15.3.1.

You can find the latest stable release of the version 1.x branch here: [Link to v1.1](https://github.com/vincentneo/LosslessSwitcher/releases/tag/1.1.0)

### For macOS Sequoia 15.4 onwards
Support for this is still in beta. You can try the latest version 2.0 beta here: [Link to v2.0 Beta 1](https://github.com/vincentneo/LosslessSwitcher/releases/tag/2.0-beta1) 

#### Steps
1. Download the `.zip` file of the preferred version.
2. Drag the app to your Applications folder.

If you wish to have it running when logging in, you should be able to add LosslessSwitcher in System Settings:
```
> User & Groups > Login Items > Add LosslessSwitcher app
```

## App details

There isn't much going on, when it comes to the UI of the app, as most of the logic is to:
1. Read Apple Music's logs to know the song's sample rate.
2. Set the sample rate to the device that you are currently playing to.


As such, the app lives on your menu bar. The screenshot above shows it's only UI component that it offers, which is to show the sample rate that it has parsed from Apple Music's logs.

<img width="252" alt="app screenshot, with music note icon shown as UI button" src="https://user-images.githubusercontent.com/23420208/164895657-35a6d8a3-7e85-4c7c-bcba-9d03bfd88b4d.png">

If you wish, the sample rate can also be directly visible as the menu bar item.

<img width="252" alt="app screenshot with sample rate shown as UI button" src="https://user-images.githubusercontent.com/23420208/164896404-c6d27328-47e5-4eb3-bd8b-71e3c9013c46.png">

Do also note that:
- There may be short interuptions to your audio playback, during the time where the app attempts to switch the sample rates.
- Prolonged use on MacBooks may accelerate battery usages, due to the frequent querying of the latest sample rate.

Bit Depth switching is also supported, although, enabling it will reduce detection accuracy, hence, it is not recommended.

### Why make this?
Ever since Apple Music Lossless launched along with macOS 11.4, the app would never switch the sample rates according to the song that was playing. A trip down to the Audio MIDI Setup app was required.
This still happens today, with macOS 12.3.1, despite iOS's Music app having such an ability.

I think this improvement might be well appreciated by many, hence this project is here, free and open source.

## Prerequisites
Due to how the app works, this app is not, and cannot be sandboxed.
It also has the following requirement, due to the use of `OSLog` API: 
- The user running LosslessSwitcher must be an **admin**. This is not tested and assumed due to this [Apple Developer Forums thread](https://developer.apple.com/forums/thread/677068).
- Apple Music app must have Lossless mode on. (well, of course)

Other than that, it should run on any Mac running macOS 11.4 or later.

## Disclaimer
By using LosslessSwitcher, you agree that under no circumstances will the developer or any contributors be held responsible or liable in any way for any claims, damages, losses, expenses, costs or liabilities whatsoever or any other consequences suffered by you or incurred by you directly or indirectly in connection with any form of usages of LosslessSwitcher.

## Devices tested

Here are some device combinations tested to be working, by users of LosslessSwitcher.
Regardless, you are still reminded to use LosslessSwitcher at your own risk.


### Version 1.x
| CPU             | Mac Model                                            | macOS Version      | Beta macOS? | Audio Device                                                 |
| --------------- | ---------------------------------------------------- | ------------------ | ----------- | ------------------------------------------------------------ |
|      Intel      | MacBook Pro 13 inch (Early 2015, Dual Core i5)       | 11.6.2             | No          | Denon AVR-X4400H                                             |
|      Intel      | Mac mini (2018)                                      | 12.2<br/>12.4      | No          | Denon PMA-50                                                 |
|      Intel      | MacBook Pro 13 inch (2018)                           | 12.3.1             | No          | Denon PMA-50                                                 |
|      Intel      | MacBook Pro 13 inch, four Thunderbolt 3 ports (2016) | 12.3.1             | No          | Topping DX7 Pro                                              |
|  Apple Silicon  | MacBook Pro 13 inch (M1, 2020)                       | 12.3.1             | No          | FX Audio DAC-X6                                              |
|      Intel      | MacBook Pro 15 inch (2016)                           | 12.4               | No          | Topping D30Pro                                               |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 12.4               | No          | Meridian Explorer 2                                          |
|      Intel      | Hackintosh (XPS 9570, i7-8750H)                      | 12.4               | No          | Universal Audio Apollo X4<br/>FiiO Q3<br/>FiiO M5 (DAC mode) |
|      Intel      | MacBook Pro 13 inch (2016)                           | 12.4<br/>12.6.1    | No          | AudioQuest Dragonfly Cobalt                                  |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 12.4               | No          | iFi Zen DAC V2                                               |
|      Intel      | MacBook Pro 15 inch (2018)                           | 12.4               | No          | PS Audio Sprout                                              |
|  Apple Silicon  | MacBook Air 13 inch (2020)                           | 12.5.1             | No          | Shanling M8                                                  |
|  Apple Silicon  | Mac Studio (M1 Max, 2022)                            | 12.6               | No          | Focusrite Scarlett 18i8 (2nd Gen)                            | 
|      Intel      | MacBook Pro 16 inch (2019)                           | 12.6               | No          | Mytek Brooklyn+ DAC                                          |
|      Intel      | Mac mini (Late 2014)                                 | 12.6.3             | No          | NAD C658                                                     |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 13.0               | 22A5286j    | Topping D50s                                                 |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 13.0               | No          | iBasso DC06<br/>Khadass Tone 2 Pro                           |
|  Apple Silicon  | MacBook Pro 14 inch (M1 Pro, 2021)                   | 13.0<br/>13.0.1    | No          | Topping D10 Balanced                                         |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 13.0.1             | No          | Fiio K7<br/>Fiio K5 Pro (AKM DAC)<br/>Topping EX5            |
|  Apple Silicon  | MacBook Pro 14 inch (2021)                           | 13.0.1             | No          | AudioQuest Dragonfly Black v1.5                              |
|  Apple Silicon  | MacBook Air (M1, 2020)                               | 13.1               | No          | Schiit Bifrost 2                                             |
|      Intel      | MacBook Pro 15 inch (2018)                           | 13.1               | No          | Apogee Groove                                                |
|  Apple Silicon  | iMac 24 inch (M1, 2021)                              | 13.1               | No          | SMSL PO100                                                   |
|  Apple Silicon  | MacBook Pro 14 inch (2021)                           | 13.1               | No          | Chord Mojo                                                   |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 13.2               | No          | RME ADI-2 DAC FS                                             |
|  Apple Silicon  | MacBook Pro 16 inch (M1 Max, 2021)                   | 13.2               | No          | M-Audio Fast Track                                           |
|  Apple Silicon  | MacBook Pro 14 inch (M1 Pro, 2021)                   | 13.2               | No          | Topping D10s                                                 |
|  Apple Silicon  | Mac Studio (M1 Max, 2022)                            | 13.2.1             | No          | RME ADI-2 PRO FS R (Black Edition)                           |
|      Intel      | 27-inch iMac (2017)                                  | 13.2.1             | No          | Chord Hugo M Scaler + TT2 Combo                              |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 13.2.1             | No          | Moondrop Moonriver 2                                         |
|  Apple Silicon  | MacBook Pro 13 inch (M1, 2020)                       | 13.3.1             | No          | Gustard X18                                                  |
|      Intel      | 27-inch iMac (Late 2014)                             | 13.3.1 (a)         | No          | SMSL M500                                                    |
|  Apple Silicon  | Mac mini (M2 Pro, 2023)                              | 13.5               | No          | FiiO K5 Pro                                                  |
|  Apple Silicon  | Mac mini (M2 Pro, 2023)                              | 13.5               | No          | JDS Labs Element III MK 2                                    |  
|      Intel      | Mac mini (Late 2014)                                 | 13.5 (Opencore)    | No          | VLink192 to Rega DAC                                         |
|      Intel      | MacBook Pro 16 inch (2019)                           | 13.6.4             | No          | VMV D1SE                                                     |
|      Intel      | MacBook Pro 16 inch (2019)                           | 13.6.4             | No          | Denon AVR-X6700H                                             |
|  Apple Silicon  | MacBook Pro 16 inch (M1 Max, 2021)                   | 14.0               | 23A5328b    | Focusrite Scarlett 2i2 3rd Gen, Internal MacBook DAC         |
|      Intel      | MacBook Air 13 inch (2020 i5 1.1 Ghz Quad-Core)      | 14.0               | 23A5328d    | PreSonus Studio 1810c                                        |
|  Apple Silicon  | MacBoox Air 13 inch (M1, 2020)                       | 14.0               | No          | Cambridge Audio DacMagic 100                                 |
|  Apple Silicon  | Mac Studio (M1 Max, 2022)                            | 14.4.1             | No          | Hidizs S9 PRO                                                |
|  Apple Silicon  | MacBook Air 13 inch (M2, 2022)                       | 14.4.1             | No          | Cambridge Audio DacMagic XS                                  |
|  Apple Silicon  | MacBook Pro 14 inch (M3 Pro, 2024)                   | 14.4.1             | No          | RME ADI-2 PRO FS R (Black Edition)                           |
|      Intel      | Mac Pro 6.1 (2013)                                   | 14.4.1 (Opencore)  | No          | Cambridge Audio Edge NQ                                      |
|  Apple Silicon  | MacBook Air 13 inch (M2, 2022)                       | 14.5               | No          | HiBy FD3                                                     |
|  Apple Silicon  | MacBook Pro 14 inch (M1 Pro, 2021)                   | 14.6.1             | No          | FiiO BTR15                                                   |
|  Apple Silicon  | MacBook Air 13 inch (M3, 2024)                       | 14.6.1             | No          | iBasso DC03 Pro                                              |
|      Intel      | MacBook Pro 16 inch (i7, 2019)                       | 14.6.1             | No          | Fiio KA17                                                    |
|  Apple Silicon  | MacBook Pro 16 inch (M1 Max, 2021)                   | 15.0               | 24A5264n    | Internal Soundcard<br/>Focusrite 2i2 3rd Gen<br/>M-Track 2x2 |
|      Intel      | MacBook Pro 15 inch (2012)                           | 15.1 (Opencore)    | 24B5035e    | Fiio KA3<br/>Fiio KB3                                        |
|  Apple Silicon  | Mac mini (M2, 2023)                                  | 15.1.1             | No          | Sony NW-A55 (USB DAC mode)                                   |
|  Apple Silicon  | Mac mini (M4, 2024)                                  | 15.3.1             | No          | MOTU M2                                                      |


### Version 2.x
| CPU             | Mac Model                                            | macOS Version      | Beta macOS? | Audio Device                       | Version    |
| --------------- | ---------------------------------------------------- | ------------------ | ----------- | -----------------------------------|------------|
|  Apple Silicon  | MacBook Pro 13 inch (M1, 2020)                       | 15.4.1             | No          | Cambridge Audio CXA81              | 2.0 Beta 1 | 
|  Apple Silicon  | Mac Studio (M1 Max, 2022)                            | 15.4.1             | No          | Denon PMA-150H                     | 2.0 Beta 1 |
|  Apple Silicon  | MacBook Pro 13 inch (M1, 2020)                       | 15.5               | No          | Cambridge Audio CXA81              | 2.0 Beta 2 | 
|  Apple Silicon  | MacBook Pro 14 inch (M1 Max, 2021)                   | 15.5               | No          | Cambridge Audio DacMagic 200M      | 2.0 Beta 2 |
|  Apple Silicon  | MacBook Pro 14 inch (M4 Pro, 2024)                   | 15.5               | No          | Cambridge Audio CXA81              | 2.0 Beta 2 |
|      Intel      | Mac Pro 6.1 (2013) with OpenCore Patcher             | 15.5               | No          | Cambridge Audio Edge NQ            | 2.0 Beta 2 |
|  Apple Silicon  | MacBook Air 13 inch (M4, 2025)                       | 15.6.1             | No          | Akliam PD5                         | 2.0 Beta 2 |
|  Apple Silicon  | Mac mini (M4, 2024)                                  | 15.6.1             | No          | Focusrite Scarlett 2i2 Gen4        | 2.0 Beta 2 |
|      Intel      | MacBook Pro 15 inch (2.3GHz i9, 2019)                | 15.7.3             | No          | Fiio KA3                           | 2.0 Beta 2 |
|  Apple Silicon  | MacBook Pro 14 inch (M2 Pro, 2023)                   | 26.0               | Pub. beta 2 | AudioQuest Dragonfly Red           | 2.0 Beta 2 |
|  Apple Silicon  | MacBook Pro 14 inch (M3 Pro, 2023)                   | 26.0.1             | No          | Fiio K11                           | 2.0 Beta 2 |
|  Apple Silicon  | MacBook Pro 14 inch (M1 Pro, 2021)                   | 26.1               | Dev. Beta 2 | iBasso DC Elite                    | 2.0 Beta 2 |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 26.1               | No          | Fiio K11                           | 2.0 Beta 2 |
|  Apple Silicon  | Mac mini (M1, 2020)                                  | 26.1               | No          | Ayre QB-9 Twenty                   | 2.0 Beta 2 |
|  Apple Silicon  | MacBook Air 13 inch (M3, 2024)                       | 26.3               | No          | Fiio K17                           | 2.0 Beta 3 |
|  Apple Silicon  | MacBook Air 13 inch (M1, 2020)                       | 26.3.1             | No          | Fosi Audio K5 Pro                  | 2.0        |


You can add to this list by modifying this README and opening a new pull request!

Do note that Steven Slate Audio VSX software may not be fully compatible with LosslessSwitcher, and both software may interfere with each other. Please refer to discussion https://github.com/vincentneo/LosslessSwitcher/discussions/100 for more information.

## License
LosslessSwitcher is licensed under GPL-3.0.

## Love the idea of this?
If you appreciate the development of this application, feel free to spread the word around so more people get to know about LosslessSwitcher. 
You can also show your support by [sponsoring](https://github.com/sponsors/vincentneo) this project!

## Dependencies
- [Sweep](https://github.com/JohnSundell/Sweep), by @JohnSundell, an easy to use Swift `String` scanner.
- [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio), by @rnine, a framework that makes `CoreAudio` so much easier to use.
- [PrivateMediaRemote](https://github.com/PrivateFrameworks/MediaRemote), by @DimitarNestorov, in order to use private media remote framework.
