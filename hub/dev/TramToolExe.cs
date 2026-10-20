// TramTool.exe của bản portable: bấm đúp để mở Trạm Tool. hub\dev\DongGoi.ps1 dịch file này bằng csc.exe có sẵn
// trong Windows (.NET Framework 4), nên không cần cài gì để dựng hay để chạy.
// Việc của nó: chạy máy chủ của trạm (hub\TramTool.ps1) với cửa sổ ẩn, chuyển nguyên tham số (vd -Browser edge);
// máy chủ tự mở giao diện, tự sửa .venv khi đổi thư mục (Initialize-PortableRuntime). Máy chủ thoát ngay với mã khác 0
// thì báo lỗi và chỉ cách xem chi tiết. Không ghi registry, không cài gì.
// Bài thử: TRAMTOOL_EXE_POWERSHELL thay powershell.exe bằng file giả; TRAMTOOL_EXE_LOG ghi lệnh đã chạy;
// TRAMTOOL_EXE_KHONG_HOI ghi lời báo vào file log thay vì hiện hộp thoại.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

[assembly: AssemblyTitle("Trạm Tool")]
[assembly: AssemblyProduct("Trạm Tool (bản portable)")]
[assembly: AssemblyDescription("Mở Trạm Tool: chọn và chạy công cụ Windows")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class TramToolExe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    const string Title = "Trạm Tool";

    static void Bao(string text, bool loi) {
        string log = Environment.GetEnvironmentVariable("TRAMTOOL_EXE_LOG");
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TRAMTOOL_EXE_KHONG_HOI")) && !string.IsNullOrEmpty(log)) {
            File.AppendAllText(log, "BAO: " + text.Replace("\n", " ") + "\r\n", new UTF8Encoding(false));
            return;
        }
        MessageBoxW(IntPtr.Zero, text, Title, loi ? 0x10u : 0x40u);
    }

    // Đặt một tham số trong dấu ngoặc kép theo quy tắc CommandLineToArgvW (dấu \ đứng trước " phải nhân đôi).
    static string Quote(string a) {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return a;
        StringBuilder sb = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in a) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { sb.Append('\\', slashes * 2 + 1); sb.Append('"'); slashes = 0; continue; }
            sb.Append('\\', slashes); slashes = 0; sb.Append(c);
        }
        sb.Append('\\', slashes * 2);
        sb.Append('"');
        return sb.ToString();
    }

    [STAThread]
    static int Main(string[] args) {
        string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string hub = Path.Combine(root, "hub\\TramTool.ps1");
        if (!File.Exists(hub)) {
            Bao("Không tìm thấy hub\\TramTool.ps1 cạnh TramTool.exe.\n\nGiải nén đủ cả thư mục TramTool (đừng chỉ chép riêng TramTool.exe) rồi bấm lại.", true);
            return 1;
        }
        string ps = Environment.GetEnvironmentVariable("TRAMTOOL_EXE_POWERSHELL");
        if (string.IsNullOrEmpty(ps)) ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
        if (!File.Exists(ps)) {
            Bao("Máy này thiếu Windows PowerShell (" + ps + "), Trạm Tool cần nó để chạy.", true);
            return 1;
        }
        StringBuilder argv = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -File " + Quote(hub));
        foreach (string a in args) argv.Append(' ').Append(Quote(a));

        ProcessStartInfo psi = new ProcessStartInfo(ps, argv.ToString());
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = root;
        string log = Environment.GetEnvironmentVariable("TRAMTOOL_EXE_LOG");
        if (!string.IsNullOrEmpty(log)) File.AppendAllText(log, "CHAY: " + ps + " " + psi.Arguments + "\r\n", new UTF8Encoding(false));

        Process p;
        try { p = Process.Start(psi); }
        catch (Exception e) {
            Bao("Không chạy được máy chủ của Trạm Tool: " + e.Message, true);
            return 1;
        }
        // Đợi máy chủ mở cổng (ghi hub\data\runtime.json có pid của nó) hoặc thoát: trạm đang chạy sẵn thì nó mở lại
        // giao diện rồi thoát mã 0; lỗi khi khởi động thì thoát mã khác 0.
        string rt = Path.Combine(root, "hub\\data\\runtime.json");
        for (int i = 0; i < 300; i++) {
            if (p.WaitForExit(100)) {
                if (p.ExitCode != 0) {
                    Bao("Trạm Tool không mở được (mã " + p.ExitCode + ").\n\nBấm đúp TramTool.bat trong cùng thư mục để xem lỗi trong cửa sổ máy chủ.", true);
                    return p.ExitCode;
                }
                return 0;
            }
            try {
                if (File.Exists(rt)) {
                    Match m = Regex.Match(File.ReadAllText(rt, Encoding.UTF8), "\"pid\"\\s*:\\s*(\\d+)");
                    if (m.Success && m.Groups[1].Value == p.Id.ToString()) return 0;
                }
            } catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        return 0;
    }
}
