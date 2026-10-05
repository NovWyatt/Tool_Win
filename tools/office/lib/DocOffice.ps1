# Office - đọc hiện trạng, chỉ đọc: Office Click-to-Run, Office cài bằng MSI, Office từ Microsoft Store, giấy phép,
# dấu vết công cụ kích hoạt lậu, phần còn sót sau khi gỡ; đọc bộ cài mẫu (setup.exe và file cấu hình của
# Office Deployment Tool, gọi tắt ODT).
# Khoá sản phẩm: không đọc giá trị ProductKeys trong registry. Khoá trong file cấu hình và 5 ký tự cuối của khoá đã cài
# chỉ dùng để so khớp trong bộ nhớ (Get-KeyTailHash), không in, không ghi ra đâu.

$script:OfficeAppId = '0ff1ce15-a989-479d-af46-f275c6370663'
$script:C2RKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun'
$script:C2RConfigKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$script:OdtSafeVersion = [version]'16.0.19426.20170'   # setup.exe cũ hơn bản này có lỗ hổng CVE-2026-20943
$script:OdtDownload = 'https://www.microsoft.com/download/details.aspx?id=49117'
$script:MinFreeBytes = 4GB

# Kênh cập nhật đã đối chiếu với tài liệu Microsoft: GUID trong CDNBaseUrl → tên kênh trong file cấu hình.
# Kênh PerpetualVL2021, PerpetualVL2024 không có ở đây: nhận ra qua mã sản phẩm (ProPlus2021Volume...).
$script:Channels = @(
    [pscustomobject]@{ Guid = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'; Id = 'Current'; Label = 'Current (cập nhật hằng tháng)' }
    [pscustomobject]@{ Guid = '64256afe-f5d9-4f86-8936-8840a6a4f5be'; Id = 'CurrentPreview'; Label = 'Current Preview' }
    [pscustomobject]@{ Guid = '5440fd1f-7ecb-4221-8110-145efaa6372f'; Id = 'BetaChannel'; Label = 'Beta' }
    [pscustomobject]@{ Guid = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'; Id = 'MonthlyEnterprise'; Label = 'Monthly Enterprise' }
    [pscustomobject]@{ Guid = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'; Id = 'SemiAnnual'; Label = 'Semi-Annual Enterprise' }
    [pscustomobject]@{ Guid = 'b8f9b850-328d-4355-9145-c59439a0c4cf'; Id = 'SemiAnnualPreview'; Label = 'Semi-Annual Enterprise Preview' }
    [pscustomobject]@{ Guid = 'f2e724c1-748f-4b47-8fb8-8e0d210e9208'; Id = 'PerpetualVL2019'; Label = 'PerpetualVL2019 (Office 2019 bản Volume)' }
)
# Tên kênh cũ ODT vẫn nhận.
$script:ChannelAlias = @{
    'Monthly' = 'Current'; 'Insiders' = 'BetaChannel'; 'InsiderFast' = 'BetaChannel'; 'FirstReleaseCurrent' = 'CurrentPreview'
    'Broad' = 'SemiAnnual'; 'Deferred' = 'SemiAnnual'; 'Targeted' = 'SemiAnnualPreview'; 'FirstReleaseDeferred' = 'SemiAnnualPreview'
}

# Ứng dụng: tên trong ExcludeApp của ODT → (tên hiển thị, file chạy trong root\Office16).
$script:OfficeApps = [ordered]@{
    Word = @('Word', 'WINWORD.EXE'); Excel = @('Excel', 'EXCEL.EXE'); PowerPoint = @('PowerPoint', 'POWERPNT.EXE')
    Outlook = @('Outlook', 'OUTLOOK.EXE'); Access = @('Access', 'MSACCESS.EXE'); Publisher = @('Publisher', 'MSPUB.EXE')
    OneNote = @('OneNote', 'ONENOTE.EXE'); Lync = @('Skype for Business', 'lync.exe'); Groove = @('OneDrive for Business', 'GROOVE.EXE')
    Visio = @('Visio', 'VISIO.EXE'); Project = @('Project', 'WINPROJ.EXE')
}
$script:ExcludeNames = @{ Groove = 'OneDrive for Business (Groove)'; Lync = 'Skype for Business (Lync)'; OneDrive = 'OneDrive'; Teams = 'Teams'; Bing = 'Bing' }

# Khoá KMS chung (GVLK) Microsoft công bố cho bản Volume 2016-2024 (learn.microsoft.com/office/volume-license-activation/gvlks).
# Lưu dạng mã băm SHA256 của "tram-tool-office-gvlk:" + khoá để trong mã nguồn không có chuỗi giống khoá. Khoá trong mẫu
# trùng một khoá ở đây: Office chỉ tự kích hoạt được qua máy chủ KMS của tổ chức.
$script:GvlkHashes = @{
    '390C7E07FA2B909A4445030C38CE2E6F0D70319B1E83A6C4BBF4896E7D25BE02' = 'Office LTSC Professional Plus 2024'
    'D1BC0B84BDD606D94B311D1D21CA430CF03A3DBE2A2421EC192D8A29C4CECED0' = 'Office LTSC Standard 2024'
    '892ECBBBAE3F19620D34CAAC1720EE2CAA86E6954BE1F490BDC656238CD64FB4' = 'Project Professional 2024'
    '17594851D3C1AAF8A7D121D207655B7A3F03718A64710689455935B9B4A9CE8F' = 'Project Standard 2024'
    '3500E2EBF6F59914C82A6FD7C1E626C49833DFCBCF40718A4B00EA055BC95FE7' = 'Visio LTSC Professional 2024'
    'CD4C9E42B46EE27D4A922FF09B80827D1A0C8AC1777475D2E2B9C4D4602948E6' = 'Visio LTSC Standard 2024'
    '6BF7E5C3C9D33FC11A0751D52CA16D57D00B5D41E3DA4ABD3B7B64A70837A740' = 'Access LTSC 2024'
    '6A6E9472C4CE94E91DB567B47BD83452DD7C3595605DCC5282492807FFC8137B' = 'Excel LTSC 2024'
    '6AEA416C36EE2B508496F007639CE6D44125E670667A9240B6544D2468AC55F6' = 'Outlook LTSC 2024'
    '3A8748D141654D5DAA2FAC421D0A9BBF825D9E1C63A01C9EBD29BBC60920B91E' = 'PowerPoint LTSC 2024'
    'CCBA90A444FFB2BE03509014B46B88757D78249D2DB75518B2A8C3FD130CA6BA' = 'Skype for Business LTSC 2024'
    'C39FB72721DBAB3A0ECAE1E42ACB8F9EE45656196B8CDAEF633A8C173B239B03' = 'Word LTSC 2024'
    '5C027DE6969D27F912092C2E1389DD036FE78D9FC1AB86277E78DF38199C91D9' = 'Office LTSC Professional Plus 2021'
    '270F8135320D08AAA2DECF9BA1E1A970FB4705948C87A03DD7A7FBA58B8E756E' = 'Office LTSC Standard 2021'
    '01728F72290CDEED2E1DE4743B1749123CD58AB867EE006B65BEDD96D97CE730' = 'Project Professional 2021'
    '4D4EA57979FAFD845CC365010E580D84E03C62079C9ED34235357C1B8E707861' = 'Project Standard 2021'
    '08F79FD1E2DACC570C0FB504065E341F4B1E901EBB5052C1455270EB6999323C' = 'Visio LTSC Professional 2021'
    '4A69E54782238E5838030CDEC6BBE02CD4A67621354E531A4ECE48E26CE9B53E' = 'Visio LTSC Standard 2021'
    '4DD6496489D6E3F2A45677ADEB7A9342FDEA03EBDC8A5216EBE2D6EA6581B5D1' = 'Access LTSC 2021'
    'AF1B867EE04FCD700A49802808AA1045244C88147E3BE54BCF1023436868E525' = 'Excel LTSC 2021'
    '876DDD7CEC5C7D189B6E488462B8ADBDE6865C723D8A664324BAF0841168E466' = 'Outlook LTSC 2021'
    '3DCEE5DE4F1A5CC2A5909EA0DE9C9CE1620BBFAB596211B854F0080CC8FCE08C' = 'PowerPoint LTSC 2021'
    'BEAF34A4CF8D7783AE9E9859530DA07CD31469F8C3FEBBAEEB806C43232D0B06' = 'Publisher LTSC 2021'
    '9431E9FEBA18CABA25AEF52266185FF6BE2F8FD00C5D2917C5AC98F22912DF13' = 'Skype for Business LTSC 2021'
    '9591DD93267DD7872D64B484FE5D2E02800799C0F92CB7B1554682C06D8C5A88' = 'Word LTSC 2021'
    '1A1BE644B470D6AAACF96DFFD42C4EBD445D5EF9CB5E2A22D34FBEBB0755FD15' = 'Office Professional Plus 2019'
    'AA3323C40710DA5572F98C131C265E2E52654542329B292E6B18D801061CBF8B' = 'Office Standard 2019'
    '6706A1163B8261D5B927E8280BFE484F646CDEB287F24A1C84E1EAE3202D60CD' = 'Project Professional 2019'
    'C1C701A2A3AF2DBA53EBB607694005F193057026EED7DF9B15C9901FBB8C63B9' = 'Project Standard 2019'
    'EE664A20221A765BB6A71644083EF55FDFA9D3DECEEBDB292935BA33B4F67E91' = 'Visio Professional 2019'
    'EAA857DC84763E987175B71BA573052EF9A3DC34D68A25C981322CC631C6F0FD' = 'Visio Standard 2019'
    'C69D7AFBAD13F65EFF92027CE6031EA0C9F332D421D233BA5E0C0170504F5B8B' = 'Access 2019'
    'DC5E1C8EA992AF924352AF3130CD82492CB49CEAED80734C129178B73B645166' = 'Excel 2019'
    'F2D79FA30ED3948DDA5DD57922C014B164EF65D2DAA0302A8148C39B971C0A5E' = 'Outlook 2019'
    'C47DC858ADEA9842AD12FCCD3C6AEC7A7CB1B6BD5D62AE10CBA3374B7A31B92A' = 'PowerPoint 2019'
    '2D1F614251601FF2E589B5D9F225C65A14C7C94C2CFE45B9C10C48C41AE0B48E' = 'Publisher 2019'
    'A9618A2BA7058587EE65DD94D58B7BA20C64C715E2A81EDAE4D7539498E79D82' = 'Skype for Business 2019'
    'F81FB788640B784669C45E6E0A5905B9F69906AA97ADBEEE56917B83DE4BE921' = 'Word 2019'
    '1F2BD08D8BD3A0B899D30C7A5CEC022B5411943D42DE49A011D04BDE31796193' = 'Office Professional Plus 2016'
    '1D99F46A804C25C841322C55BB188FFD04EDE15AEFADCECF2D96BC627AE4CAE7' = 'Office Standard 2016'
    '067546B086F755296B15489D46C28B40D1699919903C5EDFE02C73977BB98A65' = 'Project Professional 2016'
    'FBABE2EE2AA75A23C4EF9CEB9BC1A3841263F97ADA0D255A0729F504E045B8E7' = 'Project Standard 2016'
    'FF646238012F855D4A0DEC16D6D1A312B51827ADF08D0E56A4D35CFC7894CA73' = 'Visio Professional 2016'
    '078CF41239D09540DB4C202B657736A2ECC6CA7193DD6A05B734D5CDF64FE2B4' = 'Visio Standard 2016'
    '9D18F582F68809FD6567F94D376F2C82040E62AA09D62A3A3427D15264035D6D' = 'Access 2016'
    'C6C6F8E63788D490522CA1E5B78B579E6E909B534CDE5843C3BEA5F0A09FEA54' = 'Excel 2016'
    '040D7BE6CECFA8BCA79ACCF380B0E6951D3F3195A6147EF0BE84181BDCAADECD' = 'OneNote 2016'
    '4FFF9D07CA3E4A1E0DFE7D6AEDA077394CA4F48D03F2B5C7B01CB229091BF190' = 'Outlook 2016'
    'F3E604D60167741F2092750F808B13F7433F18269E24D41776BA775670F1F04C' = 'PowerPoint 2016'
    'B75D4FE6F824F2EEA48C70AB484BB7F3D76DE63F6650B3ABFDE4A4A2CF55C688' = 'Publisher 2016'
    'D7F21CCB3925AFEBD151DDBF7E4A000D14FBC9F9C2A7EC78441A6EDDFBA9C370' = 'Skype for Business 2016'
    '5B3C91B29F8B296610D39398EDDF3ABE3CC720BBBAA387E01D84D1E1E705FB41' = 'Word 2016'
}

# Tiến trình Office cần đóng trước khi gỡ, cài, trả lại thiết lập.
$script:OfficeProcs = [ordered]@{
    WINWORD = 'Word'; EXCEL = 'Excel'; POWERPNT = 'PowerPoint'; OUTLOOK = 'Outlook'; MSACCESS = 'Access'; MSPUB = 'Publisher'
    ONENOTE = 'OneNote'; lync = 'Skype for Business'; GROOVE = 'OneDrive for Business'; VISIO = 'Visio'; WINPROJ = 'Project'
    MSOUC = 'Office Upload Center'; OIS = 'Office Picture Manager'; SETLANG = 'Office Language Preferences'; INFOPATH = 'InfoPath'
    GRAPH = 'Microsoft Graph'; MSOSYNC = 'Office Document Cache'; Teams = 'Teams (bản cũ)'
}

# ---------------------------------------------------------------- tên sản phẩm, vòng đời
function Get-ProductName {
    # ProPlus2019Volume → "Office Professional Plus 2019 (bản Volume)". Mã lạ thì trả nguyên mã.
    param([string]$Id)
    if ($Id -notmatch '^(?<sku>[A-Za-z0-9]+?)(?<year>2019|2021|2024)?(?<lic>Retail|Volume)$') { return $Id }
    $sku = $Matches.sku; $year = [string]$Matches.year; $lic = $Matches.lic
    $m365 = @{ O365ProPlus = 'Microsoft 365 Apps for enterprise'; O365Business = 'Microsoft 365 Apps for business'; O365HomePrem = 'Microsoft 365 Personal/Family'; O365SmallBusPrem = 'Microsoft 365 Business' }
    if ($m365.ContainsKey($sku)) { return $m365[$sku] }
    $suite = @{ ProPlus = 'Professional Plus'; Standard = 'Standard'; Professional = 'Professional'; HomeBusiness = 'Home & Business'; HomeStudent = 'Home & Student'; Personal = 'Personal' }
    $apps = @{
        VisioPro = 'Visio Professional'; VisioStd = 'Visio Standard'; ProjectPro = 'Project Professional'; ProjectStd = 'Project Standard'
        Word = 'Word'; Excel = 'Excel'; PowerPoint = 'PowerPoint'; Outlook = 'Outlook'; Access = 'Access'; Publisher = 'Publisher'
        AccessRuntime = 'Access Runtime'; SkypeforBusiness = 'Skype for Business'; SkypeforBusinessEntry = 'Skype for Business Basic'
    }
    if (-not $year) { $year = '2016' }
    $ltsc = ($lic -eq 'Volume' -and $year -in '2021', '2024')
    if ($suite.ContainsKey($sku)) { $name = $suite[$sku]; $prefix = if ($ltsc) { 'Office LTSC ' } else { 'Office ' } }
    elseif ($apps.ContainsKey($sku)) {
        # Cách Microsoft gọi: Visio LTSC Professional 2024, Word LTSC 2024, Project Professional 2024 (không có LTSC).
        $name = $apps[$sku]; $prefix = ''
        if ($ltsc -and $name -like 'Visio *') { $name = $name -replace '^Visio ', 'Visio LTSC ' }
        elseif ($ltsc -and $name -notlike 'Project *') { $name = "$name LTSC" }
    }
    else { return $Id }
    $suffix = if ($lic -eq 'Volume' -and -not $ltsc) { ' (bản Volume)' } else { '' }
    return ('{0}{1} {2}{3}' -f $prefix, $name, $year, $suffix)
}

function Get-ProductLifecycle {
    # Hạn hỗ trợ của Microsoft. Status: subscription (Microsoft 365), ended, soon (dưới 1 năm), ok, unknown.
    param([string]$Id = '', [int]$MsiMajor = 0)
    $year = ''
    if ($MsiMajor) { $year = @{ 16 = '2016'; 15 = '2013'; 14 = '2010'; 12 = '2007' }[$MsiMajor] }
    elseif ($Id -match '^O365') { return [pscustomobject]@{ Name = 'Microsoft 365'; End = $null; Status = 'subscription'; Text = 'Microsoft 365: được cập nhật khi dùng kênh còn hỗ trợ.' } }
    elseif ($Id -match '(2019|2021|2024)(Retail|Volume)$') { $year = $Matches[1] }
    elseif ($Id -match '(Retail|Volume)$') { $year = '2016' }
    $ends = @{ '2007' = '2017-10-10'; '2010' = '2020-10-13'; '2013' = '2023-04-11'; '2016' = '2025-10-14'; '2019' = '2025-10-14'; '2021' = '2026-10-13'; '2024' = '2029-10-09' }
    if (-not $year -or -not $ends.ContainsKey($year)) { return [pscustomobject]@{ Name = ''; End = $null; Status = 'unknown'; Text = '' } }
    $name = if ($Id -match 'Volume$' -and $year -in '2021', '2024') { "Office LTSC $year" } else { "Office $year" }
    $end = [datetime]::ParseExact($ends[$year], 'yyyy-MM-dd', $null)
    $today = (Get-Date).Date
    if ($today -gt $end) {
        return [pscustomobject]@{ Name = $name; End = $end; Status = 'ended'; Text = ('{0} đã hết hỗ trợ từ {1:dd/MM/yyyy}: không còn bản vá bảo mật.' -f $name, $end) }
    }
    $left = [int]($end - $today).TotalDays
    if ($left -le 365) {
        return [pscustomobject]@{ Name = $name; End = $end; Status = 'soon'; Text = ('{0} hết hỗ trợ ngày {1:dd/MM/yyyy} (còn {2} ngày).' -f $name, $end, $left) }
    }
    return [pscustomobject]@{ Name = $name; End = $end; Status = 'ok'; Text = ('{0} được hỗ trợ đến {1:dd/MM/yyyy}.' -f $name, $end) }
}

function Get-ChannelInfo {
    # Kênh từ URL (CDNBaseUrl/UpdateChannel) hoặc GUID. Không biết GUID thì đoán theo mã sản phẩm.
    param([string]$Url, [string[]]$Products = @())
    $guid = ''
    if ($Url -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = $Matches[1].ToLowerInvariant() }
    $known = $script:Channels | Where-Object { $_.Guid -eq $guid } | Select-Object -First 1
    if ($known) { return [pscustomobject]@{ Guid = $guid; Id = $known.Id; Label = $known.Label } }
    foreach ($p in $Products) {
        if ($p -match '(2021|2024)Volume$') { return [pscustomobject]@{ Guid = $guid; Id = "PerpetualVL$($Matches[1])"; Label = "PerpetualVL$($Matches[1]) (Office LTSC $($Matches[1]))" } }
    }
    $label = if ($guid) { "kênh khác ($guid)" } else { 'không rõ' }
    return [pscustomobject]@{ Guid = $guid; Id = ''; Label = $label }
}

function Resolve-ChannelId {
    # Tên kênh trong file cấu hình → tên chuẩn (đổi tên cũ như Monthly, Broad sang tên mới).
    param([string]$Name)
    if (-not $Name) { return '' }
    foreach ($k in $script:ChannelAlias.Keys) { if ($k -ieq $Name) { return $script:ChannelAlias[$k] } }
    foreach ($c in $script:Channels) { if ($c.Id -ieq $Name) { return $c.Id } }
    return $Name
}

function Get-ExpectedChannel {
    # Kênh hợp với sản phẩm: bản Volume 2019/2021/2024 đi kênh PerpetualVL cùng năm; bản khác không đi kênh PerpetualVL.
    param([string]$ProductId)
    if ($ProductId -match '(2019|2021|2024)Volume$') { return "PerpetualVL$($Matches[1])" }
    return ''
}

# ---------------------------------------------------------------- Office đang cài
function Get-OfficeApps {
    # Ứng dụng có file chạy trong <thư mục cài>\root\Office16.
    param([string]$InstallPath)
    if (-not $InstallPath) { return @() }
    $dir = Join-Path $InstallPath 'root\Office16'
    $found = foreach ($k in $script:OfficeApps.Keys) {
        if (Test-Path -LiteralPath (Join-Path $dir $script:OfficeApps[$k][1]) -PathType Leaf) { $k }
    }
    return @($found)
}

function Get-C2RInfo {
    # Office Click-to-Run, $null khi chưa cài. Chỉ đọc đúng các giá trị cần (không đọc ProductKeys).
    if (-not (Test-Path -LiteralPath $script:C2RConfigKey)) { return $null }
    $k = Get-Item -LiteralPath $script:C2RConfigKey
    $v = { param($n) $x = $k.GetValue($n); if ($null -eq $x) { '' } else { [string]$x } }
    $ids = @((& $v 'ProductReleaseIds') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $path = & $v 'InstallationPath'
    if (-not $path) { $path = [string](Get-RegValue $script:C2RKey 'InstallPath') }
    $url = & $v 'UpdateChannel'
    if (-not $url) { $url = & $v 'CDNBaseUrl' }
    return [pscustomobject]@{
        Products = $ids; Version = (& $v 'VersionToReport'); Platform = (& $v 'Platform'); Culture = (& $v 'ClientCulture')
        Channel = (Get-ChannelInfo $url $ids); InstallPath = $path; UpdatesEnabled = (& $v 'UpdatesEnabled')
        Apps = @(Get-OfficeApps $path)
    }
}

function Get-ArpOffice {
    # Mục Office trong "Gỡ cài đặt chương trình" (cả 64 và 32 bit). Kind:
    #   c2r      mục gỡ của Click-to-Run (OfficeClickToRun.exe)
    #   c2r-msi  thành phần MSI đi kèm Click-to-Run (ẩn, gỡ cùng Click-to-Run)
    #   suite    bộ Office cài bằng MSI (Office Setup Controller)
    #   msi      sản phẩm Office MSI lẻ (mã {9...0FF1CE})
    #   ace      Access Database Engine (phần mềm khác hay cần)
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    $list = New-Object System.Collections.ArrayList
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
            $name = [string]$key.GetValue('DisplayName')
            $un = [string]$key.GetValue('UninstallString')
            $code = $key.PSChildName
            $isOfficeCode = $code -match '(?i)^\{9[0-9A-F]{7}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{6}0FF1CE\}$'
            $kind = ''
            if ($un -match '(?i)OfficeClickToRun\.exe') { $kind = 'c2r' }
            elseif ($name -match '(?i)Access database engine' -or ($isOfficeCode -and $code -match '(?i)^\{9[0-9A-F]{7}-00D1-')) { $kind = 'ace' }
            elseif ($isOfficeCode -and ($code -match '(?i)^\{9[0-9A-F]{7}-(0060|008C|008F|007E|00FC|00DD)-' -or $name -match 'Click-to-Run')) { $kind = 'c2r-msi' }
            elseif ($un -match '(?i)Office Setup Controller') { $kind = 'suite' }
            elseif ($isOfficeCode -and [string]$key.GetValue('SystemComponent') -ne '1' -and $name) { $kind = 'msi' }
            if (-not $kind) { continue }
            $ver = [string]$key.GetValue('DisplayVersion')
            $major = 0
            if ($ver -match '^(\d+)\.') { $major = [int]$Matches[1] }
            elseif ($code -match '^Office(\d+)\.') { $major = [int]$Matches[1] }
            [void]$list.Add([pscustomobject]@{
                    Kind = $kind; Code = $code; Name = $(if ($name) { $name } else { $code }); Version = $ver; Major = $major
                    Uninstall = $un; Bits = $(if ($r -match 'WOW6432Node') { '32' } else { '64' }); RegPath = $key.PSPath
                })
        }
    }
    return @($list)
}

function Get-StoreOffice {
    # Office từ Microsoft Store (bản Desktop Bridge cũ). Không có quyền Admin thì chỉ thấy của tài khoản đang chạy.
    try {
        $p = if (Test-IsAdmin) { @(Get-AppxPackage -AllUsers -Name 'Microsoft.Office.Desktop*' -ErrorAction Stop) }
        else { @(Get-AppxPackage -Name 'Microsoft.Office.Desktop*' -ErrorAction Stop) }
        return @($p | Sort-Object PackageFullName -Unique | ForEach-Object { [pscustomobject]@{ Name = $_.Name; FullName = $_.PackageFullName; Version = [string]$_.Version } })
    } catch { return @() }
}

function Get-OfficeState {
    # Mọi thứ về Office đang có trên máy, đọc một lần.
    $arp = @(Get-ArpOffice)
    $c2r = Get-C2RInfo
    $state = [pscustomobject]@{
        C2R = $c2r
        C2RArp = @($arp | Where-Object { $_.Kind -eq 'c2r' })
        C2RMsi = @($arp | Where-Object { $_.Kind -eq 'c2r-msi' })
        Suites = @($arp | Where-Object { $_.Kind -eq 'suite' })
        Msi = @($arp | Where-Object { $_.Kind -eq 'msi' })
        Ace = @($arp | Where-Object { $_.Kind -eq 'ace' })
        Store = @(Get-StoreOffice)
    }
    $state | Add-Member -NotePropertyName Any -NotePropertyValue ([bool]($c2r -and $c2r.Products.Count) -or $state.C2RArp.Count -or $state.Suites.Count -or $state.Msi.Count -or $state.Store.Count)
    return $state
}

function Get-OfficeRunning {
    # Ứng dụng Office đang mở: @{ Name; Label; Count; Processes }.
    $list = foreach ($n in $script:OfficeProcs.Keys) {
        $ps = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        if ($ps.Count) { [pscustomobject]@{ Name = $n; Label = $script:OfficeProcs[$n]; Count = $ps.Count; Processes = $ps } }
    }
    return @($list)
}

# ---------------------------------------------------------------- giấy phép
function Get-KeyTailHash {
    # Băm 5 ký tự cuối của khoá để so khoá trong mẫu với khoá đã cài mà không phải giữ khoá. 5 ký tự dò ngược được từ
    # mã băm, nên mã băm cũng không in ra, không ghi đi đâu: chỉ dùng để so sánh trong bộ nhớ.
    param([string]$Key)
    $t = ([string]$Key).Trim().ToUpperInvariant()
    if ($t.Length -gt 5) { $t = $t.Substring($t.Length - 5) }
    if ($t.Length -ne 5) { return '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('tram-tool-office:' + $t)) } finally { $sha.Dispose() }
    return [BitConverter]::ToString($b).Replace('-', '')
}

function Test-IsGvlk {
    # Khoá là khoá KMS chung (GVLK) Microsoft công bố: so mã băm của cả khoá, không giữ khoá.
    param([string]$Key)
    $k = ([string]$Key).Trim().ToUpperInvariant()
    if (-not $k) { return $false }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('tram-tool-office-gvlk:' + $k)) } finally { $sha.Dispose() }
    return $script:GvlkHashes.ContainsKey([BitConverter]::ToString($b).Replace('-', ''))
}

function Test-KmsDiscoverable {
    # Có máy chủ KMS công bố trong DNS (bản ghi _vlmcs._tcp theo tên miền của máy, của mạng) không.
    $suffixes = @()
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PartOfDomain -and $cs.Domain) { $suffixes += [string]$cs.Domain }
    } catch { }
    try { $suffixes += @((Get-DnsClientGlobalSetting -ErrorAction Stop).SuffixSearchList) } catch { }
    try { $suffixes += @(Get-DnsClient -ErrorAction Stop | ForEach-Object { $_.ConnectionSpecificSuffix }) } catch { }
    foreach ($s in @($suffixes | Where-Object { $_ } | Sort-Object -Unique)) {
        try {
            $r = @(Resolve-DnsName -Name "_vlmcs._tcp.$s" -Type SRV -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.Type -eq 'SRV' })
            if ($r.Count) { return $true }
        } catch { }
    }
    return $false
}

function Get-OfficeLicenses {
    # Sản phẩm Office trong Windows (Software Protection) có cài khoá. KeyMatch: khoá đã cài trùng khoá trong mẫu.
    param([string[]]$TemplateKeyHashes = @())
    $flt = "ApplicationID='$script:OfficeAppId' AND PartialProductKey IS NOT NULL"
    $list = foreach ($p in @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $flt -ErrorAction Stop)) {
        $h = Get-KeyTailHash ([string]$p.PartialProductKey)
        [pscustomobject]@{
            Id = [string]$p.ID; Name = [string]$p.Name; Description = [string]$p.Description; Status = [int]$p.LicenseStatus
            GraceMinutes = [int64]$p.GracePeriodRemaining; Channel = [string]$p.ProductKeyChannel
            KmsHost = [string]$p.KeyManagementServiceMachine; KmsFound = [string]$p.DiscoveredKeyManagementServiceMachineName
            KeyMatch = [bool]($h -and $TemplateKeyHashes -contains $h)
        }
    }
    return @($list)
}

function Get-LicenseStatusText {
    param([int]$Status, [int64]$GraceMinutes = 0)
    $days = [Math]::Floor($GraceMinutes / 1440)
    switch ($Status) {
        0 { return 'Chưa kích hoạt' }
        1 { if ($GraceMinutes -gt 0) { return "Đã kích hoạt (còn $days ngày, phải gia hạn qua KMS)" } return 'Đã kích hoạt' }
        2 { return "Chưa kích hoạt, đang trong thời gian dùng thử (còn $days ngày)" }
        3 { return "Quá hạn gia hạn KMS, còn $days ngày" }
        4 { return 'Windows coi là không chính hãng' }
        5 { return 'Chưa kích hoạt, đã hết thời gian dùng thử (Office bị giới hạn tính năng)' }
        6 { return "Đang gia hạn thêm (còn $days ngày)" }
    }
    return "Trạng thái $Status"
}

function Get-LicenseChannelText {
    param([string]$Channel)
    switch -Regex ($Channel) {
        'MAK' { return 'khoá MAK (kích hoạt qua Internet)' }
        'GVLK' { return 'khoá KMS chung (kích hoạt qua máy chủ KMS của tổ chức)' }
        'Retail' { return 'khoá bán lẻ' }
        'OEM' { return 'khoá OEM' }
    }
    return $Channel
}

function Find-KmsTraces {
    # Dấu vết công cụ kích hoạt không chính thống (KMSpico, KMSAuto, AAct, giả lập KMS...). Chỉ báo, không xoá.
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($n in 'KMSELDI', 'Service_KMS', 'KMSpico', 'KMSAutoS', 'kms-service') {
        if (Get-Service -Name $n -ErrorAction SilentlyContinue) { $hits.Add("dịch vụ $n") }
    }
    $paths = @(
        "$env:ProgramFiles\KMSpico", "${env:ProgramFiles(x86)}\KMSpico", "$env:windir\KMSAutoS", "$env:ProgramData\KMSAutoS",
        "$env:ProgramData\KMSAuto", "$env:windir\AAct_Tools", "$env:ProgramData\AAct", "$env:windir\System32\SppExtComObjHook.dll",
        "$env:windir\System32\SECOH-QAD.exe", "$env:windir\System32\SECOH-QAD.dll"
    )
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { $hits.Add($p) } }
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -match '(?i)KMS|AutoPico|AAct|Activation-Renewal|Activation-Run_Once' })) {
            $hits.Add("tác vụ hẹn giờ $($t.TaskPath)$($t.TaskName)")
        }
    } catch { }
    $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SppExtComObj.exe'
    if ($null -ne (Get-RegValue $ifeo 'VerifierDlls') -or $null -ne (Get-RegValue $ifeo 'Debugger')) { $hits.Add('móc vào SppExtComObj.exe (giả lập KMS)') }
    return @($hits)
}

# ---------------------------------------------------------------- phần còn sót sau khi gỡ
function Get-OfficeBaseDirs {
    # Thư mục cài Click-to-Run có thể có: theo registry, và Program Files\Microsoft Office (64, 32 bit).
    param($State = $null)
    $dirs = @()
    if ($State -and $State.C2R -and $State.C2R.InstallPath) { $dirs += $State.C2R.InstallPath }
    $dirs += (Join-Path $env:ProgramFiles 'Microsoft Office')
    if (${env:ProgramFiles(x86)}) { $dirs += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office') }
    return @($dirs | ForEach-Object { $_.TrimEnd('\') } | Sort-Object -Unique)
}

function Test-C2RItem {
    # Mục trong thư mục Microsoft Office là của Click-to-Run: root, Updates, PackageManifests, PackageSunrisePolicies,
    # AppXManifest.xml, FileSystemMetadata.xml; Office16 chỉ khi bên trong toàn file OSPP, SLERROR.XML (Office cài bằng
    # MSI cũng cài vào Office16).
    param($Item)
    if (-not $Item.PSIsContainer) { return ($Item.Name -in 'AppXManifest.xml', 'FileSystemMetadata.xml') }
    if ($Item.Name -in 'root', 'Updates', 'PackageManifests', 'PackageSunrisePolicies') { return $true }
    if ($Item.Name -ne 'Office16') { return $false }
    $inside = @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue)
    return (-not @($inside | Where-Object { $_.PSIsContainer -or $_.Name -notmatch '^(?i)(OSPP\.(HTM|VBS)|OSPPREARM\.EXE|SLERROR\.XML)$' }).Count)
}

function Get-OfficeLeftovers {
    # Phần Click-to-Run còn trên máy: dịch vụ, tác vụ hẹn giờ, thư mục, khoá registry, mục gỡ cài đặt, thành phần MSI.
    # Chỉ dọn khi không còn Office nào. $State: Get-OfficeState (để biết thư mục cài theo registry).
    param($State = $null)
    $r = [ordered]@{ Service = $false; Tasks = @(); Folders = @(); Keys = @(); ArpKeys = @(); C2RMsi = @() }
    $r.Service = [bool](Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue)
    try { $r.Tasks = @(Get-ScheduledTask -TaskPath '\Microsoft\Office\*' -ErrorAction Stop | ForEach-Object { $_.TaskPath + $_.TaskName }) } catch { }
    $folders = @()
    foreach ($b in (Get-OfficeBaseDirs $State)) {
        # Cả thư mục Microsoft Office chỉ xoá khi bên trong toàn là của Click-to-Run; còn thứ khác (Office cài bằng MSI,
        # file của phần mềm khác) thì chỉ xoá các thư mục con của Click-to-Run.
        if (-not (Test-Path -LiteralPath $b -PathType Container)) { continue }
        $c2r = @(); $other = 0
        foreach ($i in @(Get-ChildItem -LiteralPath $b -Force -ErrorAction SilentlyContinue)) {
            if (Test-C2RItem $i) { $c2r += $i } else { $other++ }
        }
        if (-not $c2r.Count) { continue }
        if ($other) { $folders += @($c2r | Where-Object { $_.PSIsContainer } | ForEach-Object { $_.FullName }) }
        else { $folders += $b }
    }
    $more = @(
        (Join-Path $env:CommonProgramFiles 'Microsoft Shared\ClickToRun')
        (Join-Path $env:ProgramData 'Microsoft\ClickToRun')
        (Join-Path $env:ProgramData 'Microsoft\Office\ClickToRunPackageLocker')
    )
    if (${env:CommonProgramFiles(x86)}) { $more += (Join-Path ${env:CommonProgramFiles(x86)} 'Microsoft Shared\ClickToRun') }
    foreach ($m in $more) { if (Test-Path -LiteralPath $m -PathType Container) { $folders += $m } }
    $r.Folders = @($folders | Sort-Object -Unique)
    $r.Keys = @($script:C2RKey, 'HKLM:\SOFTWARE\Microsoft\AppVISV' | Where-Object { Test-Path -LiteralPath $_ })
    $arp = @(Get-ArpOffice)
    $r.ArpKeys = @($arp | Where-Object { $_.Kind -eq 'c2r' })
    $r.C2RMsi = @($arp | Where-Object { $_.Kind -eq 'c2r-msi' })
    $r.Any = [bool]($r.Service -or $r.Tasks.Count -or $r.Folders.Count -or $r.Keys.Count -or $r.ArpKeys.Count -or $r.C2RMsi.Count)
    return [pscustomobject]$r
}

function Test-OfficeRebootPending {
    # Windows còn chờ khởi động lại để xoá, thay file của Office (sau khi gỡ). Cài Office lúc này dễ lỗi.
    $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
    foreach ($line in @($v)) { if ([string]$line -match '(?i)Microsoft Office|ClickToRun|Microsoft Shared\\OFFICE1') { return $true } }
    return $false
}

# ---------------------------------------------------------------- bộ cài mẫu
function Format-FolderArg {
    # 'E:', 'E:\', 'E:\.' → 'E:\.' để truyền qua dòng lệnh không vỡ dấu ngoặc ("E:\" thành E:"); bỏ '\' cuối của thư mục khác.
    param([string]$Path)
    $p = ([string]$Path).Trim().Trim('"')
    if (-not $p) { return '' }
    if ($p -match '^([A-Za-z]):(\\\.?)?$') { return ($Matches[1].ToUpperInvariant() + ':\.') }
    return $p.TrimEnd('\')
}

function Find-TemplateDir {
    # Thư mục bộ cài mẫu (có setup.exe): -Mau, rồi thư mục mau\ của công cụ, rồi "<ổ>:\Program Files\Microsoft Office"
    # trên các ổ cứng, USB (chỗ hay để mẫu). -Mau là file setup.exe hay file .xml thì lấy thư mục chứa nó.
    param([string]$Given = '')
    if ($Given) {
        $g = $Given.Trim().Trim('"')
        if (Test-Path -LiteralPath $g -PathType Leaf) { return [IO.Path]::GetDirectoryName($g) }
        return $g
    }
    $cands = @(Join-Path $script:ToolDir 'mau')
    foreach ($d in @([IO.DriveInfo]::GetDrives())) {
        try { if (-not $d.IsReady -or [string]$d.DriveType -notin 'Fixed', 'Removable') { continue } } catch { continue }
        $cands += (Join-Path $d.RootDirectory.FullName 'Program Files\Microsoft Office')
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath (Join-Path $c 'setup.exe') -PathType Leaf) { return $c } }
    return ''
}

function Read-OdtXml {
    # Đọc file cấu hình ODT (không tải DTD hay file ngoài). Lỗi định dạng thì ném lỗi, câu báo không chứa nội dung file.
    param([string]$Path)
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try {
        $doc = New-Object Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.Load($reader)
        return $doc
    } finally { $reader.Dispose() }
}

function Test-OdtInstallConfig {
    # File .xml là cấu hình cài đặt của ODT (gốc <Configuration> có <Add>).
    param([string]$Path)
    try {
        $doc = Read-OdtXml $Path
        return ($doc.DocumentElement.Name -eq 'Configuration' -and $null -ne $doc.DocumentElement.SelectSingleNode('Add'))
    } catch { return $false }
}

function Select-TemplateConfig {
    # File cấu hình dùng để cài: -CauHinh (tên file trong mẫu, hoặc đường dẫn đầy đủ), không có thì Configuration.xml,
    # không có nữa thì file cấu hình cài đặt duy nhất trong mẫu. Nhiều file mà chưa chọn: trả danh sách để hỏi.
    param([string]$Dir, [string]$Name = '')
    if ($Name) {
        $p = if ([IO.Path]::IsPathRooted($Name)) { $Name } else { Join-Path $Dir $Name }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return [pscustomobject]@{ Path = ''; Candidates = @(); Problem = "Không thấy file cấu hình '$Name'." } }
        return [pscustomobject]@{ Path = $p; Candidates = @(); Problem = '' }
    }
    # Configuration.xml dùng luôn kể cả khi hỏng (để báo lỗi của chính nó); file khác phải là cấu hình cài đặt đọc được.
    $main = Join-Path $Dir 'Configuration.xml'
    if (Test-Path -LiteralPath $main -PathType Leaf) { return [pscustomobject]@{ Path = $main; Candidates = @(); Problem = '' } }
    $cfgs = @(Get-ChildItem -LiteralPath $Dir -Filter '*.xml' -File -ErrorAction SilentlyContinue | Where-Object { Test-OdtInstallConfig $_.FullName })
    if ($cfgs.Count -eq 1) { return [pscustomobject]@{ Path = $cfgs[0].FullName; Candidates = @(); Problem = '' } }
    if (-not $cfgs.Count) { return [pscustomobject]@{ Path = ''; Candidates = @(); Problem = 'Mẫu không có file cấu hình cài đặt (.xml có thẻ <Add>).' } }
    return [pscustomobject]@{ Path = ''; Candidates = @($cfgs | ForEach-Object { $_.Name }); Problem = 'Mẫu có nhiều file cấu hình, chưa chọn file nào.' }
}

function Expand-VersionDescriptor {
    # Lấy VersionDescriptor.xml trong v64.cab/v32.cab của bộ cài: bản dựng, kênh (FFNRoot), sản phẩm có trong bộ cài.
    param([string]$Cab)
    $tmp = Join-Path $env:TEMP ('TramTool_Office_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $tmp -Force)
    try {
        [void](Invoke-Native 'expand.exe' @($Cab, '-F:VersionDescriptor.xml', $tmp))
        $f = Join-Path $tmp 'VersionDescriptor.xml'
        if (-not (Test-Path -LiteralPath $f)) {
            # cab chỉ có một file thì expand.exe đặt tên file giải nén theo tên cab
            $one = @(Get-ChildItem -LiteralPath $tmp -File)
            if ($one.Count -ne 1) { return $null }
            $f = $one[0].FullName
        }
        $doc = Read-OdtXml $f
        $root = $doc.DocumentElement
        $avail = $root.SelectSingleNode('Available')
        $ffn = $root.SelectSingleNode('DeliveryMechanism')
        return [pscustomobject]@{
            Build = $(if ($avail) { $avail.GetAttribute('Build') } else { '' })
            Ffn = $(if ($ffn) { $ffn.GetAttribute('FFNRoot').ToLowerInvariant() } else { '' })
            Products = @($root.SelectNodes('ProductReleaseIds/ProductReleaseId') | ForEach-Object { $_.GetAttribute('Name') })
        }
    } catch { return $null }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-LanguageList {
    # Ngôn ngữ cần có trong bộ cài: MatchOS → ngôn ngữ giao diện Windows; MatchInstalled, MatchPreviousMSI bỏ qua.
    param([string[]]$Languages)
    $out = foreach ($l in $Languages) {
        if ($l -ieq 'MatchOS') { [Globalization.CultureInfo]::InstalledUICulture.Name.ToLowerInvariant() }
        elseif ($l -match '^(?i)Match') { continue }
        else { $l.ToLowerInvariant() }
    }
    return @($out | Sort-Object -Unique)
}

function Read-OfficeTemplate {
    # Đọc và kiểm tra bộ cài mẫu. Problems: lỗi chặn việc cài. Warnings: nên biết trước khi cài. Không in gì.
    param([string]$Dir, [string]$Config = '')
    $t = [ordered]@{
        Dir = $Dir; Setup = ''; SetupVersion = ''; SetupSigned = $false; Config = ''; ConfigName = ''; Candidates = @()
        Products = @(); Edition = '64'; Channel = ''; Version = ''; SourcePath = ''; CdnFallback = $false; AutoActivate = $false
        RemoveMSI = $false; HasRemove = $false; UpdatesEnabled = ''; DisplayLevel = ''; LogPath = ''; KeyHashes = @(); Source = $null
        KeyKind = ''   # gvlk: chỉ có khoá KMS chung; key: có khoá riêng (MAK, bán lẻ); '': không có khoá
        Problems = New-Object System.Collections.Generic.List[string]; Warnings = New-Object System.Collections.Generic.List[string]
    }
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) {
        $t.Problems.Add($(if ($Dir) { "Không thấy thư mục mẫu '$Dir'." } else { 'Không thấy bộ cài mẫu.' }))
        return [pscustomobject]$t
    }
    $t.Dir = (Resolve-Path -LiteralPath $Dir).ProviderPath.TrimEnd('\')

    # setup.exe: phải có chữ ký số hợp lệ của Microsoft.
    $setup = Join-Path $t.Dir 'setup.exe'
    if (Test-Path -LiteralPath $setup -PathType Leaf) {
        $t.Setup = $setup
        $t.SetupVersion = [string](Get-Item -LiteralPath $setup).VersionInfo.FileVersion
        $sig = Get-AuthenticodeSignature -LiteralPath $setup
        $t.SetupSigned = ([string]$sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'CN=Microsoft Corporation')
        if (-not $t.SetupSigned) { $t.Problems.Add('setup.exe trong mẫu không có chữ ký số hợp lệ của Microsoft: không chạy file này.') }
        $ver = $null
        if ([version]::TryParse(($t.SetupVersion -replace '[^0-9.].*$', ''), [ref]$ver) -and $ver -lt $script:OdtSafeVersion) {
            $t.Warnings.Add("setup.exe (ODT) bản $($t.SetupVersion) cũ, có lỗ hổng CVE-2026-20943: tải ODT mới ở $script:OdtDownload rồi chép đè setup.exe trong mẫu.")
        }
    } else {
        $t.Problems.Add('Mẫu không có setup.exe (Office Deployment Tool).')
    }

    # File cấu hình.
    $sel = Select-TemplateConfig $t.Dir $Config
    $t.Candidates = $sel.Candidates
    if (-not $sel.Path) { $t.Problems.Add($sel.Problem); return [pscustomobject]$t }
    $t.Config = $sel.Path
    $t.ConfigName = Split-Path -Leaf $sel.Path
    try { $doc = Read-OdtXml $t.Config }
    catch { $t.Problems.Add("File cấu hình $($t.ConfigName) lỗi định dạng XML."); return [pscustomobject]$t }
    $root = $doc.DocumentElement
    $add = if ($root.Name -eq 'Configuration') { $root.SelectSingleNode('Add') } else { $null }
    if (-not $add) { $t.Problems.Add("$($t.ConfigName) không phải cấu hình cài đặt (thiếu thẻ <Add>)."); return [pscustomobject]$t }

    if ($add.GetAttribute('OfficeClientEdition') -eq '32') { $t.Edition = '32' }
    $t.Channel = $add.GetAttribute('Channel')
    $t.Version = $add.GetAttribute('Version')
    $t.SourcePath = $add.GetAttribute('SourcePath')
    $t.CdnFallback = ($add.GetAttribute('AllowCdnFallback') -ieq 'TRUE')
    $hashes = @()
    $t.Products = @(foreach ($p in @($add.SelectNodes('Product'))) {
            $key = $p.GetAttribute('PIDKEY')
            $h = if ($key) { Get-KeyTailHash $key } else { '' }
            if ($h) { $hashes += $h }
            $gvlk = [bool]($key -and (Test-IsGvlk $key))
            $key = $null
            [pscustomobject]@{
                Id = $p.GetAttribute('ID'); HasKey = [bool]$h; Gvlk = $gvlk
                Languages = @($p.SelectNodes('Language') | ForEach-Object { $_.GetAttribute('ID') } | Where-Object { $_ })
                Exclude = @($p.SelectNodes('ExcludeApp') | ForEach-Object { $_.GetAttribute('ID') } | Where-Object { $_ })
            }
        })
    $t.KeyHashes = $hashes
    $withKey = @($t.Products | Where-Object { $_.HasKey })
    if ($withKey.Count) { $t.KeyKind = if (@($withKey | Where-Object { -not $_.Gvlk }).Count) { 'key' } else { 'gvlk' } }
    elseif (@($t.Products | Where-Object { $_.Id -match 'Volume$' }).Count) { $t.KeyKind = 'gvlk' }   # bản Volume không ghi khoá: ODT tự cài khoá KMS chung
    foreach ($prop in @($root.SelectNodes('Property'))) {
        $n = $prop.GetAttribute('Name'); $v = $prop.GetAttribute('Value')
        if ($n -ieq 'AUTOACTIVATE') { $t.AutoActivate = ($v -in '1', 'TRUE', 'true') }
    }
    $t.RemoveMSI = ($null -ne $root.SelectSingleNode('RemoveMSI'))
    $t.HasRemove = ($null -ne $root.SelectSingleNode('Remove'))
    $u = $root.SelectSingleNode('Updates')
    if ($u) { $t.UpdatesEnabled = $u.GetAttribute('Enabled') }
    $d = $root.SelectSingleNode('Display')
    if ($d) { $t.DisplayLevel = $d.GetAttribute('Level') }
    $lg = $root.SelectSingleNode('Logging')
    if ($lg) { $t.LogPath = $lg.GetAttribute('Path') }
    $doc = $null; $root = $null; $add = $null

    if (-not $t.Products.Count) { $t.Problems.Add("$($t.ConfigName) không có sản phẩm nào (thẻ <Product>).") }
    if ($t.KeyKind -eq 'gvlk') {
        $t.Warnings.Add('Mẫu chỉ có khoá KMS chung (GVLK) Microsoft công bố cho bản Volume: Office chỉ tự kích hoạt khi máy nối mạng có máy chủ KMS của tổ chức. Không có thì sau khi cài phải nhập khoá MAK hoặc khoá bản quyền khác (công cụ hỏi ở bước kích hoạt).')
    }
    if ($t.HasRemove) { $t.Warnings.Add("$($t.ConfigName) có thẻ <Remove>: ODT sẽ gỡ sản phẩm ghi trong đó trước khi cài.") }
    if ($t.Edition -eq '64' -and -not [Environment]::Is64BitOperatingSystem) { $t.Problems.Add('Mẫu cài Office 64 bit nhưng Windows trên máy là 32 bit.') }

    # Kênh hợp với sản phẩm.
    $chan = Resolve-ChannelId $t.Channel
    foreach ($p in $t.Products) {
        $want = Get-ExpectedChannel $p.Id
        if ($want -and $chan -and $chan -ne $want) { $t.Warnings.Add("$($p.Id) đi kênh $want nhưng file cấu hình ghi kênh $($t.Channel): ODT có thể báo lỗi.") }
        if (-not $want -and $chan -like 'PerpetualVL*') { $t.Warnings.Add("$($p.Id) không phải bản Volume nhưng file cấu hình ghi kênh $($t.Channel).") }
    }

    # Bộ cài có sẵn trong mẫu (Office\Data): đủ thì cài không cần Internet.
    $t.Source = Test-TemplateSource ([pscustomobject]$t)
    if (-not $t.Source.Complete) {
        foreach ($m in $t.Source.Missing) { $t.Warnings.Add($m) }
    }
    return [pscustomobject]$t
}

function Test-TemplateSource {
    # Kiểm tra bộ cài trong mẫu khớp file cấu hình: bản dựng, kênh, sản phẩm, ngôn ngữ, 32/64 bit.
    # Thiếu gì thì ODT tải phần đó từ Internet (hoặc báo lỗi khi không có mạng).
    param($T)
    $s = [ordered]@{ Base = ''; Online = $false; Build = ''; Channel = $null; Size = [int64]0; Complete = $false; Missing = (New-Object System.Collections.Generic.List[string]) }
    $base = if ($T.SourcePath) { $T.SourcePath } else { $T.Dir }
    $s.Base = $base
    if ($base -match '^(?i)https?://') {
        $s.Online = $true
        $s.Missing.Add('Bộ cài lấy từ địa chỉ mạng trong file cấu hình (SourcePath): cần mạng khi cài.')
        return [pscustomobject]$s
    }
    $arch = if ($T.Edition -eq '32') { 'x86' } else { 'x64' }
    $cab = Join-Path $base ('Office\Data\v{0}.cab' -f $T.Edition)
    $online = 'ODT sẽ tải Office từ Internet khi cài (vài GB).'
    if (-not (Test-Path -LiteralPath $cab -PathType Leaf)) {
        $s.Missing.Add("Mẫu không có sẵn bộ cài Office $($T.Edition) bit (Office\Data\v$($T.Edition).cab): $online")
        return [pscustomobject]$s
    }
    $vd = Expand-VersionDescriptor $cab
    if (-not $vd -or -not $vd.Build) {
        $s.Missing.Add("Không đọc được v$($T.Edition).cab trong mẫu (file hỏng?): $online")
        return [pscustomobject]$s
    }
    $s.Build = if ($T.Version) { $T.Version } else { $vd.Build }
    $s.Channel = Get-ChannelInfo $vd.Ffn @($T.Products | ForEach-Object { $_.Id })
    $verDir = Join-Path $base ('Office\Data\' + $s.Build)
    if (-not (Test-Path -LiteralPath $verDir -PathType Container)) {
        $s.Missing.Add("Mẫu không có bộ cài bản $($s.Build) (Office\Data\$($s.Build)): $online")
        return [pscustomobject]$s
    }
    $s.Size = (Get-FolderSize $verDir).Bytes
    if (-not (Test-Path -LiteralPath (Join-Path $verDir "stream.$arch.x-none.dat") -PathType Leaf)) {
        $s.Missing.Add("Bộ cài trong mẫu thiếu file chính stream.$arch.x-none.dat (chép dở?): $online")
    }
    $langs = Get-LanguageList @($T.Products | ForEach-Object { $_.Languages })
    foreach ($l in $langs) {
        if (-not (Test-Path -LiteralPath (Join-Path $verDir "stream.$arch.$l.dat") -PathType Leaf)) {
            $s.Missing.Add("Bộ cài trong mẫu không có ngôn ngữ $l`: ODT sẽ tải phần ngôn ngữ này từ Internet.")
        }
    }
    foreach ($p in $T.Products) {
        if ($vd.Products.Count -and $vd.Products -notcontains $p.Id) { $s.Missing.Add("Bộ cài trong mẫu không có $($p.Id): $online") }
    }
    $want = Resolve-ChannelId $T.Channel
    $wantGuid = ($script:Channels | Where-Object { $_.Id -eq $want } | Select-Object -First 1).Guid
    if ($wantGuid -and $vd.Ffn -and $wantGuid -ne $vd.Ffn) {
        $s.Missing.Add("Bộ cài trong mẫu thuộc kênh $($s.Channel.Label), file cấu hình ghi kênh $($T.Channel): $online")
    }
    $s.Complete = ($s.Missing.Count -eq 0)
    return [pscustomobject]$s
}

function Test-TemplateInsideOffice {
    # Mẫu nằm trong thư mục cài Office (sẽ bị xoá khi gỡ).
    param($T, $State)
    foreach ($b in (Get-OfficeBaseDirs $State)) {
        if ($T.Dir -and ($T.Dir.TrimEnd('\') + '\').StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-Internet {
    # Có tới được máy chủ tải Office của Microsoft không (bất kỳ phản hồi HTTP nào cũng tính là có mạng).
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $req = [Net.WebRequest]::Create('https://officecdn.microsoft.com/')
        $req.Method = 'HEAD'; $req.Timeout = 10000
        $resp = $req.GetResponse(); $resp.Close()
        return $true
    } catch [Net.WebException] {
        return ($null -ne $_.Exception.Response)
    } catch { return $false }
}

function Get-FreeSpace {
    # Dung lượng trống ổ Windows (byte).
    try { return [int64]([IO.DriveInfo]::new($env:SystemDrive)).AvailableFreeSpace } catch { return [int64]-1 }
}
