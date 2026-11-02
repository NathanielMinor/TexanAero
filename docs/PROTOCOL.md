# ThrustStand serial protocol — version 2

The Arduino and the PC exchange short ASCII lines over USB serial. Version 2 adds a second
load cell and the airspeed sensor; it is not compatible with version 1 firmware (the app
tells you to re-upload the sketch if it finds v1).

| Setting | Value |
|---|---|
| Baud rate | **250000**, 8 data bits, no parity, 1 stop bit (exact on a 16 MHz Uno) |
| Line ending | `\n` (a `\r` before it is ignored) |
| Checksum | `*HH` at the end of every Arduino line: XOR of all bytes before `*`, two upper-case hex digits (NMEA style) |

Lines that fail the checksum are **rejected and counted**, never repaired.
Commands from the PC may carry the same checksum; the firmware verifies it when present
(the Python application always sends it).

## Streams

One Arduino carries three independent sample streams, each with its own sequence numbers:

| Stream | Hardware | Frame | Typical rate | File |
|---|---|---|---|---|
| Motor 1 | HX711 #1, DOUT D3 / SCK D2 | `D,1,…` | 10 or 80 Hz (HX711 RATE pin) | `thrust_data.csv` |
| Motor 2 | HX711 #2, DOUT D5 / SCK D4 | `D,2,…` | 10 or 80 Hz | `thrust2_data.csv` |
| Airspeed | Matek ASPD-4525 (MS4525DO) on I2C 0x28 | `A,…` | 50 Hz | `airspeed_data.csv` |
| Current + voltage (jank mode, fw ≥ 2.1) | ACS758ECB-200B OUT2 on A3, battery divider on A2 | `E,…` | 50 Hz, only after `ELEC,1` | `power_data.csv` |

All streams use the same Arduino `micros()` clock. A missing sensor simply produces no frames
(and an event); the others are unaffected.

## Arduino → PC

### `HELLO` — banner (at boot, or in reply to `HELLO`)
```
HELLO,TSAD-THRUST,fw=2.0.0,proto=2,cells=2,cal1=46500.000,cal2=46500.000,zero1=restored,zero2=boot_tare,as=OK*HH
```
`zeroN=restored`: that cell's tare offset was loaded from EEPROM. `boot_tare`: it tared at
power-up because no saved zero existed. `as=OK|NONE`: airspeed sensor detected or not.
`el=0|1` (firmware 2.1+): the current/voltage stream is off/on — its presence means the firmware
has it.

### `D` — one HX711 conversion
```
D,<cell>,<seq>,<t_us>,<net_counts>,<thrust_lb>,<flags>*HH
D,2,1532,19234567,93012,2.00026,1*5C
```
| Field | Meaning |
|---|---|
| `cell` | 1 = motor 1, 2 = motor 2 |
| `seq` | Sample number of this cell, +1 for **every** conversion. A gap means samples were lost. Restarts at 1 after a reset. |
| `t_us` | Arduino `micros()` when the conversion was detected. 32-bit, wraps every 71.6 min (the PC unwraps it). |
| `net_counts` | Raw 24-bit ADC reading minus that cell's tare offset. |
| `thrust_lb` | `net_counts / calibration_factor`, 5 decimals. |
| `flags` | Hex bitfield: `1` test active, `2` tare in progress, `4` ADC saturated. |

### `A` — one airspeed reading
```
A,<seq>,<t_us>,<dp_pa>,<raw_counts>,<temp_c>,<flags>*HH
A,881,19240012,123.45,8310,24.6,0*3A
```
| Field | Meaning |
|---|---|
| `dp_pa` | Pitot differential pressure in Pa, minus the stored airspeed zero, 2 decimals |
| `raw_counts` | 14-bit sensor output (8192 ≈ 0 Pa); 1 count ≈ 1.05 Pa |
| `temp_c` | Sensor temperature (°C) |
| `flags` | `1` test active, `2` zeroing in progress, `4` outside 5–95 % of range, `8` not zeroed yet (nominal zero used) |

Airspeed itself is computed on the PC: `v = √(2·max(ΔP,0)/ρ)`, with ρ from the field
elevation and the sensor temperature (or a fixed value) — see Settings → Airspeed.
ΔP is averaged over 0.2 s before the square root, and speeds below 5 mph read 0 (the sensor's
noise floor; both adjustable in Settings → Airspeed). The CSV's `diff_pressure_pa` stays raw.
Readings flagged "stale" by the sensor are skipped, never repeated.

### `E` — current and voltage inputs (jank mode)
```
E,<seq>,<t_us>,<sum_a3>,<sum_a2>,<n_a3>,<flags>,<n_a2>,<bandgap>*HH
E,412,19251234,28680,5120,40,1,10,232*4C
```
| Field | Meaning |
|---|---|
| `t_us` | `micros()` in the middle of the averaging window |
| `sum_a3` | sum of `n_a3` 10-bit readings (0–1023) of A3 (hall current sensor), one every ~0.5 ms at a randomised moment in its slot (fw 2.2: 40 per frame) |
| `sum_a2` | sum of `n_a2` readings of A2 (voltage divider), one every 2 ms (10 per frame) |
| `flags` | `1` test active, `4` an input reached the end of the ADC range |
| `n_a2` | fw 2.2+; firmware 2.1 sent 7 fields with `n_a3 = n_a2 = 10` (the parser accepts both) |
| `bandgap` | fw 2.3+: the internal 1.1 V reference read against the 5 V rail, once a second (`0` = not yet): 5 V rail = 1.1 × 1023 / bandgap. A2 is selected ~0.5 ms before each voltage reading so a high-resistance divider can charge the ADC. |

Amps and volts are computed on the PC (zero, sensitivity, divider ratio and the 5 V rail are
settings there) — see docs/JANK_MODE.md.

### `ACK` — command accepted
| Reply | Fields |
|---|---|
| `ACK,TARE,<cell>,<n>,<mask>` | taring `cell` (0 = all) over `n` conversions; `mask` = cells actually tared (bit0 motor 1, bit1 motor 2). Completion: `EVT,TARE_DONE` |
| `ACK,CAL,<cell>,<factor>` | the factor now in use for that cell (3 decimals) |
| `ACK,AZERO,<n>` | airspeed zero started over `n` readings; completion: `EVT,AZERO_DONE` |
| `ACK,RESET_MAX` | — |
| `ACK,START,<t_us>,<next1>,<next2>,<nextA>[,<nextE>]` | `micros()` when the sync LED switched on; seq of the first "test active" sample of motor 1, motor 2, airspeed (and, fw 2.1+, the current/voltage stream) |
| `ACK,STOP,<t_us>,<next1>,<next2>,<nextA>,<max1>,<max2>[,<nextE>]` | firmware maxima since START (`nan` if none) |
| `ACK,ELEC,<on>,<sample_us>,<n_a3>[,<n_a2>]` | current/voltage stream on/off; current readings every `sample_us` on average, `n_a3` current and `n_a2` voltage readings per frame |
| `ACK,STATUS,key=value,…` | `fw, proto, cal1, off1, sps1, hx1, zero1, max1, cal2, off2, sps2, hx2, zero2, max2, as, as_hz, as_off, as_zero, as_err, el, el_hz, test, up, txd` |
| `ACK,PING,<token>,<t_us>` | clock alignment / USB round-trip measurement |
| `ACK,SYNC,<t_us>` | `micros()` when the sync LED switched on |
| `ACK,DEFAULTS,46500.000` | both factors back to default; saved zeros (both cells + airspeed) forgotten for the next boot |

### `NAK,<cmd>,<reason>` — command rejected
`UNKNOWN`, `BAD_ARG`, `BUSY` (already taring/zeroing), `CHECKSUM`, `OVERFLOW` (line longer
than 63 characters), `HX711_TIMEOUT` (that load cell isn't producing readings),
`AIRSPEED_ABSENT`.

### `EVT` — asynchronous events
| Event | Meaning |
|---|---|
| `EVT,TARE_DONE,<cell>,<offset>,<n>` | new zero offset for that cell, stored in RAM and EEPROM |
| `EVT,TARE_FAILED,<cell>,HX711_TIMEOUT` | that HX711 stopped during a tare |
| `EVT,HX711_TIMEOUT,<cell>` | no conversion from that cell for 1 s (wiring, power) |
| `EVT,HX711_RECOVERED,<cell>` | conversions resumed |
| `EVT,HX711_FAULT,<cell>` | DOUT stuck low (amplifier unpowered or shorted); readings suppressed |
| `EVT,AIRSPEED_FOUND` / `EVT,AIRSPEED_LOST` | airspeed sensor appeared / stopped answering on I2C |
| `EVT,AZERO_DONE,<zero_counts>,<n>` | airspeed zero stored in RAM and EEPROM |

Lines starting with `#` are comments and carry no checksum.

## PC → Arduino

| Command | Action |
|---|---|
| `TARE` / `TARE,<cell>` / `TARE,<cell>,<n>` | Zero cell 1, 2 or all (0, default) over *n* conversions (1–100, default 10). Non-blocking. "All" skips a disconnected cell. |
| `CAL,<cell>,<value>` | Calibration factor of that cell in counts per lb; 1 ≤ \|value\| ≤ 10⁸; negative flips the sign. Saved to EEPROM. |
| `AZERO` / `AZERO,<n>` | Average *n* airspeed readings (1–200, default 50) as the zero. **No airflow!** Saved to EEPROM. |
| `ELEC` / `ELEC,<0\|1>` | Stop / start the current + voltage stream (`E` frames). Off at power-up; the app sends `ELEC,1` after connecting while jank mode is on. |
| `RESET_MAX` | Reset both firmware maxima. |
| `START` / `STOP` | Mark the start/end of a test (sets flag bit 0; START flashes the sync LED on D13 for 100 ms). |
| `STATUS` | Report status. |
| `PING,<n>` | Echo token *n* with the current `micros()`. |
| `SYNC` | Flash the sync LED and report its time. |
| `HELLO` | Re-send the banner. |
| `DEFAULTS` | Factor 46500 for both cells; forget the EEPROM zeros. |

Commands are case-insensitive. The PC waits for `ACK`/`NAK` (default 1 s) and retries once.

## Future sensors — `M` frames
The parser also accepts a generic multi-channel frame:
```
M,<seq>,<t_us>,voltage_v=16.42,current_a=31.5,rpm=9120*HH
```
Each key becomes a CSV column and a dashboard readout. Use the channel names listed in
`app/sensors/model.py` so derived quantities work automatically.

## Timing guarantees
* The firmware never calls `delay()`; each HX711 is read only after `is_ready()`, and the
  I2C bus has a 3 ms timeout so a jammed sensor can't freeze the loop.
* At 250000 baud, both cells at 80 SPS plus airspeed at 50 Hz use about a third of the link; the
  current/voltage stream adds ~2.3 kB/s.
* Reading the current (~0.11 ms every 0.5 ms) and the voltage (two conversions, one discarded
  after switching inputs, every 2 ms) uses about a third of the CPU; no single step blocks for more
  than ~0.34 ms, so HX711 conversions are still picked up promptly.
* A data frame waits at most ~2 ms for UART space; beyond that it is dropped and counted
  (`txd`), producing a visible sequence gap.
* The Uno's UART drains at a fixed rate whether or not the PC is listening, so an unplugged
  or frozen PC can never stall the firmware.
