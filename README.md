# Mic Boost

macOS caps microphone input at 100% and third party apps (Zoom, Discord,
Voice Memos) have no gain control of their own. If your mic is quiet at
100%, this is the only way to make it louder.

Mic Boost captures your microphone, applies gain past the normal ceiling,
and sends the result to [BlackHole](https://github.com/existentialaudio/blackhole),
a free virtual audio device. Other apps then select BlackHole as their
input and get the boosted signal.

<details>
<summary>Why this exists</summary>

My SteelSeries Arctis Nova 5 headset mic was extremely quiet on macOS even
at 100% input level. SteelSeries GG has no mic gain control on macOS, and
Sonar (which does) isn't available on macOS either. Since macOS only
exposes the mic's built-in level to apps, no app can boost it on its own.
Mic Boost adds a software gain stage in front of BlackHole so any app can
use the boosted signal.

</details>

## Prerequisites

- Xcode Command Line Tools: `xcode-select --install`
- Homebrew: https://brew.sh
- BlackHole 2ch:
  ```
  brew install blackhole-2ch
  ```
  Then either reboot, or restart the audio daemon:
  ```
  sudo killall coreaudiod
  ```

This needs admin rights, since the BlackHole driver installs into
`/Library/Audio/Plug-Ins/HAL`.

## Build

```
./build.sh
open MicBoost.app
```

This builds `MicBoost.app` (the menu bar app) and `micboostctl` (the CLI).

## Use

1. Click the mic icon in the menu bar to open the dropdown.
2. Pick your real microphone (not BlackHole).
3. Set the boost slider and click Start. The level meter shows the post
   boost signal, and the menu bar icon fills in while running.
4. In the app you want boosted audio in (Zoom, Voice Memos, etc.), set the
   input device to BlackHole 2ch.

There's no Dock icon or window. Click the mic icon again to reopen the
dropdown, and use Quit in it to exit.

## CLI

`micboostctl` is a remote control for the same engine running inside the
menu bar app. It launches the app automatically if it isn't already open.

```
./micboostctl run     # ask for device/boost/bass, then start and show a live dashboard
./micboostctl start   # start with the settings from the last run
./micboostctl stop
```

`run` prompts for the device, boost %, and bass boost dB. Press Enter on
any prompt to keep the default shown, which is whatever you picked last
time (or 100%/6dB the first time). The choice is saved to
`~/Library/Application Support/MicBoost/last-run-settings.txt`, so a later
`start` reapplies it with no prompts.

After setup, `run` shows a live dashboard: level meter, device, boost, and
bass. Press `s` to toggle start/stop. `q` or Ctrl-C stops the mic boost and
exits, so it's fine to leave `micboostctl run` in a tmux pane and Ctrl-C it
when you're done. You can also run `micboostctl stop` from another
terminal at any time; the dashboard updates live.

Put `micboostctl` on your PATH to run it from anywhere:

```
ln -s "$(pwd)/micboostctl" /usr/local/bin/micboostctl
```

## How the gain works

The boost is a linear multiplier (400% is 4x amplitude), followed by a
soft limiter so louder settings round off peaks instead of clipping
harshly. Loudness gains taper off at high boost values as a result.
