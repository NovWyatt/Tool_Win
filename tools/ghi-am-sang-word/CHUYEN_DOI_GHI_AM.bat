@echo off
chcp 65001 >nul
title Chuyen ghi am thanh van ban
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Chua co moi truong Python ^(.venv^). Nho Claude cai dat lai.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" -u "%~dp0chuyen_doi.py" %*
set "RC=%errorlevel%"
if not "%RC%"=="0" if not "%RC%"=="1" if not "%RC%"=="2" (
  echo.
  echo Card do hoa bi loi. Chay lai bang CPU ^(se cham hon nhieu^)...
  ".venv\Scripts\python.exe" -u "%~dp0chuyen_doi.py" --cpu %*
)
echo.
pause
