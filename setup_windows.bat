@echo off
REM ==========================================================================
REM  Tarleton SAE Aero Design - Propulsion Test Stand : one-time setup
REM  Creates .venv, installs dependencies and puts a shortcut on the desktop.
REM ==========================================================================
setlocal
cd /d "%~dp0"
echo.
echo === Propulsion Test Stand setup ===
echo.

where py >nul 2>nul
if errorlevel 1 (
  echo The Python launcher "py" was not found.
  echo Install Python 3.12 from https://www.python.org/downloads/windows/ and run this again.
  pause
  exit /b 1
)

set "PY=py -3.12"
%PY% -c "import sys" >nul 2>nul
if errorlevel 1 set "PY=py -3"
%PY% -c "import sys; assert sys.version_info >= (3, 10), sys.version" >nul 2>nul
if errorlevel 1 (
  echo Python 3.10 or newer is required. Python 3.12 is recommended.
  pause
  exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
  echo Creating virtual environment...
  %PY% -m venv .venv
  if errorlevel 1 goto :fail
)

echo Installing packages (first run downloads ~250 MB)...
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 goto :fail
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto :fail
".venv\Scripts\python.exe" -c "import PySide6, pyqtgraph, cv2, serial, numpy, pandas; print('All packages import correctly.')"
if errorlevel 1 goto :fail

echo Creating desktop shortcuts...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1" ^
  -Target "%~dp0.venv\Scripts\pythonw.exe" -Arguments "-m app" -WorkDir "%~dp0" ^
  -Name "Propulsion Test Stand" -Icon "%~dp0assets\icon.ico"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1" ^
  -Target "%~dp0.venv\Scripts\pythonw.exe" -Arguments "-m app --simulate" -WorkDir "%~dp0" ^
  -Name "Propulsion Test Stand (SIMULATION)" -Icon "%~dp0assets\icon.ico"

echo.
echo Setup complete. Start the program from the desktop shortcut or run_app.bat.
echo Use the SIMULATION shortcut to try the software without hardware.
pause
exit /b 0

:fail
echo.
echo Setup FAILED - read the messages above. Common fixes: check the internet connection,
echo or delete the .venv folder and run setup_windows.bat again.
pause
exit /b 1
