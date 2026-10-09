# Danh sách file của repo (đã commit và file mới chưa bị .gitignore), bỏ submodule tools\mdf2sql (repo riêng).
# Không có git (repo tải dạng .zip) thì duyệt thư mục, bỏ các thư mục dữ liệu, môi trường.
function Get-RepoFiles([string[]]$Ext) {
    $files = @()
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git -and (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        $list = @(& $git.Source -C $RepoRoot -c core.quotepath=off ls-files --cached --others --exclude-standard)
        $files = @($list | ForEach-Object { Join-Path $RepoRoot ($_ -replace '/', '\') })
    } else {
        $skip = '.git', 'node_modules', '.venv', 'venv', 'du-lieu', 'ket_qua', '__pycache__', 'models', 'data'
        $stack = New-Object System.Collections.Stack
        $stack.Push($RepoRoot)
        while ($stack.Count) {
            $d = $stack.Pop()
            foreach ($c in [IO.Directory]::GetDirectories($d)) { if ($skip -notcontains (Split-Path $c -Leaf)) { $stack.Push($c) } }
            $files += [IO.Directory]::GetFiles($d)
        }
    }
    $m2s = Join-Path $ToolsDir 'mdf2sql'
    return @($files | Where-Object {
            -not $_.StartsWith($m2s + '\', [StringComparison]::OrdinalIgnoreCase) -and $_ -ne $m2s -and
            $Ext -contains [IO.Path]::GetExtension($_).ToLowerInvariant() -and (Test-Path -LiteralPath $_ -PathType Leaf)
        } | Sort-Object)
}

function Get-RelPath([string]$Path) { return $Path.Substring($RepoRoot.Length + 1) }
