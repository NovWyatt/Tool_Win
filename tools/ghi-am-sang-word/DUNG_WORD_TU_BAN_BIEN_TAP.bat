@echo off
chcp 65001 >nul
title Dung file Word tu ban bien tap
cd /d "%~dp0"
if "%~1"=="" (
  echo Keo tha file ban bien tap ^(.txt^) vao file nay de dung file Word hoan chinh.
  echo File Word ra nam canh file .txt, cung ten.
  echo Cach viet ban bien tap: xem HUONG_DAN_SU_DUNG.txt, muc BAN BIEN TAP.
  pause
  exit /b 2
)
if not exist ".venv\Scripts\python.exe" (
  echo Chua co moi truong Python ^(.venv^). Chay CAI_DAT.ps1 truoc.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" -u "%~dp0bien_tap_sang_word.py" "%~1" "%~dpn1.docx"
set "RC=%errorlevel%"
echo.
pause
exit /b %RC%
