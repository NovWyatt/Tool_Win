@echo off
chcp 65001 >nul
title Windows 11 Service Optimizer
color 0C

:menu
cls
echo =====================================
echo   WINDOWS 11 SERVICE OPTIMIZER
echo         Created by: Wyatt
echo =====================================
echo.
echo 1. Tắt DiagTrack - Thu thập dữ liệu telemetry
echo 2. Tắt Defragsvc - Tối ưu hóa ổ cứng tự động
echo 3. Tắt WinInsider - Dịch vụ Windows Insider
echo 4. Tắt SysMain - Prefetch và SuperFetch
echo 5. Tắt tất cả service trên
echo 6. Bật lại DiagTrack - Khôi phục thu thập telemetry
echo 7. Bật lại Defragsvc - Khôi phục tối ưu ổ cứng tự động
echo 8. Bật lại WinInsider - Khôi phục dịch vụ Windows Insider
echo 9. Bật lại SysMain - Khôi phục Prefetch và SuperFetch
echo 10. Bật lại tất cả service
echo 11. Kiểm tra trạng thái tất cả service
echo 0. Thoát
echo.
echo CẢNH BÁO: Tắt các service này có thể ảnh hưởng chức năng hệ thống!
echo.
set /p choice="Chọn tùy chọn (0-11): "

if "%choice%"=="1" goto disable_diagtrack
if "%choice%"=="2" goto disable_defrag
if "%choice%"=="3" goto disable_insider
if "%choice%"=="4" goto disable_sysmain
if "%choice%"=="5" goto disable_all
if "%choice%"=="6" goto enable_diagtrack
if "%choice%"=="7" goto enable_defrag
if "%choice%"=="8" goto enable_insider
if "%choice%"=="9" goto enable_sysmain
if "%choice%"=="10" goto enable_all
if "%choice%"=="11" goto check_status
if "%choice%"=="0" goto exit
goto menu

:disable_diagtrack
cls
echo =====================================
echo      TẮT CONNECTED USER EXPERIENCES
echo         AND TELEMETRY (DiagTrack)
echo =====================================
echo.
echo Chức năng: Thu thập dữ liệu sử dụng và gửi về Microsoft
echo Tác động: Giảm việc theo dõi, tăng quyền riêng tư
echo.

sc query DiagTrack | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ Service DiagTrack đã được tắt rồi, không cần thực hiện thêm!
) else (
    echo Đang tắt DiagTrack service...
    sc stop DiagTrack >nul 2>&1
    sc config DiagTrack start= disabled >nul 2>&1
    echo ✓ Đã tắt thành công DiagTrack service!
)
echo.
pause
goto menu

:disable_defrag
cls
echo =====================================
echo       TẮT OPTIMIZE DRIVES
echo         (defragsvc)
echo =====================================
echo.
echo Chức năng: Tối ưu hóa và defrag ổ cứng tự động
echo Tác động: Giảm hoạt động nền, phù hợp với SSD
echo.

sc query defragsvc | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ Service Defrag đã được tắt rồi, không cần thực hiện thêm!
) else (
    echo Đang tắt Defrag service...
    sc stop defragsvc >nul 2>&1
    sc config defragsvc start= disabled >nul 2>&1
    echo ✓ Đã tắt thành công Defrag service!
)
echo.
pause
goto menu

:disable_insider
cls
echo =====================================
echo      TẮT WINDOWS INSIDER SERVICE
echo =====================================
echo.
echo Chức năng: Hỗ trợ chương trình Windows Insider Preview
echo Tác động: Giảm tiến trình nền không cần thiết
echo.

sc query wisvc | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ Service Windows Insider đã được tắt rồi, không cần thực hiện thêm!
) else (
    echo Đang tắt Windows Insider service...
    sc stop wisvc >nul 2>&1
    sc config wisvc start= disabled >nul 2>&1
    echo ✓ Đã tắt thành công Windows Insider service!
)
echo.
pause
goto menu

:disable_sysmain
cls
echo =====================================
echo          TẮT SYSMAIN
echo     (Prefetch & SuperFetch)
echo =====================================
echo.
echo Chức năng: Preload ứng dụng vào RAM để khởi động nhanh
echo Tác động: Giảm sử dụng RAM, phù hợp với máy RAM thấp
echo.

sc query SysMain | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ Service SysMain đã được tắt rồi, không cần thực hiện thêm!
) else (
    echo Đang tắt SysMain service...
    sc stop SysMain >nul 2>&1
    sc config SysMain start= disabled >nul 2>&1
    echo ✓ Đã tắt thành công SysMain service!
)
echo.
pause
goto menu

:disable_all
cls
echo =====================================
echo       TẮT TẤT CẢ SERVICES
echo =====================================
echo.
echo Đang kiểm tra và tắt tất cả services...
echo.

echo [1/4] Kiểm tra DiagTrack...
sc query DiagTrack | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ DiagTrack đã tắt rồi
) else (
    sc stop DiagTrack >nul 2>&1
    sc config DiagTrack start= disabled >nul 2>&1
    echo ✓ Đã tắt DiagTrack
)

echo [2/4] Kiểm tra Defrag...
sc query defragsvc | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ Defrag đã tắt rồi
) else (
    sc stop defragsvc >nul 2>&1
    sc config defragsvc start= disabled >nul 2>&1
    echo ✓ Đã tắt Defrag
)

echo [3/4] Kiểm tra Windows Insider...
sc query wisvc | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ Windows Insider đã tắt rồi
) else (
    sc stop wisvc >nul 2>&1
    sc config wisvc start= disabled >nul 2>&1
    echo ✓ Đã tắt Windows Insider
)

echo [4/4] Kiểm tra SysMain...
sc query SysMain | find "STOPPED" >nul
if %errorlevel%==0 (
    echo ✓ SysMain đã tắt rồi
) else (
    sc stop SysMain >nul 2>&1
    sc config SysMain start= disabled >nul 2>&1
    echo ✓ Đã tắt SysMain
)

echo.
echo =====================================
echo     HOÀN TẤT TẤT CẢ SERVICES!
echo =====================================
pause
goto menu

:enable_diagtrack
cls
echo =====================================
echo      BẬT LẠI CONNECTED USER EXPERIENCES
echo         AND TELEMETRY (DiagTrack)
echo =====================================
echo.
echo Khôi phục: Thu thập dữ liệu sử dụng và gửi về Microsoft
echo.

sc query DiagTrack | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ Service DiagTrack đã được bật rồi, đang hoạt động bình thường!
) else (
    echo Đang bật lại DiagTrack service...
    sc config DiagTrack start= auto >nul 2>&1
    sc start DiagTrack >nul 2>&1
    echo ✓ Đã bật lại thành công DiagTrack service!
)
echo.
pause
goto menu

:enable_defrag
cls
echo =====================================
echo       BẬT LẠI OPTIMIZE DRIVES
echo         (defragsvc)
echo =====================================
echo.
echo Khôi phục: Tối ưu hóa và defrag ổ cứng tự động
echo.

sc query defragsvc | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ Service Defrag đã được bật rồi, đang hoạt động bình thường!
) else (
    echo Đang bật lại Defrag service...
    sc config defragsvc start= auto >nul 2>&1
    sc start defragsvc >nul 2>&1
    echo ✓ Đã bật lại thành công Defrag service!
)
echo.
pause
goto menu

:enable_insider
cls
echo =====================================
echo      BẬT LẠI WINDOWS INSIDER SERVICE
echo =====================================
echo.
echo Khôi phục: Hỗ trợ chương trình Windows Insider Preview
echo.

sc query wisvc | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ Service Windows Insider đã được bật rồi, đang hoạt động bình thường!
) else (
    echo Đang bật lại Windows Insider service...
    sc config wisvc start= manual >nul 2>&1
    sc start wisvc >nul 2>&1
    echo ✓ Đã bật lại thành công Windows Insider service!
)
echo.
pause
goto menu

:enable_sysmain
cls
echo =====================================
echo          BẬT LẠI SYSMAIN
echo     (Prefetch & SuperFetch)
echo =====================================
echo.
echo Khôi phục: Preload ứng dụng vào RAM để khởi động nhanh
echo.

sc query SysMain | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ Service SysMain đã được bật rồi, đang hoạt động bình thường!
) else (
    echo Đang bật lại SysMain service...
    sc config SysMain start= auto >nul 2>&1
    sc start SysMain >nul 2>&1
    echo ✓ Đã bật lại thành công SysMain service!
)
echo.
pause
goto menu

:enable_all
cls
echo =====================================
echo       BẬT LẠI TẤT CẢ SERVICES
echo =====================================
echo.
echo Đang khôi phục tất cả services về trạng thái mặc định...
echo.

echo [1/4] Bật lại DiagTrack...
sc query DiagTrack | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ DiagTrack đã bật rồi
) else (
    sc config DiagTrack start= auto >nul 2>&1
    sc start DiagTrack >nul 2>&1
    echo ✓ Đã bật lại DiagTrack
)

echo [2/4] Bật lại Defrag...
sc query defragsvc | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ Defrag đã bật rồi
) else (
    sc config defragsvc start= auto >nul 2>&1
    sc start defragsvc >nul 2>&1
    echo ✓ Đã bật lại Defrag
)

echo [3/4] Bật lại Windows Insider...
sc query wisvc | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ Windows Insider đã bật rồi
) else (
    sc config wisvc start= manual >nul 2>&1
    sc start wisvc >nul 2>&1
    echo ✓ Đã bật lại Windows Insider
)

echo [4/4] Bật lại SysMain...
sc query SysMain | find "RUNNING" >nul
if %errorlevel%==0 (
    echo ✓ SysMain đã bật rồi
) else (
    sc config SysMain start= auto >nul 2>&1
    sc start SysMain >nul 2>&1
    echo ✓ Đã bật lại SysMain
)

echo.
echo =====================================
echo     ĐÃ KHÔI PHỤC TẤT CẢ SERVICES!
echo      Hệ thống trở về trạng thái mặc định
echo =====================================
pause
goto menu

:check_status
cls
echo =====================================
echo      KIỂM TRA TRẠNG THÁI SERVICES
echo =====================================
echo.

echo DiagTrack (Telemetry):
sc query DiagTrack | find "RUNNING" >nul && echo ✓ Đang chạy (Mặc định) || echo ✗ Đã tắt (Tối ưu)

echo.
echo Defragsvc (Optimize Drives):
sc query defragsvc | find "RUNNING" >nul && echo ✓ Đang chạy (Mặc định) || echo ✗ Đã tắt (Tối ưu)

echo.
echo WiSvc (Windows Insider):
sc query wisvc | find "RUNNING" >nul && echo ✓ Đang chạy (Mặc định) || echo ✗ Đã tắt (Tối ưu)

echo.
echo SysMain (Prefetch):
sc query SysMain | find "RUNNING" >nul && echo ✓ Đang chạy (Mặc định) || echo ✗ Đã tắt (Tối ưu)

echo.
echo =====================================
pause
goto menu

:exit
cls
echo =====================================
echo    Cảm ơn bạn đã sử dụng Service Optimizer!
echo    
echo    LƯU Ý: Để khôi phục lại services:
echo    sc config [tên_service] start= auto
echo    sc start [tên_service]
echo =====================================
pause
exit