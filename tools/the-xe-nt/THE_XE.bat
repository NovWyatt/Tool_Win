@echo off
rem File the xe .nt cho phan mem giu xe - bam dup de mo menu, hoac keo tha file .nt / danh sach vao day.
rem Chay thang mot che do: THE_XE.bat -Mode xem -File "D:\the\3257-3426.nt" (xem TheXe.ps1).
rem Jet OLEDB 4.0 chi co ban 32 bit nen dung PowerShell 32 bit (SysWOW64) khi co.
set "PS32=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS32%" set "PS32=powershell.exe"
"%PS32%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0TheXe.ps1" %*
exit /b %errorlevel%
