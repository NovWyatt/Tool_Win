@echo off
setlocal
chcp 65001 >nul
title MyExcel VietQR - Hoan tac lan sua
rem Hoan tac mot lan sua. Chay FixMyExcel_VietQR.bat canh file nay (ban moi nhat) o che do HOAN TAC, nen ban sao luu
rem cua ban cu cung duoc hoan tac an toan: luu cau hinh hien tai truoc, file Excel da sua tiep thi giu lai.
rem   HOAN_TAC.bat                     liet ke ban sao luu cua tai khoan nay de chon (moi nhat truoc), tim trong
rem                                    %LOCALAPPDATA%\MyExcelFix\SaoLuu va tren Desktop (ban cu)
rem   HOAN_TAC.bat "<thu muc sao luu>" hoan tac dung thu muc MyExcelFix_SaoLuu_<gio> do
rem Ma thoat: 0 xong, 1 loi, 2 chua hoan tac gi, 3 mot phan.
if "%~1"=="" goto :chon
if not exist "%~1\" goto :sai_thu_muc
if not exist "%~1\manifest.json" goto :thieu_manifest
if not exist "%~dp0FixMyExcel_VietQR.bat" goto :ban_trong_thu_muc
set "MYX_UNDO_DIR=%~f1"
call "%~dp0FixMyExcel_VietQR.bat"
exit /b %errorlevel%

:chon
if not exist "%~dp0FixMyExcel_VietQR.bat" goto :thieu_ban_sua
set "MYX_UNDO_DIR="
set "MYX_UNDO_CHON=1"
call "%~dp0FixMyExcel_VietQR.bat"
exit /b %errorlevel%

:ban_trong_thu_muc
rem Thieu ban sua canh file nay: dung ban sao HoanTac_FixMyExcel.bat do lan sua tao ra
if not exist "%~1\HoanTac_FixMyExcel.bat" goto :sai_thu_muc
call "%~1\HoanTac_FixMyExcel.bat"
exit /b %errorlevel%

:thieu_ban_sua
echo Khong thay FixMyExcel_VietQR.bat canh file nay.
echo Chep HOAN_TAC.bat vao cung thu muc voi FixMyExcel_VietQR.bat, hoac bam dup HoanTac_FixMyExcel.bat
echo trong thu muc sao luu MyExcelFix_SaoLuu_... (thuong o %LOCALAPPDATA%\MyExcelFix\SaoLuu).
if not defined MYX_NOPAUSE pause
exit /b 2

:sai_thu_muc
echo Khong thay thu muc sao luu hop le: "%~1"
echo Hay chon dung thu muc MyExcelFix_SaoLuu_... do lan sua tao ra, hoac chay HOAN_TAC.bat khong kem thu muc de chon.
if not defined MYX_NOPAUSE pause
exit /b 2

:thieu_manifest
echo Thu muc sao luu thieu manifest.json nen khong hoan tac duoc: "%~1"
if not defined MYX_NOPAUSE pause
exit /b 2
