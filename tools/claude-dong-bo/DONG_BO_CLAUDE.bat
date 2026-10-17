@echo off
rem Dong bo phien Claude: dua cac phien tab Code cua tai khoan Claude khac sang tai khoan dang dang nhap.
rem Bam dup de mo menu. Chay thang: DONG_BO_CLAUDE.bat -Mode kiem-tra   (xem DongBoClaude.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DongBoClaude.ps1" %*
exit /b %errorlevel%
