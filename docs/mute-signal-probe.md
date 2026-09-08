# XM6 mute signal probe

This diagnostic mode observes public macOS metadata and events only. It does not
open an input device, capture audio samples, write mute state, or change the
production microphone indicator.

## Public APIs investigated

- `AVAudioApplication` (macOS 14+): reads the app-level `isInputMuted` value,
  observes `inputMuteStateChangeNotification`, and installs the documented input
  mute change handler. The handler only logs the requested value and returns
  `false`, because XM6 Control has no audio samples to mute and must not claim that
  it changed them. No call to `setInputMuted` is made.
- CoreAudio HAL: enumerates input-capable WH-1000XM6 endpoints and passively reads
  and observes `kAudioDevicePropertyMute` with input scope on the main element and
  each input channel where the property exists.
- `IOBluetoothHandsFree` / `IOBluetoothHandsFreeAudioGateway`: Passive HFP
  observation not available through the public API without owning the connection.
  The documented initializers create a hands-free role object, while `connect`
  establishes its own RFCOMM service-level connection. The probe therefore creates
  no HFP object, opens no SCO connection, and registers no HFP delegate.

The package and app deployment targets remain macOS 13. On macOS 13 the
`AVAudioApplication` path logs that macOS 14 is required; the CoreAudio path still
runs.

## Run

```sh
open ".build/XM6 Control.app" --args --mute-signal-probe
```

Results use the existing timestamped log:

```text
~/Library/Application Support/XM6 Control/protocol.log
```

Probe logging is enabled for that process only and does not change the persisted
Debug logging preference.

## Manual sequence

1. Build the app and connect the WH-1000XM6 as both output and input.
2. Launch with `--mute-signal-probe` and verify `MuteProbe: started`.
3. Add a visual marker to the log with `echo "===== OUTSIDE PRESS =====" >> "$HOME/Library/Application Support/XM6 Control/protocol.log"`, then double-press the headset mic button outside a call.
4. Join a Meet or Teams call using the XM6 microphone and add `===== JOIN MEETING =====`; confirm `CoreAudio: XM6 input active`.
5. Add `===== MIC OFF =====`, press the hardware mic control until the headset says “Mic Off”, and wait several seconds.
6. Add `===== MIC ON =====`, press it again until “Mic On”, and wait several seconds.
7. Add `===== LEAVE =====`, leave the call, and confirm `CoreAudio: XM6 input inactive`.
8. Quit the probe app and inspect the timestamped lines around each marker.

Evidence of an AVAudioApplication signal is either
`MuteProbe: AVAudioApplication callback -> muted=true/false` or the corresponding
notification line. Evidence of a CoreAudio signal is
`MuteProbe: CoreAudio input mute changed ... -> true/false`. The HFP result is fixed
at startup: `MuteProbe: Passive HFP observation not available through the public API without owning the connection`.
