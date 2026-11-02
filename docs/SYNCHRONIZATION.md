# How thrust and video are synchronized — and how accurate it is

This system uses **software synchronization**. It is good enough to read the watt meter at
the moment of peak thrust, but it is not hardware-synchronized acquisition. This page
explains exactly what is measured, the size of each error, and how to measure the largest
one (camera latency) with the sync LED.

## One clock for everything
Every host timestamp comes from `time.perf_counter_ns()` (Windows QueryPerformanceCounter):
monotonic, sub-microsecond resolution, identical in every thread. When you press
**START TEST** the program takes one reading of this clock, `t0`, and every elapsed time in
the test files is measured from it. `test_metadata.json` also stores the pairing of `t0`
with wall-clock time.

## Thrust samples
Each sample carries two times:

| Column | Source | Error |
|---|---|---|
| `arduino_time_us` | Arduino `micros()` when the HX711 conversion was detected | jitter-free, but the Uno's ceramic resonator is only accurate to about ±0.5 % (up to 0.3 s per minute) |
| `host_time_ns` / `elapsed_time_s` | PC clock when the bytes were read from USB | includes USB/driver delay: about 1–4 ms minimum plus jitter, occasionally tens of ms |
| `aligned_time_s` | Arduino time mapped onto the PC clock (written when the test is saved) | typically within about 1–2 ms of the true detection time |

**Alignment method.** Transport delay is always positive, so the *lowest* values of
`host − arduino` trace the true relationship between the two clocks. The program takes the
minimum in 0.5 s windows, fits a straight line through those minima (slope = Arduino clock
drift, reported in ppm), shifts the line so it bounds every sample from below, and subtracts
half of the smallest measured PING round-trip (an estimate of the minimum one-way USB
delay). Drift, jitter percentiles and the method are saved under `synchronization` in the
metadata. If the Arduino resets mid-test, each segment is fitted separately.

**What alignment cannot fix.** The HX711 itself low-pass filters the signal: its datasheet
output settling time is 400 ms at 10 SPS and 50 ms at 80 SPS, so a sudden thrust change shows
up gradually. Use 80 SPS if your board allows it.

## Video frames
Each frame is stamped the moment `grab()` returns, using the same PC clock
(`video_timestamps.csv`). That is when the frame *reached the PC*, not when the sensor
exposed it. USB webcams add their own internal latency (exposure, on-camera compression,
USB transfer, driver buffering) — commonly 50–150 ms, and it is different for every camera,
resolution and exposure setting. Software alone cannot observe it.

Because the frame rate of a USB camera is not perfectly constant, the review window always
uses the per-frame timestamps, never "frame number ÷ nominal fps". The MP4's container frame
rate is set to the *measured* rate so it plays at close to real speed in other players.

## Measuring camera latency with the sync LED (hardware-referenced)
1. Wire a bright LED with a 330 Ω resistor from Arduino **D13** to **GND** and place it in the
   camera's view next to the watt meter (the Uno's tiny on-board "L" LED also works if visible).
2. Record a test. START flashes the LED for 100 ms; the **Sync flash** button flashes it
   again at any time. The Arduino reports the exact `micros()` of each flash, which the
   alignment converts to test time (shown as dashed START/SYNC lines in the review graph).
3. In **Review tests**, step frame-by-frame (◀ 1 / 1 ▶) to the **first frame where the LED is
   lit** and click **Mark LED frame**. The program computes
   `latency = frame arrival time − LED on time` and sets the *Camera latency* box.
4. Click **Save**. From then on the video is shifted by that latency when matched to thrust.

The result is accurate to about one frame period (33 ms at 30 fps), because the LED may
switch on at any point during an exposure. Repeat for a few flashes and use the smallest
value. Re-measure if you change camera, resolution, frame rate or exposure.

## Error budget (typical, 30 fps camera, 80 SPS HX711)

| Source | Size | Corrected? |
|---|---|---|
| USB delay of thrust samples | 1–4 ms + jitter | yes (`aligned_time_s`) |
| Arduino clock drift | up to ±5000 ppm | yes (clock fit) |
| HX711 internal filter | ~50 ms (80 SPS) / ~400 ms (10 SPS) settling | no — physical |
| Camera latency | 50–150 ms typical | yes, if measured with the LED |
| Video frame period | 33 ms at 30 fps | no — use a higher frame rate |

Without the LED measurement, assume the video can be about 0.1–0.2 s **behind** the thrust
trace. With it, expect agreement to about one frame.

## Hardware synchronization (if you ever need better)
True hardware sync would require the camera to be triggered by, or report its exposure time
to, the same clock as the ADC (e.g. a machine-vision camera with a trigger input driven by
the Arduino). Consumer USB webcams, including the Creality Nebula, have no such input.
