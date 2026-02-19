@echo off
setlocal
cd /d "%~dp0"

:: Resolve Python path (same order as GetPythonPath in bruce-helper.ahk)
set "PYTHON="
if exist "..\python-embedded\python.exe" (
    set "PYTHON=..\python-embedded\python.exe"
) else if exist "%LOCALAPPDATA%\vaguslab\python-embedded\python.exe" (
    set "PYTHON=%LOCALAPPDATA%\vaguslab\python-embedded\python.exe"
) else if exist "python\python.exe" (
    set "PYTHON=python\python.exe"
)

if "%1"=="listen" goto listen

echo ============================================================
echo  Bruce Helper - Server Diagnostics
echo ============================================================
echo.

echo [1] Python executable
if "%PYTHON%"=="" (
    echo ERROR: Python not found. Checked:
    echo   ..\python-embedded\python.exe
    echo   %LOCALAPPDATA%\vaguslab\python-embedded\python.exe
    echo   python\python.exe
    goto end
)
echo   %PYTHON%
"%PYTHON%" --version
if errorlevel 1 (
    echo ERROR: Python found but failed to run
    goto end
)
echo.

echo [2] Standard library imports
"%PYTHON%" -c "import asyncio, json, base64, logging, re, os, secrets; print('  OK')"
if errorlevel 1 (echo   FAILED & goto end)

echo [3] cryptography
"%PYTHON%" -c "from cryptography.hazmat.primitives.ciphers import Cipher; print('  OK')"
if errorlevel 1 (echo   FAILED & goto end)

echo [4] websockets
"%PYTHON%" -c "import websockets; print('  OK - version', websockets.__version__)"
if errorlevel 1 (echo   FAILED & goto end)

echo [5] watchdog
"%PYTHON%" -c "from watchdog.observers import Observer; print('  OK')"
if errorlevel 1 (echo   FAILED & goto end)

echo [6] Full server.py import (no start)
"%PYTHON%" -c "import sys, os; sys.path.insert(0, os.getcwd()); import server; print('  OK')"
if errorlevel 1 (echo   FAILED & goto end)

echo [7] State file resolution
"%PYTHON%" -c "import sys, os; sys.path.insert(0, os.getcwd()); import server; print('  STATE_FILE:', server.STATE_FILE)"
echo.

echo ============================================================
echo  All checks passed
echo ============================================================
echo.

:: Check if server is already running on port 8765
"%PYTHON%" -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('localhost',8765)); s.close(); exit(0)" 2>nul
if not errorlevel 1 (
    echo  Server already running on port 8765 — switching to listener mode.
    echo  Press Ctrl+C to disconnect.
    echo.
    "%PYTHON%" -u "%~dp0_ws_listener.py"
    goto end
)

echo  Starting server (Ctrl+C to stop)
echo.

"%PYTHON%" server.py
goto end

:: ============================================================
:: Listen mode: connect to a running server and print broadcasts
:: ============================================================
:listen
echo ============================================================
echo  Bruce Helper - WebSocket Listener
echo ============================================================
echo.
echo  Connecting to ws://localhost:8765 ...
echo  Press Ctrl+C to disconnect.
echo.

if "%PYTHON%"=="" (
    echo ERROR: Python not found.
    goto end
)

"%PYTHON%" -u "%~dp0_ws_listener.py"

:end
echo.
echo Exit code: %errorlevel%
echo.
echo Press any key to close...
pause >nul
endlocal
