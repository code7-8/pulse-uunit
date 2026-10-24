@echo off
set PYTHONUTF8=1
"%~dp0backend\.venv\Scripts\python.exe" -X utf8 "%~dp0scripts\public_server.py" stop
pause
