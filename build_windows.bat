@echo off
REM ==========================================================================
REM  Build a standalone Windows program: dist\PropulsionTestStand\PropulsionTestStand.exe
REM  Copy the whole dist\PropulsionTestStand folder to any Windows 10/11 PC - no Python needed.
REM ==========================================================================
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Run setup_windows.bat first.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" -m pip install -r requirements-dev.txt
if errorlevel 1 goto :fail

echo Running the automated tests...
".venv\Scripts\python.exe" -m pytest -q
if errorlevel 1 (
  echo Tests failed - build stopped. Fix the failures or run PyInstaller manually.
  goto :fail
)

echo Building with PyInstaller...
".venv\Scripts\python.exe" -m PyInstaller --noconfirm --clean PropulsionTestStand.spec
if errorlevel 1 goto :fail

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1" ^
  -Target "%~dp0dist\PropulsionTestStand\PropulsionTestStand.exe" -WorkDir "%~dp0dist\PropulsionTestStand" ^
  -Name "Propulsion Test Stand" -Icon "%~dp0assets\icon.ico"
echo.
echo Build complete: dist\PropulsionTestStand\PropulsionTestStand.exe
echo The desktop shortcut now points to the built program.
pause
exit /b 0

:fail
echo Build FAILED.
pause
exit /b 1
