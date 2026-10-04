@echo off
chcp 65001 >nul
title Chuyen ban ve DWG sang PDF
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" goto :thieu
if not exist "bin\libredwg\dwg2dxf.exe" goto :thieu
".venv\Scripts\python.exe" -c "import ezdxf, pymupdf" >nul 2>&1
if errorlevel 1 goto :thieu

".venv\Scripts\python.exe" -u "%~dp0chuyen_dwg_sang_pdf.py" %*
echo.
pause
exit /b %errorlevel%

:thieu
echo Chua cai moi truong cho cong cu nay (Python .venv, ezdxf, PyMuPDF, LibreDWG).
echo Can mang Internet, tai khoang 100 MB, chi lam mot lan.
choice /C YN /M "Cai ngay bay gio"
if errorlevel 2 exit /b 2
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CAI_DAT.ps1"
if errorlevel 1 (
    echo Cai dat chua xong. Xem loi phia tren.
    pause
    exit /b 2
)
echo.
if "%~1"=="" (
    echo Da cai xong. Keo tha thu muc ban ve .dwg vao CHUYEN_DWG_SANG_PDF.bat de chuyen.
    pause
    exit /b 0
)
".venv\Scripts\python.exe" -u "%~dp0chuyen_dwg_sang_pdf.py" %*
echo.
pause
