@echo off
chcp 65001 >nul
title Windows Clock ^& Performance Optimizer
color 0B

:menu
cls
echo =====================================
echo  WINDOWS CLOCK ^& PERFORMANCE OPTIMIZER
echo         Created by: Wyatt
echo =====================================
echo.
echo 1. Tắt UsePlatformClock - Giảm stutter trong game
echo 2. Tắt Dynamic Tick - Tăng độ mượt hệ thống
echo 3. Tắt cả hai (Recommended)
echo 4. Bật lại UsePlatformClock
echo 5. Bật lại Dynamic Tick
echo 6. Bật lại cả hai
echo 7. Kiểm tra trạng thái hiện tại
echo 0. Thoát
echo.
echo INFO: Những thay đổi này cần KHỞI ĐỘNG LẠI để có hiệu lực!
echo.
set /p choice="Chọn tùy chọn (0-7): "

if "%choice%"=="1" goto disable_platform_clock
if "%choice%"=="2" goto disable_dynamic_tick
if "%choice%"=="3" goto disable_both
if "%choice%"=="4" goto enable_platform_clock
if "%choice%"=="5" goto enable_dynamic_tick
if "%choice%"=="6" goto enable_both
if "%choice%"=="7" goto check_status
if "%choice%"=="0" goto exit
goto menu

:disable_platform_clock
cls
echo =====================================
echo        TẮT USEPLATFORMCLOCK
echo =====================================
echo.
echo Chức năng: Sử dụng đồng hồ của platform thay vì TSC
echo Tác dụng: Giảm stutter và lag spike trong game
echo Phù hợp: Máy gaming, chơi game có FPS cao
echo.

reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock 2>nul | find "0x0" >nul
if %errorlevel%==0 (
    echo ✓ UsePlatformClock đã được tắt rồi, không cần thực hiện thêm!
) else (
    echo Đang tắt UsePlatformClock...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock /t REG_DWORD /d 0 /f >nul
    echo ✓ Đã tắt thành công UsePlatformClock!
    echo ⚠ Cần khởi động lại để có hiệu lực!
)
echo.
pause
goto menu

:disable_dynamic_tick
cls
echo =====================================
echo         TẮT DYNAMIC TICK
echo =====================================
echo.
echo Chức năng: Điều chỉnh tần số timer linh hoạt
echo Tác dụng: Tăng độ mượt, giảm input lag
echo Phù hợp: Máy gaming, work station
echo.

reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick 2>nul | find "0x1" >nul
if %errorlevel%==0 (
    echo ✓ Dynamic Tick đã được tắt rồi, không cần thực hiện thêm!
) else (
    echo Đang tắt Dynamic Tick...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick /t REG_DWORD /d 1 /f >nul
    echo ✓ Đã tắt thành công Dynamic Tick!
    echo ⚠ Cần khởi động lại để có hiệu lực!
)
echo.
pause
goto menu

:disable_both
cls
echo =====================================
echo      TẮT CẢ HAI (RECOMMENDED)
echo =====================================
echo.
echo Đang áp dụng cả hai tối ưu hóa cho gaming...
echo.

set need_reboot=0

echo [1/2] Kiểm tra UsePlatformClock...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock 2>nul | find "0x0" >nul
if %errorlevel%==0 (
    echo ✓ UsePlatformClock đã tắt rồi
) else (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock /t REG_DWORD /d 0 /f >nul
    echo ✓ Đã tắt UsePlatformClock
    set need_reboot=1
)

echo [2/2] Kiểm tra Dynamic Tick...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick 2>nul | find "0x1" >nul
if %errorlevel%==0 (
    echo ✓ Dynamic Tick đã tắt rồi
) else (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick /t REG_DWORD /d 1 /f >nul
    echo ✓ Đã tắt Dynamic Tick
    set need_reboot=1
)

echo.
if %need_reboot%==1 (
    echo =====================================
    echo   HOÀN TẤT! CẦN KHỞI ĐỘNG LẠI MÁY!
    echo =====================================
) else (
    echo =====================================
    echo  TẤT CẢ ĐÃ ĐƯỢC TỐI ƯU TỪ TRƯỚC!
    echo =====================================
)
pause
goto menu

:enable_platform_clock
cls
echo =====================================
echo        BẬT LẠI USEPLATFORMCLOCK
echo =====================================
echo.

reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock 2>nul | find "0x1" >nul
if %errorlevel%==0 (
    echo ✓ UsePlatformClock đã được bật rồi!
) else (
    echo Đang bật lại UsePlatformClock...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock /t REG_DWORD /d 1 /f >nul
    echo ✓ Đã bật lại thành công UsePlatformClock!
    echo ⚠ Cần khởi động lại để có hiệu lực!
)
echo.
pause
goto menu

:enable_dynamic_tick
cls
echo =====================================
echo         BẬT LẠI DYNAMIC TICK
echo =====================================
echo.

reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick 2>nul | find "0x0" >nul
if %errorlevel%==0 (
    echo ✓ Dynamic Tick đã được bật rồi!
) else (
    echo Đang bật lại Dynamic Tick...
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick /t REG_DWORD /d 0 /f >nul
    echo ✓ Đã bật lại thành công Dynamic Tick!
    echo ⚠ Cần khởi động lại để có hiệu lực!
)
echo.
pause
goto menu

:enable_both
cls
echo =====================================
echo        BẬT LẠI CẢ HAI
echo =====================================
echo.
echo Đang khôi phục cài đặt mặc định...
echo.

set need_reboot=0

echo [1/2] Bật lại UsePlatformClock...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock 2>nul | find "0x1" >nul
if %errorlevel%==0 (
    echo ✓ UsePlatformClock đã bật rồi
) else (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock /t REG_DWORD /d 1 /f >nul
    echo ✓ Đã bật lại UsePlatformClock
    set need_reboot=1
)

echo [2/2] Bật lại Dynamic Tick...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick 2>nul | find "0x0" >nul
if %errorlevel%==0 (
    echo ✓ Dynamic Tick đã bật rồi
) else (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick /t REG_DWORD /d 0 /f >nul
    echo ✓ Đã bật lại Dynamic Tick
    set need_reboot=1
)

echo.
if %need_reboot%==1 (
    echo =====================================
    echo   HOÀN TẤT! CẦN KHỞI ĐỘNG LẠI MÁY!
    echo =====================================
) else (
    echo =====================================
    echo  TẤT CẢ ĐÃ Ở TRẠNG THÁI MẶC ĐỊNH!
    echo =====================================
)
pause
goto menu

:check_status
cls
echo =====================================
echo      KIỂM TRA TRẠNG THÁI HIỆN TẠI
echo =====================================
echo.

echo UsePlatformClock:
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock 2>nul | find "0x0" >nul
if %errorlevel%==0 (
    echo ✓ ĐÃ TẮT (Tối ưu cho gaming)
) else (
    echo ✗ ĐANG BẬT (Mặc định Windows)
)

echo.
echo Dynamic Tick:
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick 2>nul | find "0x1" >nul
if %errorlevel%==0 (
    echo ✓ ĐÃ TẮT (Tối ưu cho gaming)
) else (
    echo ✗ ĐANG BẬT (Mặc định Windows)
)

echo.
echo =====================================
echo TRẠNG THÁI TỔNG QUAN:
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v useplatformclock 2>nul | find "0x0" >nul && reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v disabledynamictick 2>nul | find "0x1" >nul
if %errorlevel%==0 (
    echo ✓ ĐÃ TỐI ƯU HOÀN TOÀN CHO GAMING!
) else (
    echo ⚠ CHƯA TỐI ƯU HOÀN TOÀN
)
echo =====================================
pause
goto menu

:exit
cls
echo =====================================
echo   Cảm ơn bạn đã sử dụng Clock Optimizer!
echo.
echo   LƯU Ý QUAN TRỌNG:
echo   - Cần KHỞI ĐỘNG LẠI để thay đổi có hiệu lực
echo   - Các thay đổi này tối ưu cho gaming
echo   - Có thể bật lại bất cứ lúc nào
echo.
echo   Gaming Performance: ✓ Optimized
echo =====================================
pause
exit