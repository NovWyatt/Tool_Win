@echo off
chcp 65001 >nul
title Kiem tra va Khac phuc su co Wi-Fi

:: Kiem tra quyen Administrator (fltmc khong can dich vu Server nhu net session)
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    echo ========================================================
    echo VUI LONG CHAY FILE NAY DUOI QUYEN ADMIN (Run as Administrator)
    echo ========================================================
    pause
    exit /b 2
)

:MENU
cls
echo ========================================================
echo          CONG CU KIEM TRA VA SUA LOI WI-FI
echo ========================================================
echo 1. Kiem tra card Wi-Fi va quet mang xung quanh
echo 2. Tu dong sua loi (Reset IP, Flush DNS, Reset Winsock)
echo 3. Khoi dong lai Card Mang Wi-Fi
echo 4. Thoat
echo ========================================================
set /p choice="Nhap lua chon cua ban (1-4): "

if "%choice%"=="1" goto CHECK
if "%choice%"=="2" goto FIX
if "%choice%"=="3" goto RESTART_ADAPTER
if "%choice%"=="4" exit /b
goto MENU

:CHECK
cls
echo [1/4] Kiem tra trang thai Card Wi-Fi...
netsh interface show interface | findstr /i "Wi-Fi Wireless WLAN"
if %errorlevel% neq 0 (
    echo [CANH BAO] Khong tim thay card mang Wi-Fi! (Co the chua cai Driver hoac bi disable)
) else (
    echo - Da nhan dien card Wi-Fi.
)
echo.

echo [2/4] Kiem tra trang thai phan cung (Driver/Hardware)...
netsh wlan show interfaces
echo.

echo [3/4] Quet danh sach Wi-Fi xung quanh...
netsh wlan show networks
echo.

echo [4/4] Kiem tra ket noi Internet (Ping 8.8.8.8 & google.com)...
ping -n 2 8.8.8.8 >nul
if %errorlevel% equ 0 (
    echo - Ping IP thanh cong (Co ket noi mang).
) else (
    echo - Khong the ping IP (Mat ket noi hoan toan).
)

ping -n 2 google.com >nul
if %errorlevel% equ 0 (
    echo - Phan giai ten mien DNS tot.
) else (
    echo - Loi phan giai ten mien DNS.
)
echo.
echo ========================================================
pause
goto MENU

:FIX
cls
echo Dang tien hanh dat lai cac thiet lap mang...
echo.
echo 1. Lam sach bo nho dem DNS...
ipconfig /flushdns
echo 2. Giai phong va cap lai IP...
ipconfig /release >nul 2>&1
ipconfig /renew >nul 2>&1
echo 3. Dat lai Winsock...
netsh winsock reset >nul
echo 4. Dat lai TCP/IP stack...
netsh int ip reset >nul

echo.
echo ========================================================
echo Da hoan tat sua loi mang co ban!
echo Ban nen khoi dong lai laptop neu van chua bat duoc Wi-Fi.
echo ========================================================
pause
goto MENU

:RESTART_ADAPTER
cls
echo Dang tim va khoi dong lai Card Wi-Fi...
for /f "tokens=4*" %%a in ('netsh interface show interface ^| findstr /i "Wi-Fi Wireless"') do (
    set adapter_name=%%a %%b
)

if defined adapter_name (
    echo - Dang tat card mang: %adapter_name%
    netsh interface set interface "%adapter_name%" disable
    timeout /t 2 >nul
    echo - Dang bat lai card mang: %adapter_name%
    netsh interface set interface "%adapter_name%" enable
    echo - Hoan tat!
) else (
    echo - Khong xac dinh duoc ten card Wi-Fi de khoi dong lai.
)
echo.
pause
goto MENU