"""Launcher used by PyInstaller and for double-click starts (equivalent to ``python -m app``)."""
from app.main import main

if __name__ == "__main__":
    raise SystemExit(main())
