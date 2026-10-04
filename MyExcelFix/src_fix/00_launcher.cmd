<# :
@echo off
rem ==========================================================================
rem  MyExcel VietQR - SUA LOI cho profile Windows bi loi (dung cho nhieu may)
rem  Loi: bat/tao VietQR khong duoc, tao profile Windows moi thi lai duoc.
rem  Double-click trong profile BI LOI. Luu va dong Excel truoc.
rem  Script tu tim bo MyExcel chuan, sao luu truoc khi sua, tao file hoan tac.
rem  Ban sao cua file nay ten HoanTac_FixMyExcel.bat trong thu muc sao luu
rem  se tu chay che do HOAN TAC.
rem ==========================================================================
chcp 65001 >nul
title MyExcel VietQR - Sua loi
set "MYX_SELF=%~f0"
set "MYX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "MYX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%MYX_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MYX_SELF,[Text.Encoding]::UTF8); iex $s"
echo.
if not defined MYX_NOPAUSE pause
exit /b
#>
