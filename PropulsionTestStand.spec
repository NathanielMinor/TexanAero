# -*- mode: python ; coding: utf-8 -*-
# PyInstaller build for the Propulsion Test Stand (one-folder build: fast start-up, no temp extraction).
#   pyinstaller --noconfirm --clean PropulsionTestStand.spec
# Output: dist\PropulsionTestStand\PropulsionTestStand.exe
import sys
from PyInstaller.utils.hooks import collect_submodules

block_cipher = None

SKIP = ("examples", "opengl", "jupyter", "canvas", "console", "flowchart", "multiprocess", "parametertree.interactive")
hidden = collect_submodules("pyqtgraph", filter=lambda name: not any(s in name for s in SKIP))
hidden += ["serial.tools.list_ports"]
if sys.platform == "win32":
    hidden += collect_submodules("pygrabber") + ["comtypes", "comtypes.client"]

a = Analysis(
    ["PropulsionTestStand.py"],
    pathex=["."],
    binaries=[],
    datas=[("assets", "assets"), ("arduino", "arduino"), ("docs", "docs"), ("README.md", ".")],
    hiddenimports=hidden,
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "PyQt5", "PyQt6", "IPython", "pytest", "scipy", "PySide6.QtWebEngineCore",
              "PySide6.Qt3DCore", "PySide6.QtQuick3D"],
    noarchive=False,
    cipher=block_cipher,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="PropulsionTestStand",
    debug=False,
    strip=False,
    upx=False,                 # UPX-packed Qt DLLs often trigger antivirus false positives
    console=False,             # windowed app; logs go to %APPDATA%\TarletonSAEAero\PropulsionTestStand\logs
    icon="assets/icon.ico",
)
coll = COLLECT(exe, a.binaries, a.zipfiles, a.datas, strip=False, upx=False, name="PropulsionTestStand")
