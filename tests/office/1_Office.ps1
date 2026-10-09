# Kiểm thử giả lập cho tools\office. Không đổi máy thật: lệnh hệ thống (gỡ, cài, registry, dịch vụ, giấy phép,
# tiến trình) được thay bằng hàm giả; dữ liệu người dùng, Program Files, ProgramData, TEMP đều trỏ vào tests\.tam.
# setup.exe trong mẫu giả là bản chép của một file .exe có chữ ký Microsoft (Edge) và không bao giờ được chạy:
# Start-Process là hàm giả. Mẫu thật của bạn (file cấu hình có khoá sản phẩm) không được đọc tới.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$repo = "$ToolsDir\office"
$sp = Join-Path $TestRoot 'mock'
[void](New-Item -ItemType Directory -Path $sp)

function Find-MicrosoftSignedExe {
    # File .exe nhỏ nhất có chữ ký số hợp lệ "CN=Microsoft Corporation" trong thư mục Edge (máy Windows 10/11 nào cũng có)
    $dirs = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application", "$env:ProgramFiles\Microsoft\Edge\Application") | Where-Object { Test-Path -LiteralPath $_ }
    $exes = @($dirs | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue } | Sort-Object Length)
    foreach ($f in ($exes | Select-Object -First 8)) {
        $s = Get-AuthenticodeSignature -LiteralPath $f.FullName
        if ([string]$s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -match 'CN=Microsoft Corporation') { return $f.FullName }
    }
    return $null
}
$realTemplateSetup = Find-MicrosoftSignedExe
if (-not $realTemplateSetup) {
    Skip-Test 'không thấy file .exe có chữ ký Microsoft (Edge) để làm setup.exe giả'
    Complete-Test
}

$env:APPDATA = "$sp\appdata"; $env:LOCALAPPDATA = "$sp\localappdata"; $env:TEMP = "$sp\temp"; $env:TMP = "$sp\temp"
$env:ProgramFiles = "$sp\pf"; ${env:ProgramFiles(x86)} = "$sp\pf86"; $env:CommonProgramFiles = "$sp\pf\Common Files"
${env:CommonProgramFiles(x86)} = "$sp\pf86\Common Files"; $env:ProgramData = "$sp\pd"
foreach ($d in $env:APPDATA, $env:LOCALAPPDATA, $env:TEMP, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) { [void](New-Item -ItemType Directory -Path $d -Force) }

$script:ToolDir = "$sp\tool"
[void](New-Item -ItemType Directory -Path $script:ToolDir)
$script:ToolVersion = '1.0-thu'
. "$repo\lib\Chung.ps1"
. "$repo\lib\DocOffice.ps1"
. "$repo\lib\SaoLuu.ps1"
. "$repo\lib\GoOffice.ps1"
. "$repo\lib\CaiOffice.ps1"
. "$repo\lib\KiemTra.ps1"
$script:Modes = [ordered]@{
    'kiem-tra' = @{ No = 1; Label = 'Kiểm tra' }; 'go-va-cai' = @{ No = 2; Label = 'Gỡ và cài' }; 'go-sach' = @{ No = 3; Label = 'Gỡ sạch' }
    'cai-dat' = @{ No = 4; Label = 'Cài' }; 'kich-hoat' = @{ No = 5; Label = 'Kích hoạt' }; 'tra-lai' = @{ No = 6; Label = 'Trả lại' }
}

# ---------------------------------------------------------------- khung kiểm thử
function Say([string]$s) { [Console]::WriteLine($s) }
$global:Calls = New-Object System.Collections.ArrayList
function Log-Call([string]$s) { [void]$global:Calls.Add($s) }
function Calls-Like([string]$re) { return @($global:Calls | Where-Object { $_ -match $re }) }
function Reset-Test {
    $global:Calls.Clear(); $script:Report.Clear(); $script:Findings.Clear(); $global:Answers.Clear()
    $global:ProcPlan = @{}; $global:ProcOutput = ''
}
function Report-Text { return ($script:Report -join "`n") }

function Write-Host { }   # công cụ in qua Write-Host: im lặng, nội dung vẫn vào $script:Report

# ---------------------------------------------------------------- hàm giả
$global:Answers = New-Object System.Collections.Queue
function Test-NoInput { return $false }
function Read-Host {
    param([Parameter(Position = 0)][string]$Prompt, [switch]$AsSecureString)
    if ($global:Answers.Count -eq 0) { throw "Không có câu trả lời soạn sẵn cho: $Prompt" }
    $a = [string]$global:Answers.Dequeue()
    if ($AsSecureString) { Log-Call "ASK-SECRET: $Prompt"; return (ConvertTo-SecureString $a -AsPlainText -Force) }
    Log-Call "ASK: $Prompt => $a"
    return $a
}
function Answer([string[]]$a) { foreach ($x in $a) { $global:Answers.Enqueue($x) } }
function Start-Sleep { param($Seconds, $Milliseconds) Log-Call "SLEEP $Seconds" }

$global:ProcPlan = @{}; $global:ProcOutput = ''; $global:AfterInstallHook = $false
function Start-Process {
    param([Parameter(Position = 0)][string]$FilePath, [Parameter(Position = 1)]$ArgumentList, [string]$WorkingDirectory, [switch]$PassThru, [switch]$Wait,
        [switch]$NoNewWindow, [string]$RedirectStandardOutput, [string]$RedirectStandardError, [string]$Verb, [string]$WindowStyle)
    $argText = if ($ArgumentList -is [array]) { $ArgumentList -join ' ' } else { [string]$ArgumentList }
    Log-Call "START: $FilePath | $argText | wd=$WorkingDirectory"
    if ($argText -match '/configure "([^"]+)"' -and $Matches[1] -like '*GoOffice.xml') { Copy-Item -LiteralPath $Matches[1] -Destination "$sp\GoOffice.captured.xml" -Force }
    if ($global:AfterInstallHook -and $argText -match '/configure ".*Configuration\.xml"') {
        # ODT cài xong thì Windows có khoá trong mẫu, đã kích hoạt
        [void]$global:Spp.Add((New-SppProduct 'prod-new' 'Office 19, Office19ProPlus2019VL_MAK_AE edition' 'QWXYZ' 1 'Volume:MAK'))
    }
    $code = 0
    foreach ($k in $global:ProcPlan.Keys) { if ("$FilePath $argText" -match $k) { $code = [int]$global:ProcPlan[$k] } }
    $cmdArgs = "/c exit $code"
    if ($RedirectStandardOutput) {
        if ($global:ProcOutput) { $cmdArgs = "/c echo $($global:ProcOutput)& exit $code" }
        $p = Microsoft.PowerShell.Management\Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -PassThru -NoNewWindow -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError
    } else {
        $p = Microsoft.PowerShell.Management\Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -PassThru -WindowStyle Hidden
    }
    if ($Wait) { $p.WaitForExit() }
    if ($PassThru) { return $p }
}

$global:RealInvokeNative = ${function:Invoke-Native}
$global:CmdkeyList = ''
function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList = @())
    Log-Call ("NATIVE: {0} {1}" -f $FilePath, ($ArgumentList -join ' '))
    switch -Regex ($FilePath) {
        'robocopy|expand' { return (& $global:RealInvokeNative $FilePath $ArgumentList) }
        'reg\.exe' {
            if ($ArgumentList[0] -eq 'export') { [IO.File]::WriteAllText($ArgumentList[2], 'Windows Registry Editor Version 5.00') }
            return [pscustomobject]@{ Code = 0; Output = '' }
        }
        'cmdkey' {
            if ($ArgumentList[0] -eq '/list') { return [pscustomobject]@{ Code = 0; Output = $global:CmdkeyList } }
            return [pscustomobject]@{ Code = $(if ($ArgumentList[0] -like '/delete:LegacyGeneric:*') { 0 } else { 1 }); Output = '' }
        }
        'sc\.exe' { return [pscustomobject]@{ Code = 0; Output = '' } }
        'GetHelpCmd' {
            if ($ArgumentList[0] -eq '-DisplayEULA') { [IO.File]::WriteAllText($ArgumentList[1], 'EULA giả') }
            return [pscustomobject]@{ Code = 0; Output = '' }
        }
    }
    return [pscustomobject]@{ Code = 0; Output = '' }
}

function Get-Process { param([Parameter(Position = 0)][string[]]$Name) Log-Call ("GETPROC: " + ($Name -join ',')); return @() }
function Get-Service { param([Parameter(Position = 0)][string]$Name) Log-Call "GETSVC: $Name"; return $null }
function Stop-Service { param([string]$Name, [switch]$Force, $ErrorAction) Log-Call "STOPSVC: $Name" }
function Unregister-ScheduledTask { param([string]$TaskPath, [string]$TaskName, $Confirm, $ErrorAction) Log-Call "UNREGTASK: $TaskPath$TaskName" }
function Remove-AppxPackage { param([string]$Package, [switch]$AllUsers, $ErrorAction) Log-Call "APPXREMOVE: $Package allusers=$AllUsers" }
function Remove-Item {
    param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, [switch]$Recurse, [switch]$Force)
    $p = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($p -match '^(HKLM:|HKCU:|Microsoft\.PowerShell\.Core\\Registry::)') { Log-Call "REGDEL: $p"; return }
    if (-not $p.StartsWith($sp, [StringComparison]::OrdinalIgnoreCase)) { throw "Thử xoá ngoài thư mục thử: $p" }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $p -Recurse:$Recurse -Force:$Force -ErrorAction SilentlyContinue
    Log-Call "DEL: $p"
}
$global:FakeHkcu = $true
function Test-Path {
    param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, [string]$PathType)
    $p = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($p -like 'HKCU:\Software\Microsoft\Office*') { return $global:FakeHkcu }
    if ($PathType) { return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $p -PathType $PathType) }
    return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $p)
}

# Giấy phép giả trong Software Protection.
$global:Spp = New-Object System.Collections.ArrayList
function New-SppProduct([string]$Id, [string]$Name, [string]$Partial, [int]$Status, [string]$Channel, [string]$Kms = '') {
    return [pscustomobject]@{ ID = $Id; Name = $Name; Description = "$Name desc"; LicenseStatus = $Status; GracePeriodRemaining = 0
        ProductKeyChannel = $Channel; KeyManagementServiceMachine = $Kms; DiscoveredKeyManagementServiceMachineName = ''; PartialProductKey = $Partial; ApplicationID = $script:OfficeAppId }
}
$global:ActivateResult = @{}   # ID → '' (thành công) hoặc HRESULT hex
function Get-CimInstance {
    param([Parameter(Position = 0)][string]$ClassName, [string]$Filter)
    Log-Call "CIM: $ClassName $Filter"
    switch ($ClassName) {
        'SoftwareLicensingProduct' {
            if ($Filter -match "ID='([^']+)'" -and $Filter -notmatch 'ApplicationID') { return @($global:Spp | Where-Object { $_.ID -eq $Matches[1] }) }
            return @($global:Spp | Where-Object { $_.PartialProductKey })
        }
        'SoftwareLicensingService' { return [pscustomobject]@{ Kind = 'service' } }
        'Win32_ComputerSystem' { return [pscustomobject]@{ UserName = (Get-CurrentUser); PartOfDomain = $false; Domain = 'WORKGROUP' } }
    }
    return $null
}
function Invoke-CimMethod {
    param($InputObject, [string]$MethodName, [hashtable]$Arguments, $ErrorAction)
    $id = [string]$InputObject.ID
    Log-Call "CIMCALL: $MethodName $id"
    switch ($MethodName) {
        'UninstallProductKey' { $x = $global:Spp | Where-Object { $_.ID -eq $id }; if ($x) { $x.PartialProductKey = $null; $x.LicenseStatus = 0 } }
        'ClearKeyManagementServiceMachine' { $x = $global:Spp | Where-Object { $_.ID -eq $id }; if ($x) { $x.KeyManagementServiceMachine = '' } }
        'ClearKeyManagementServicePort' { }
        'Activate' {
            $r = [string]$global:ActivateResult[$id]
            if ($r) { throw "HRESULT 0x$r" }
            $x = $global:Spp | Where-Object { $_.ID -eq $id }; if ($x) { $x.LicenseStatus = 1 }
        }
        'InstallProductKey' {
            $k = [string]$Arguments.ProductKey
            Log-Call 'INSTALLKEY'
            $x = $global:Spp | Where-Object { $_.Name -like 'Office 19*' } | Select-Object -First 1
            if (-not $x) { $x = New-SppProduct 'prod-new' 'Office 19, Office19ProPlus2019VL_MAK_AE edition' '' 0 'Volume:MAK'; [void]$global:Spp.Add($x) }
            $x.PartialProductKey = $k.Substring($k.Length - 5); $x.ProductKeyChannel = 'Volume:MAK'; $x.LicenseStatus = 0
            $global:ActivateResult.Remove($x.ID)   # khoá MAK kích hoạt qua Internet được
        }
    }
    return [pscustomobject]@{ ReturnValue = 0 }
}

# Hiện trạng Office giả (hàng đợi: mỗi lần gọi lấy một trạng thái, hết thì giữ cái cuối).
$global:StateQueue = New-Object System.Collections.Queue
$global:LastState = $null
function Get-OfficeState { if ($global:StateQueue.Count) { $global:LastState = $global:StateQueue.Dequeue() }; Log-Call 'STATE'; return $global:LastState }
function New-State {
    param($C2R = $null, $Suites = @(), $Msi = @(), $Store = @(), $Ace = @(), $C2RArp = @())
    $s = [pscustomobject]@{ C2R = $C2R; C2RArp = @($C2RArp); C2RMsi = @(); Suites = @($Suites); Msi = @($Msi); Ace = @($Ace); Store = @($Store) }
    $s | Add-Member -NotePropertyName Any -NotePropertyValue ([bool]($C2R -and $C2R.Products.Count) -or @($C2RArp).Count -or @($Suites).Count -or @($Msi).Count -or @($Store).Count)
    return $s
}
function New-C2R([string[]]$Products, [string]$Platform = 'x64', [string]$Channel = 'PerpetualVL2019', [string[]]$Apps = @('Word', 'Excel', 'PowerPoint')) {
    $ch = [pscustomobject]@{ Guid = ''; Id = $Channel; Label = $Channel }
    return [pscustomobject]@{ Products = $Products; Version = '16.0.10417.20208'; Platform = $Platform; Culture = 'en-us'; Channel = $ch
        InstallPath = "$env:ProgramFiles\Microsoft Office"; UpdatesEnabled = 'True'; Apps = $Apps }
}
$global:C2RAfter = $null
function Get-C2RInfo { Log-Call 'C2RINFO'; return $global:C2RAfter }
$global:Leftovers = $null
$global:RealGetLeftovers = ${function:Get-OfficeLeftovers}
function Get-OfficeLeftovers { param($State) Log-Call 'LEFTOVERS'; $l = $global:Leftovers; $global:Leftovers = [pscustomobject]@{ Service = $false; Tasks = @(); Folders = @(); Keys = @(); ArpKeys = @(); C2RMsi = @(); Any = $false }; return $l }
$global:RebootPending = $false
function Test-OfficeRebootPending { return $global:RebootPending }
$global:Running = New-Object System.Collections.ArrayList
function Get-OfficeRunning {
    $live = @($global:Running | Where-Object { -not $_.Closed })
    if (-not $live.Count) { return @() }
    return @([pscustomobject]@{ Name = 'WINWORD'; Label = 'Word'; Count = $live.Count; Processes = $live })
}
function New-FakeProc([int]$Session, [bool]$Window) {
    $p = [pscustomobject]@{ SessionId = $Session; MainWindowHandle = $(if ($Window) { [IntPtr]1 } else { [IntPtr]::Zero }); Closed = $false; Id = Get-Random }
    $p | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value { Log-Call "CLOSEWIN $($this.Id)"; $this.Closed = $true; return $true }
    $p | Add-Member -MemberType ScriptMethod -Name Kill -Value { Log-Call "KILL $($this.Id)"; $this.Closed = $true }
    return $p
}
$global:Free = 50GB
function Get-FreeSpace { return [int64]$global:Free }
$global:Internet = $true
function Test-Internet { return $global:Internet }
function Test-KmsDiscoverable { return $false }
$global:IsAdmin = $true
function Test-IsAdmin { return $global:IsAdmin }
function Invoke-WebRequest { param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, $TimeoutSec) Log-Call "DOWNLOAD: $Uri"; [IO.File]::WriteAllText($OutFile, 'zip giả') }
function Expand-Archive { param([string]$LiteralPath, [string]$DestinationPath, [switch]$Force) [void](New-Item -ItemType Directory -Path $DestinationPath -Force); [IO.File]::WriteAllText((Join-Path $DestinationPath 'GetHelpCmd.exe'), 'exe giả') }
$global:GetHelpSigned = $true
function Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    if ($LiteralPath -like '*GetHelpCmd.exe') {
        if ($global:GetHelpSigned) { return [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' } } }
        return [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null }
    }
    return (Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $LiteralPath)
}

# ---------------------------------------------------------------- mẫu giả
$fakeKey = 'TESTA-BBBBB-CCCCC-DDDDD-QWXYZ'      # khoá giả, không phải khoá thật
$gvlk2019 = 'NMMKJ-6RK4F-KMJVX-8D9MJ-6MWKP'    # GVLK Microsoft công bố (Office Professional Plus 2019)
$ffn2019 = 'f2e724c1-748f-4b47-8fb8-8e0d210e9208'
function New-Template {
    param([string]$Name, [string]$Config, [string]$ConfigName = 'Configuration.xml', [switch]$NoSetup, [switch]$FakeSetup,
        [string]$Build = '16.0.10417.20211', [string]$Ffn = $ffn2019, [string[]]$Products = @('ProPlus2019Volume'), [string[]]$Langs = @('en-us'),
        [switch]$NoCab, [string]$Bits = '64')
    $dir = "$sp\mau\$Name"
    [void](New-Item -ItemType Directory -Path $dir -Force)
    if ($FakeSetup) { [IO.File]::WriteAllText("$dir\setup.exe", 'không phải exe') }
    elseif (-not $NoSetup) { Copy-Item -LiteralPath $realTemplateSetup -Destination "$dir\setup.exe" }
    if ($Config) { [IO.File]::WriteAllText("$dir\$ConfigName", $Config) }
    if (-not $NoCab) {
        $data = "$dir\Office\Data"
        [void](New-Item -ItemType Directory -Path "$data\$Build" -Force)
        $pr = ($Products | ForEach-Object { "<ProductReleaseId Name=""$_"" />" }) -join ''
        $vd = "$sp\temp\VersionDescriptor.xml"
        [IO.File]::WriteAllText($vd, "<?xml version=""1.0""?><Version><Available Build=""$Build"" /><ProductReleaseIds>$pr</ProductReleaseIds><DeliveryMechanism FFNRoot=""$Ffn"" /></Version>")
        $r = & $global:RealInvokeNative 'makecab.exe' @('/L', $data, $vd, "v$Bits.cab")
        if (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$data\v$Bits.cab")) { throw "makecab không tạo được cab: $($r.Output)" }
        $arch = if ($Bits -eq '32') { 'x86' } else { 'x64' }
        [IO.File]::WriteAllText("$data\$Build\stream.$arch.x-none.dat", 'x')
        foreach ($l in $Langs) { [IO.File]::WriteAllText("$data\$Build\stream.$arch.$l.dat", 'x') }
    }
    return $dir
}
function Cfg([string]$Product = 'ProPlus2019Volume', [string]$Key = '', [string]$Channel = 'PerpetualVL2019', [string]$Lang = 'en-us', [string]$Extra = '', [string]$Edition = '64') {
    $k = if ($Key) { " PIDKEY=""$Key""" } else { '' }
    $c = if ($Channel) { " Channel=""$Channel""" } else { '' }
    return "<Configuration><Add OfficeClientEdition=""$Edition""$c><Product ID=""$Product""$k><Language ID=""$Lang"" /><ExcludeApp ID=""Outlook"" /></Product></Add><Property Name=""AUTOACTIVATE"" Value=""1"" /><Updates Enabled=""TRUE"" /><RemoveMSI />$Extra</Configuration>"
}
function Assert-NoKey([string]$Name, [string]$Text) {
    foreach ($g in $fakeKey.Split('-') + @($fakeKey) + @('MAKKE', 'ZZZZZ', 'MAKKE-YAAAA-BBBBB-CCCCC-ZZZZZ')) {
        Check "$Name không lộ khoá" ($Text.IndexOf($g, [StringComparison]::OrdinalIgnoreCase) -lt 0) "($g)"
    }
}

# ================================================================= T1 che khoá
$t = Protect-Text 'x PIDKEY="ABCDE-12345-FGHIJ-67890-KLMNO" y'
Check 'T1 PIDKEY che' ($t -notmatch 'ABCDE|KLMNO' -and $t -match 'khoá đã che')
Check 'T1 khoá trần che' ((Protect-Text 'Key: ABCDE-12345-FGHIJ-67890-KLMNO.') -notmatch 'ABCDE')
Check 'T1 chữ thường che' ((Protect-Text 'abcde-12345-fghij-67890-klmno') -notmatch 'abcde')
Check 'T1 GUID giữ' ((Protect-Text '{90160000-008C-0000-1000-0000000FF1CE}') -eq '{90160000-008C-0000-1000-0000000FF1CE}')
Check 'T1 version giữ' ((Protect-Text '16.0.10417.20208') -eq '16.0.10417.20208')
Reset-Test
Write-Out "PIDKEY=""$fakeKey"""
Assert-NoKey 'T1 Write-Out' (Report-Text)

# ================================================================= T2-T5 tên, vòng đời, kênh, khoá
Check 'T2 2019' ((Get-ProductName 'ProPlus2019Volume') -eq 'Office Professional Plus 2019 (bản Volume)') (Get-ProductName 'ProPlus2019Volume')
Check 'T2 2021' ((Get-ProductName 'ProPlus2021Volume') -eq 'Office LTSC Professional Plus 2021')
Check 'T2 365' ((Get-ProductName 'O365ProPlusRetail') -eq 'Microsoft 365 Apps for enterprise')
Check 'T2 2016' ((Get-ProductName 'ProPlusRetail') -eq 'Office Professional Plus 2016')
Check 'T2 Visio' ((Get-ProductName 'VisioPro2024Volume') -eq 'Visio LTSC Professional 2024') (Get-ProductName 'VisioPro2024Volume')
Check 'T2 Word' ((Get-ProductName 'Word2021Volume') -eq 'Word LTSC 2021') (Get-ProductName 'Word2021Volume')
Check 'T2 Project' ((Get-ProductName 'ProjectPro2024Volume') -eq 'Project Professional 2024') (Get-ProductName 'ProjectPro2024Volume')
Check 'T2 HB retail' ((Get-ProductName 'HomeBusiness2021Retail') -eq 'Office Home & Business 2021')
Check 'T2 lạ' ((Get-ProductName 'LanguagePack') -eq 'LanguagePack')
Check 'T3 2019 hết' ((Get-ProductLifecycle 'ProPlus2019Volume').Status -eq 'ended')
Check 'T3 2016 hết' ((Get-ProductLifecycle 'ProPlusRetail').Status -eq 'ended')
$lc = Get-ProductLifecycle 'ProPlus2021Volume'
Check 'T3 2021 sắp hết' ($lc.Status -eq 'soon' -and $lc.Text -match '13/10/2026') $lc.Text
Check 'T3 2024 còn' ((Get-ProductLifecycle 'ProPlus2024Volume').Status -eq 'ok')
Check 'T3 365' ((Get-ProductLifecycle 'O365ProPlusRetail').Status -eq 'subscription')
Check 'T3 MSI 2013' ((Get-ProductLifecycle -MsiMajor 15).Name -eq 'Office 2013')
Check 'T4 kênh 2019' ((Get-ChannelInfo "http://officecdn.microsoft.com/pr/$ffn2019").Id -eq 'PerpetualVL2019')
Check 'T4 kênh 2021 đoán' ((Get-ChannelInfo 'http://officecdn.microsoft.com/pr/5030841d-c919-4594-8d2d-84ae4f96e58e' @('ProPlus2021Volume')).Id -eq 'PerpetualVL2021')
Check 'T4 tên cũ' ((Resolve-ChannelId 'Monthly') -eq 'Current' -and (Resolve-ChannelId 'broad') -eq 'SemiAnnual')
Check 'T4 kênh hợp' ((Get-ExpectedChannel 'ProPlus2024Volume') -eq 'PerpetualVL2024' -and (Get-ExpectedChannel 'O365ProPlusRetail') -eq '')
Check 'T5 GVLK' (Test-IsGvlk $gvlk2019)
Check 'T5 GVLK chữ thường' (Test-IsGvlk $gvlk2019.ToLowerInvariant())
Check 'T5 khoá giả không GVLK' (-not (Test-IsGvlk $fakeKey))
Check 'T5 băm đuôi' ((Get-KeyTailHash $fakeKey) -eq (Get-KeyTailHash 'qwxyz') -and (Get-KeyTailHash $fakeKey) -ne (Get-KeyTailHash $gvlk2019) -and (Get-KeyTailHash 'abc') -eq '')
Check 'T19 mã lỗi' ((Format-ErrorCode 3010) -eq '3010' -and (Format-ErrorCode -1073430520) -eq '0xC004C008' -and (Format-ErrorCode 0xC004F074) -eq '0xC004F074')
Check 'T19 cỡ' ((Format-Size 500) -eq '1 KB' -and (Format-Size (5MB)) -eq '5 MB' -and (Format-Size (1.5GB)) -match '^1[.,]5 GB$')
$s = Split-CommandLine '"C:\Program Files\Common Files\x\setup.exe" /uninstall PROPLUS /dll OSETUP.DLL'
Check 'T19 tách lệnh' ($s[0] -eq 'C:\Program Files\Common Files\x\setup.exe' -and $s[1] -eq '/uninstall PROPLUS /dll OSETUP.DLL')
$s = Split-CommandLine 'MsiExec.exe /X{90160000-0011-0000-0000-0000000FF1CE}'
Check 'T19 tách msiexec' ($s[0] -eq 'MsiExec.exe' -and $s[1] -eq '/X{90160000-0011-0000-0000-0000000FF1CE}')
Check 'T19 thư mục' ((Format-FolderArg 'E:\') -eq 'E:\.' -and (Format-FolderArg 'D:\Mau\') -eq 'D:\Mau' -and (Format-FolderArg '"D:\a b"') -eq 'D:\a b')

# ================================================================= T6 đọc mẫu
$ok = New-Template 'ok' (Cfg -Key $fakeKey)
$t = Read-OfficeTemplate $ok
Check 'T6a không lỗi' ($t.Problems.Count -eq 0) ($t.Problems -join '|')
Check 'T6a ký' ($t.SetupSigned)
Check 'T6a nguồn đủ' ($t.Source.Complete) ($t.Source.Missing -join '|')
Check 'T6a khoá riêng' ($t.KeyKind -eq 'key' -and $t.KeyHashes.Count -eq 1 -and $t.Products[0].HasKey -and -not $t.Products[0].Gvlk)
Check 'T6a loại trừ' ($t.Products[0].Exclude -contains 'Outlook')
Check 'T6a RemoveMSI, AUTOACTIVATE' ($t.RemoveMSI -and $t.AutoActivate)
$json = $t | ConvertTo-Json -Depth 6
Assert-NoKey 'T6a đối tượng mẫu' $json
$t = Read-OfficeTemplate (New-Template 'gvlk' (Cfg -Key $gvlk2019))
Check 'T6b GVLK' ($t.KeyKind -eq 'gvlk' -and $t.Products[0].Gvlk -and @($t.Warnings | Where-Object { $_ -match 'KMS chung' }).Count)
Check 'T6b không lộ GVLK' (($t | ConvertTo-Json -Depth 6).IndexOf('NMMKJ') -lt 0)
$t = Read-OfficeTemplate (New-Template 'volnokey' (Cfg))
Check 'T6c Volume không khoá = GVLK' ($t.KeyKind -eq 'gvlk')
$t = Read-OfficeTemplate (New-Template 'o365' (Cfg -Product 'O365ProPlusRetail' -Channel 'Current') -Products @('O365ProPlusRetail') -Ffn '492350f6-3a01-4f97-b9c0-c7c6ddf67d60')
Check 'T6d 365 không khoá' ($t.KeyKind -eq '' -and $t.Problems.Count -eq 0 -and $t.Source.Complete) ($t.Source.Missing -join '|')
$t = Read-OfficeTemplate (New-Template 'xmlhong' '<Configuration><Add>')
Check 'T6e XML hỏng' (@($t.Problems | Where-Object { $_ -match 'lỗi định dạng XML' }).Count) ($t.Problems -join '|')
$t = Read-OfficeTemplate (New-Template 'khongadd' '<Configuration><Remove All="TRUE" /></Configuration>')
Check 'T6f thiếu Add' (@($t.Problems | Where-Object { $_ -match 'cấu hình cài đặt' }).Count) ($t.Problems -join '|')
$two = New-Template 'haicfg' (Cfg) -ConfigName 'a.xml'
[IO.File]::WriteAllText("$two\b.xml", (Cfg -Product 'Standard2019Volume'))
$t = Read-OfficeTemplate $two
Check 'T6g nhiều cấu hình' ($t.Candidates.Count -eq 2 -and @($t.Problems | Where-Object { $_ -match 'nhiều file' }).Count)
$t = Read-OfficeTemplate $two 'b.xml'
Check 'T6h chọn b.xml' ($t.ConfigName -eq 'b.xml' -and $t.Products[0].Id -eq 'Standard2019Volume')
$t = Read-OfficeTemplate (New-Template 'thieulang' (Cfg -Lang 'vi-vn'))
Check 'T6i thiếu ngôn ngữ' (@($t.Warnings | Where-Object { $_ -match 'vi-vn' }).Count -and -not $t.Source.Complete)
$t = Read-OfficeTemplate (New-Template 'lechkenh' (Cfg -Product 'O365ProPlusRetail' -Channel 'Current') -Products @('O365ProPlusRetail'))
Check 'T6j lệch kênh nguồn' (@($t.Warnings | Where-Object { $_ -match 'thuộc kênh' }).Count) ($t.Warnings -join '|')
$t = Read-OfficeTemplate (New-Template 'thieusp' (Cfg -Product 'Standard2019Volume'))
Check 'T6k sản phẩm không có trong nguồn' (@($t.Warnings | Where-Object { $_ -match 'không có Standard2019Volume' }).Count) ($t.Warnings -join '|')
$t = Read-OfficeTemplate (New-Template 'nosetup' (Cfg) -NoSetup)
Check 'T6l thiếu setup' (@($t.Problems | Where-Object { $_ -match 'không có setup.exe' }).Count)
$t = Read-OfficeTemplate (New-Template 'fakesetup' (Cfg) -FakeSetup)
Check 'T6m setup không ký' (@($t.Problems | Where-Object { $_ -match 'chữ ký' }).Count)
$t = Read-OfficeTemplate (New-Template 'nocab' (Cfg) -NoCab)
Check 'T6n không có bộ cài' (@($t.Warnings | Where-Object { $_ -match 'không có sẵn bộ cài' }).Count -and -not $t.Source.Complete)
$t = Read-OfficeTemplate (New-Template 'kenhsai' (Cfg -Product 'ProPlus2021Volume' -Channel 'PerpetualVL2019') -Products @('ProPlus2021Volume'))
Check 'T6o kênh không hợp sản phẩm' (@($t.Warnings | Where-Object { $_ -match 'đi kênh PerpetualVL2021' }).Count) ($t.Warnings -join '|')
$t = Read-OfficeTemplate (New-Template 'bit32' (Cfg -Edition '32'))
Check 'T6p 32 bit thiếu v32' (@($t.Warnings | Where-Object { $_ -match 'v32.cab' }).Count)
$xxe = '<?xml version="1.0"?><!DOCTYPE c [<!ENTITY x SYSTEM "file:///C:/Windows/win.ini">]><Configuration><Add><Product ID="&x;" /></Add></Configuration>'
$t = Read-OfficeTemplate (New-Template 'xxe' $xxe)
Check 'T6q chặn DTD' (@($t.Problems | Where-Object { $_ -match 'lỗi định dạng XML' }).Count -and -not $t.Products.Count) ($t.Problems -join '|')
$t = Read-OfficeTemplate "$sp\khongco"
Check 'T6r thiếu thư mục' (@($t.Problems | Where-Object { $_ -match 'Không thấy thư mục' }).Count)
Check 'T6s file làm mẫu' ((Find-TemplateDir "$ok\Configuration.xml") -eq $ok)

# ================================================================= T7 rào chắn xoá
$off = "$env:ProgramFiles\Microsoft Office"
[void](New-Item -ItemType Directory -Path "$off\root\Office16" -Force)
[IO.File]::WriteAllText("$off\root\Office16\WINWORD.EXE", 'x')
Check 'T7 dưới Program Files' (Test-SafeToDelete $off)
Check 'T7 chính Program Files' (-not (Test-SafeToDelete $env:ProgramFiles))
Check 'T7 ngoài vùng' (-not (Test-SafeToDelete "$sp\khac\x"))
Check 'T7 Windows' (-not (Test-SafeToDelete 'C:\Windows\System32'))
Check 'T7 mẫu bên trong' (-not (Test-SafeToDelete $off @("$off\mau")))
Check 'T7 chính mẫu' (-not (Test-SafeToDelete "$off\mau" @("$off\mau")))
Check 'T7 mẫu D:' (-not (Test-SafeToDelete 'D:\Program Files\Microsoft Office'))
$oldTool = $script:ToolDir; $script:ToolDir = "$env:ProgramData\Tram\tools\office"
Check 'T7 thư mục công cụ' (-not (Test-SafeToDelete "$env:ProgramData\Tram"))
$script:ToolDir = $oldTool
$outside = "$sp\ngoai"; [void](New-Item -ItemType Directory -Path $outside -Force); [IO.File]::WriteAllText("$outside\quan-trong.txt", 'giữ')
$c2rpd = "$env:ProgramData\Microsoft\ClickToRun"
[void](New-Item -ItemType Directory -Path $c2rpd -Force); [IO.File]::WriteAllText("$c2rpd\a.dat", 'x')
[void](New-Item -ItemType Junction -Path "$c2rpd\link" -Target $outside)
$jroot = "$env:ProgramData\Microsoft\JunctionRoot"
[void](New-Item -ItemType Junction -Path $jroot -Target $outside)
Check 'T7 junction gốc' (-not (Test-SafeToDelete $jroot))
Reset-Test
Check 'T7 xoá thư mục có junction' (Remove-SafeFolder $c2rpd)
Check 'T7 không đi theo junction' ((Microsoft.PowerShell.Management\Test-Path -LiteralPath "$outside\quan-trong.txt") -and -not (Microsoft.PowerShell.Management\Test-Path -LiteralPath $c2rpd))
[IO.Directory]::Delete($jroot, $false)
Check 'T7 không xoá mẫu' (-not (Remove-SafeFolder $off @("$off\root")))
Check 'T7 mẫu còn' (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$off\root\Office16\WINWORD.EXE")

# ================================================================= T8 đóng ứng dụng
Reset-Test
$global:Running.Clear()
$a1 = New-FakeProc ([Diagnostics.Process]::GetCurrentProcess().SessionId) $true
$a2 = New-FakeProc 99 $true
[void]$global:Running.Add($a1); [void]$global:Running.Add($a2)
Answer @('T', 'D', 'K')
$r = Close-OfficeApps 'thử'
Check 'T8 kết quả ok' ($r -eq 'ok')
Check 'T8 D đóng cửa sổ cùng phiên' ((Calls-Like "CLOSEWIN $($a1.Id)").Count -eq 1)
Check 'T8 D không đụng phiên khác' ((Calls-Like "CLOSEWIN $($a2.Id)").Count -eq 0 -and (Calls-Like "KILL $($a2.Id)").Count -eq 1)
Check 'T8 báo người dùng khác' ((Report-Text) -match 'người dùng khác')
Reset-Test
$global:Running.Clear(); [void]$global:Running.Add((New-FakeProc 1 $true))
Answer @('H')
Check 'T8 huỷ' ((Close-OfficeApps 'thử') -eq 'cancel')
$global:Running.Clear()
Check 'T8 không có gì mở' ((Close-OfficeApps 'thử') -eq 'ok')

# ================================================================= T9 sao lưu, trả lại
function Set-UserData {
    foreach ($f in @(
            "$env:APPDATA\Microsoft\Templates\Normal.dotm", "$env:APPDATA\Microsoft\Templates\LiveContent\16\big.bin",
            "$env:APPDATA\Microsoft\UProof\CUSTOM.DIC", "$env:APPDATA\Microsoft\Office\MSO1033.acl", "$env:APPDATA\Microsoft\Office\khac.txt",
            "$env:APPDATA\Microsoft\Excel\XLSTART\PERSONAL.XLSB", "$env:APPDATA\Microsoft\Excel\Excel15.xlb",
            "$env:LOCALAPPDATA\Microsoft\Office\Word.officeUI", "$env:APPDATA\Microsoft\Signatures\ky.htm")) {
        [void](New-Item -ItemType Directory -Path (Split-Path $f) -Force); [IO.File]::WriteAllText($f, "goc:$f")
    }
}
Set-UserData
Reset-Test
$plan = @(Get-UserDataPlan)
Check 'T9 kế hoạch' ($plan.Count -eq 7) ("có $($plan.Count) mục: " + (($plan | ForEach-Object { $_.Item.Id }) -join ','))
$b = Backup-OfficeUserData -Registry
Check 'T9 sao lưu' ($b.Items.Count -eq 7 -and -not $b.Failed.Count -and $b.Registry) ($b.Failed -join '|')
Check 'T9 bỏ LiveContent' (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$($b.Dir)\templates\LiveContent"))
Check 'T9 chỉ lấy .acl' ((Microsoft.PowerShell.Management\Test-Path -LiteralPath "$($b.Dir)\autocorrect\MSO1033.acl") -and -not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$($b.Dir)\autocorrect\khac.txt"))
$m = [IO.File]::ReadAllText("$($b.Dir)\SaoLuu.json") | ConvertFrom-Json
Check 'T9 manifest' ($m.registry -eq 'Office.reg' -and @($m.items).Count -eq 7 -and $m.reason -eq 'truoc-khi-go')
$name1 = Split-Path -Leaf $b.Dir
Microsoft.PowerShell.Utility\Start-Sleep -Seconds 1
[IO.File]::WriteAllText("$env:APPDATA\Microsoft\Templates\Normal.dotm", 'da sua')
Microsoft.PowerShell.Management\Remove-Item -LiteralPath "$env:APPDATA\Microsoft\Signatures" -Recurse -Force
Reset-Test
Answer @('c', 'k')     # Trả lại ngay? có; nhập registry? không
$r = Invoke-TraLai -SaoLuu $name1
Check 'T9 trả lại mã 0' ($r -eq 0) "mã $r"
Check 'T9 Normal.dotm về bản gốc' ([IO.File]::ReadAllText("$env:APPDATA\Microsoft\Templates\Normal.dotm") -like 'goc:*')
Check 'T9 chữ ký về' (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$env:APPDATA\Microsoft\Signatures\ky.htm")
Check 'T9 không nhập registry' ((Calls-Like 'reg\.exe import').Count -eq 0)
$all = @(Get-Backups)
$before = $all | Where-Object { $_.Manifest.reason -eq 'truoc-khi-tra-lai' } | Select-Object -First 1
Check 'T9 sao lưu trước khi trả lại' ($before -and [IO.File]::ReadAllText("$($before.Dir)\templates\Normal.dotm") -eq 'da sua')
Reset-Test
Answer @('2', 'c', 'c')   # chọn bản thứ 2 (bản cũ hơn), trả lại ngay, nhập registry
$r = Invoke-TraLai
Check 'T9 chọn trong danh sách + nhập registry' ($r -eq 0 -and (Calls-Like 'reg\.exe import').Count -eq 1) "mã $r"
Reset-Test
Answer @('H')
Check 'T9 huỷ chọn' ((Invoke-TraLai) -eq 1223)
Reset-Test
Check 'T9 tên sai' ((Invoke-TraLai -SaoLuu 'SaoLuu_khongco') -eq 2)
Reset-Test
Check 'T9 chạy thử' ((Invoke-TraLai -SaoLuu $name1 -DryRun) -eq 0 -and -not (Calls-Like 'robocopy').Count)

# ================================================================= T10-T12 các bước gỡ
function Set-RemoveScene {
    $global:Spp.Clear()
    [void]$global:Spp.Add((New-SppProduct 'prod-mak' 'Office 19, Office19ProPlus2019VL_MAK_AE edition' 'AAAAA' 1 'Volume:MAK' 'kms.vi-du.local'))
    $global:CmdkeyList = "Currently stored credentials:`n    Target: LegacyGeneric:target=MicrosoftOffice16_Data:SSPI:a@vi-du.com`n    Target: LegacyGeneric:target=MicrosoftOffice15_Data:ADAL:b@vi-du.com`n    Target: LegacyGeneric:target=git:https://github.com"
    [void](New-Item -ItemType Directory -Path "$env:LOCALAPPDATA\Microsoft\Office\Licenses" -Force)
    [IO.File]::WriteAllText("$env:LOCALAPPDATA\Microsoft\Office\Licenses\token.dat", 'x')
    [void](New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\ClickToRun" -Force)
    $global:Leftovers = [pscustomobject]@{
        Service = $true; Tasks = @('\Microsoft\Office\Office Automatic Updates 2.0'); Folders = @("$env:ProgramData\Microsoft\ClickToRun")
        Keys = @('HKLM:\SOFTWARE\Microsoft\Office\ClickToRun'); ArpKeys = @([pscustomobject]@{ Name = 'Microsoft Office Professional Plus 2019 - en-us'; RegPath = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ProPlus2019Volume - en-us' })
        C2RMsi = @([pscustomobject]@{ Name = 'Office 16 Click-to-Run Licensing Component'; Code = '{90160000-007E-0000-1000-0000000FF1CE}' }); Any = $true
    }
    $global:StateQueue.Clear()
    $suite = [pscustomobject]@{ Kind = 'suite'; Code = 'Office16.PROPLUS'; Name = 'Microsoft Office Professional Plus 2016'; Version = '16.0.4266.1001'; Major = 16; Uninstall = '"C:\Fake\Office Setup Controller\setup.exe" /uninstall PROPLUS /dll OSETUP.DLL' }
    $msi = [pscustomobject]@{ Kind = 'msi'; Code = '{90160000-0051-0000-0000-0000000FF1CE}'; Name = 'Microsoft Visio Viewer 2016'; Version = '16.0'; Major = 16; Uninstall = 'MsiExec.exe /X{90160000-0051-0000-0000-0000000FF1CE}' }
    $store = [pscustomobject]@{ Name = 'Microsoft.Office.Desktop'; FullName = 'Microsoft.Office.Desktop_16.0_x64__8wekyb3d8bbwe'; Version = '16.0' }
    $ace = [pscustomobject]@{ Kind = 'ace'; Name = 'Microsoft Access database engine 2016 (English)' }
    $global:Before = New-State -C2R (New-C2R @('ProPlus2019Volume')) -Suites @($suite) -Msi @($msi) -Store @($store) -Ace @($ace)
    $global:StateQueue.Enqueue((New-State -Ace @($ace)))
}
Reset-Test; Set-UserData; Set-RemoveScene
$global:ProcPlan = @{ 'msiexec.exe /x \{90160000-0051' = 3010 }
$odt = "$ok\setup.exe"
$r = Invoke-RemoveSteps $global:Before $odt @($ok) $true -XoaThietLap
$rt = Report-Text
Check 'T10 mã 0, sạch, cần khởi động lại' ($r.Code -eq 0 -and $r.Clean -and $r.Reboot) ("code=$($r.Code) clean=$($r.Clean) reboot=$($r.Reboot)")
Check 'T10 sao lưu trước' ($r.Backup -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$($r.Backup)\Office.reg"))
$x = [IO.File]::ReadAllText("$sp\GoOffice.captured.xml")
Check 'T10 cấu hình gỡ' ($x -match '<Remove All="TRUE" />' -and $x -match 'Display Level="None"' -and $x -notmatch 'PIDKEY' -and $x -match 'nhat-ky-odt')
Check 'T10 ODT chạy trong thư mục mẫu' ((Calls-Like ([regex]::Escape("START: $odt | /configure")) | Where-Object { $_ -match ([regex]::Escape("wd=$ok")) }).Count -eq 1)
Check 'T10 gỡ suite MSI' ((Calls-Like 'START: C:\\Fake\\Office Setup Controller\\setup.exe \| /uninstall PROPLUS').Count -eq 1)
Check 'T10 gỡ MSI lẻ' ((Calls-Like 'START: msiexec.exe \| /x \{90160000-0051.* /passive /norestart').Count -eq 1)
Check 'T10 gỡ Store mọi tài khoản' ((Calls-Like 'APPXREMOVE: Microsoft.Office.Desktop_16.0_x64__8wekyb3d8bbwe allusers=True').Count -eq 1)
Check 'T10 xoá dịch vụ' ((Calls-Like 'NATIVE: sc.exe delete ClickToRunSvc').Count -eq 1)
Check 'T10 xoá tác vụ' ((Calls-Like 'UNREGTASK: \\Microsoft\\Office\\Office Automatic Updates 2.0').Count -eq 1)
Check 'T10 gỡ thành phần MSI C2R' ((Calls-Like 'START: msiexec.exe \| /x \{90160000-007E.* /qn /norestart').Count -eq 1)
Check 'T10 xoá thư mục sót' (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$env:ProgramData\Microsoft\ClickToRun"))
Check 'T10 xoá registry sót' ((Calls-Like 'REGDEL: HKLM:\\SOFTWARE\\Microsoft\\Office\\ClickToRun').Count -eq 1 -and (Calls-Like 'REGDEL: Microsoft.PowerShell.Core\\Registry::.*ProPlus2019Volume - en-us').Count -eq 1)
Check 'T10 gỡ khoá, xoá KMS' ((Calls-Like 'CIMCALL: ClearKeyManagementServiceMachine prod-mak').Count -eq 1 -and (Calls-Like 'CIMCALL: UninstallProductKey prod-mak').Count -eq 1)
Check 'T10 xoá giấy phép người dùng' (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$env:LOCALAPPDATA\Microsoft\Office\Licenses") -and (Calls-Like 'REGDEL: HKCU:\\Software\\Microsoft\\Office\\16.0\\Common\\Identity').Count -eq 1)
Check 'T10 xoá đúng 2 tài khoản Office' ((Calls-Like 'NATIVE: cmdkey.exe /delete:').Count -eq 2 -and (Calls-Like 'cmdkey.exe /delete:.*git').Count -eq 0)
Check 'T10 không in email' ($rt -notmatch 'vi-du\.com')
Check 'T10 xoá thiết lập sau khi sao lưu' ((Calls-Like 'REGDEL: HKCU:\\Software\\Microsoft\\Office$').Count -eq 1)
Check 'T10 không gỡ Access Database Engine' ($rt -notmatch 'Gỡ Microsoft Access database engine')
Assert-NoKey 'T10 nhật ký' $rt

Reset-Test; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue((New-State -C2R (New-C2R @('ProPlus2019Volume'))))
$r = Invoke-RemoveSteps $global:Before $odt @($ok) $true
Check 'T11 còn Office: mã 3, không dọn' ($r.Code -eq 3 -and -not $r.Clean -and (Calls-Like 'sc.exe delete').Count -eq 0 -and (Calls-Like 'UninstallProductKey').Count -eq 0)

Reset-Test; Set-RemoveScene
$global:Running.Clear(); [void]$global:Running.Add((New-FakeProc ([Diagnostics.Process]::GetCurrentProcess().SessionId) $true))
Answer @('H')
$r = Invoke-RemoveSteps $global:Before $odt @($ok) $true
Check 'T12 huỷ khi đóng ứng dụng' ($r.Code -eq 1223 -and (Calls-Like 'START:').Count -eq 0)
$global:Running.Clear()

Reset-Test; Set-RemoveScene
$r = Invoke-RemoveSteps $global:Before $odt @($ok) $false -XoaThietLap
Check 'T12b người dùng khác: bỏ phần từng người' (-not $r.Backup -and (Calls-Like 'cmdkey').Count -eq 0 -and (Calls-Like 'REGDEL: HKCU:').Count -eq 0 -and (Calls-Like 'UninstallProductKey').Count -eq 1)

Reset-Test; Set-RemoveScene
$noOdt = New-State -C2RArp @([pscustomobject]@{ Kind = 'c2r'; Name = 'Microsoft Office Professional Plus 2019 - en-us'; RegPath = "$sp\khongco-regpath"; Uninstall = '"C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe" scenario=install scenariosubtype=ARP sourcetype=None productstoremove=ProPlus2019Volume.16_en-us_x-none culture=en-us version.16=16.0' })
$r = Invoke-RemoveSteps $noOdt '' @() $true
Check 'T12c không có ODT: bỏ qua mục đã mất' ((Calls-Like 'OfficeClickToRun.exe').Count -eq 0)

# ================================================================= T13 quét sâu
Reset-Test
Answer @('C')
$global:ProcOutput = '00: Successfully completed this scenario.'
$g = Invoke-GetHelpScrub
Check 'T13 00' ($g.Code -eq '00' -and $g.Ok) ("code=$($g.Code)")
Check 'T13 chạy đúng lệnh' ((Calls-Like 'START: .*GetHelpCmd.exe \| -S OfficeScrubScenario -AcceptEula -OfficeVersion All').Count -eq 1)
Check 'T13 mở điều khoản' ((Calls-Like 'START: notepad.exe').Count -eq 1)
Check 'T13 dọn file tải' (-not @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'TramTool_Office_*').Count)
Reset-Test
Answer @('C')
$global:ProcOutput = '06: Office programs are running. Please close all open Office programs and then rerun this scenario.'
$g = Invoke-GetHelpScrub
Check 'T13 06' ($g.Code -eq '06' -and -not $g.Ok)
Reset-Test
Answer @('B')
$g = Invoke-GetHelpScrub
Check 'T13 bỏ qua' ($g.Code -eq 'skip' -and (Calls-Like 'GetHelpCmd.exe \| -S').Count -eq 0)
Reset-Test
$global:GetHelpSigned = $false
$g = Invoke-GetHelpScrub
Check 'T13 không ký: không chạy' ($g.Code -eq 'error' -and (Calls-Like 'GetHelpCmd').Count -eq 0)
$global:GetHelpSigned = $true
Reset-Test
Answer @('C')
$global:ProcOutput = 'Something unexpected'
$g = Invoke-GetHelpScrub
Check 'T13 kết quả lạ' ($g.Code -eq 'error')

# ================================================================= T14 cài, kích hoạt, nhập khoá
$T = Read-OfficeTemplate $ok
function Set-InstallScene([int]$Status = 0) {
    $global:Spp.Clear()
    [void]$global:Spp.Add((New-SppProduct 'prod-gvlk' 'Office 19, Office19ProPlus2019VL_KMS_Client_AE edition' '6MWKP' $Status 'Volume:GVLK'))
    $global:C2RAfter = New-C2R @('ProPlus2019Volume')
    $global:ActivateResult = @{ 'prod-gvlk' = 'C004F074' }
}
Reset-Test; Set-InstallScene
Answer @('K', 'N', 'MAKKE-YAAAA-BBBBB-CCCCC-ZZZZZ')
$code = Invoke-InstallSteps $T
$rt = Report-Text
[IO.File]::WriteAllText("$TestRoot\T14.txt", $rt, (New-Object Text.UTF8Encoding($true)))
Check 'T14 cài xong, kích hoạt bằng khoá nhập' ($code -eq 0) "mã $code"
Check 'T14 ODT cài đúng lệnh' ((Calls-Like ([regex]::Escape("START: $ok\setup.exe | /configure ""$ok\Configuration.xml"" | wd=$ok"))).Count -eq 1)
Check 'T14 báo lỗi KMS' ($rt -match '0xC004F074' -and $rt -match 'máy chủ KMS')
Check 'T14 nhập khoá một lần' ((Calls-Like 'INSTALLKEY').Count -eq 1 -and (Calls-Like 'ASK-SECRET').Count -eq 1)
Check 'T14 chờ tự kích hoạt 12 lần' ((Calls-Like 'SLEEP 10').Count -eq 11)
Assert-NoKey 'T14 nhật ký' $rt
Assert-NoKey 'T14 lời gọi' ($global:Calls -join "`n")
Reset-Test; Set-InstallScene
Answer @('N', 'abc', 'B')
$code = Invoke-InstallSteps $T
Check 'T14b khoá sai dạng: báo, không cài khoá' ($code -eq 3 -and (Report-Text) -match '5 nhóm 5 ký tự' -and (Calls-Like 'INSTALLKEY').Count -eq 0)
Reset-Test; Set-InstallScene
Answer @('B')
$code = Invoke-InstallSteps $T
Check 'T14c bỏ qua kích hoạt: mã 3' ($code -eq 3)
Reset-Test; Set-InstallScene 1
$code = Invoke-InstallSteps $T
Check 'T14d đã tự kích hoạt: mã 0, không hỏi' ($code -eq 0 -and (Calls-Like 'ASK').Count -eq 0)
Reset-Test; Set-InstallScene 1
$global:C2RAfter = New-C2R @('ProPlus2019Volume') -Apps @('Word', 'Excel')
$code = Invoke-InstallSteps $T
Check 'T14e thiếu PowerPoint: mã 1' ($code -eq 1 -and (Report-Text) -match 'Thiếu PowerPoint')
Reset-Test; Set-InstallScene 1
$global:C2RAfter = $null
$global:ProcPlan = @{ 'setup.exe /configure' = 17002 }
$code = Invoke-InstallSteps $T
Check 'T14f ODT lỗi: mã 1, báo mã' ($code -eq 1 -and (Report-Text) -match '17002')

# ================================================================= T15 kiểm tra trước khi cài
$same = New-State -C2R (New-C2R @('ProPlus2019Volume'))
$r = Test-InstallReady $T $same
Check 'T15 giống mẫu' ($r.Same -and -not $r.Blocking.Count) ($r.Blocking -join '|')
$r = Test-InstallReady $T (New-State -C2R (New-C2R @('O365ProPlusRetail') -Channel 'Current'))
Check 'T15 khác mẫu: chặn' (@($r.Blocking | Where-Object { $_ -match 'khác mẫu' }).Count)
$r = Test-InstallReady $T (New-State -C2R (New-C2R @('ProPlus2019Volume') -Platform 'x86'))
Check 'T15 khác 32/64: chặn' (@($r.Blocking | Where-Object { $_ -match 'khác mẫu' }).Count)
$suite = [pscustomobject]@{ Name = 'Microsoft Office Professional Plus 2016' }
$r = Test-InstallReady $T (New-State -Suites @($suite))
Check 'T15 MSI + RemoveMSI: cảnh báo' (-not $r.Blocking.Count -and @($r.Warnings | Where-Object { $_ -match 'ODT sẽ gỡ' }).Count)
$T2 = Read-OfficeTemplate (New-Template 'khongremovemsi' ((Cfg) -replace '<RemoveMSI />', ''))
$r = Test-InstallReady $T2 (New-State -Suites @($suite))
Check 'T15 MSI không RemoveMSI: chặn' (@($r.Blocking | Where-Object { $_ -match 'cài bằng MSI' }).Count)
$r = Test-InstallReady $T (New-State -Store @([pscustomobject]@{ Name = 'Microsoft.Office.Desktop' }))
Check 'T15 Store: chặn' (@($r.Blocking | Where-Object { $_ -match 'Microsoft Store' }).Count)
$r = Test-InstallReady $T (New-State -Ace @([pscustomobject]@{ Name = 'Microsoft Access database engine 2016' }))
Check 'T15 Ace: gợi ý IgnoreProduct' (@($r.Warnings | Where-Object { $_ -match 'AceRedist' }).Count)
$global:Free = 2GB
$r = Test-InstallReady $T (New-State)
Check 'T15 thiếu chỗ: chặn' (@($r.Blocking | Where-Object { $_ -match '4 GB' }).Count)
$r = Test-InstallReady $T (New-State) -WillRemove
Check 'T15 thiếu chỗ khi sắp gỡ: cảnh báo' (-not $r.Blocking.Count -and @($r.Warnings | Where-Object { $_ -match '4 GB' }).Count)
$global:Free = 50GB
$Tnocab = Read-OfficeTemplate (New-Template 'nocab2' (Cfg) -NoCab)
$global:Internet = $false
$r = Test-InstallReady $Tnocab (New-State)
Check 'T15 thiếu bộ cài, không mạng: chặn' (@($r.Blocking | Where-Object { $_ -match 'không vào được' }).Count)
$global:Internet = $true
$r = Test-InstallReady $Tnocab (New-State)
Check 'T15 thiếu bộ cài, có mạng: được' (-not $r.Blocking.Count)
$global:RebootPending = $true
$r = Test-InstallReady $T (New-State)
Check 'T15 chờ khởi động lại: cảnh báo' (@($r.Warnings | Where-Object { $_ -match 'khởi động lại' }).Count)
$global:RebootPending = $false

# ================================================================= T16 gỡ rồi cài trọn vẹn
function Set-FullScene {
    Set-RemoveScene
    $global:C2RAfter = New-C2R @('ProPlus2019Volume')
    $global:ActivateResult = @{}
    $global:ProcPlan = @{}
}
Reset-Test; Set-FullScene
$nb = @(Get-Backups).Count
$r = Invoke-GoVaCai -Mau "$sp\mau\nosetup"
Check 'T16a mẫu hỏng: dừng trước khi gỡ' ($r -eq 2 -and (Calls-Like 'START:').Count -eq 0 -and @(Get-Backups).Count -eq $nb)
Reset-Test; Set-FullScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before); $global:StateQueue.Enqueue((New-State))
# sau khi gỡ: khoá MAK đã gỡ; sau khi cài: ODT cài khoá trong mẫu (giả lập bằng hàm giả ở lần đọc giấy phép đầu sau cài)
Answer @('DONG Y')
$global:AfterInstallHook = $true
$r = Invoke-GoVaCai -Mau $ok
$rt = Report-Text
$iRemove = [array]::IndexOf(@($global:Calls), @(Calls-Like 'GoOffice.xml')[0])
$iInstall = [array]::IndexOf(@($global:Calls), @(Calls-Like 'Configuration.xml')[0])
Check 'T16b gỡ trước, cài sau' ($iRemove -ge 0 -and $iInstall -gt $iRemove) "gỡ=$iRemove cài=$iInstall"
Check 'T16b cảnh báo khoá MAK trước khi gỡ' ($rt -match 'đang kích hoạt bằng khoá MAK')
[IO.File]::WriteAllText("$TestRoot\T16b.txt", $rt, (New-Object Text.UTF8Encoding($true)))
Check 'T16b mã kết thúc 0' ($r -eq 0) "mã $r"
Assert-NoKey 'T16b nhật ký' $rt
$global:AfterInstallHook = $false
Reset-Test; Set-FullScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before); $global:StateQueue.Enqueue((New-State))
Answer @('khong')
$r = Invoke-GoVaCai -Mau $ok
Check 'T16c không gõ DONG Y: huỷ, chưa gỡ' ($r -eq 1223 -and (Calls-Like 'START:').Count -eq 0)
Reset-Test; Set-FullScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before); $global:StateQueue.Enqueue((New-State))
$global:ProcPlan = @{ 'msiexec.exe /x \{90160000-0051' = 3010 }
Answer @('DONG Y')
$r = Invoke-GoVaCai -Mau $ok
Check 'T16d cần khởi động lại: dừng trước khi cài' ($r -eq 3 -and (Calls-Like 'Configuration.xml').Count -eq 0 -and (Report-Text) -match 'Chỉ cài Office theo mẫu')
Reset-Test; Set-FullScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before); $global:StateQueue.Enqueue((New-State))
$r = Invoke-GoVaCai -Mau $ok -DryRun
Check 'T16e chạy thử: không làm gì' ($r -eq 0 -and (Calls-Like 'START:|REGDEL|CIMCALL|robocopy').Count -eq 0)
Reset-Test; Set-FullScene
$inside = "$env:ProgramFiles\Microsoft Office\mauben"
Copy-Item -LiteralPath $ok -Destination $inside -Recurse
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before)
$r = Invoke-GoVaCai -Mau $inside
Check 'T16f mẫu trong thư mục Office: dừng' ($r -eq 2 -and (Calls-Like 'START:').Count -eq 0)

# ================================================================= T18 kích hoạt riêng
Reset-Test; Set-InstallScene
$global:IsAdmin = $false
Check 'T18 cần Admin' ((Invoke-KichHoat) -eq 2)
$global:IsAdmin = $true
Reset-Test; Set-InstallScene
Check 'T18 chạy thử' ((Invoke-KichHoat -DryRun) -eq 0 -and (Calls-Like 'CIMCALL').Count -eq 0)
Reset-Test; Set-InstallScene
$global:ActivateResult = @{}
Answer @('K')
Check 'T18 kích hoạt lại được' ((Invoke-KichHoat) -eq 0)

# ================================================================= T20 kiểm tra (báo cáo) với hiện trạng giả
Reset-Test; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before)
$global:Leftovers = $null
$code = Invoke-KiemTra -Mau $ok
$rt = Report-Text
Check 'T20 báo cáo lưu' ($code -eq 0 -and @(Get-ChildItem -LiteralPath "$script:ToolDir\ket_qua" -Filter 'BaoCao_Office_*.txt').Count)
Check 'T20 nhiều kiểu Office' ($rt -match 'nhiều kiểu Office')
Check 'T20 KMS ngoài domain' ($rt -match 'kms\.vi-du\.local')
Assert-NoKey 'T20 báo cáo' $rt

# ================================================================= T21 thư mục Microsoft Office còn sót
$off = "$env:ProgramFiles\Microsoft Office"
function Reset-OfficeDir([string[]]$Files) {
    if (Microsoft.PowerShell.Management\Test-Path -LiteralPath $off) { [IO.Directory]::Delete($off, $true) }
    foreach ($f in $Files) {
        $p = Join-Path $off $f
        if ($f.EndsWith('\')) { [void](New-Item -ItemType Directory -Path $p -Force) }
        else { [void](New-Item -ItemType Directory -Path (Split-Path $p) -Force); [IO.File]::WriteAllText($p, 'x') }
    }
}
$c2rOnly = @('root\Office16\WINWORD.EXE', 'Updates\Download\', 'PackageManifests\a.xml', 'Office16\OSPP.VBS', 'Office16\SLERROR.XML', 'AppXManifest.xml', 'FileSystemMetadata.xml')
Reset-OfficeDir $c2rOnly
$l = & $global:RealGetLeftovers (New-State)
Check 'T21a toàn Click-to-Run: xoá cả thư mục' ($l.Folders -contains $off -and -not @($l.Folders | Where-Object { $_ -like "$off\*" }).Count) ($l.Folders -join '|')
Reset-OfficeDir ($c2rOnly + 'Office16\ACEOLEDB.DLL' + 'Office15\WINWORD.EXE')
$l = & $global:RealGetLeftovers (New-State)
$want = @("$off\root", "$off\Updates", "$off\PackageManifests")
Check 'T21b còn file khác: chỉ thư mục con của Click-to-Run' (-not @($want | Where-Object { $l.Folders -notcontains $_ }).Count -and $l.Folders -notcontains $off -and $l.Folders -notcontains "$off\Office16" -and $l.Folders -notcontains "$off\Office15") ($l.Folders -join '|')
Reset-Test
$clean = [pscustomobject]@{ Service = $false; Tasks = @(); Folders = @($l.Folders | Where-Object { $_ -like "$off*" }); Keys = @(); ArpKeys = @(); C2RMsi = @(); Any = $true }
$fail = Remove-OfficeLeftovers $clean @($ok)
Check 'T21c dọn xong, giữ file khác' ($fail -eq 0 -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$off\Office16\ACEOLEDB.DLL") -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$off\Office15\WINWORD.EXE") -and -not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$off\root")) "lỗi $fail"
Reset-OfficeDir @('MauOffice\setup.exe')
$l = & $global:RealGetLeftovers (New-State)
Check 'T21d không có gì của Click-to-Run: không xoá' (-not @($l.Folders | Where-Object { $_ -like "$off*" }).Count) ($l.Folders -join '|')
Reset-OfficeDir @('Office16\')
$l = & $global:RealGetLeftovers (New-State)
Check 'T21e Office16 rỗng: xoá' ($l.Folders -contains $off) ($l.Folders -join '|')

# ================================================================= T22 Access Database Engine
$aceObj = [pscustomobject]@{ Kind = 'ace'; Name = 'Microsoft Access database engine 2016 (English)' }
Reset-Test
Show-RemovePlan (New-State -C2R (New-C2R @('ProPlus2019Volume')) -Ace @($aceObj)) $null $odt $true 0 -QuetSau
Check 'T22a quét sâu: báo có thể gỡ Access Database Engine' ((Report-Text) -match 'có thể gỡ cả Microsoft Access database engine')
Reset-Test
Show-RemovePlan (New-State -C2R (New-C2R @('ProPlus2019Volume')) -Ace @($aceObj)) $null $odt $true 0
Check 'T22b không quét sâu: không báo' ((Report-Text) -notmatch 'có thể gỡ cả')
Reset-Test; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue((New-State))
$r = Invoke-RemoveSteps $global:Before $odt @($ok) $true
Check 'T22c mất Access Database Engine: báo' ((Report-Text) -match 'Access database engine 2016 \(English\) không còn trên máy')
Reset-Test; Set-RemoveScene
$r = Invoke-RemoveSteps $global:Before $odt @($ok) $true
Check 'T22d còn Access Database Engine: không báo' ((Report-Text) -notmatch 'không còn trên máy')
Check 'T22d trả danh sách còn lại' (@($r.Ace).Count -eq 1)
Reset-Test; Set-InstallScene 1
$global:StateQueue.Clear(); $global:StateQueue.Enqueue((New-State))
$code = Invoke-InstallSteps $T @($aceObj)
Check 'T22e <RemoveMSI> gỡ mất khi cài: báo' ($code -eq 0 -and (Report-Text) -match 'không còn trên máy \(thẻ <RemoveMSI>') "mã $code"
Reset-Test; Set-InstallScene 1
$global:StateQueue.Clear(); $global:StateQueue.Enqueue((New-State -Ace @($aceObj)))
$code = Invoke-InstallSteps $T @($aceObj)
Check 'T22f còn sau khi cài: không báo' ($code -eq 0 -and (Report-Text) -notmatch 'không còn trên máy') "mã $code"
Reset-Test; Set-InstallScene 1
$code = Invoke-InstallSteps $T
Check 'T22g không có Access Database Engine: không đọc lại Office' ($code -eq 0 -and (Calls-Like '^STATE$').Count -eq 0)

# ================================================================= T23 file kết quả JSON cho Trạm Tool
# Invoke-Mode, Invoke-ModeSafe lấy nguyên từ Office.ps1 (không chạy phần bắt đầu của script).
$mainAst = [Management.Automation.Language.Parser]::ParseFile("$repo\Office.ps1", [ref]$null, [ref]$null)
foreach ($fn in 'Invoke-Mode', 'Invoke-ModeSafe') {
    $def = $mainAst.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $fn }, $true)
    . ([scriptblock]::Create($def.Extent.Text))
}
foreach ($k in @($script:Modes.Keys)) { $script:Modes[$k].Log = $(if ($k -eq 'kiem-tra') { '' } else { 'NhatKy_Office' }) }
$kq = "$script:ToolDir\ket_qua"
function Clear-KetQua { Get-ChildItem -LiteralPath $kq -Filter '*Office_*' -File -ErrorAction SilentlyContinue | ForEach-Object { [IO.File]::Delete($_.FullName) } }
function Get-KetQua([string]$Name) {
    $f = @(Get-ChildItem -LiteralPath $kq -Filter "KetQua_Office_$($Name)_*.json" -ErrorAction SilentlyContinue)
    if ($f.Count -ne 1) { return $null }
    $b = [IO.File]::ReadAllBytes($f[0].FullName)
    $txt = [IO.File]::ReadAllText($f[0].FullName)
    return [pscustomobject]@{ Path = $f[0].FullName; Text = $txt; J = ($txt | ConvertFrom-Json); Bom = ($b.Count -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB) }
}
function Test-Order($J) {
    $rank = @{ loi = 0; 'canh-bao' = 1; 'thong-tin' = 2; ok = 3 }
    $r = @($J.phatHien | ForEach-Object { $rank[[string]$_.mucDo] })
    for ($i = 1; $i -lt $r.Count; $i++) { if ($r[$i] -lt $r[$i - 1]) { return $false } }
    $n = @{}
    foreach ($m in 'loi', 'canh-bao', 'thong-tin') { $n[$m] = @($J.phatHien | Where-Object { $_.mucDo -eq $m }).Count }
    $ma = if ($n['loi']) { 'CO_LOI' } elseif ($n['canh-bao']) { 'CO_CANH_BAO' } else { 'KHONG_CO_LOI' }
    return ($J.tomTat.loi -eq $n['loi'] -and $J.tomTat.canhBao -eq $n['canh-bao'] -and $J.tomTat.thongTin -eq $n['thong-tin'] -and $J.ma -eq $ma -and
        -not @($J.phatHien | Where-Object { $_.ma -notmatch '^[A-Z][A-Z0-9_]+$' }).Count)
}

Clear-KetQua
Reset-Test; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before)
$global:Leftovers = $null
$code = Invoke-ModeSafe 'kiem-tra' @{ Mau = $ok; CauHinh = ''; ChayThu = $false }
$r = Get-KetQua 'KiemTra'
Check 'T23a kiểm tra: một file kết quả' ($code -eq 0 -and $r) "mã $code"
if ($r) {
    $j = $r.J
    $ma = @($j.phatHien | ForEach-Object { $_.ma })
    Check 'T23a đúng chuẩn, chế độ, phiên bản' ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'office' -and $j.cheDo -eq 'kiem-tra' -and $j.phienBan -eq $script:ToolVersion -and $j.maThoat -eq 0 -and $j.trangThai -eq 'xong' -and $j.chayThu -eq $false -and $j.may -eq $env:COMPUTERNAME)
    Check 'T23a UTF-8 không BOM, không còn .tmp' (-not $r.Bom -and -not @(Get-ChildItem -LiteralPath $kq -Filter '*.tmp').Count)
    Check 'T23a thứ tự, tóm tắt, mã CHU_HOA' (Test-Order $j) ($ma -join ', ')
    $nk = @($j.phatHien | Where-Object { $_.ma -eq 'NHIEU_KIEU_OFFICE' })
    Check 'T23a nhiều kiểu Office: nút Gỡ và cài' ($nk.Count -eq 1 -and $nk[0].mucDo -eq 'canh-bao' -and $nk[0].chayTiep.congCu -eq 'office' -and $nk[0].chayTiep.action -eq 'go-va-cai' -and $nk[0].cachSua -match '^Chạy "Gỡ và cài"') ($ma -join ', ')
    Check 'T23a có lỗi thì không kết luận ổn' (($ma -notcontains 'KHONG_CO_VAN_DE') -and $j.ma -ne 'KHONG_CO_LOI' -and $j.thongDiep -match 'cảnh báo')
    $tep = @($j.tep)
    Check 'T23a kèm báo cáo .txt' ($tep.Count -eq 1 -and $tep[0].duongDan -match 'BaoCao_Office_' -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath $tep[0].duongDan)) (($tep | ForEach-Object { $_.duongDan }) -join '|')
    Check 'T23a kiểm tra không ghi nhật ký' (-not @(Get-ChildItem -LiteralPath $kq -Filter 'NhatKy_Office_*').Count)
    Assert-NoKey 'T23a JSON' $r.Text
}

# Không có lỗi, cảnh báo: thêm mục ok KHONG_CO_VAN_DE (gợi ý thông tin vẫn giữ)
Reset-Test
Add-Finding -Ma 'OFFICE_KHAC_MAU' info 'Office trên máy khác mẫu.' -Fix 'go-va-cai'
Show-Conclusion
$okF = @($script:Findings | Where-Object { $_.Ma -eq 'KHONG_CO_VAN_DE' })
Check 'T23b không lỗi: thêm mục ok' ($okF.Count -eq 1 -and $okF[0].Level -eq 'ok')
Clear-KetQua
$p = Save-RunResult -CheDo 'kiem-tra' -Code 0 -Start (Get-Date)
$r = Get-KetQua 'KiemTra'
Check 'T23b không lỗi: KHONG_CO_LOI, ok xếp cuối' ($p -and $r -and $r.J.ma -eq 'KHONG_CO_LOI' -and $r.J.phatHien[-1].ma -eq 'KHONG_CO_VAN_DE' -and $r.J.phatHien[-1].mucDo -eq 'ok' -and $r.J.tomTat.thongTin -eq 1 -and $r.J.thongDiep -match 'Không thấy vấn đề')
Reset-Test
Add-Finding -Ma 'CHUA_KICH_HOAT' warn 'Office chưa kích hoạt.' -Fix 'kich-hoat'
Show-Conclusion
Check 'T23b có cảnh báo: không thêm mục ok' (-not @($script:Findings | Where-Object { $_.Ma -eq 'KHONG_CO_VAN_DE' }).Count)

# Khoá sản phẩm lọt vào chữ của phát hiện vẫn bị che trong JSON
Reset-Test; Clear-KetQua
Add-Finding -Ma 'MAU_HONG' bad ('Cấu hình lỗi gần PIDKEY="{0}".' -f $fakeKey) -Hint ('Khoá {0} sai.' -f $fakeKey)
$p = Save-RunResult -CheDo 'kiem-tra' -Code 0 -Start (Get-Date)
$r = Get-KetQua 'KiemTra'
Check 'T23c che khoá trong JSON' ($r -and $r.Text -match 'khoá đã che')
if ($r) { Assert-NoKey 'T23c JSON' $r.Text }

# Gỡ sạch chạy thử: chayThu, không nhật ký
Reset-Test; Clear-KetQua; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before)
$global:IsAdmin = $false
$code = Invoke-ModeSafe 'go-sach' @{ Mau = $ok; ChayThu = $true }
$global:IsAdmin = $true
$r = Get-KetQua 'GoSach'
Check 'T23d gỡ chạy thử: chayThu, không nhật ký' ($code -eq 0 -and $r -and $r.J.chayThu -eq $true -and $r.J.trangThai -eq 'xong' -and $r.J.thongDiep -match 'Chạy thử' -and -not @($r.J.tep).Count -and -not @($r.J.phatHien).Count -and -not @(Get-ChildItem -LiteralPath $kq -Filter 'NhatKy_Office_*').Count) "mã $code"
Check 'T23d gỡ chạy thử: không gỡ gì' ((Calls-Like '^START:|APPXREMOVE|UninstallProductKey|REGDEL').Count -eq 0)

# Thiếu quyền Admin: THIEU_DIEU_KIEN lấy dòng [X] đã in, nút Kiểm tra, kèm nhật ký
Reset-Test; Clear-KetQua; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before)
$global:IsAdmin = $false
$code = Invoke-ModeSafe 'go-sach' @{ Mau = $ok; ChayThu = $false }
$global:IsAdmin = $true
$r = Get-KetQua 'GoSach'
Check 'T23e thiếu Admin: mã 2, thieu-dieu-kien' ($code -eq 2 -and $r -and $r.J.maThoat -eq 2 -and $r.J.trangThai -eq 'thieu-dieu-kien' -and $r.J.ma -eq 'CO_CANH_BAO') "mã $code"
if ($r) {
    $f = @($r.J.phatHien)
    Check 'T23e một mục THIEU_DIEU_KIEN' ($f.Count -eq 1 -and $f[0].ma -eq 'THIEU_DIEU_KIEN' -and $f[0].tieuDe -eq 'Cần quyền Admin để gỡ Office.' -and $f[0].chayTiep.action -eq 'kiem-tra') (($f | ForEach-Object { "$($_.ma): $($_.tieuDe)" }) -join ' | ')
    $tep = @($r.J.tep)
    Check 'T23e kèm nhật ký' ($tep.Count -eq 1 -and $tep[0].duongDan -match 'NhatKy_Office_' -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath $tep[0].duongDan))
}

# Huỷ (không gõ DONG Y): có nhật ký, không có file kết quả
Reset-Test; Clear-KetQua; Set-RemoveScene
$global:StateQueue.Clear(); $global:StateQueue.Enqueue($global:Before)
Answer @('')
$code = Invoke-ModeSafe 'go-sach' @{ Mau = $ok; ChayThu = $false }
Check 'T23f huỷ: mã 1223, không ghi kết quả' ($code -eq 1223 -and -not @(Get-ChildItem -LiteralPath $kq -Filter 'KetQua_Office_*').Count -and (Calls-Like '^START:').Count -eq 0) "mã $code"

# Lỗi không lường trước: LOI_KHONG_LUONG_TRUOC, không thêm CHUA_XONG
Reset-Test; Clear-KetQua
$savedState = ${function:Get-OfficeState}
${function:Get-OfficeState} = { throw 'lỗi giả khi đọc Office' }
$code = Invoke-ModeSafe 'go-sach' @{ Mau = $ok; ChayThu = $false }
${function:Get-OfficeState} = $savedState
$r = Get-KetQua 'GoSach'
Check 'T23g lỗi lạ: mã 1, một mục LOI_KHONG_LUONG_TRUOC' ($code -eq 1 -and $r -and $r.J.trangThai -eq 'loi' -and $r.J.ma -eq 'CO_LOI' -and @($r.J.phatHien).Count -eq 1 -and $r.J.phatHien[0].ma -eq 'LOI_KHONG_LUONG_TRUOC' -and $r.J.phatHien[0].tieuDe -match 'lỗi giả') "mã $code"

# Chỗ ghi phát hiện nào cũng có mã cố định; nút chạy tiếp trỏ tới chế độ có thật trong tool.json
$manifest = [IO.File]::ReadAllText("$repo\tool.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
$actionIds = @($manifest.actions | ForEach-Object { $_.id })
$codes = @(); $bad = @(); $fixes = @(); $n = 0
foreach ($file in @(Get-ChildItem -LiteralPath "$repo\lib" -Filter '*.ps1') + @(Get-Item -LiteralPath "$repo\Office.ps1")) {
    $a = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    foreach ($c in @($a.FindAll({ param($x) $x -is [Management.Automation.Language.CommandAst] -and $x.GetCommandName() -eq 'Add-Finding' }, $true))) {
        $n++
        $e = @($c.CommandElements); $ma = $null; $fix = $null
        for ($i = 1; $i -lt $e.Count - 1; $i++) {
            if ($e[$i] -is [Management.Automation.Language.CommandParameterAst]) {
                if ($e[$i].ParameterName -eq 'Ma') { $ma = $e[$i + 1] }
                if ($e[$i].ParameterName -eq 'Fix') { $fix = $e[$i + 1] }
            }
        }
        if ($ma -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $ma.Value -notmatch '^[A-Z][A-Z0-9_]+$') { $bad += "$($file.Name):$($c.Extent.StartLineNumber)"; continue }
        $codes += $ma.Value
        if ($fix) { $fixes += @($fix.FindAll({ param($x) $x -is [Management.Automation.Language.StringConstantExpressionAst] -and $x.StringConstantType -ne 'BareWord' }, $true) | ForEach-Object { $_.Value } | Where-Object { $_ }) }
    }
}
Check 'T23h mọi chỗ ghi phát hiện có -Ma CHU_HOA' ($n -ge 20 -and -not $bad.Count) "$n chỗ; thiếu: $($bad -join ', ')"
$dup = @($codes | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check 'T23h mã không trùng' (-not $dup.Count) ($dup -join ', ')
$wrong = @($fixes + 'kiem-tra' | Where-Object { $actionIds -notcontains $_ })
Check 'T23h nút chạy tiếp trỏ tới chế độ có thật' ($fixes.Count -ge 5 -and -not $wrong.Count) "($($wrong -join ', '))"
Clear-KetQua

Complete-Test
