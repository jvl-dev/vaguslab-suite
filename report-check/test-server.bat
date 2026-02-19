@echo off
REM =============================================
REM Report Check — Python Backend Diagnostic
REM Checks embedded Python and all required imports
REM =============================================

setlocal

echo =============================================
echo  Report Check - Python Backend Diagnostic
echo =============================================
echo.

REM --- Locate embedded Python ---
set "PYTHON="

REM Check relative to this script (../python-embedded/)
set "SCRIPT_DIR=%~dp0"
set "CANDIDATE=%SCRIPT_DIR%..\python-embedded\python.exe"
if exist "%CANDIDATE%" (
    set "PYTHON=%CANDIDATE%"
    goto :found_python
)

REM Check AppData
set "CANDIDATE=%LOCALAPPDATA%\vaguslab\python-embedded\python.exe"
if exist "%CANDIDATE%" (
    set "PYTHON=%CANDIDATE%"
    goto :found_python
)

REM Check local python subfolder
set "CANDIDATE=%SCRIPT_DIR%python\python.exe"
if exist "%CANDIDATE%" (
    set "PYTHON=%CANDIDATE%"
    goto :found_python
)

echo [FAIL] Embedded Python not found.
echo        Checked:
echo          %SCRIPT_DIR%..\python-embedded\python.exe
echo          %LOCALAPPDATA%\vaguslab\python-embedded\python.exe
echo          %SCRIPT_DIR%python\python.exe
echo.
goto :end

:found_python
echo [OK]   Python found: %PYTHON%

REM --- Python version ---
"%PYTHON%" --version 2>&1
echo.

REM --- Check standard library modules ---
echo Checking standard library...

"%PYTHON%" -c "import json; print('[OK]   json')"           2>&1 || echo [FAIL] json
"%PYTHON%" -c "import re; print('[OK]   re')"               2>&1 || echo [FAIL] re
"%PYTHON%" -c "import logging; print('[OK]   logging')"     2>&1 || echo [FAIL] logging
"%PYTHON%" -c "from logging.handlers import RotatingFileHandler; print('[OK]   logging.handlers')" 2>&1 || echo [FAIL] logging.handlers
"%PYTHON%" -c "from pathlib import Path; print('[OK]   pathlib')" 2>&1 || echo [FAIL] pathlib
"%PYTHON%" -c "from datetime import datetime; print('[OK]   datetime')" 2>&1 || echo [FAIL] datetime
"%PYTHON%" -c "import traceback; print('[OK]   traceback')" 2>&1 || echo [FAIL] traceback
echo.

REM --- Check third-party packages ---
echo Checking third-party packages...

"%PYTHON%" -c "import anthropic; print('[OK]   anthropic ' + anthropic.__version__)" 2>&1 || echo [FAIL] anthropic  — install with: pip install anthropic
"%PYTHON%" -c "from google import genai; print('[OK]   google-genai ' + genai.__version__)" 2>&1 || echo [FAIL] google-genai  — install with: pip install google-genai
"%PYTHON%" -c "import openai; print('[OK]   openai ' + openai.__version__)" 2>&1 || echo [FAIL] openai  — install with: pip install openai
"%PYTHON%" -c "import win32com.client; print('[OK]   win32com (pywin32)')" 2>&1 || echo [FAIL] win32com (pywin32)  — install with: pip install pywin32
echo.

REM --- Check project modules ---
echo Checking project modules...

"%PYTHON%" -c "import sys, os; sys.path.insert(0, os.path.dirname(r'%SCRIPT_DIR%backend.py')); import logger; print('[OK]   logger')" 2>&1 || echo [FAIL] logger.py
"%PYTHON%" -c "import sys, os; sys.path.insert(0, r'%SCRIPT_DIR%.'); import utils; print('[OK]   utils')" 2>&1 || echo [FAIL] utils.py
"%PYTHON%" -c "import sys, os; sys.path.insert(0, r'%SCRIPT_DIR%.'); import config_reader; print('[OK]   config_reader')" 2>&1 || echo [FAIL] config_reader.py
"%PYTHON%" -c "import sys, os; sys.path.insert(0, r'%SCRIPT_DIR%.'); import api_handler; print('[OK]   api_handler')" 2>&1 || echo [FAIL] api_handler.py
"%PYTHON%" -c "import sys, os; sys.path.insert(0, r'%SCRIPT_DIR%.'); import html_generator; print('[OK]   html_generator')" 2>&1 || echo [FAIL] html_generator.py
"%PYTHON%" -c "import sys, os; sys.path.insert(0, r'%SCRIPT_DIR%.'); import targeted_review; print('[OK]   targeted_review')" 2>&1 || echo [FAIL] targeted_review.py
"%PYTHON%" -c "import sys, os; sys.path.insert(0, r'%SCRIPT_DIR%.'); import backend; print('[OK]   backend')" 2>&1 || echo [FAIL] backend.py
echo.

REM --- Check template file ---
echo Checking templates...
if exist "%SCRIPT_DIR%templates\report_template.html" (
    echo [OK]   templates\report_template.html
) else (
    echo [FAIL] templates\report_template.html not found
)

REM --- Check system prompts (shipped in prompts\, user override in pref folder) ---
if exist "%SCRIPT_DIR%prompts\system_prompt_comprehensive.txt" (
    echo [OK]   prompts\system_prompt_comprehensive.txt
) else (
    echo [FAIL] prompts\system_prompt_comprehensive.txt not found
)
if exist "%SCRIPT_DIR%prompts\system_prompt_proofreading.txt" (
    echo [OK]   prompts\system_prompt_proofreading.txt
) else (
    echo [FAIL] prompts\system_prompt_proofreading.txt not found
)
if exist "%SCRIPT_DIR%prompts\system_prompt_targeted_review.txt" (
    echo [OK]   prompts\system_prompt_targeted_review.txt
) else (
    echo [FAIL] prompts\system_prompt_targeted_review.txt not found
)
echo.

echo =============================================
echo  Diagnostic complete
echo =============================================

:end
echo.
pause
endlocal
