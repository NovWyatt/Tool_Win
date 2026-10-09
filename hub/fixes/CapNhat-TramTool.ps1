<#
  Trạm Tool - cập nhật trạm và các công cụ từ kho git: fast-forward nhánh đang dùng, rồi cập nhật submodule.
  Chạy bằng quyền thường, trong cửa sổ riêng (nút "Cập nhật" ở trang Cài đặt của trạm).
  An toàn: không đụng sửa đổi trên máy. Có file git theo dõi đang sửa thì dừng (không stash, không reset); nhánh trên
  máy lệch với kho thì dừng (không merge, không rebase). File không theo dõi (kết quả, dữ liệu khách) giữ nguyên.
  Mã thoát: 0 = đã mới nhất hoặc đã cập nhật, 1 = lỗi git hoặc mạng, 2 = không cập nhật an toàn được (file đang
  sửa, nhánh lệch, không phải kho git), 1223 = người dùng chọn dừng.
  -ThuMuc: kho khác thư mục trạm (bài thử). -KhongHoi: không hỏi, không chờ bấm phím khi xong.
#>
[CmdletBinding()]
param([string]$ThuMuc = '', [switch]$KhongHoi)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\AnToan.ps1')
. (Join-Path $PSScriptRoot '..\lib\CapNhat.ps1')
try { $Host.UI.RawUI.WindowTitle = 'Trạm Tool - cập nhật công cụ' } catch { }
$root = if ($ThuMuc) { [IO.Path]::GetFullPath($ThuMuc) } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }

function Stop-CapNhat([int]$Code) { if (-not $KhongHoi) { Wait-AtClose }; exit $Code }

function Invoke-GitHien {
    # Chạy git trong cửa sổ này (thấy tiến trình tải, hỏi đăng nhập được nếu kho cần). Trả mã thoát.
    param([string[]]$GitArgs)
    & git.exe -C $root @GitArgs | Out-Host   # không để chữ của git lẫn vào giá trị trả về
    return $LASTEXITCODE
}

Write-AtHead 'CẬP NHẬT TRẠM TOOL' $root
$info = Get-RepoUpdateInfo -RootDir $root
if (-not $info.repo) { Write-AtWarn $info.reason; Stop-CapNhat 2 }
if (-not $info.upstream) { Write-AtWarn $info.reason; Stop-CapNhat 2 }
Write-AtInfo "Nhánh $($info.branch) (theo $($info.upstream)), đang ở $($info.commit): $($info.subject)"
if ($info.dirty.Count) {
    Write-AtWarn "Có $($info.dirty.Count) file đang sửa trên máy này; cập nhật sẽ ghi đè nên dừng lại:"
    foreach ($f in ($info.dirty | Select-Object -First 15)) { Write-AtInfo "  $f" }
    Write-AtInfo 'Chép các file đó ra chỗ khác (hoặc commit) rồi chạy lại.'
    Stop-CapNhat 2
}

Write-Host ''
Write-AtInfo 'Đang hỏi kho xem có bản mới không (git fetch)...'
$code = Invoke-GitHien @('fetch', '--prune')
if ($code -ne 0) { Write-AtBad "Không lấy được thông tin từ kho (git fetch trả mã $code). Kiểm tra mạng hoặc quyền đọc kho."; Stop-CapNhat 1 }
$info = Get-RepoUpdateInfo -RootDir $root
if ($info.ahead -gt 0 -and $info.behind -gt 0) {
    Write-AtWarn "Nhánh trên máy có $($info.ahead) commit riêng, kho có $($info.behind) commit mới: hai bên đã lệch, cần gộp bằng tay."
    Stop-CapNhat 2
}

$truoc = (& git.exe -C $root rev-parse HEAD).Trim()
if ($info.behind -eq 0) {
    if ($info.ahead -gt 0) { Write-AtOk "Đã mới nhất (máy có $($info.ahead) commit chưa đẩy lên kho)." }
    else { Write-AtOk 'Đã là bản mới nhất.' }
} else {
    Write-Host ''
    Write-AtInfo "Kho có $($info.behind) commit mới:"
    foreach ($c in ($info.incoming | Select-Object -First 15)) { Write-AtInfo ("  {0}  {1}" -f $c.commit, $c.subject) }
    if ($info.behind -gt 15) { Write-AtInfo "  ... và $($info.behind - 15) commit nữa" }
    if (-not $KhongHoi) {
        Write-Host ''
        $c = Read-AtChoice -Prompt '[C] Cập nhật   [D] Dừng' -Keys @('C', 'D') -Fallback 'D'
        if ($c -ne 'C') { Write-AtInfo 'Đã dừng, không đổi gì.'; Stop-CapNhat 1223 }
    }
    $code = Invoke-GitHien @('merge', '--ff-only', '--quiet', '@{u}')
    if ($code -ne 0) { Write-AtBad "Không cập nhật được (git merge --ff-only trả mã $code). Máy giữ nguyên bản cũ."; Stop-CapNhat 1 }
    Write-AtOk "Đã cập nhật lên $((& git.exe -C $root log -1 --format=%h).Trim())."
}

# Submodule (vd tools\mdf2sql) theo đúng commit kho chính ghi: chạy cả khi kho chính đã mới nhất mà submodule chưa về.
$sub = @(& git.exe -C $root submodule status 2>$null | Where-Object { $_ -match '^[-+U]' })
if ($sub.Count) {
    Write-AtInfo "Cập nhật $($sub.Count) submodule..."
    $code = Invoke-GitHien @('submodule', 'update', '--init', '--recursive')
    if ($code -ne 0) { Write-AtBad "Submodule chưa cập nhật được (mã $code). Chạy lại khi có mạng."; Stop-CapNhat 1 }
    Write-AtOk 'Submodule đã cập nhật.'
}

$sau = (& git.exe -C $root rev-parse HEAD).Trim()
if ($sau -ne $truoc) {
    $doi = @(& git.exe -C $root diff --name-only $truoc $sau)
    if (@($doi | Where-Object { $_ -like 'hub/*' }).Count) {
        Write-AtWarn 'Phần máy chủ của trạm có bản mới: vào Cài đặt > Tắt trạm, rồi mở lại TramTool.bat để dùng bản mới.'
    }
    $caiLai = @($doi | Where-Object { $_ -match '^tools/([^/]+)/(requirements[^/]*\.txt|CAI_DAT\.ps1|package(-lock)?\.json)$' } | ForEach-Object { ($_ -split '/')[1] } | Select-Object -Unique)
    if ($caiLai.Count) { Write-AtWarn ("Công cụ đổi thư viện, bấm Cài hoặc sửa môi trường chạy ở trang công cụ: " + ($caiLai -join ', ')) }
    Write-AtInfo 'Trạm sẽ tự đọc lại danh sách công cụ khi cửa sổ này đóng.'
}
Stop-CapNhat 0
