@echo off
rem Bo ung dung van phong: cai Zalo, bo go tieng Viet, 7-Zip, doc PDF, UltraViewer, Chrome... tu nguon winget.
rem Bam dup de mo menu. Chay thang: BO_UNG_DUNG.bat -Mode kiem-tra   (xem BoUngDung.ps1, danh sach trong DanhSach.json)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BoUngDung.ps1" %*
exit /b %errorlevel%
