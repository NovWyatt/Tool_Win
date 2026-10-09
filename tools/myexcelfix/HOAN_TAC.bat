@echo off
setlocal
chcp 65001 >nul
title MyExcel VietQR - Hoan tac lan sua
rem Hoan tac mot lan sua: tham so la thu muc sao luu MyExcelFix_SaoLuu_<gio> ma lan sua da tao.
rem Chay FixMyExcel_VietQR.bat canh file nay (ban moi nhat) o che do HOAN TAC tren thu muc do, nen ban sao luu
rem cua ban cu cung duoc hoan tac an toan: luu cau hinh hien tai truoc, file Excel da sua tiep thi giu lai.
rem Dung tu Tram Tool (chon thu muc sao luu). Ma thoat: 0 xong, 1 loi, 2 chua hoan tac gi, 3 mot phan.
if "%~1"=="" goto :thieu_thu_muc
if not exist "%~1\" goto :sai_thu_muc
if not exist "%~1\manifest.json" goto :thieu_manifest
if not exist "%~dp0FixMyExcel_VietQR.bat" goto :ban_trong_thu_muc
set "MYX_UNDO_DIR=%~f1"
call "%~dp0FixMyExcel_VietQR.bat"
exit /b %errorlevel%

:ban_trong_thu_muc
rem Thieu ban sua canh file nay: dung ban sao HoanTac_FixMyExcel.bat do lan sua tao ra
if not exist "%~1\HoanTac_FixMyExcel.bat" goto :sai_thu_muc
call "%~1\HoanTac_FixMyExcel.bat"
exit /b %errorlevel%

:thieu_thu_muc
echo Chon thu muc sao luu MyExcelFix_SaoLuu_... cua lan sua can hoan tac.
echo Thu muc nay thuong nam tren Desktop cua tai khoan da sua.
if not defined MYX_NOPAUSE pause
exit /b 2

:sai_thu_muc
echo Khong thay thu muc sao luu hop le: "%~1"
echo Hay chon dung thu muc MyExcelFix_SaoLuu_... do lan sua tao ra.
if not defined MYX_NOPAUSE pause
exit /b 2

:thieu_manifest
echo Thu muc sao luu thieu manifest.json nen khong hoan tac duoc: "%~1"
if not defined MYX_NOPAUSE pause
exit /b 2
