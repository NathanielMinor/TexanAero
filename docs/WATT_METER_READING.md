# Reading the watt meter with the camera

The camera that records the watt meter can also **read** it: volts, amps and watts are
taken from the meter's screen every time its display updates, shown live, logged to
`wattmeter_data.csv`, plotted, and combined with thrust into an efficiency figure (g/W).

## How it works

The 150 A "watt meter / power analyzer" uses a standard 16×2 character LCD (HD44780 type):
every character is a 5×8 grid of dots drawn from a fixed font. Because the font is known,
no general-purpose OCR is needed:

1. **The text is located** — automatically, or inside the screen whose four corners you
   clicked. The program
   straightens that area (perspective correction), so the camera doesn't have to be square
   to the meter.
2. **It fits the character grid**: it works out how many characters the marked text spans
   and moves the four corners and the row spacing until the dots line up with the font.
3. **To read it**, each character cell is filtered to remove glare and backlight gradients
   and compared with the font glyphs by correlation. The best match wins; a poor match is
   reported as `?`.
4. **Only live values count**: a number followed by exactly `A`, `V` or `W`. The meter's
   other screens (`Ah`, `Ap` peak amps, `Vm` minimum volts, `Wh`, `Wp`…) are ignored.

### Following the meter's display (one row per update)

The meter samples, averages and redraws its screen only a few times a second, and the liquid
crystal needs 0.1–0.3 s to fade from the old digits to the new ones. Reading every camera frame
would log the same numbers over and over and, worse, half-faded "ghost" digits. So the reader
follows the display instead:

1. Every frame, the screen is compared with the last still picture of it. A dot-sized
   difference above the camera's own noise means **the display is updating**.
2. One-frame flickers (video compression, a reflection, auto-exposure) are ignored: a small
   difference must still be there on the next frame to count.
3. Once the screen has been **still for the settle time** (Settings → Watt meter, default
   100 ms) it is read — from the **average of all the still frames**, which removes camera
   noise. If the next update comes first, a value that was still for at least 60 ms is read
   anyway rather than lost.
   Some meters update faster than their LCD can finish fading, and a 15–20 fps camera may then
   catch each value fully for only a frame or two. Such an update is read from its **most settled
   frame** instead (flag 512), with a stricter glyph match, and only if all three values are read
   and W = V × A.
4. The row is **dated when the update first appeared**, not when it was read (`settle_ms`
   says how long it waited, `frames_averaged` how many frames were averaged).
5. While the display holds still, the same values are logged again every second (flag 16) so
   the data has no gaps.

### Checks on every reading
- every character of a value matched the font well (default 0.6);
- the value is plausible: ≤ 60 V, ≤ 200 A, ≤ 12 000 W (adjustable);
- the number format is the one this meter uses (learned automatically, e.g. two decimals for
  amps); a dropped decimal point ("1234A" from "12.34A") is a misread;
- **W = V × A**: when all three are read, watts must agree with volts × amps within display
  rounding (2 %, at least 1 W). If one digit was uncertain (two glyphs almost equally likely),
  the check picks the one that makes W = V × A true (flag 8). If it still disagrees, the row is
  flagged (flag 2), the card shows "⚠ V×A≠W", and it is left out of statistics and graphs.

If the meter or camera gets nudged, the reader searches small shifts of the grid by
itself (up to about 3 dots); after a bigger move it finds the screen again.

### After the test
- **Spikes**: a value that jumps for a single display update and comes straight back, while
  the other quantities (amps ↔ watts, volts sagging with current, thrust following power) say
  nothing happened, is flagged as a misread (flags 32 volts / 64 amps / 128 watts) and left out
  of statistics and graphs. A jump that the other readings confirm is a real throttle blip and
  is kept. With nothing to compare against, nothing is flagged.
- **Meter lag**: the meter's averaging makes its numbers trail the load cells by a few tenths
  of a second. The program slides the meter's current (held between updates) along the total
  thrust, 0–1.5 s, and keeps the shift that lines them up best. That shift is removed from
  `aligned_time_s` and reported (`results.wattmeter.meter_lag`). It is only applied when the
  throttle changed enough during the test to measure it clearly (turn it off in Settings →
  Watt meter).
- **Statistics as steps**: averages, battery charge (mAh) and energy (Wh) treat each reading as
  held until the next update — exactly what the display shows — never across a gap of more
  than 2 s where the screen couldn't be read. The graphs draw the meter's values as steps too.
- `display_update_interval_s` in the results is the meter's measured refresh interval.

## Setting it up

**Normally there is nothing to do.** As soon as the camera is open, the program looks for
the meter's screen by itself:

1. it finds the backlit screen by its colour (bright blue, or yellow-green on other meters),
   ignoring labels printed on the bezel ("SOURCE", "LOAD", "150A");
2. it finds the two rows of lit characters inside it;
3. it fits the character grid and checks that it actually reads a value.

The found position is saved. If the screen can't be read for a few seconds (camera or meter
moved), it searches again on its own. The event log says when it found the screen.

**If it can't find the screen — click its four corners.** Open **Meter reading…** above the
camera preview and click the four corners of the meter's **screen** (the lit window):
① top-left, ② top-right, ③ bottom-right, ④ bottom-left. Zoom in with the mouse wheel (pan
with the right button) to click accurately; a few pixels off is fine — the clicks are snapped
to the lit screen when it can be seen. The program then finds the text inside, fits the
grid and shows:
- the grid over the camera image,
- a **screen close-up**: just the screen, straightened and enlarged, with the grid it reads,
- what it reads (amps, volts, watts and the match %).

Drag a corner to adjust (it searches again). For fine adjustment switch *Clicks mark* to
**the text's corners** and click/drag the corners of the outer characters, then **Fit again**.
**Save** keeps the position and the screen outline.

**Zoom to screen** (next to *Meter reading…*) makes the live preview show the same close-up
instead of the whole camera picture — the grid is cyan while it reads, orange when it can't.

What helps the reading:
- **No reflections on the screen.** Glare is the main cause of misreads. Tilt the meter or the
  camera a few degrees and shade overhead lights.
- Sharp focus (turn off autofocus once it's sharp) and the screen reasonably large in the
  picture: at least ~12 pixels per character.
- The meter showing its normal screen (amps · volts on top, watts bottom right).

Settings → Watt meter → *Find the screen automatically* turns the automatic search off (then
only a marked position is used); *Forget the marked screen position* clears it.

## Re-reading a test from its video

**Review tests → Re-read meter…** reads the meter again from the test's `camera.mp4`, every
frame, timed with `video_timestamps.csv` (the same PC clock as the load cells). Use it when
the live reading was poor, the screen wasn't marked during the test, or after changing the
settings. It first shows a frame of the video in the same dialog (check or click the screen's
corners), then reads in the background with a progress bar. The live readings are kept as
`wattmeter_data_live.csv`, the results, summary and saved graph are recomputed, and you can go
back to the live readings afterwards.

## What is recorded

`wattmeter_data.csv` (one row per display update, plus a repeat row about every second while
the display holds still):

| column | meaning |
|---|---|
| `sample_number` | reading counter |
| `frame_number` | camera capture index of the frame that was read |
| `host_time_ns`, `elapsed_time_s` | when the display update first appeared in the camera (PC clock, same as thrust and video) |
| `aligned_time_s` | `elapsed_time_s` minus the camera latency setting and the measured meter lag (added after the test) |
| `voltage_v`, `current_a`, `power_w` | as displayed by the meter; empty = not read confidently |
| `v_times_a_w` | `voltage_v × current_a`, for checking `power_w` |
| `read_confidence` | mean font-match score of the screen (0–1) |
| `settle_ms` | how long after the update appeared it was read (0 for repeat rows) |
| `frames_averaged` | camera frames averaged for this reading |
| `flags` | sum of: 1 = all three values read together, 2 = W ≠ V×A (suspect), 4 = grid re-tracked, 8 = a digit fixed by the W = V×A check, 16 = repeat (display unchanged), 32 / 64 / 128 = volts / amps / watts flagged as a spike after the test, 256 = a later, better-averaged read of the same display differed, 512 = read from the most settled frame (the display was never still for the settle time) |
| `lcd_text` | both LCD rows exactly as recognised (`?` = unrecognised character) |
| `motor1_thrust_lb_interp`, `motor2_thrust_lb_interp` | thrust at the same instant (linear interpolation of the load-cell data, added after the test) |
| `thrust_per_watt_g_per_w` | total thrust / power, for readings ≥ 5 W |

The test results (metadata, summary CSV, summary window, review window, report) include
maximum power with the volts and amps at that moment, thrust per watt at maximum power,
maximum and average current, the voltage range, average voltage and **voltage sag** (highest
minus lowest during the test), the **battery charge (mAh) and energy (Wh) used** (amps and
watts integrated over time as steps, never across a gap of more than 2 s where the screen
couldn't be read, leaving out flagged misreads), the meter's display update interval and the
meter lag that was removed. Averages are time-weighted.

**Graphs.** Power, and current (left axis) with voltage (right axis), get their own panels under
the thrust graph — live on the dashboard, in Review (with the cursor; a dot marks each reading),
in the saved `thrust_graph.png` and in the report. They are drawn as **steps**, because the
meter holds each value until its next update. Rows flagged as misreads are left out. The
dashboard's **Panels** menu hides or shows the airspeed, power and current & voltage panels.

## Timing — read this before comparing power and thrust closely

- Each reading carries the time the display update **first appeared in a camera frame that
  reached the PC**. The camera adds its own delay (typically 50–150 ms). Measure it with the
  sync LED (docs/SYNCHRONIZATION.md) and enter it as the camera latency; `aligned_time_s`
  removes it.
- The meter itself samples, averages and refreshes its display a few times per second, so
  its numbers trail rapid throttle changes by roughly 0.2–0.5 s. When the throttle changed
  during the test, that lag is measured against the thrust and removed too (see *After the
  test*). Even so, a meter that updates every 0.4 s can't show anything faster than that: for
  efficiency numbers, hold the throttle steady for a couple of seconds at each point.

## If it can't read the screen

| symptom | fix |
|---|---|
| Card says "meter screen not found" | Get the screen in view, in focus and free of glare; or open **Meter reading…** and click the four corners of the screen. |
| "can't read the screen", match below ~70 % | Glare, focus or a moved camera/meter. Fix the image, then mark again. |
| Volts or watts missing, the text line shows `?` or wrong letters at one end | Usually glare over those characters, or the grid off by a character — check the screen close-up, drag a corner (or mark the text's corners) and press **Fit again**. |
| Wrong number of characters per row after fitting | Mark the corners while the meter shows its normal screen; zoom in and click on the dots themselves. |
| Updates missed or ghost values during fast changes | Raise *LCD settle time* (Settings → Watt meter), then **Review → Re-read meter…** to read the video again. |
| "⚠ V×A≠W" | One value is being misread — see glare/focus. Flagged rows are excluded from statistics. |

**Save image…** in the marking dialog stores a full-resolution camera frame; keep it if you
need help tuning the reader.
