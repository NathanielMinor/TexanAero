@echo off
REM Start with a console window so errors and OpenCV/serial messages are visible (troubleshooting).
cd /d "%~dp0"
".venv\Scripts\python.exe" -m app %*
pause
