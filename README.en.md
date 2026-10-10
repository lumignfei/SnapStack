<p align="center"><img src="Resources/AppIcon-source.png" width="120" alt="SnapStack screenshot queue icon"></p>

# SnapStack — screenshot queue for macOS

[简体中文](README.md) · [English](README.en.md)

**Capture several screen regions, reorder them, and paste them in sequence. Add optional text notes and image markup.**

SnapStack (连截) is a native macOS utility built with SwiftUI and AppKit. It keeps screenshots in a floating toolbar for the current session. Notes stay attached to their image when reordered and are pasted as separate text, without changing the original image.

## Version and availability

Source version: **0.2.0**. A 0.2.0 app download has **not** been published. [Existing releases](https://github.com/lumignfei/SnapStack/releases) include the older v0.1.2, which has different shortcuts and does not include the new interface or notes described here. Build from source to try the current version.

- macOS 13.5 or later; no Windows or Linux version.
- Swift 6 / Xcode or Command Line Tools for building; no third-party Swift package dependencies.
- Free, open-source software under the [MIT License](LICENSE); no account or subscription required.

## When to use it

- Collect several steps of a bug report, with a note on the relevant screenshot.
- Gather interface references and explain selected buttons or layouts.
- Prepare an ordered set of images before pasting into an app that accepts images.

SnapStack focuses on a session-based screenshot queue. It includes rectangle, ellipse, arrow, pen, text and mosaic markup, with color, stroke width, undo and redo controls. It does not provide screen recording, OCR, cloud sync, or persistent clipboard history.

## Quick start

```sh
git clone https://github.com/lumignfei/SnapStack.git
cd SnapStack
bash scripts/setup-local-signing.sh
bash scripts/build-app.sh release
open dist/SnapStack.app
```

1. Grant Screen Recording permission to capture selected regions. Grant Accessibility permission for automated Command-V paste events.
2. Press **Control + Shift + A** to capture a region; repeat to collect more images.
3. Open the compact image tray to reorder or delete images. Click a thumbnail for a larger preview, optional notes and image markup. Notes grow to a capped height, then scroll. Return closes the note editor; Shift + Return inserts a newline. Input-method composition is handled separately.
4. Click the input area in your target app, then use **Control + Shift + S** or the Paste button. Hover over Paste to check the target.
5. Check the received images. The queue remains available until cleared or the app exits.

Shortcuts work only while SnapStack is running. The toolbar can collapse into a floating button. No launch-at-login option is included.

## Notes and compatibility

Each image is pasted first, followed by its nonempty note in the format `图片 N：…` (Image N). Numbers follow the current order. Notes are optional and remain bound to the original image when reordered. No Enter key is sent to submit chat messages.

The receiving app controls layout: it may show image attachments separately from the note text. Side-by-side image/text layout is not guaranteed. The complete current workflow has **not** been validated specifically in ChatGPT or WeChat. Fixed paste delays cannot confirm that an app finished processing or uploading an image; focus changes and dialogs can interrupt the sequence.

Native clipboard image/text tests, note identity and reordering checks, hotkey registration checks, and seven permission-launch checks have passed. Markup export, undo/redo, original preservation, reordered identity and long-note layout checks also passed. See the [current validation record](docs/markup-checks.md) for scope. Intel, macOS 13.5, multiple displays, Spaces and fullscreen scenarios have not had dedicated device testing. Animation frame rates have not been measured.

## Permissions and privacy

Historical downloads use **ad-hoc signing, without Developer ID signing or notarization**. Gatekeeper may block a downloaded app; follow [Apple’s guidance](https://support.apple.com/en-us/102445) only if you trust the source. Do not disable system security protections.

Rebuilding can invalidate existing permission records. If permission is enabled but capture or paste fails, quit SnapStack, remove its old entry in the relevant privacy settings, add the current app, and reopen as prompted. Build scripts accept an existing signing identity through `SNAPSTACK_SIGNING_IDENTITY`.

SnapStack does not connect to the network or upload data. Original PNGs are held in a system temporary directory; notes and the queue last for the current session. Deleting, clearing, or quitting normally removes the associated images. Crashes may leave temporary files. There is no recovery of the queue after quitting.

Pasting overwrites the system clipboard, leaving the final image or note written. The target application’s data handling applies after you paste into it.

## FAQ

**Can I add a note or markup to only one screenshot?** Yes. Each image keeps its own notes and marks.

**Are notes drawn into the image?** No. Notes are pasted as separate text. Markup is rendered into the pasted image; the source image remains intact during the session.

**Does it send messages automatically?** No. It pastes without pressing Enter.

**Can I restore screenshots after quitting?** No. The queue is session-only.

**Where do I report a problem?** Open an [issue](https://github.com/lumignfei/SnapStack/issues) with your macOS version, chip, target app and reproduction steps. Avoid sharing private screenshots.

## Development and credits

See the [Chinese README](README.md) for test and universal-package commands, and the [0.2.0 source update notes](docs/releases/v0.2.0.md).

System-integration ideas were informed by [Clippy](https://github.com/yarasaa/Clippy), and UI interactions by [DogSC](https://github.com/laogou717/dogsc). SnapStack is independently implemented. The app icon was AI-assisted.

Local builds require a persistent signing identity. Run `scripts/setup-local-signing.sh` once; the private key stays in the login keychain and machine configuration in `~/Library/Application Support/SnapStack/Signing/`. Keep this identity across updates. No global trust is changed. First signing may require Keychain confirmation. Switching identities requires reauthorization; Screen Recording and Accessibility permissions survived two subsequent source updates on the development Mac; other devices still need verification. Set `SNAPSTACK_SIGNING_IDENTITY` to use an existing certificate, or explicitly `-` for temporary testing only. Local self-signing is not Developer ID signing or notarization.
