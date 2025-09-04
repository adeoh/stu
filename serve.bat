@echo off
setlocal

rem Simple local static file server for this folder
rem Usage: serve.bat [port]

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8000"

rem Change to the directory of this script
cd /d "%~dp0"

echo.
echo Serving "%CD%" at http://localhost:%PORT%  (Ctrl+C to stop)
echo.

rem Try Python via Windows launcher first (handles Py3 and Py2)
where py >nul 2>nul
if %ERRORLEVEL%==0 (
  py -3 -V >nul 2>nul
  if %ERRORLEVEL%==0 (
    py -3 -m http.server %PORT%
    goto :eof
  )
  py -2 -V >nul 2>nul
  if %ERRORLEVEL%==0 (
    py -2 -m SimpleHTTPServer %PORT%
    goto :eof
  )
  rem Unknown default; try Py3 http.server then Py2 SimpleHTTPServer
  py -m http.server %PORT% 2>nul
  if %ERRORLEVEL%==0 goto :eof
  py -m SimpleHTTPServer %PORT%
  goto :eof
)

rem Fallback to python on PATH
where python >nul 2>nul
if %ERRORLEVEL%==0 (
  python -c "import http.server" 1>nul 2>nul
  if %ERRORLEVEL%==0 (
    python -m http.server %PORT%
  ) else (
    python -m SimpleHTTPServer %PORT%
  )
  goto :eof
)

echo.
echo ERROR: Python not found on PATH.
echo - Install Python: https://www.python.org/downloads/
echo - Or use Node:    npx serve -l %PORT%
exit /b 1

