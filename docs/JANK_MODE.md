# Jank mode — current and voltage from the Arduino

**Activate jank mode** (under the camera preview) measures power with two analog inputs on the
Arduino instead of reading the watt meter's screen with the camera:

| Quantity | Hardware | Arduino pin |
|---|---|---|
| Current | Allegro **ACS758ECB-200B** hall-effect sensor, ±200 A, its **OUT2** (shielded copy of OUT1) | **A3** |
| Battery voltage | resistor divider, battery volts ÷ **6.5556** | **A2** |
| Power | volts × amps, computed on the PC | — |

Because the Arduino reads them on the same clock as the load cells, the current and voltage
line up with thrust exactly — no camera delay, no watt-meter lag — and they arrive 50 times a
second instead of whenever the meter's display updates. The camera keeps recording video; it
just stops reading the meter's screen.

## Wiring

```
ACS758ECB-200B module           Arduino Uno
  VCC  ───────────────────────  5V      (must be the Arduino's 5 V: see "ratiometric" below)
  GND  ───────────────────────  GND
  OUT2 ───────────────────────  A3
  big current terminals: in series with the battery lead (either one; flip the sign in setup if
  the current reads negative)

Voltage divider (battery + → R_top → node → R_bottom → battery −)
  node ───────────────────────  A2
  battery − ──────────────────  GND     (the divider needs a common ground with the Arduino)
```

**Never let A2 go above 5 V.** With a ÷6.5556 divider that's **32.8 V** at the battery — fine for
up to 7S LiPo (29.4 V full), **not** for 8S (33.6 V). A bigger battery needs a bigger ratio.

## First time

1. **Upload the firmware** `arduino/ThrustStand/ThrustStand.ino` (version 2.3) with the Arduino
   IDE — 2.0 doesn't have the analog inputs (the app will say so); 2.1/2.2 work but are noisier and
   can make the voltage rise under load (see below).
2. Click **Activate jank mode**. (There's a pop-up. Enjoy it.)
3. **Zero the current** with the motor **off** — from the pop-up or **Jank setup… → Zero current**.
   The sensor's output at 0 A is about half of 5 V but differs from part to part by a few amps'
   worth. The app refuses to zero while the load cells read thrust or the current is moving.
4. **Match the voltage** once — **don't skip this**: measure the battery with a multimeter, type it
   into **Jank setup… → Multimeter says the battery is**, press **Match**. The voltage is measured
   against the Arduino's 5 V pin, and on USB an Uno's 5 V is usually only 4.6–4.9 V, so
   uncalibrated the voltage reads **2–8 % high** — at rest and under load alike. (The current isn't
   affected: the hall sensor runs off the same 5 V and scales with it.) Alternatively measure the
   5V pin to GND with the multimeter and enter that as *Arduino 5 V rail*. Until one of the two is
   done, the power card says "voltage not calibrated", and it warns if the voltage is above a full
   pack for the cell count in Test setup.
5. Optional: **match the current** against a reference (the watt meter, a clamp meter) with a
   steady current flowing.

The settings are saved; jank mode stays on across restarts until you turn it off.

**Tests recorded before calibrating** can be fixed: open the test in **Review tests** and click
**Re-apply jank calibration**. It recomputes current, voltage and power from the ADC counts
saved with every reading, using the calibration as it is now, and redoes the results, summary and
graphs.

## Noise, and what's done about it

The ACS758 is fast (120 kHz), so it passes the ESC's switching ripple — the battery current
really does swing by tens of percent thousands of times a second — plus interference from the
motor wires. Sampled a few hundred times a second, that shows up as big random jumps. Three
layers deal with it:

1. **Firmware 2.2** reads the current every ~0.5 ms (40 readings per frame) at randomised moments
   within each slot, so the readings can't lock onto the ripple, and averages them.
2. **Live filter** (Jank setup → *Smoothing*, default 0.25 s, and *Throw out single-frame
   spikes*): the median of the last 5 frames (0.1 s) removes interference spikes, then a moving
   average smooths the ripple. Live readouts lag by about half the window (~0.15 s).
3. **After the test** the saved `current_a`, `voltage_v`, `power_w` are re-smoothed the same way
   but centred on each reading — no lag, so power lines up with thrust. The unsmoothed frame
   values stay in `*_raw` columns and the ADC counts in `*_counts`. Battery mAh and Wh are
   integrated from the unsmoothed values (averaging can't bias them); peaks and minimum voltage
   use the smoothed ones (otherwise noise would inflate them).

On a simulated ESC with ±35 % ripple and occasional spikes, this takes the current from ±2.8 A
(46 A peak-to-peak) to ±0.4 A (1.7 A peak-to-peak), and the power from ±45 W to ±6 W.

**Hardware helps most — two capacitors:**
* Current: a **1 kΩ resistor in series** from OUT2 to A3, and a **10 µF capacitor from A3 to GND**
  at the Arduino end (a 16 Hz low-pass). Don't put a big capacitor straight on OUT2 — the ACS758
  only likes ~10 nF there; the resistor isolates it.
* Voltage: a **1–10 µF capacitor across the divider's bottom resistor** (A2 to GND).
* Keep the OUT2 / divider wires short and away from the motor phase wires; twist each with its
  ground wire. Use OUT2 (shielded), not OUT1.

## Voltage that goes UP under load

A battery's voltage always drops as the current rises (its internal and wiring resistance). If the
reading rises instead, something is pushing it up in proportion to the current. Two usual causes,
both handled by **firmware 2.3**:

1. **Crosstalk inside the Arduino's ADC.** There is one ADC, switched between pins. When it moves
   from A3 (current sensor) to A2 (divider), its sample capacitor still holds A3's voltage. A divider
   made of large resistors (100 kΩ – MΩ; 1 MΩ + 180 kΩ gives exactly 6.5556) can't recharge it in the
   few microseconds it gets, so A2 reads partly A3. At rest both sit near 2.5 V, so it looks right;
   under load the current sensor's output climbs 10 mV per amp and drags the voltage reading up.
   Firmware 2.3 selects A2 about half a millisecond before each voltage reading, so it settles
   fully. A **1–10 µF capacitor from A2 to GND** fixes it in hardware too.
2. **The Arduino's 5 V moving.** The voltage is measured against the 5 V rail. If the rail sags
   under load (USB port drooping, Arduino powered from the ESC's BEC), the voltage reads high. The
   current doesn't care (ratiometric). Firmware 2.3 measures the rail once a second against the
   chip's internal 1.1 V reference; after you **Match** the voltage with 2.3 running, the app follows
   it. (The internal reference is only good to ±10 % per chip, which is why the Match is needed.)

After each test the app fits voltage against current: normally it reports the **battery + wiring
resistance** (mΩ); if the voltage rose with the current, it warns.

## How the numbers are computed

The firmware reads A3 every ~0.5 ms and A2 every 2 ms and sends the sums of 40 and 10 readings
50 times a second (`E` frames, docs/PROTOCOL.md). The PC turns them into amps and volts:

```
amps  = (A3_counts − zero_counts) × 5 / (1023 × 0.010 V/A) × current_scale     (≈ 2.05 counts per amp)
volts = A2_counts / 1023 × 5 V rail × 6.5556 × voltage_scale                   (≈ 32 mV per count)
        5 V rail = the Arduino's measurement (firmware 2.3, once matched with it), else the fixed setting
watts = volts × amps
```

* **Ratiometric:** the ACS758's zero point and sensitivity scale with its supply voltage, and the
  Arduino's ADC measures relative to the same 5 V, so the current reading doesn't depend on the
  exact USB voltage — as long as the sensor is powered from the Arduino's 5 V pin.
* **Resolution:** one ADC step is ~0.5 A and ~32 mV. Averaging 40 readings (the sensor's noise and
  the ripple act as dither) and then smoothing gives roughly 0.1 A and 10 mV steps. Below ~3 A
  the current is rough; at 20–150 A it's a few percent.
* Every reading keeps its raw counts in the CSV, so values can be recomputed later with a
  better zero or scale.

Everything in **Jank setup…** applies immediately: sensitivity (10 mV/A for the -200B; 40 for
-050B, 20 for -100B, 13.3 for -150B), divider ratio, the 5 V rail, flipping the current's sign,
and the fine corrections.

## What is recorded

`power_data.csv` (one row per frame, 50 per second):

| column | meaning |
|---|---|
| `sample_number`, `arduino_time_us`, `arduino_time_ms` | frame counter and Arduino time (middle of the 20 ms averaging window) |
| `host_time_ns`, `elapsed_time_s`, `aligned_time_s` | PC arrival time; aligned = on the load cells' time base (added after the test) |
| `current_a`, `voltage_v`, `power_w` | smoothed (live filter while recording; re-smoothed without lag after the test) |
| `current_a_raw`, `voltage_v_raw`, `power_w_raw` | that frame's values before smoothing |
| `current_counts`, `voltage_counts` | mean A3 / A2 readings (0–1023) behind them |
| `arduino_5v_v` | the Arduino's 5 V rail, measured against its 1.1 V reference (firmware 2.3) |
| `flags` | 1 = test running, 4 = an input at the end of the ADC range (sensor saturated or unplugged — left out of the current and power results) |
| `motor1_thrust_lb_interp`, `motor2_thrust_lb_interp`, `thrust_per_watt_g_per_w` | thrust at the same instant and efficiency (added after the test) |

The test results, summary, review window, report and saved graph show the same figures as
for the watt meter — peak power with volts and amps, thrust per watt, max/average current,
voltage range and sag, battery mAh and Wh — labelled *hall sensor (jank mode)*. The
metadata records the wiring, formula and calibration used (`sensors.elec`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| "firmware doesn't have the current/voltage inputs" | Upload ThrustStand.ino 2.3. |
| Voltage goes **up** under load | Upload firmware 2.3, then **Match** the voltage again (so it follows the measured 5 V). Add 1–10 µF from A2 to GND. Make sure the divider's ground goes to the Arduino's GND and nothing else ties the Arduino to the battery negative. |
| Card says "waiting for readings from A3/A2" | Arduino connected? Jank mode on? The event log shows whether the Arduino accepted `ELEC,1`. |
| Current reads a few amps with the motor off | Zero it (motor off). |
| Current is negative | Sensor mounted the other way: Jank setup → "flip the sign". |
| Still noisy | Upload firmware 2.2; raise *Smoothing* in Jank setup (0.5 s); add the two capacitors above. ~±0.5 A at rest is the 10-bit ADC's step on a 200 A sensor. |
| Voltage reads high (at rest and under load) | Not calibrated: the Arduino's 5 V on USB is below 5.00 V. Jank setup → type the multimeter reading → **Match**. Then fix earlier tests with **Review → Re-apply jank calibration**. |
| "input at the ADC limit" | A3 at 0 or 1023: sensor unpowered/unplugged, or beyond ±200 A. A2 at 1023: battery above 32.8 V — **disconnect, the divider ratio is too small**. |
