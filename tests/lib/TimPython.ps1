# Tìm Python thật để chạy bài thử Python. Bỏ qua lối tắt Microsoft Store (WindowsApps\python.exe): lối tắt này chỉ
# mở Store chứ không chạy được gì. Không thấy thì trả $null.
function Find-Python {
    foreach ($n in 'python', 'py') {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c -and $c.Source -notlike '*\WindowsApps\*') { return $c.Source }
    }
    return $null
}
