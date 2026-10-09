function Get-TestBase {
    # Thư mục tạm chung của mọi bài thử. Nằm NGOÀI repo vì vài công cụ (new-windows) từ chối ghi dữ liệu nhạy cảm
    # vào thư mục Trạm Tool. Mặc định <thư mục cha của repo>\.TramTool-KiemThu (cùng ổ với repo);
    # đổi bằng biến môi trường TRAMTOOL_TEST_TAM (tên thư mục cuối phải có chữ "KiemThu").
    $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $b = if ($env:TRAMTOOL_TEST_TAM) { $env:TRAMTOOL_TEST_TAM } else { Join-Path (Split-Path $repo -Parent) '.TramTool-KiemThu' }
    $b = [IO.Path]::GetFullPath($b).TrimEnd('\')
    if ((Split-Path $b -Leaf) -notlike '*KiemThu*') { throw "Thư mục tạm của bài thử phải có chữ KiemThu trong tên: $b" }
    if (($b + '\').StartsWith($repo.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Thư mục tạm của bài thử không được nằm trong repo: $b" }
    return $b
}

function Remove-TestDir([string]$Path) {
    # Xoá thư mục thử mà không đi theo junction/symlink bên trong (Remove-Item -Recurse của PowerShell 5.1
    # có thể xoá luôn nội dung nơi junction trỏ tới). Chỉ nhận đường dẫn trong thư mục tạm chung (Get-TestBase).
    if (-not $Path -or -not (Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path)) { return }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $base = Get-TestBase
    if (-not ($full -eq $base -or $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase))) { throw "Không xoá ngoài thư mục tạm của bài thử: $full" }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($full, $false); return }
    $stack = New-Object System.Collections.Stack
    $stack.Push($full)
    while ($stack.Count) {
        $d = $stack.Pop()
        foreach ($c in [IO.Directory]::GetDirectories($d)) {
            if ([IO.File]::GetAttributes($c) -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($c, $false) }
            else { $stack.Push($c) }
        }
    }
    foreach ($f in [IO.Directory]::GetFiles($full, '*', 'AllDirectories')) {
        $a = [IO.File]::GetAttributes($f)
        if ($a -band [IO.FileAttributes]::ReparsePoint) { [IO.File]::Delete($f) }
        elseif ($a -band [IO.FileAttributes]::ReadOnly) { [IO.File]::SetAttributes($f, 'Normal') }
    }
    [IO.Directory]::Delete($full, $true)
}
