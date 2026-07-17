# Mic Boost

OSX caps microphone input volume at 100% in System Settings, and there is
no built in way to push a mic louder than that. Some microphones (including
headset mics) are just quiet even at max volume, and third party apps like
Zoom, Discord, and Voice Memos have no separate gain control of their own,
they just use whatever level the input device provides.

This is a small menu app that fixes this. It captures your microphone,
applies gain past the normal ceiling, and sends the result to
[BlackHole](https://github.com/existentialaudio/blackhole), a free virtual
audio device. Any app can then select BlackHole as its input and receive the
boosted signal, since macOS has no way for one app to hand processed audio
to another app as a microphone without a virtual device in between.

## Why this exists

<details>
<summary>The problem this solves</summary>

I built this because my **SteelSeries Arctis Nova 5 headset microphone was extremely quiet on macOS**, even though everything appeared to be configured correctly.

The microphone input level in macOS System Settings was already at 100%, but the signal was still too low. The SteelSeries GG app did not provide any additional microphone gain control, and **SteelSeries Sonar is not available on macOS**, so there was no official software solution to increase the mic volume.

Because macOS only exposes the microphone's built-in input level to applications, apps like Zoom, Discord, and Voice Memos cannot independently make a quiet microphone louder. They can only use the audio level they receive from the system.

Mic Boost solves this by acting as a software gain stage: it takes the microphone input, boosts it beyond the macOS volume limit, and exposes the processed signal through BlackHole as a new virtual microphone input that any app can use.

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

This requires admin rights on the Mac, since the BlackHole driver installs
into `/Library/Audio/Plug-Ins/HAL`.

## Build

```
./build.sh
open MicBoost.app
```

## Use

1. Pick your real microphone from the dropdown (not BlackHole).
2. Set the boost slider and click Start. The level meter shows the
   post boost signal in real time.
3. In the app you want boosted audio in (Zoom, Voice Memos, etc.), set the
   input device to BlackHole 2ch.

## How the gain works

The boost is a linear multiplier (400% is 4x amplitude), followed by a
soft limiter so louder settings round off peaks instead of clipping
harshly. This means loudness gains taper off at high boost values.
