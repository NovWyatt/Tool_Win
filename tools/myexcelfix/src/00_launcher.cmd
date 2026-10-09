<# :
@echo off
rem ==========================================================================
rem  MyExcel VietQR - script kiem tra loi theo profile Windows (chi DOC, khong sua)
rem  Cach dung: copy file nay sang may bi loi, DOUBLE-CLICK trong profile bi loi.
rem  KHONG "Run as administrator" bang tai khoan khac (se doc sai HKCU).
rem  Ma thoat: 0 kiem tra xong, 1 khong ghi duoc bao cao, 2 chay sai tai khoan.
rem  Phien ban: __MYX_VERSION__
rem ==========================================================================
chcp 65001 >nul
title MyExcel VietQR - Kiem tra loi (__MYX_VERSION__)
set "MYX_SELF=%~f0"
set "MYX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "MYX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%MYX_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MYX_SELF,[Text.Encoding]::UTF8); iex $s"
set "MYX_RC=%ERRORLEVEL%"
echo.
if "%MYX_RC%"=="0" echo Da xong. Bao cao da duoc mo bang Notepad va luu trong C:\Users\Public\Documents\MyExcelCheck
if not defined MYX_NOPAUSE pause
exit /b %MYX_RC%
#>
