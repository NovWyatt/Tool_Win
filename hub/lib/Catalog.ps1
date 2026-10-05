# Trạm Tool - đọc danh mục công cụ từ tools\<thư-mục>\tool.json
# Thư mục/script thả vào tools\ mà chưa có tool.json vẫn hiện ra (manifest tự sinh).

$script:ValidRisks = @('read-only', 'asks-before-change', 'modifies-system')
$script:ValidTypes = @('console', 'open', 'url')
$script:ValidArgTypes = @('file', 'folder', 'text', 'number', 'choice', 'bool')
$script:ScriptExts = @('.bat', '.cmd', '.ps1')

function Get-HubCategories {
    param([string]$HubDir)
    return @(Read-JsonFile (Join-Path $HubDir 'categories.json'))
}

function Get-HubCatalog {
    param([Parameter(Mandatory)][string]$ToolsDir, [Parameter(Mandatory)][string]$RootDir)
    $list = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $ToolsDir)) { return @() }

    foreach ($dir in @(Get-ChildItem -LiteralPath $ToolsDir -Directory | Where-Object { $_.Name -notmatch '^[._]' } | Sort-Object Name)) {
        $manifestPath = Join-Path $dir.FullName 'tool.json'
        if (Test-Path -LiteralPath $manifestPath) {
            [void]$list.Add((Read-ToolManifest -ManifestPath $manifestPath -RootDir $RootDir))
        } else {
            $auto = New-AutoManifest -Path $dir.FullName -RootDir $RootDir
            if ($auto) { [void]$list.Add($auto) }
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $ToolsDir -File | Where-Object { $script:ScriptExts -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)) {
        [void]$list.Add((New-AutoManifest -Path $file.FullName -RootDir $RootDir))
    }

    # Trùng id thì thêm hậu tố để mỗi công cụ vẫn gọi được riêng.
    $seen = @{}
    foreach ($t in $list) {
        $id = $t.id
        if ($seen.ContainsKey($id)) {
            $n = 2
            while ($seen.ContainsKey("$id-$n")) { $n++ }
            $t.problems += "Trùng id '$id' với công cụ khác, tạm dùng '$id-$n'."
            $t.id = "$id-$n"
        }
        $seen[$t.id] = $true
    }
    return , $list.ToArray()
}

function ConvertTo-HubAction {
    param($Raw, [string]$ToolDir, [System.Collections.ArrayList]$Problems)
    $id = [string](Get-Prop $Raw 'id' '')
    $file = [string](Get-Prop $Raw 'file' '')
    $type = [string](Get-Prop $Raw 'type' 'console')
    $risk = [string](Get-Prop $Raw 'risk' 'modifies-system')
    $label = [string](Get-Prop $Raw 'label' $id)
    if (-not $id) { [void]$Problems.Add("Có action thiếu 'id'.") }
    if ($script:ValidTypes -notcontains $type) { [void]$Problems.Add("Action '$id': type '$type' không hợp lệ."); $type = 'console' }
    if ($script:ValidRisks -notcontains $risk) { [void]$Problems.Add("Action '$id': risk '$risk' không hợp lệ."); $risk = 'modifies-system' }

    $exists = $true
    if ($type -ne 'url') {
        if (-not $file) { [void]$Problems.Add("Action '$id' thiếu 'file'."); $exists = $false }
        else {
            $full = Expand-HubPath -Path $file -BaseDir $ToolDir
            if (-not (Test-PathInside -Path $full -Root $ToolDir)) { [void]$Problems.Add("Action '$id': file nằm ngoài thư mục công cụ."); $exists = $false }
            elseif (-not (Test-Path -LiteralPath $full)) { [void]$Problems.Add("Action '$id': không thấy file '$file'."); $exists = $false }
        }
    }

    # Tham số người dùng nhập khi bấm Chạy. Có 'flag' thì truyền "flag giá trị" (bool: chỉ flag), không thì truyền theo vị trí.
    $argsOut = @()
    $n = 0
    foreach ($a in @(Get-Prop $Raw 'args' @())) {
        $argType = [string](Get-Prop $a 'type' 'file')
        if ($script:ValidArgTypes -notcontains $argType) { [void]$Problems.Add("Action '$id': tham số kiểu '$argType' không hợp lệ."); $argType = 'text' }
        $argId = [string](Get-Prop $a 'id' "a$n")
        $flag = [string](Get-Prop $a 'flag' '')
        if ($flag -and $flag -notmatch '^--?[A-Za-z0-9][A-Za-z0-9_-]*$') { [void]$Problems.Add("Action '$id': flag '$flag' không hợp lệ."); $flag = '' }
        if ($argType -eq 'bool' -and -not $flag) { [void]$Problems.Add("Action '$id': tham số bật/tắt '$argId' cần 'flag'.") }
        $options = @()
        foreach ($o in @(Get-Prop $a 'options' @())) {
            if ($o -is [string]) { $options += [ordered]@{ value = $o; label = $o } }
            else { $options += [ordered]@{ value = [string](Get-Prop $o 'value' ''); label = [string](Get-Prop $o 'label' (Get-Prop $o 'value' '')) } }
        }
        $required = [bool](Get-Prop $a 'required' $false)
        if ($null -ne (Get-Prop $a 'optional' $null)) { $required = -not [bool](Get-Prop $a 'optional' $true) }
        $argsOut += [ordered]@{
            id          = $argId
            type        = $argType
            label       = [string](Get-Prop $a 'label' $(if ($argType -eq 'folder') { 'Chọn thư mục' } else { 'Chọn file' }))
            flag        = $flag
            required    = $required
            multiple    = [bool](Get-Prop $a 'multiple' $false)
            filter      = [string](Get-Prop $a 'filter' 'Tất cả|*.*')
            startIn     = [string](Get-Prop $a 'startIn' 'desktop')
            placeholder = [string](Get-Prop $a 'placeholder' '')
            help        = [string](Get-Prop $a 'help' '')
            default     = (Get-Prop $a 'default' $null)
            options     = $options
            min         = (Get-Prop $a 'min' $null)
            max         = (Get-Prop $a 'max' $null)
            # Tham số "Chạy thử": khi được chọn, trạm không tạo điểm khôi phục, không ghi trạng thái. Mặc định nhận
            # theo quy ước tham số bool có id 'chay-thu'.
            dryRun      = [bool](Get-Prop $a 'dryRun' ($argType -eq 'bool' -and $argId -eq 'chay-thu'))
        }
        $n++
    }

    # Điểm khôi phục hệ thống chỉ tạo được trong cửa sổ Admin mà trạm mở (.bat, .cmd, .ps1). Mặc định: có với
    # action đổi máy (modifies-system); tool.json đặt restorePoint true/false để bật, tắt riêng.
    $admin = [bool](Get-Prop $Raw 'admin' $false)
    $rpRaw = Get-Prop $Raw 'restorePoint' $null
    $canRp = $admin -and $type -eq 'console' -and ([IO.Path]::GetExtension($file).ToLowerInvariant() -in '.bat', '.cmd', '.ps1')
    if ($rpRaw -eq $true -and -not $canRp) { [void]$Problems.Add("Action '$id': restorePoint chỉ dùng được cho action console .bat, .cmd, .ps1 có admin: true.") }
    $restorePoint = $canRp -and $(if ($null -ne $rpRaw) { [bool]$rpRaw } else { $risk -eq 'modifies-system' })

    return [ordered]@{
        id           = $id
        label        = $label
        description  = [string](Get-Prop $Raw 'description' '')
        file         = $file
        url          = [string](Get-Prop $Raw 'url' '')
        type         = $type
        admin        = $admin
        selfElevates = [bool](Get-Prop $Raw 'selfElevates' $false)
        risk         = $risk
        restorePoint = $restorePoint
        primary      = [bool](Get-Prop $Raw 'primary' $false)
        duration     = [string](Get-Prop $Raw 'duration' '')
        keepOpen     = [bool](Get-Prop $Raw 'keepOpen' $false)
        confirm      = [string](Get-Prop $Raw 'confirm' '')
        changes      = @(Get-Prop $Raw 'changes' @())
        fixedArgs    = @(@(Get-Prop $Raw 'fixedArgs' @()) | ForEach-Object { [string]$_ })
        args         = $argsOut
        exists       = $exists
    }
}

function Read-ToolManifest {
    param([string]$ManifestPath, [string]$RootDir)
    $dir = Split-Path $ManifestPath -Parent
    $problems = New-Object System.Collections.ArrayList
    try { $m = Read-JsonFile $ManifestPath }
    catch {
        $err = "tool.json lỗi cú pháp: $($_.Exception.Message)"
        $fallback = New-AutoManifest -Path $dir -RootDir $RootDir
        if (-not $fallback) {
            # Thư mục không có script nào để đoán: vẫn hiện ra để người dùng biết tool.json đang hỏng.
            $name = Split-Path $dir -Leaf
            $fallback = [ordered]@{
                id = ConvertTo-Slug $name; name = $name; version = ''; category = 'chua-phan-loai'; icon = 'puzzle'; audience = 'tech'
                status = 'broken'; statusNote = ''; summary = 'tool.json bị lỗi, chưa đọc được.'; description = ''; tags = @(); author = ''
                docs = ''; hasDocs = $false; dir = $dir; relDir = $dir.Substring($RootDir.TrimEnd('\').Length).TrimStart('\')
                actions = @(); outputs = @(); requires = @(); probes = @(); pack = $null; notes = @(); issues = @(); upgrades = @()
                auto = $true; autoFile = ''; problems = @()
            }
        }
        $fallback.problems = @($err)
        return $fallback
    }

    $id = [string](Get-Prop $m 'id' '')
    if (-not $id) { $id = ConvertTo-Slug (Split-Path $dir -Leaf); [void]$problems.Add("tool.json thiếu 'id'.") }
    $actions = @()
    foreach ($a in @(Get-Prop $m 'actions' @())) { $actions += (ConvertTo-HubAction -Raw $a -ToolDir $dir -Problems $problems) }
    if ($actions.Count -eq 0) { [void]$problems.Add('tool.json chưa khai báo action nào.') }
    elseif (-not ($actions | Where-Object { $_.primary })) { $actions[0].primary = $true }

    $docs = [string](Get-Prop $m 'docs' '')
    $hasDocs = $false
    if ($docs) {
        $docsFull = Expand-HubPath -Path $docs -BaseDir $dir
        $hasDocs = (Test-PathInside -Path $docsFull -Root $dir) -and (Test-Path -LiteralPath $docsFull)
        if (-not $hasDocs) { [void]$problems.Add("Không thấy file hướng dẫn '$docs'.") }
    }

    return [ordered]@{
        id          = $id
        name        = [string](Get-Prop $m 'name' $id)
        version     = [string](Get-Prop $m 'version' '')
        category    = [string](Get-Prop $m 'category' 'chua-phan-loai')
        icon        = [string](Get-Prop $m 'icon' 'toolbox')
        audience    = [string](Get-Prop $m 'audience' 'all')
        status      = [string](Get-Prop $m 'status' 'ok')
        statusNote  = [string](Get-Prop $m 'statusNote' '')
        summary     = [string](Get-Prop $m 'summary' '')
        description = [string](Get-Prop $m 'description' '')
        tags        = @(Get-Prop $m 'tags' @())
        author      = [string](Get-Prop $m 'author' 'Wyatt')
        docs        = $docs
        hasDocs     = $hasDocs
        dir         = $dir
        relDir      = $dir.Substring($RootDir.TrimEnd('\').Length).TrimStart('\')
        actions     = $actions
        outputs     = @(Get-Prop $m 'outputs' @())
        requires    = @(Get-Prop $m 'requires' @())
        probes      = @(Get-Prop $m 'probes' @())
        pack        = (Get-Prop $m 'pack' $null)
        notes       = @(Get-Prop $m 'notes' @())
        issues      = @(Get-Prop $m 'issues' @())
        upgrades    = @(Get-Prop $m 'upgrades' @())
        auto        = $false
        problems    = @($problems)
    }
}

function New-AutoManifest {
    # Công cụ chưa có tool.json: liệt kê các script ở cấp ngoài cùng làm action.
    param([string]$Path, [string]$RootDir)
    $isFile = Test-Path -LiteralPath $Path -PathType Leaf
    if ($isFile) { $dir = Split-Path $Path -Parent; $files = @(Get-Item -LiteralPath $Path) }
    else {
        $dir = $Path
        $files = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $script:ScriptExts -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
    }
    if ($files.Count -eq 0) { return $null }

    $actions = @()
    $first = $true
    foreach ($f in $files) {
        $head = ''
        try { $head = (Get-Content -LiteralPath $f.FullName -TotalCount 80 -Encoding UTF8 -ErrorAction Stop) -join "`n" } catch { }
        $selfElevates = $head -match '(?i)net session|-Verb\s+RunAs|runas'
        $actions += [ordered]@{
            id = ConvertTo-Slug $f.BaseName; label = $f.Name; description = ''; file = $f.Name; url = ''; type = 'console'
            admin = $false; selfElevates = [bool]$selfElevates; risk = 'modifies-system'; primary = $first
            duration = ''; keepOpen = $true; confirm = ''; changes = @(); fixedArgs = @(); args = @(); exists = $true
        }
        $first = $false
    }

    $docs = ''
    if (-not $isFile) {
        $doc = Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '(?i)^(readme|huong[-_ ]?dan).*\.(md|txt)$' } | Select-Object -First 1
        if ($doc) { $docs = $doc.Name }
    }
    $name = if ($isFile) { [IO.Path]::GetFileNameWithoutExtension($Path) } else { Split-Path $dir -Leaf }
    return [ordered]@{
        id = ConvertTo-Slug $name; name = $name; version = ''; category = 'chua-phan-loai'; icon = 'puzzle'; audience = 'tech'; status = 'ok'; statusNote = ''
        summary = 'Chưa có mô tả. Bấm "Tạo tool.json" để đặt tên, nhóm và mức rủi ro cho công cụ này.'
        description = ''; tags = @(); author = ''; docs = $docs; hasDocs = [bool]$docs
        dir = $dir; relDir = $dir.Substring($RootDir.TrimEnd('\').Length).TrimStart('\')
        actions = $actions; outputs = @(); requires = @(); probes = @(); pack = $null; notes = @(); issues = @(); upgrades = @()
        auto = $true; autoFile = $(if ($isFile) { Split-Path $Path -Leaf } else { '' }); problems = @()
    }
}

function New-ToolManifestFile {
    # Sinh tool.json khởi đầu cho công cụ tự phát hiện (nút "Tạo tool.json").
    param($Tool)
    if (-not $Tool.auto) { throw 'Công cụ này đã có tool.json.' }
    $dir = $Tool.dir
    if ($Tool.autoFile) {
        # Script lẻ trong tools\ -> chuyển vào thư mục riêng trước.
        $newDir = Join-Path $dir $Tool.id
        if (Test-Path -LiteralPath $newDir) { throw "Thư mục '$($Tool.id)' đã tồn tại." }
        New-Item -ItemType Directory -Path $newDir | Out-Null
        Move-Item -LiteralPath (Join-Path $dir $Tool.autoFile) -Destination $newDir
        $dir = $newDir
    }
    $actions = @()
    foreach ($a in $Tool.actions) {
        $actions += [ordered]@{
            id = $a.id; label = $a.label; file = $a.file; type = 'console'; admin = $a.selfElevates
            risk = 'modifies-system'; primary = $a.primary; keepOpen = $true; description = ''
        }
    }
    $manifest = [ordered]@{
        '$schema' = '../../hub/schema/tool.schema.json'
        id = $Tool.id; name = $Tool.name; version = '1.0'; category = 'chua-phan-loai'; icon = 'toolbox'; audience = 'tech'
        summary = 'Mô tả ngắn công cụ này làm gì.'; tags = @(); docs = $Tool.docs; actions = $actions
    }
    $path = Join-Path $dir 'tool.json'
    Write-JsonFile -Path $path -InputObject $manifest
    return $path
}
