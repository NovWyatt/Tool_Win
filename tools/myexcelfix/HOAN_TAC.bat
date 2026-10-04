@echo off
chcp 65001 >nul
title MyExcel VietQR - Hoan tac lan sua
rem Goi ban HoanTac_FixMyExcel.bat nam trong thu muc sao luu MyExcelFix_SaoLuu_<gio> ma lan sua da tao.
rem Ban do tu chay che do HOAN TAC va doc manifest.json canh no. Dung tu Tram Tool (chon thu muc sao luu).
if "%~1"=="" goto :thieu_thu_muc
if not exist "%~1\HoanTac_FixMyExcel.bat" goto :sai_thu_muc
if not exist "%~1\manifest.json" goto :thieu_manifest
call "%~1\HoanTac_FixMyExcel.bat"
exit /b %errorlevel%

:thieu_thu_muc
echo Chon thu muc sao luu MyExcelFix_SaoLuu_... cua lan sua can hoan tac.
echo Thu muc nay thuong nam tren Desktop cua tai khoan da sua.
pause
exit /b 2

:sai_thu_muc
echo Khong thay HoanTac_FixMyExcel.bat trong "%~1"
echo Hay chon dung thu muc MyExcelFix_SaoLuu_... do lan sua tao ra.
pause
exit /b 2

:thieu_manifest
echo Thu muc sao luu thieu manifest.json nen khong hoan tac duoc: "%~1"
pause
exit /b 2
