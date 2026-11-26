---
name: iphone-mirror-control
description: Operate the mirrored iPhone on macOS with mirrorctl — percent-axis screenshots, OCR-based text location, calibrated taps/drags, and wait/collect helpers. Use when driving iPhone Mirroring, debugging click accuracy, or building automation on top of it.
---

# iPhone Mirror Control

`mirrorctl` (+ `ClaudeMirrorHelper.app`) observes the iPhone Mirroring window and
sends clicks/keys. All user-visible coordinates are **percentages of the iPhone
display**, printed on the top and left axes of every annotated screenshot.

## Setup / permissions

```bash
cd ~/code/swift/iPhoneMirror
swift build -c release            # build the CLI
./Helper/build.sh --install       # build + install + launch the capture helper
```

- The helper needs **Screen Recording** permission (System Settings → Privacy &
  Security → Screen Recording). The CLI itself does not.
- The helper is ad-hoc signed: **rebuilding it changes its cdhash and resets the
  grant**. Re-approve after each rebuild.
- If macOS keeps asking for permission, check for duplicate helper processes:
  `pgrep -fl ClaudeMirrorHelper`; kill extras (`pkill -f <path>`). Only one
  helper should run.
- Capture directory: `~/.local/share/iphone-mirror/capture` (`MIRROR_CAPTURE_DIR`
  overrides). Helper path: `MIRROR_HELPER_APP` override.

## Coordinates & calibration

- `mirrorctl capture` saves an annotated PNG: 10% grid, 2% ticks, top/left
  percent axes, and a blue **last tap** marker if a recent tap was recorded.
- Coordinates are `0,0` = display top-left, `100,100` = bottom-right. Read
  positions from the axes, not from an un-annotated raw screenshot.
- The display rectangle is detected from the window capture on every command,
  then mapped through the window frame to global screen points, so window
  moves/resizes do not break percent coordinates.
- Verify before tapping: `mirrorctl click 50 60 --dry-run` draws a red crosshair
  at the target and prints the screen point. The similar blue marker in
  `capture` shows where the previous tap actually landed.
- After a tap: `--verify` prints the screen-diff percentage. <0.3% usually means
  the tap missed or the element is not interactive.
- OCR uses Vision (`zh-Hans,en-US`). `--fast` is much faster but often fails on
  Chinese; use accurate for Chinese UI. `wait-text`/`wait-any` poll OCR and can
  click as soon as the target appears, avoiding blind sleeps.

## Command cheat sheet

```bash
mirrorctl status --json                 # window/display geometry
mirrorctl capture [--ocr-boxes]         # annotated screenshot path
mirrorctl find 去领取                    # OCR text -> percent coordinates
mirrorctl click-text 去领取 --verify     # OCR + tap (handles small/odd targets)
mirrorctl wait-text 开心收下 --click --timeout 8
mirrorctl wait-any 返回会场 返回领取 任务完成 --click --timeout 25
mirrorctl collect                       # 去领取 -> 开心收下, one-shot claim
mirrorctl drag 50 85 50 35 --duration 300
mirrorctl scroll 50 70 -8               # wheel scroll (may be ignored by some apps)
mirrorctl key 53                        # Escape (keycodes); text via `mirrorctl text`
mirrorctl helper status|launch
```

## Practical tips

- Large buttons in the center are forgiving; small icons near edges are not.
  Use OCR (`click-text`/`find`) or `--dry-run` crosshairs for those.
- A faint top-left `<` may be decorative, hidden, or have a tiny hit area. If a
  tap there does nothing, look for a labeled breadcrumb (e.g., “• 支付宝”),
  another visible close control, or use the system back gesture.
- The iPhone Mirroring window can show a hidden title bar/toolbar with Home and
  App Switcher buttons at `(≈1233, 70)` and `(≈1279, 70)` screen points; hover
  first, then click.
- The mirrored session ends if the iPhone is unlocked/used; reconnect with the
  Connect button, or lock the phone. Expect “iPhone in Use” placeholder pages.
- Fast automation pattern: `click-text … --verify` → `wait-any … --click` →
  `collect`, rather than fixed `sleep`s between every step.
