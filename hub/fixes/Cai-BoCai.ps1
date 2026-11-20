# Cài một gói có sẵn trong runtime\bo-cai của bản portable (cả gói phụ thuộc), không cần mạng hay winget.
# Trạm Tool gọi script này khi bấm nút Cài của một yêu cầu loại winget mà bản này có sẵn bộ cài (vd ODBC Driver 18 kèm
# Visual C++ Redistributable cho Khôi phục .mdf). Kiểm mã SHA-256 trước khi chạy bộ cài.
#   -Id <mã gói winget>   -ChayThu: chỉ in việc sẽ làm.
# Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (không có gói, thiếu quyền Admin).
param([Parameter(Mandatory = $true)][string]$Id, [switch]$ChayThu)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { $Host.UI.RawUI.WindowTitle = "Tram Tool - cai $Id" } catch { }
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\BoCai.ps1')

$root = Get-HubBoCaiRoot
$p = Get-BoCaiPackage $root $Id
if (-not $p) { Write-Host "LOI: Bản này không có sẵn bộ cài $Id ($root)." -ForegroundColor Red; exit 2 }
Write-Host "Cài $($p.ten) bản $($p.phienBan) từ bộ cài có sẵn (không cần mạng)."
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($p.phamVi -ne 'user' -and -not $admin -and -not $ChayThu) { Write-Host 'LOI: Cần chạy với quyền Admin (trong Trạm Tool bấm nút Cài, Windows sẽ hỏi UAC).' -ForegroundColor Red; exit 2 }

$r = Install-BoCaiPackage -Root $root -Id $Id -DryRun:$ChayThu
Write-Host ''
if (-not $r.Ok) { Write-Host "LOI: $($r.Message)" -ForegroundColor Red; exit 1 }
if ($ChayThu) { Write-Host 'Chạy thử: không cài gì.'; exit 0 }
Write-Host "XONG: đã cài $($p.ten). Quay lại Trạm Tool, trạm tự kiểm tra lại." -ForegroundColor Green
if ($r.Reboot) { Write-Host 'Windows đề nghị khởi động lại máy để hoàn tất.' -ForegroundColor Yellow }
exit 0
