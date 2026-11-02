# Software architecture

```
PropulsionTestStand/
├── arduino/ThrustStand/ThrustStand.ino   Uno firmware (protocol v1)
├── app/
│   ├── main.py               entry point, logging, exception hook
│   ├── settings.py           persistent settings (JSON, tolerant loading)
│   ├── clock.py              the single host time base (perf_counter_ns)
│   ├── events.py             thread-safe event log (+ per-test events.log)
│   ├── calibration.py        factor math, units, calibration history
│   ├── test_config.py        motor/prop/battery configuration + saved profiles
│   ├── theme.py              dark theme (Qt style sheet, PyQtGraph defaults)
│   ├── sensors/
│   │   ├── protocol.py       line parser / command encoder (sensor_parser)
│   │   ├── model.py          Sample, source ids (motor1/motor2/airspeed), channel registry
│   │   ├── airspeed.py       pitot ΔP → airspeed, air-density model
│   │   ├── transport.py      pyserial transport, COM-port listing
│   │   ├── simulator.py      simulated Arduino (same bytes as the firmware)
│   │   ├── serial_manager.py worker thread: handshake, ACK/retry, reconnect, integrity
│   │   └── clock_sync.py     Arduino↔PC clock fit, drift, sequence analysis
│   ├── camera/
│   │   ├── devices.py        camera discovery and backend selection
│   │   ├── camera_manager.py capture thread, preview, controls, pre-trigger ring
│   │   ├── video_writer.py   encoder thread, MP4 + video_timestamps.csv
│   │   └── simulated.py      simulated camera
│   ├── recording/
│   │   ├── data_router.py    thread-safe hub: recording, statistics, trigger, display
│   │   ├── data_logger.py    CSV writer thread
│   │   ├── statistics.py     running statistics (Welford)
│   │   ├── auto_trigger.py   optional start/stop trigger state machine
│   │   ├── file_manager.py   folder naming, disk checks, atomic writes
│   │   ├── test_manager.py   START/STOP orchestration (no Qt)
│   │   ├── finalize.py       alignment, metadata, summary (background thread)
│   │   └── test_loader.py    loading saved tests for review
│   └── ui/                   PySide6 widgets: main window, plot, camera, calibration
│                             wizard, configuration, dialogs, review window
├── tests/                    pytest suite (+ host-compiled firmware harness)
├── tools/                    icon generator, shortcut script, AVR compile check
└── docs/
```

## Threads and data flow

```
 Arduino ──USB──► serial worker ──Sample──► DataRouter ──► CSV logger thread ──► thrust_data.csv
                     │  (parse, checksum,       │  (lock)  ├─► running statistics (exact)
                     │   seq/clock checks)      │          ├─► auto trigger → action queue
                     ▼                          │          └─► bounded display queue
               update queue                     ▼
 USB camera ──► capture thread ──frame──► VideoRecording (encoder thread) ──► camera.mp4
                     │                                                   └──► video_timestamps.csv
                     └──► latest preview / pre-trigger ring
                                   │
 GUI thread: one 30 Hz QTimer drains every queue and updates widgets.
             No worker thread ever touches a Qt widget.
```

* **The GUI never blocks on I/O.** Commands are queued to the serial worker; results come
  back through `poll_updates()`. Camera opening, enumeration and video encoding run on their
  own threads. Saving a test (alignment, metadata) runs on a background thread.
* **Recording never depends on the GUI.** Samples are written by the serial worker → router →
  logger queue path. If the GUI stalls, only the display queue drops old points.
* **Bounded buffers.** Display queue (50 000 samples), pre-trigger history (12 s), encoder
  queue (bytes-limited), pre-trigger video ring (seconds- and bytes-limited).
* **Shutdown.** Every worker has a stop event and is joined with a timeout; closing the
  window while recording stops the test and waits for the files to be finalized.

## Current sensors (protocol v2)

One Uno carries three streams — `motor1` (HX711 on D3/D2), `motor2` (HX711 on D5/D4) and
`airspeed` (MS4525DO on I2C). Each has its own sequence numbers, staleness detection, CSV
file, statistics and clock alignment; see `app/sensors/model.py` for the source ids and
`docs/PROTOCOL.md` for the frames. Airspeed is computed on the PC from the pitot ΔP and the
air density model in `app/sensors/airspeed.py`.

## Watt meter reading (app/vision)

`MeterReader` runs on its own thread at ~10 Hz, takes the newest camera frame
(`CameraManager.latest_frame_info`, no copy — frames are never modified after capture),
reads it with `lcd_reader.read_lcd` (perspective warp of the marked area → per-character
correlation with the HD44780 font) and pushes `wattmeter` samples into the `DataRouter`
like any other sensor. It never touches the capture thread or the video encoder. When the
screen's position is unknown, or it can't be read for a few seconds, the reader calls
`lcd_finder.auto_detect` (colour segmentation of the backlit screen → text rows → grid fit)
on its own thread; the GUI saves what it finds.
See [`WATT_METER_READING.md`](WATT_METER_READING.md).

## Adding a sensor (current sensor, voltage, RPM, temperature)

1. **Firmware.** Either extend `ThrustStand.ino` or use a second Arduino. Emit generic
   multi-channel frames with a checksum, e.g.
   `M,<seq>,<t_us>,voltage_v=16.42,current_a=31.5`. A Mauch Hall sensor is two analog
   outputs; read them with `analogRead()` at a fixed rate and convert with the Mauch scale
   factors in the firmware (or send raw values and convert in Python).
2. **Channel names.** Use the keys in `app/sensors/model.py` (`voltage_v`, `current_a`,
   `power_w`, `rpm`, `temp_motor_c`, `thrust2_lb`, …) or add new `ChannelInfo` entries.
3. **Same Arduino:** nothing else to do. Extra channels appear in the dashboard's
   *Additional channels* panel as soon as real frames arrive and are written as extra CSV
   columns. **Second Arduino:** create another `SerialManager(router, events, settings,
   source_id="power0")` in `MainWindow.__init__`, add a connect control, and its samples are
   logged to `power0_data.csv` in the same test folder on the same clock.
4. **Derived quantities.** Electrical power (V × I), thrust per watt (g/W) and efficiency
   comparisons are post-processing on the aligned CSV columns; because every source is
   aligned to the same host clock, merge them with `pandas.merge_asof` on `aligned_time_s`.

The watt meter is deliberately **not** read by OCR: it would add a failure mode that could
silently produce wrong numbers. The video is the record until a direct sensor is added.
