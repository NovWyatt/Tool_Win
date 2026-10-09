@echo off
chcp 65001 >nul
title Chuyen ghi am thanh van ban
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" goto :thieu
".venv\Scripts\python.exe" -c "import faster_whisper, docx" >nul 2>&1
if errorlevel 1 goto :thieu
if not exist "models\faster-whisper-large-v3\model.bin" goto :thieu

:chay
".venv\Scripts\python.exe" -u "%~dp0chuyen_doi.py" %*
set "RC=%errorlevel%"
if not "%RC%"=="0" if not "%RC%"=="1" if not "%RC%"=="2" (
  echo.
  echo Card do hoa bi loi. Chay lai bang CPU ^(se cham hon nhieu^), lam tiep tu khuc chua xong...
  set "GHI_AM_CHAY_TIEP=1"
  ".venv\Scripts\python.exe" -u "%~dp0chuyen_doi.py" --cpu %*
)
echo.
pause
exit /b

:thieu
echo Chua cai moi truong cho cong cu nay: Python .venv, faster-whisper, mo hinh nhan dang khoang 3 GB.
echo Can mang Internet, chi lam mot lan.
choice /C YN /M "Cai ngay bay gio"
if errorlevel 2 exit /b 2
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CAI_DAT.ps1"
if errorlevel 1 (
  echo Cai dat chua xong. Xem loi phia tren.
  pause
  exit /b 2
)
echo.
goto :chay
