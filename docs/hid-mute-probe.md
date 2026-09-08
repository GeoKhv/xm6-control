# XM6 HID mute probe

This diagnostic mode passively observes public macOS HID events from devices
whose metadata identifies them as WH-1000XM6. It does not change the production
mute implementation.

## Safety and privacy boundary

- `IOHIDManager` enumerates device metadata for discovery, but is not opened: an
  unfiltered manager open would also open unrelated keyboards and mice.
- Only devices whose product, manufacturer, serial, or public unique identifier
  contains normalized `WH-1000XM6` / `1000XM6` are opened.
- Candidate devices are opened with `kIOHIDOptionsTypeNone`, never with seize.
- Input value and input report callbacks are registered only on candidates.
- The probe never sends output or feature reports, sets values, creates virtual
  devices, captures microphone audio, or touches HFP/SCO.
- If no candidate is found, the log includes a one-time metadata-only list of
  Bluetooth HID devices. It excludes their serial, location, unique, and registry
  identifiers and never installs callbacks on them.

The implementation uses only public IOKit/IOHID APIs: `IOHIDManagerCreate`,
`IOHIDManagerSetDeviceMatching`, `IOHIDManagerCopyDevices`, manager matching and
run-loop scheduling APIs, `IOHIDDeviceGetProperty`, `IOHIDDeviceGetService`,
`IORegistryEntryGetRegistryEntryID`, `IOHIDDeviceOpen` / `Close`,
`IOHIDDeviceRegisterInputValueCallback`,
`IOHIDDeviceRegisterInputReportCallback`,
`IOHIDDeviceRegisterRemovalCallback`, `IOHIDDeviceCopyMatchingElements`, and the
public IOHID element/value accessors.

## Run

Install the built app at `~/Downloads/XM6 Control.app`, then run the HID probe:

```sh
open "$HOME/Downloads/XM6 Control.app" --args --hid-mute-probe
```

To run the existing AVAudioApplication/CoreAudio probe at the same time:

```sh
open "$HOME/Downloads/XM6 Control.app" --args --mute-signal-probe --hid-mute-probe
```

Both flags write timestamped diagnostics to:

```text
~/Library/Application Support/XM6 Control/protocol.log
```

Ordinary app launches install no HID listeners.

## Manual comparison

1. Quit all running XM6 Control instances, connect WH-1000XM6, and launch with
   both probe flags.
2. Confirm `MuteHIDProbe: started`; look for `candidate device`, `open device=...
   result=0x00000000`, `callbacks installed`, and the element inventory. If there
   is no candidate, retain the safe `Bluetooth HID metadata` lines.
3. Append `===== OUTSIDE =====` to `protocol.log`, then double-press once outside
   a call.
4. Join Meet or Teams with the XM6 microphone. Append `===== JOIN MEETING =====`
   and wait for `CoreAudio: XM6 input active`.
5. Append `===== MIC OFF 1 =====`, double-press until Sony says “Mic Off”, and
   wait two seconds. Append `===== MIC ON 1 =====`, double-press until Sony says
   “Mic On”, and wait two seconds.
6. Repeat step 5 twice more, using sequence numbers 2 and 3.
7. Append `===== LEAVE =====`, leave the call, and wait for
   `CoreAudio: XM6 input inactive`.
8. Quit the app and compare the `MuteHIDProbe: value` and
   `MuteHIDProbe: report` lines around every marker.

The experiment succeeds only if every in-call Mic Off/Mic On produces a stable
value/report pattern that is absent or different outside the call. A raw event is
not a mute signal until this hardware comparison establishes the correlation.
