# Tarleton SAE Aero Design — Propulsion Test Stand

Windows 11 data-acquisition software for the team's motor/propeller thrust stand:

* **Arduino Uno + two HX711 load cells** (motor 1 and motor 2) → live thrust in lb for each,
  streamed with sample numbers, Arduino timestamps and checksums.
* **Matek ASPD-4525 airspeed sensor** (pitot, I2C) → live airspeed, logged on the same clock.
* **USB camera** (Creality Nebula or any UVC webcam) → records the 150 A watt meter's LCD.
* Optional **jank mode** hardware: ACS758ECB-200B hall current sensor (OUT2 → A3) and a ÷6.5556
  battery voltage divider (→ A2), read by the Arduino instead of the camera
  ([`docs/JANK_MODE.md`](docs/JANK_MODE.md)).
* **One START TEST button** → synchronized thrust CSV + MP4 video + per-frame timestamps +
  metadata + graph + summary, in a new folder per test.
* Live dashboard, calibration wizard, saved test configurations, optional automatic
  triggering, and a review window that scrubs the video and the thrust graph together.

> ⚠ **Measurement and recording only.** Nothing in this project controls the motor, throttle
> or ESC arming. **STOP TEST stops recording — it does not stop the motor.** Always have an
> operator on the throttle / kill switch.

---

## Contents
1. [What you need](#1-what-you-need)
2. [Wiring](#2-wiring)
3. [Upload the Arduino firmware (once)](#3-upload-the-arduino-firmware-once)
4. [Install the Python application](#4-install-the-python-application)
5. [First run: COM port and camera](#5-first-run-com-port-and-camera)
6. [Tare and calibration](#6-tare-and-calibration)
7. [Running a test](#7-running-a-test)
8. [What is saved](#8-what-is-saved)
9. [Reviewing tests](#9-reviewing-tests)
10. [Automatic recording](#10-automatic-recording)
11. [Simulation mode](#11-simulation-mode)
12. [Building the standalone .exe](#12-building-the-standalone-exe)
13. [Tests and development](#13-tests-and-development)

More detail: [`docs/WATT_METER_READING.md`](docs/WATT_METER_READING.md) ·
[`docs/PROTOCOL.md`](docs/PROTOCOL.md) · [`docs/SYNCHRONIZATION.md`](docs/SYNCHRONIZATION.md) ·
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) · [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

---

## 1. What you need
* Arduino Uno R3 (or Elegoo Uno R3), two HX711 modules with their load cells, and a Matek
  ASPD-4525 airspeed sensor (each sensor is optional — the software works with whatever is
  plugged in).
* A small breadboard (or soldered Y-splices) to share the Uno's 5V and GND between sensors,
  and a JST-GH-to-jumper lead for the airspeed sensor.
* Creality Nebula camera or another USB webcam, pointed at the watt meter LCD.
* Windows 10/11 laptop with **Python 3.12** (from python.org — tick *Add python.exe to PATH*;
  the `py` launcher is installed by default) and the **Arduino IDE 2.x** for the one-time
  firmware upload.
* Optional: a bright LED + 330 Ω resistor on D13 for hardware-referenced video sync.

## 2. Wiring

| Device | Device pin | Arduino Uno |
|---|---|---|
| **HX711 #1 — Motor 1** (unchanged) | VCC | 5V (via rail) |
| | GND | GND (via rail) |
| | DOUT | **D3** |
| | SCK | **D2** |
| **HX711 #2 — Motor 2** | VCC | 5V (via rail) |
| | GND | GND (via rail) |
| | DOUT | **D5** |
| | SCK | **D4** |
| **ASPD-4525 airspeed** | 5V | 5V (via rail) |
| | G | GND (via rail) |
| | SDA | **A4** (same as the SDA pin next to AREF) |
| | SCL | **A5** (same as the SCL pin next to AREF) |
| *(optional sync LED)* | | D13 → LED → 330 Ω → GND, in the camera view |

**Power:** the Uno has only one 5V header pin, so run one wire from **5V** and one from **GND**
to the + and − rails of a small breadboard (or a soldered Y) and power all three sensors from
the rails. Total draw is about 35 mA — fine on USB power. Don't use D0/D1 (USB serial) or
A4/A5 for anything else. The ASPD-4525 runs on 4–6 V, so no level shifter is needed. If its
readings are flaky, add 4.7 kΩ pull-up resistors from SDA and SCL to 5V and keep its lead
short (the 20 cm cable it comes with is fine).

**Pitot tubes:** the tube on the pitot's tip goes to the sensor port marked for total/pitot
pressure, the side holes to static. If airspeed stays at 0 while air clearly moves, swap them.

Each HX711's RATE pin decides 10 or 80 samples/s; the software measures and shows what
each board delivers. Keep load-cell wires away from the motor and ESC leads.

## 3. Upload the Arduino firmware (once)
1. Install the Arduino IDE 2.x.
2. **Sketch → Include Library → Manage Libraries…**, search **HX711 Arduino Library** by
   *Bogdan Necula* and install it (0.7.5 or newer — the library your current sketch uses).
3. Open `arduino/ThrustStand/ThrustStand.ino` (Wire and EEPROM are built in; nothing else to install).
4. **Tools → Board → Arduino AVR Boards → Arduino Uno**, **Tools → Port →** your COM port.
5. Click **Upload**. (It compiles to about 20 KB flash / 1 KB RAM of the Uno's 32 KB / 2 KB.)
6. Optional check: open the Serial Monitor at **250000** baud — you should see a `HELLO,…`
   line (it ends with `as=OK` when the airspeed sensor is found) followed by `D,1,…`,
   `D,2,…` and `A,…` lines. **Close the Serial Monitor** before using the app: a COM port can
   only be open in one program.

What the firmware does: motor 1 keeps the original pins and default factor (46500, i.e. lb);
motor 2 has its own factor and zero. It is non-blocking (a missing HX711 or airspeed sensor
never hangs it), runs at 250000 baud, sends checksummed frames with per-sensor sample numbers
and `micros()` timestamps, accepts TARE/CAL/AZERO/RESET_MAX/START/STOP/STATUS commands with
acknowledgements, and stores the zeros and calibrations in EEPROM. On the very first power-up
after uploading it tares both load cells automatically (no load on them!); after that a USB
reconnect — which resets the Uno — restores the saved zeros instead of re-taring under a
possibly running motor. **Uploading this version clears the old single-cell calibration:
re-check or re-calibrate both cells afterwards.**

You will not need the Arduino IDE again unless you change the firmware.

## 4. Install the Python application
Double-click **`setup_windows.bat`**. It creates a private Python environment in `.venv`,
installs the packages from `requirements.txt` (PySide6, PyQtGraph, pyserial, OpenCV,
NumPy, pandas, pygrabber) and puts two shortcuts on the desktop:

* **Propulsion Test Stand** — normal use.
* **Propulsion Test Stand (SIMULATION)** — try everything without hardware.

Alternatives: `run_app.bat` (no console), `run_app_console.bat` (shows diagnostic
messages), or manually: `.venv\Scripts\python -m app [--simulate] [--tests-dir D:\Tests]`.

## 5. First run: COM port and camera
**Arduino (left column → *Arduino connection*)**
1. Plug in the Uno, press **↻**. Likely Arduinos are marked ★. Select the port, click
   **Connect**. The Uno resets (normal), sends HELLO, and the ARDUINO pill turns green.
2. *Auto-reconnect* (on by default) re-opens the port by itself after a cable glitch.
   Settings → Arduino → *Connect to the last port when the app starts* skips this step
   next time.

**Camera (right column → *Camera* tab)**
1. Plug the camera in, press **↻** (names come from DirectShow; the Nebula is pre-selected
   if found). Choose resolution, frame rate and pixel format — **MJPG** is needed for
   1080p at 30 fps on most USB cameras — and click **Open**.
2. The preview shows the *measured* frame rate. If the camera can't deliver what you asked
   for, the event log says what it delivers instead.
3. Image controls: turn off Auto exposure / Autofocus and set them manually so the LCD
   stays sharp. Controls a camera does not support are reported, not silently ignored.
   The Nebula has a manual focus ring. **Driver settings dialog…** opens the camera's own
   property page (DirectShow).
4. *Burn test time + frame number into recorded video* stamps a small label in the corner
   of the MP4 so the video is self-describing in any player (the preview is unaffected).

If the camera can't be opened, the event log tells you why (in use by another program,
wrong backend, not a UVC device…). You can record thrust without video.

**Watt meter reading (volts / amps / watts from the camera)**
1. Get a sharp, glare-free view of the meter's screen (tilt it a few degrees so no light
   reflects off it) with the screen reasonably large in the picture.
2. That's it: the program finds the screen by itself (the event log says so) and the *Watt
   meter (camera)* card shows watts, volts, amps and thrust per watt live, power and
   current & voltage graphs appear under the thrust graph (choose which with **Panels**),
   and every test saves `wattmeter_data.csv` plus the battery charge (mAh) and energy (Wh) used.
3. If it doesn't find the screen (or picks the wrong thing): **Meter reading…** above the
   preview → click the **four corners of the meter's screen**. It finds the text inside,
   fits the character grid and shows a straightened close-up of just the screen with what
   it reads. **Zoom to screen** makes the live preview show that close-up.
4. The meter only updates its display a few times a second and averages internally, so the
   program logs **one row per display update** (dated when the update appeared), draws the
   meter's values as steps, and after each test measures how far the meter lags the thrust
   and removes that lag. Misreads that slip through are flagged after the test.
5. In **Review tests**, **Re-read meter…** reads the meter again from the test's video,
   every frame — also for a test recorded before the screen was marked.

Details, accuracy and timing: [`docs/WATT_METER_READING.md`](docs/WATT_METER_READING.md).

**Jank mode (current and voltage from the Arduino instead of the camera)**
1. Wire the ACS758ECB-200B's OUT2 to **A3** (VCC → 5V, GND → GND) and the battery voltage
   divider's output to **A2** (divider ground → Arduino GND). Keep A2 under 5 V: ÷6.5556 is
   good up to 7S.
2. Upload `ThrustStand.ino` 2.3, click **Activate jank mode** under the camera preview, zero
   the current with the motor off and match the voltage to a multimeter (**Jank setup…**).
3. Power, current and voltage now come from the Arduino at 50 Hz on the load cells' clock and
   are saved to `power_data.csv`; results, review and report use them.
Details: [`docs/JANK_MODE.md`](docs/JANK_MODE.md).

## 6. Tare and calibration
**Tare both** (bottom bar) zeroes both load cells; **Tare Motor N** in the *Tare &
calibration* panel zeroes only the load cell chosen in its *Load cell* box. A confirmation
reminds you that the motors must be stopped; if a cell currently reads more than 0.2 lb you
get an extra warning. A tare never happens automatically when a test starts.

Pick **Motor 1** or **Motor 2** in the panel's *Load cell* box before using Apply, the
wizard, Save or Load — each load cell has its own calibration factor.

**Airspeed zero:** with no air moving past the pitot (motors off, tip loosely covered), click
**Zero airspeed (no airflow)**. Until it has been zeroed once, the airspeed card shows
*NOT ZEROED* and reads a few m/s even in still air. The zero is stored in the Arduino's
EEPROM; re-zero at the start of each test day, because the sensor's offset drifts with
temperature. Below about 4–5 m/s the reading is mostly noise (1 sensor count ≈ 1 Pa).
Airspeed uses the air density from Settings → Airspeed (default: ISA pressure at
1,280 ft field elevation + the sensor's temperature).

**Calibration wizard** (*Known-weight calibration wizard…*, for the selected load cell):
1. Confirm the motor is off and the cell is unloaded.
2. **Tare now** — the Arduino averages 20 readings; the wizard then checks the zero is stable.
3. Apply a known load in the thrust direction, enter its value and unit (lb, oz, kg, g, N —
   masses use standard gravity), **Capture** for a few seconds. The wizard shows mean,
   noise, signal-to-noise warnings and the resulting factor (counts per lb).
4. **Apply to Arduino** — the factor is sent, confirmed by the Arduino's acknowledgement,
   stored in its EEPROM and added to the app's calibration history.

Negative factors are fine (load cell mounted the other way). You can also type a factor and
press **Apply**, or **Save…/Load…** calibration files. Every test records the factor that
was active, as reported by the Arduino.

## 7. Running a test
1. **Test setup** tab: motor, KV, propeller (diameter × pitch, CW/CCW), number of motors,
   battery (defaults 4S 2200 mAh LiPo), ESC, operator, notes. **Save as…** stores the
   configuration for reuse.
2. Press **START TEST** (or F9). A short safety checklist appears (can be disabled). The
   program then: creates the test folder → takes the shared time reference → starts video
   capture → starts logging every thrust sample → sends START to the Arduino (which flashes
   the sync LED) → shows the red **REC** indicator and test timer.
3. Run the motor with your normal throttle procedure.
4. Press **STOP TEST** (F9). Logging stops, the video is finalized, STOP is sent, all
   buffered samples are flushed, the CSV gets its aligned-time column, the metadata, graph
   and summary are written, and a summary window opens. **This does not stop the motor.**

Dashboard notes:
* Current/maximum/minimum/average/σ, elapsed time and the measured HX711 rate. During a test
  the statistics cover the whole test (tag **TEST**); otherwise they run since the last
  reset (tag **LIVE**). If the Arduino is disconnected or silent the readouts show
  **— — —** — the app never displays invented values.
* Graph: choose the time window, zoom/pan with the mouse (*Follow live* re-enables
  scrolling), *Pause graph* (F8) freezes the display while recording continues, optional
  display-only moving average, peak marker, **Export PNG…**, shaded recorded interval.
* **Save snapshot** (F7): graph PNG + camera still + current readings (into the test folder
  while recording). **Sync flash** marks a hardware sync point at any time.
* Problems (lost samples, camera disconnect, low disk space, NAKs…) appear in the event log
  and in the test's `events.log`. Unplugging the camera ends the video cleanly while thrust
  logging continues; unplugging the Arduino keeps the test open and data resume when it
  reconnects. Recording stops automatically if the disk is nearly full.
* If the program or PC crashes mid-test, the thrust CSV (flushed several times a second)
  and frame timestamps are already on disk; at the next start the test is finalized
  automatically and marked `"status": "recovered"`.

## 8. What is saved
Default location: `Documents\PropulsionTests\` (change it in the bottom bar).

```
Motor_Test_2026-10-23_001/
    thrust_data.csv        every Motor 1 sample received from the Arduino
    thrust2_data.csv       every Motor 2 sample (if load cell 2 is connected)
    airspeed_data.csv      every airspeed reading (if the sensor is connected)
    wattmeter_data.csv     volts / amps / watts read from the meter's screen by the camera
    power_data.csv         jank mode: current (A3 hall sensor) and voltage (A2 divider) from the Arduino
    camera.mp4             watt meter video
    video_timestamps.csv   PC timestamp of every video frame
    test_metadata.json     configuration, calibration, devices, synchronization, integrity
    thrust_graph.png       graph with the peak marked
    test_summary.csv       one-row summary (easy to combine across tests in Excel)
    events.log             everything that happened during the test
    snapshots/             only if you saved snapshots
```
Folders are numbered automatically and existing files are never overwritten. Simulated tests
start with `SIM_`.

**thrust_data.csv** (motor 1) and **thrust2_data.csv** (motor 2) — same columns:

| column | meaning |
|---|---|
| `sample_number` | Arduino sequence number (gaps = lost samples) |
| `arduino_time_us`, `arduino_time_ms` | Arduino clock (unwrapped) |
| `host_time_ns` | PC monotonic clock when received |
| `elapsed_time_s` | `host_time_ns` relative to START (negative = pre-trigger) |
| `aligned_time_s` | best estimate of when the reading was taken, on the same clock as the video (see SYNCHRONIZATION.md) |
| `thrust_lb` | exactly as sent by the Arduino — never smoothed or interpolated |
| `net_counts` | raw ADC counts minus zero (allows re-calibration later) |
| `flags` | 1 test active, 2 taring, 4 ADC saturated |

**airspeed_data.csv**: `sample_number`, the same time columns, `diff_pressure_pa` (pitot ΔP
as sent by the Arduino), `airspeed_m_s` (computed: √(2·ΔP/ρ), 0 for negative ΔP),
`air_temp_c`, `air_density_kg_m3` (the ρ used), `raw_counts`, `flags`.

**wattmeter_data.csv** (one row per display update, plus a repeat row every second while the
display holds still): `sample_number`, `frame_number`, `host_time_ns`, `elapsed_time_s`,
`aligned_time_s` (minus the camera latency and the measured meter lag), `voltage_v`,
`current_a`, `power_w` (as the meter displays them), `v_times_a_w`, `read_confidence`,
`settle_ms`, `frames_averaged`, `flags`, `lcd_text`, and — added after the test — each
motor's thrust at that instant and `thrust_per_watt_g_per_w`. See
[`docs/WATT_METER_READING.md`](docs/WATT_METER_READING.md).

Each sensor keeps its own file and its own sample times — nothing is interpolated onto a
common grid (the watt meter file's `*_interp` thrust columns are the one, clearly named,
exception). To compare them (e.g. thrust vs airspeed), match rows by `aligned_time_s`
(in Excel with XLOOKUP's nearest match, or `pandas.merge_asof`).

**video_timestamps.csv**: `frame_number` (in the MP4), `capture_index` (gaps = dropped
frames), `host_time_ns`, `elapsed_time_s`.

**test_metadata.json** includes date/time, all configuration fields, both calibration factors
and zero offset, firmware version, measured HX711 rate, camera resolution/format/frame rate
(requested, reported and measured), codec, sync markers, Arduino clock drift, USB latency
statistics, lost samples, dropped frames, camera read failures, results and warnings.

## 9. Reviewing tests
**Review tests** (top bar) lists saved tests. Open one to get the thrust graph, the video,
the summary and the full metadata. Drag the yellow cursor (or click the graph) and the
video jumps to the matching frame; press ▶ and the cursor follows the video. Matching uses
the recorded frame timestamps, not an assumed frame rate. **Camera latency** shifts the
video by the camera's internal delay — measure it with **Mark LED frame** as described in
[`docs/SYNCHRONIZATION.md`](docs/SYNCHRONIZATION.md) and **Save** it with the test. Older
tests, tests without video, and tests interrupted by a crash (`camera.partial.mp4`) also
open.

**Test report** (top bar, or *Report* in the post-test summary / review window) shows a test
as one clean page: setup, headline numbers (peak thrust per motor, peak power, g/W, max
current, peak airspeed), the thrust / power / airspeed graphs, thrust vs. power, a camera still
of the watt meter at peak thrust, result tables and data-quality notes. Open any test folder
with **Open test folder…**, pick one from the recent list, or drag a folder onto the window —
folders copied from another computer work too. **Export image…** saves a sharp PNG (2800 px
wide, default name `<folder>_report.png` inside the test folder); **Copy image** puts it on
the clipboard for slides or chat. Choose *Light* (for documents) or *Dark*.

## 10. Automatic recording
**Auto trigger** tab (off by default): recording starts when thrust stays above the start
threshold for the hold time, and stops after it stays below the (lower) stop threshold for
its hold time. The gap between thresholds plus the hold times, minimum length and re-arm
delay prevent start/stop chatter. A **pre-trigger buffer** keeps the seconds of video and
thrust just before the trigger (negative times in the files). Manually started tests are
never stopped automatically.

## 11. Simulation mode
Choose **SIMULATOR** in the port list and **SIMULATED camera** in the camera list, or start
with `--simulate`. The simulated Arduino speaks the exact same protocol (including clock
drift, USB jitter and occasional lost frames) and runs a 30-second motor-run cycle; the
*Simulator controls* let you add a static weight to either load cell (to try the calibration
wizard), a steady wind for the airspeed sensor, unplug load cell 2 or the airspeed sensor, or
simulate unplugging the USB cable or the camera. Simulated data are labelled everywhere:
orange banner, SIMULATION badge, graph watermark, `SIM_` folder prefix and
`"simulated": true` in the metadata.

## 12. Building the standalone .exe
Run **`build_windows.bat`** (after `setup_windows.bat`). It installs PyInstaller, runs the
test suite, builds `dist\PropulsionTestStand\PropulsionTestStand.exe` (one-folder build —
fast start, no unpacking) and points the desktop shortcut at it. Copy the **whole**
`dist\PropulsionTestStand` folder to another PC to run it there without Python. Manual
build: `.venv\Scripts\python -m PyInstaller --noconfirm --clean PropulsionTestStand.spec`.

Settings, saved configurations, calibration history and logs live in
`%APPDATA%\TarletonSAEAero\PropulsionTestStand\`.

## 13. Tests and development
```
.venv\Scripts\python -m pip install -r requirements-dev.txt
.venv\Scripts\python -m pytest -q
```
The suite (≈120 tests, runs headless) covers packet parsing, the firmware itself (compiled
for the PC against mock Arduino/HX711/EEPROM when `g++` is available — its output is parsed
by the Python parser to prove both sides agree), tare/calibration commands, CSV writing,
timestamp handling and clock alignment, START/STOP state transitions, camera failures, the
review synchronization, file management, auto-trigger hysteresis, unplug/reconnect, thread
shutdown and bounded memory, plus GUI smoke tests driven by the simulator.

`tools/avr_compile_check.sh` compiles the firmware for the ATmega328P with `avr-gcc` (CI use).
See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the module layout, threading model and
how to add current/voltage/RPM/temperature sensors.
