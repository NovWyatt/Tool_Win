
# ----------------------------------------------------------------------------
function Set-TrustedLocation([string]$Ver) {
    $sub = $script:RegBase + "Software\Microsoft\Office\$Ver\Excel\Security\Trusted Locations"
    $tl = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
    if ($tl.GetValue('AllLocationsDisabled') -eq 1) {
        $tl.SetValue('AllLocationsDisabled', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        Done 'Bỏ tích "Disable all Trusted Locations"'
    }
    $found = $null; $max = -1
    foreach ($s in $tl.GetSubKeyNames()) {
        if ($s -match '^Location(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) }
        $lk = $tl.OpenSubKey($s, $true)
        $p = [Environment]::ExpandEnvironmentVariables([string]$lk.GetValue('Path'))
        if (-not $found -and (Test-SamePath $p $script:Target)) { $found = $lk } else { $lk.Close() }
    }
    if ($found) {
        if ($found.GetValue('AllowSubfolders') -ne 1) {
            $found.SetValue('AllowSubfolders', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            Done "Trusted Location $($script:Target): tích thêm 'Subfolders of this location are also trusted'"
        } else {
            Skip "Trusted Location $($script:Target)\ (có thư mục con) đã có sẵn"
        }
        $found.Close()
    } else {
        $nk = $tl.CreateSubKey("Location$($max + 1)")
        $nk.SetValue('Path', $script:Target + '\', [Microsoft.Win32.RegistryValueKind]::String)
        $nk.SetValue('AllowSubfolders', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $nk.SetValue('Description', 'MyExcel', [Microsoft.Win32.RegistryValueKind]::String)
        $nk.SetValue('Date', (Get-Date).ToString('M/d/yyyy h:mm tt', [Globalization.CultureInfo]::InvariantCulture), [Microsoft.Win32.RegistryValueKind]::String)
        $nk.Close()
        $script:Manifest.NewKeys += "Software\Microsoft\Office\$Ver\Excel\Security\Trusted Locations\Location$($max + 1)"
        Save-Manifest
        Done "Thêm Trusted Location $($script:Target)\ (có thư mục con)"
    }
    $tl.Close()
}

function Clear-DisabledItems([string]$Ver) {
    $dk = Open-UserKey "Software\Microsoft\Office\$Ver\Excel\Resiliency\DisabledItems" $true
    if (-not $dk) { return }
    foreach ($n in $dk.GetValueNames()) {
        $v = $dk.GetValue($n)
        $txt = ''
        if ($v -is [byte[]] -and $v.Length -gt 12) { $txt = [Text.Encoding]::Unicode.GetString($v, 12, $v.Length - 12) -replace '[\x00-\x1F]+', ' ' }
        if ($txt -match '(?i)myexcel|qr.?code|vietqr|minitool') {
            $dk.DeleteValue($n, $false)
            Done "Excel $Ver - bật lại add-in bị vô hiệu hóa: $($txt.Trim())"
        }
    }
    $dk.Close()
}
