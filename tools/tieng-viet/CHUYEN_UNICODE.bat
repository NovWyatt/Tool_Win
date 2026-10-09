@echo off
chcp 65001 >nul
title Chuyen tai lieu font VNI, TCVN3 sang Unicode
rem Keo tha file .docx, .xlsx hoac thu muc vao file nay. Tao ban sao <ten>_Unicode canh file goc; file goc giu nguyen.
rem Chay thang: CHUYEN_UNICODE.bat <file hoac thu muc> [--thu-muc <thu muc>] [--de-quy] [--chi-xem] [--ra <thu muc>]
rem Can Python 3.9 tro len (python trong PATH, khong co thi py -3). TV_KHONG_DUNG=1: khong pause khi xong.
set "PYEXE="
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>&1 && set "PYEXE=python"
if not defined PYEXE (
  py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>&1 && set "PYEXE=py -3"
)
if not defined PYEXE goto :thieu
set "PYTHONDONTWRITEBYTECODE=1"
%PYEXE% -X utf8 "%~dp0chuyen_unicode.py" %*
set "RC=%errorlevel%"
if not defined TV_KHONG_DUNG (
  echo.
  pause
)
exit /b %RC%

:thieu
echo Can Python 3.9 tro len de chuyen tai lieu, may chua co.
echo Cai bang nut Cai trong Tram Tool, hoac go lenh:
echo   winget install -e --id Python.Python.3.12 --scope user
if not defined TV_KHONG_DUNG pause
exit /b 2
