# Troubleshooting

The **event log** at the bottom of the main window explains most problems in plain language.
A detailed log is kept at `%APPDATA%\TarletonSAEAero\PropulsionTestStand\logs\teststand.log`.
`run_app_console.bat` starts the program with a console window that also shows OpenCV and
driver messages.

> Safety: this software only measures and records. If anything misbehaves while a motor is
> running, stop the motor with the throttle / kill switch first, then deal with the software.

## Arduino / load cell

| Symptom | Cause and fix |
|---|---|
| No COM port in the list | Check the USB cable (some are charge-only). Press ↻. Look in Device Manager → *Ports (COM & LPT)*. Clones with a CH340 chip need the CH340 driver. |
| "COMx is in use by another program" | Close the Arduino IDE **Serial Monitor/Plotter**, Cura/Creality Print, or any other program using the port. The app keeps retrying and connects once the port is free. |
| "running the old HX711 demo sketch" | Upload `arduino/ThrustStand/ThrustStand.ino` (README §3). |
| "No response from the ThrustStand firmware" / "Unreadable data … older firmware" / "protocol v1" | The Arduino still has the old firmware, the upload failed, or the wrong port is selected. Upload `ThrustStand.ino` again, then open the Serial Monitor at **250000** baud: you should see `HELLO,…` and `D,…` lines. Close it again before connecting the app. |
| "Motor N HX711 is not producing readings" / its card shows **— — —** | That HX711's wiring or power: Motor 1 DOUT→D3, SCK→D2; Motor 2 DOUT→D5, SCK→D4; VCC and GND to the 5V/GND rail. Check for a loose dupont wire or a rail that isn't actually connected to the Uno. The other sensors keep working. |
| Motor 1 and Motor 2 readings are swapped | The DOUT/SCK pairs are swapped between the two HX711s. Swap D3/D2 with D5/D4 at the Uno, or simply label the motors to match. |
| Airspeed card: "no airspeed sensor detected" | Check SDA→A4, SCL→A5, 5V and G. The JST-GH lead's colours vary between suppliers — follow the labels printed on the sensor board. If it still isn't found, add 4.7 kΩ pull-ups from SDA and SCL to 5V. The app re-checks every 2 s, so it appears as soon as the wiring is right. |
| Airspeed reads a few m/s with no wind, or shows NOT ZEROED | Zero it: *Zero airspeed (no airflow)* in the Tare & calibration panel, with the motors off and the pitot tip loosely covered. Re-zero each test day (the offset drifts with temperature). |
| Airspeed stays at 0 while air is moving | Pitot and static tubes are swapped at the sensor, a tube is kinked, or the pitot isn't facing the flow. Negative pressure shows as 0 m/s, but `diff_pressure_pa` in the CSV will be negative. |
| Airspeed is very jumpy at low speed | Expected: the ±1 psi sensor resolves about 1 Pa, i.e. roughly 1.3 m/s at 1 m/s but 0.07 m/s at 15 m/s. Below 4–5 m/s treat readings as approximate. In prop wash the flow itself is turbulent — use the moving average to read the graph. |
| "HX711 DOUT stuck low" | The amplifier has no power, or DOUT is shorted to GND. |
| Rate shows ≈10 Hz but you want 80 | The HX711 RATE pin selects 10 SPS (low) or 80 SPS (high). Many green modules tie RATE to GND on the board; changing it needs a board modification or a module with a RATE jumper. 80 SPS is noisier but responds faster. The app always shows the rate the board actually delivers. |
| Thrust reads negative when the motor pushes | Mount direction. Either re-run the calibration wizard (it produces a negative factor automatically) or enter the existing factor with a minus sign and press Apply. |
| Readings drift with the motor off | Let the HX711 and load cell warm up 5–10 minutes, keep wires short and away from motor/ESC leads, then tare. |
| Very noisy readings with the motor running | Vibration is real signal: use the display-only moving average to read the graph (recorded data stay raw). Stiffen the stand, add damping, and twist the load-cell wires. |
| "sample(s) lost" warnings | Occasional gaps are logged and listed in the metadata. Frequent gaps: use a different USB port/cable, avoid unpowered hubs, close heavy programs. |
| Values jump after reconnecting | The Uno resets when the port opens; the firmware restores its saved zero from EEPROM so it does **not** re-tare. If you changed the load-cell mounting since the last tare, tare again (motor off). |
| ADC SATURATED shown under the reading | The load is beyond the amplifier's range (or a wire is broken). Check wiring; use a lower-gain setup or a different load cell for very high thrust. |

## Camera

| Symptom | Cause and fix |
|---|---|
| Camera list is empty / shows only "SIMULATED" | Plug the camera directly into the laptop (not a hub), press ↻. Check that Windows *Camera* app can see it. Settings → Privacy & security → **Camera** → allow desktop apps to access the camera. |
| "Could not open …" | Another program holds the camera (Windows Camera, Teams, a browser tab, Creality Print). Close it. Try the other **Backend** (DirectShow ↔ Media Foundation) in the Camera tab. |
| The Creality Nebula is not listed at all | The Nebula is sold as an accessory for Creality printers; it advertises 1920×1080 and a manual focus ring, but it is not documented as a Windows webcam. If Windows itself (Camera app / Device Manager → Cameras) does not see it, OpenCV cannot either — use another USB webcam; the app works with any UVC webcam. |
| Opens but "delivered no frames" / black preview | Lower the resolution, try pixel format **YUY2** or **default**, try the other backend, unplug and replug. |
| Low frame rate at 1080p | Choose pixel format **MJPG** (uncompressed YUY2 1080p is limited to ~5 fps over USB 2.0). Good lighting also helps: many webcams lower the frame rate automatically in dim light. Turn off *Auto exposure* and set a short exposure. |
| LCD digits unreadable | Fix focus (the Nebula has a manual focus ring; for others turn off Autofocus and set Focus), avoid glare by angling the camera, set a manual exposure, keep the frame rate ≥ 15 fps. |
| "This camera/driver does not support setting …" | Normal: not all webcams expose every control. Use **Driver settings dialog…** (DirectShow) to reach the camera's own property page. |
| "Requested 1920×1080; camera is delivering …" | The camera does not offer that mode with the chosen pixel format. Pick another resolution or MJPG. |
| Video won't play in Windows Media Player | Use VLC, or choose the H.264 (Media Foundation) codec in the Camera tab. Files named `camera.partial.mp4` were not finished (crash/power loss) — VLC can usually still play them. |
| "Video encoder can't keep up — frames dropped" | Lower resolution or frame rate, or close other programs. Dropped frames are counted in the metadata and visible as gaps in `capture_index`. |
| "Camera disconnected during recording" | The video was closed safely at the last good frame; thrust recording continued. Check the cable. |

## Watt meter reading (camera)

| Problem | What to do |
|---|---|
| Card says "meter screen not found" | Get the screen in view, in focus and without reflections; or click **Meter reading…** and click the four corners of the meter's screen. |
| It found the text inside the screen, but the close-up shows the grid off by a character | Drag a screen corner a little (it searches again), or switch to “the text's corners” and drag those, then **Fit again**. |
| "can't read the screen" / low match % | Remove reflections on the LCD (tilt the meter or camera), refocus, make the screen bigger in the picture, then mark again. |
| One value missing or wrong | Look at the line under the preview: `?` or wrong letters at one end mean glare there or a corner one character off. Drag the corners in **Meter reading…** and press **Fit again**. |
| Report / review has no Power or Current & voltage graphs | No watt meter readings were logged during that test. Fix the reading (screen position, glare, focus), then open the test in **Review tests → Re-read meter…** to read it from the video. |
| "⚠ V×A≠W" | One of the values is misread; those rows are flagged and excluded from the statistics. Fix glare/focus. |
| Camera or meter moved | Small moves are followed automatically; after a bigger move the screen is searched for again within ~10 s (the marked screen outline moves with it). |
| Meter rows are missing during fast throttle changes / a value looks like a ghost of two numbers | Raise Settings → Watt meter → *LCD settle time* (cold LCDs fade slowly). Afterwards, **Review → Re-read meter…** reads every frame of the video again. |
| "Meter lag removed: 0 ms (… not shifted)" | The lag is only measured when the throttle changed during the test (current and thrust must line up clearly). Hold steady points for a couple of seconds when comparing thrust and power. |
| Graphs of watts/amps/volts look like stairs | That's what the meter shows: it holds each value until its next update. |

More: [`WATT_METER_READING.md`](WATT_METER_READING.md).

## Jank mode (hall sensor + voltage divider)

| Problem | What to do |
|---|---|
| "firmware doesn't have the current/voltage inputs" | Upload `arduino/ThrustStand/ThrustStand.ino` (2.3) with the Arduino IDE. |
| Voltage goes **up** when current flows | ADC crosstalk from the current input or the Arduino's 5 V sagging. Upload firmware 2.3 and **Match** the voltage again; add 1–10 µF from A2 to GND. See JANK_MODE.md. |
| Lots of noise on current / power | Upload firmware 2.3 (reads the current 4× as often); **Jank setup… → Smoothing** (try 0.5 s); add 1 kΩ + 10 µF on A3 and 1–10 µF across the divider's bottom resistor — see JANK_MODE.md. |
| Power card: "waiting for readings from A3/A2" | Arduino connected and jank mode on? Check the event log for the Arduino's reply to `ELEC,1`. |
| A few amps with the motor off / negative current | **Jank setup… → Zero current** (motor off); flip the sign there if it reads negative under load. |
| Voltage reads high, at rest and under load | Not calibrated yet — the Arduino's 5 V on USB is usually 4.6–4.9 V, so the divider reading comes out 2–8 % high (the current is unaffected). **Jank setup…** → type the multimeter reading → **Match**; then **Review → Re-apply jank calibration** for tests already recorded. |
| "input at ADC limit" | A3: sensor unpowered/unplugged or over ±200 A. A2: battery above 32.8 V — disconnect, the divider ratio is too small. |

More: [`JANK_MODE.md`](JANK_MODE.md).

## Recording

| Symptom | Cause and fix |
|---|---|
| START TEST is greyed out | The Arduino must be connected and sending readings. |
| "Only … GB free on the save drive" | Free space or choose another folder (bottom bar → Change…). Thresholds are in Settings → Recording. |
| Test stopped with "Disk almost full" | The app stops recording before the disk fills so the files stay valid. |
| A test folder has `camera.partial.mp4` and status "recovered" | The program or PC stopped during that test. Thrust data up to the interruption are complete; the unfinished MP4 usually still plays in VLC. |
| Auto trigger never starts | Check the trigger is enabled and **Applied**, the thresholds are in lb, *Use \|thrust\|* is ticked if your cell reads negative, and the start threshold is above the idle noise. |
| Auto trigger starts/stops too often | Increase the gap between start and stop thresholds and the hold times. |

## Windows executable

| Symptom | Cause and fix |
|---|---|
| Antivirus quarantines the .exe | PyInstaller programs are sometimes flagged. The build disables UPX to reduce this; add an exclusion for the `dist\PropulsionTestStand` folder if needed. |
| Program does not start, no window | Run `dist\PropulsionTestStand\PropulsionTestStand.exe` from a Command Prompt, and read `%APPDATA%\TarletonSAEAero\PropulsionTestStand\logs\teststand.log`. Copy the **whole** `dist\PropulsionTestStand` folder, not just the .exe. |
| Build fails at the tests step | Run `.venv\Scripts\python -m pytest -q` to see which test fails. Firmware tests are skipped automatically when no C++ compiler is installed. |

## Resetting the application
Close the program and delete `%APPDATA%\TarletonSAEAero\PropulsionTestStand\settings.json`
(saved configurations are in `profiles.json`, calibration history in `calibrations.json`).
Test results are never stored there.
