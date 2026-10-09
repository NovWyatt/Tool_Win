# Nạp thư viện của tools\may-in-lan (không chạy MayInLan.ps1), thư mục công cụ giả trong thư mục tạm.
# Nạp sau KiemThu.ps1:  . "$PSScriptRoot\_Nap.ps1"
$ErrorActionPreference = 'Stop'
$lib = "$ToolsDir\may-in-lan\lib"
$script:ToolDir = New-TestDir 'tooldir'
$script:MainScript = "$ToolsDir\may-in-lan\MayInLan.ps1"
$script:ToolVersion = 'test'
. "$lib\Chung.ps1"; . "$lib\NhatKy.ps1"; . "$lib\ChanDoan.ps1"; . "$lib\SuaLoi.ps1"
$script:Modes = [ordered]@{
    'bat-chia-se' = @{ No = 4; Label = 'Bật chia sẻ' }; 'noi-bao-mat' = @{ No = 8; Label = 'Nới bảo mật' }
    'ket-noi-thu-muc' = @{ No = 7; Label = 'Kết nối thư mục' }; 'them-may-in-ip' = @{ No = 6; Label = 'Thêm IP' }
}
