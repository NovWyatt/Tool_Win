@echo off
chcp 65001 >nul
title Windows System Repair Tool
color 0A

:menu
cls
echo =====================================
echo    WINDOWS SYSTEM REPAIR TOOL
echo         Created by: Wyatt
echo =====================================
echo.
echo 1. SFC Scan - Kiểm tra và sửa file hệ thống bị lỗi
echo 2. DISM Restore Health - Sửa chữa Windows Image
echo 3. DISM Scan Health - Kiểm tra tình trạng Windows Image
echo 4. Reset Network - Làm mới cấu hình mạng
echo 5. Check Disk - Kiểm tra và sửa lỗi ổ cứng
echo 6. Memory Test - Kiểm tra RAM (yêu cầu khởi động lại)
echo 7. Reset Windows Update - Khôi phục Windows Update
echo 8. Clean Temp Files - Dọn dẹp file tạm
echo 9. Registry Cleanup - Dọn dẹp Registry
echo 10. Run All Critical Repairs - Chạy tất cả lệnh quan trọng
echo 0. Thoát
echo.
set /p choice="Chọn tùy chọn (0-10): "

if "%choice%"=="1" goto sfc_scan
if "%choice%"=="2" goto dism_restore
if "%choice%"=="3" goto dism_scan
if "%choice%"=="4" goto network_reset
if "%choice%"=="5" goto check_disk
if "%choice%"=="6" goto memory_test
if "%choice%"=="7" goto windows_update_reset
if "%choice%"=="8" goto clean_temp
if "%choice%"=="9" goto registry_cleanup
if "%choice%"=="10" goto run_all
if "%choice%"=="0" goto exit
goto menu

:sfc_scan
cls
echo =====================================
echo     SFC SCAN - SYSTEM FILE CHECKER
echo =====================================
echo.
echo Đang kiểm tra và sửa chữa các file hệ thống bị lỗi...
echo Quá trình này có thể mất 10-15 phút.
echo.
sfc /scannow
echo.
echo SFC Scan hoàn tất!
pause
goto menu

:dism_restore
cls
echo =====================================
echo        DISM RESTORE HEALTH
echo =====================================
echo.
echo Đang sửa chữa Windows Image bằng Windows Update...
echo Quá trình này có thể mất 15-30 phút.
echo.
dism /online /cleanup-image /restorehealth
echo.
echo DISM Restore Health hoàn tất!
pause
goto menu

:dism_scan
cls
echo =====================================
echo         DISM SCAN HEALTH
echo =====================================
echo.
echo Đang kiểm tra tình trạng Windows Image...
echo.
dism /online /cleanup-image /scanhealth
echo.
echo DISM Scan Health hoàn tất!
pause
goto menu

:network_reset
cls
echo =====================================
echo          NETWORK RESET
echo =====================================
echo.
echo Đang reset cấu hình mạng...
echo.
ipconfig /flushdns
netsh winsock reset
netsh int ip reset
ipconfig /release
ipconfig /renew
netsh advfirewall reset
echo.
echo Network reset hoàn tất! Khuyến nghị khởi động lại máy.
pause
goto menu

:check_disk
cls
echo =====================================
echo           CHECK DISK
echo =====================================
echo.
echo Đang kiểm tra và sửa lỗi ổ cứng C:...
echo.
chkdsk C: /f /r
echo.
echo Check Disk hoàn tất!
pause
goto menu

:memory_test
cls
echo =====================================
echo          MEMORY TEST
echo =====================================
echo.
echo Lên lịch kiểm tra RAM khi khởi động lại...
echo Máy sẽ tự động kiểm tra RAM ở lần khởi động tiếp theo.
echo.
mdsched.exe
echo.
echo Memory test đã được lên lịch!
pause
goto menu

:windows_update_reset
cls
echo =====================================
echo      WINDOWS UPDATE RESET
echo =====================================
echo.
echo Đang reset Windows Update...
echo.
net stop wuauserv
net stop cryptsvc
net stop bits
net stop msiserver
ren C:\Windows\SoftwareDistribution SoftwareDistribution.old
ren C:\Windows\System32\catroot2 catroot2.old
net start wuauserv
net start cryptsvc
net start bits
net start msiserver
echo.
echo Windows Update reset hoàn tất!
pause
goto menu

:clean_temp
cls
echo =====================================
echo         CLEAN TEMP FILES
echo =====================================
echo.
echo Đang dọn dẹp file tạm...
echo.
del /q /f /s %temp%\*
del /q /f /s C:\Windows\Temp\*
cleanmgr /sagerun:1
echo.
echo Dọn dẹp file tạm hoàn tất!
pause
goto menu

:registry_cleanup
cls
echo =====================================
echo        REGISTRY CLEANUP
echo =====================================
echo.
echo Đang dọn dẹp Registry...
echo.
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders" /f 2>nul
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" /f 2>nul
echo.
echo Registry cleanup hoàn tất!
pause
goto menu

:run_all
cls
echo =====================================
echo        RUN ALL CRITICAL REPAIRS
echo =====================================
echo.
echo Đang chạy tất cả lệnh sửa chữa quan trọng...
echo Quá trình này có thể mất 30-60 phút.
echo.
echo [1/4] Đang chạy SFC Scan...
sfc /scannow
echo.
echo [2/4] Đang chạy DISM Restore Health...
dism /online /cleanup-image /restorehealth
echo.
echo [3/4] Đang reset Network...
ipconfig /flushdns
netsh winsock reset
netsh int ip reset
echo.
echo [4/4] Đang dọn dẹp file tạm...
del /q /f /s %temp%\* 2>nul
del /q /f /s C:\Windows\Temp\* 2>nul
echo.
echo =====================================
echo   TẤT CẢ LỆNH SỬA CHỮA HOÀN TẤT!
echo   Khuyến nghị khởi động lại máy tính.
echo =====================================
pause
goto menu

:exit
cls
echo Cảm ơn bạn đã sử dụng Windows System Repair Tool!
echo Nhớ khởi động lại máy tính để hoàn tất các thay đổi.
pause
exit