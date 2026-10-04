@echo off
chcp 65001 >nul
title Logout GitHub credential local

echo ==========================================
echo  XOA DANG NHAP GITHUB TREN MAY LOCAL
echo ==========================================
echo.
echo File nay chi xoa credential GitHub da luu tren Windows.
echo Khong xoa code, khong xoa commit, khong xoa repo local.
echo.

echo [1] Credential GitHub hien tai neu co:
cmdkey /list | findstr /i "github"
echo.

echo [2] Dang xoa credential GitHub pho bien...

cmdkey /delete:git:https://github.com >nul 2>&1
cmdkey /delete:github.com >nul 2>&1
cmdkey /delete:https://github.com >nul 2>&1
cmdkey /delete:git:https://github.com/ >nul 2>&1

echo Da chay lenh xoa credential GitHub.
echo.

where gh >nul 2>&1
if %errorlevel%==0 (
echo [3] Phat hien GitHub CLI tren may.
choice /C YN /M "Ban co muon dang xuat GitHub CLI khong"
if errorlevel 2 goto CHECK_AGAIN
if errorlevel 1 (
gh auth logout --hostname github.com
)
) else (
echo [3] Khong phat hien GitHub CLI, bo qua buoc gh auth logout.
)

:CHECK_AGAIN
echo.
echo [4] Kiem tra lai credential GitHub con luu khong:
cmdkey /list | findstr /i "github"

echo.
echo ==========================================
echo  HOAN TAT
echo ==========================================
echo.
echo Sau do vao repo can day code va chay:
echo git push
echo.
echo Khi GitHub hoi dang nhap, hay chon dung tai khoan can dung.
echo.
pause
