@echo off
REM Start the Propulsion Test Stand without a console window. Extra arguments are passed on
REM (e.g.  run_app.bat --simulate ).
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
  echo Run setup_windows.bat first.
  pause
  exit /b 1
)
start "" ".venv\Scripts\pythonw.exe" -m app %*
