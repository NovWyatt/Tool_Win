# Bài thử của Trạm Tool

Bài thử giả lập cho các công cụ và cho chính Trạm. Chạy trên máy dev bằng quyền thường, không đổi máy thật: lệnh đổi
máy (dịch vụ, BCD, BitLocker, máy in, Wi-Fi, Office, registry hệ thống, xoá file) được thay bằng hàm giả. Nên chạy
trước mỗi lần commit.

## Chạy

```
tests\CHAY_KIEM_THU.bat                                  chạy hết (bấm đúp được)
powershell -ExecutionPolicy Bypass -File tests\ChayTatCa.ps1 -Chi new-windows,office
powershell -ExecutionPolicy Bypass -File tests\ChayTatCa.ps1 -Chi "new-windows/2*" -ChiTiet -GiuTam
powershell -ExecutionPolicy Bypass -File tests\ChayTatCa.ps1 -DanhSach
```

| Tham số | Ý nghĩa |
|---|---|
| `-Chi <bộ>[,<bộ>]` | chỉ chạy bộ (tên thư mục, vd `office`) hoặc bài (`bộ/tên`, có `*`) |
| `-ChiTiet` | in toàn bộ đầu ra từng bài (mặc định chỉ in dòng hỏng) |
| `-GiuTam` | giữ thư mục tạm của cả bài đạt (bài hỏng luôn được giữ, kèm nhật ký `.log`) |
| `-KhongDocMay` | bỏ các bài có đọc máy thật (thẻ `doc-may`, xem dưới) |
| `-DanhSach` | chỉ liệt kê bài thử |
| `-GioiHanGiay <n>` | dừng bài chạy quá n giây (mặc định 900) |

Mã thoát: 0 đạt hết, 1 có bài hỏng, 2 không có bài nào khớp `-Chi`, 99 đang có quyền Admin (từ chối chạy).

Cả lượt mất khoảng 6 phút. Bộ chậm nhất: `new-windows/4_TienTrinh` (gọi tiến trình thật ở chế độ chạy thử), `the-xe-nt`
(dùng Excel tạo file mẫu), `tram/2_KichBanAnToan`.

## Cần gì

- Windows PowerShell 5.1 (có sẵn). Không cần Pester.
- Python 3 cho `mdf2sql` (`tools\mdf2sql\tests`, dùng pyodbc và tkinter giả, không cần SQL Server) và
  `ghi-am-sang-word` (không cần `.venv` hay mô hình). Không có Python thì bỏ qua. `mdf2sql/1_ChayTool` không cần Python:
  bài này biên dịch một `python.exe` giả.
- Excel cho `the-xe-nt` (tạo file `.xls` mẫu), PowerShell 32 bit (Jet) do trình chạy tự gọi. Không có Excel thì bỏ qua.
- Node.js cho `tinh/4_LuocDo` (kiểm `tool.json` theo lược đồ bằng Ajv, kiểm cú pháp JavaScript của giao diện). Cài Ajv
  một lần: `cd tests` rồi `npm install` (vào `tests\node_modules`, không commit). Thiếu Ajv thì bỏ phần lược đồ.
- git cho `tinh/5_DuLieuKhach`.

## Nơi ghi

- Thư mục tạm chung nằm **ngoài repo**: `<thư mục cha của repo>\.TramTool-KiemThu` (vd `D:\Repo\.TramTool-KiemThu`),
  đổi bằng biến môi trường `TRAMTOOL_TEST_TAM` (tên thư mục cuối phải có chữ `KiemThu`). Phải ở ngoài repo vì
  new-windows từ chối lưu bản sao lưu vào thư mục Trạm Tool. Chạy đạt hết thì thư mục này bị xoá.
- Registry: chỉ `HKCU\Software\TramToolTest`, trình chạy xoá trước và sau mỗi lượt.
- Xoá thư mục tạm không đi theo junction (bài Office, Dọn ổ C có tạo junction để thử).
- Công cụ ghi vào thư mục của tài khoản (`%LOCALAPPDATA%`, `%PUBLIC%`, Desktop): bài thử trỏ các biến đó vào thư mục
  tạm. Bộ `myexcelfix` so `%LOCALAPPDATA%\MyExcelFix`, `%PUBLIC%\Documents\MyExcelCheck` và Desktop thật trước, sau
  mỗi bài (`Assert-RealUntouched`); có file mới là bài hỏng.

## Thẻ `doc-may`

Bài có dòng `# KiemThu: doc-may` có đọc máy thật nhưng không đổi gì:

| Bài | Đọc gì |
|---|---|
| `new-windows/4_TienTrinh` | chạy thử xuất (`-DryRun`): tên mạng Wi-Fi đã lưu, máy in, ổ đĩa; không đọc mật khẩu |
| `myexcelfix/3_KiemTra` | Kiểm tra MyExcel (chỉ đọc), kết quả ghi vào thư mục tạm; thêm hai bộ MyExcel giả (`MYX_EXTRA_ROOT`) để máy nào cũng có lỗi gợi ý *Sửa lỗi* |
| `myexcelfix/5_KiemTraNoiLuu` | Kiểm tra MyExcel (chỉ đọc) với `LOCALAPPDATA`, `PUBLIC`, Desktop trỏ vào thư mục tạm |
| `bitlocker/2_KiemTraThat` | Kiểm tra thật bằng quyền thường (TPM, nhật ký BitLocker, tìm file khoá theo Mã khoá; không đọc từng ổ), báo cáo và JSON kết quả vào thư mục tạm (`BDE_KET_QUA`); file kết quả không có chuỗi dạng khoá |
| `may-in-lan/4_ChanDoanThat` | Chẩn đoán thật bằng quyền thường (mạng, dịch vụ, tường lửa, SMB, máy in, ổ mạng, nhật ký; không gọi máy khác), báo cáo và JSON kết quả vào thư mục tạm (`MIL_KET_QUA`) |
| `tram/3_KhoiChay` | Máy in LAN `-ChayThu -KhongDung` dò máy này và 127.0.0.1 |
| `checkwinfix/3_ThuThap` | chạy thật phần PowerShell của Thu thập thông tin bằng quyền thường (`-KhongHoi`, không mở Notepad), báo cáo và JSON vào thư mục tạm, khoảng 1,5 phút |
| `checkwinfix/4_ChuyenSau` | chạy thật phần PowerShell của Chẩn đoán phần cứng, Giải mã WHEA, Xuất bằng chứng, Sụp nguồn bằng quyền thường (`-KhongHoi`: không hỏi tạo Custom View, đổi CrashControl hay bật theo dõi; không mở Notepad, Explorer); báo cáo, hồ sơ, JSON vào thư mục tạm, vài phút |
| `don-o-c/2_ChayThat` | Xem ổ C thật (chỉ đọc, đo dung lượng), Dọn rác của bạn ở chế độ chạy thử (đo rồi dừng trước bước hỏi xoá); báo cáo và JSON kết quả vào thư mục tạm (`DOC_KET_QUA`) |
| `fix-win/2_ChayThuThat` | Quét ổ đĩa, đặt lại mạng, Windows Update ở chế độ chạy thử (đọc sức khoẻ ổ vật lý, IP và DNS đặt tay; không hỏi UAC, không đổi máy), JSON kết quả vào thư mục tạm (`FIX_KET_QUA`); chế độ sai, đã nâng quyền mà thiếu quyền |
| `office/2_KiemTraThat` | Kiểm tra Office thật (chỉ đọc: Office, giấy phép, ứng dụng đang mở) với thư mục mẫu rỗng nên không đọc tới bộ cài mẫu thật; Gỡ sạch ở chế độ chạy thử (không hỏi UAC, không gỡ gì); báo cáo và JSON kết quả vào thư mục tạm (`OFFICE_KET_QUA`), không có chuỗi dạng khoá sản phẩm |
| `gio-chu-ky-so/2_ChayThat` | Kiểm tra thật (hỏi máy chủ giờ qua mạng, đọc dịch vụ, đầu đọc thẻ, kho chứng thư của tài khoản; không hỏi PIN); Sửa giờ, Sửa token, Trả lại ở chế độ chạy thử; so cấu hình giờ, dịch vụ trước và sau |
| `bo-ung-dung/2_ChayThat` | Kiểm tra thật (`winget export`, chỉ đọc); Cài, Cập nhật ở chế độ chạy thử (không hỏi UAC, không cài gì); cờ lạ, chế độ sai; so danh sách phần mềm đã cài trước và sau |
| `toi-uu/3_ToiUu` | Kiểm tra dịch vụ nền thật (chỉ đọc); phần đồng hồ chạy `-ChayThu` nên không hỏi UAC, `bcdedit /enum` bị từ chối khi không có quyền Admin |

`tram/1_LanCanAnToan` cũng đọc trạng thái Bảo vệ hệ thống, winget, dịch vụ SysMain, build Windows (chỉ đọc).

## Bộ thử

| Bộ | Thử gì |
|---|---|
| `tinh` | cú pháp mọi `.ps1` (cả PowerShell nhúng trong `.bat`), BOM/CRLF, danh mục `tool.json`, lược đồ, không commit dữ liệu khách; action tự nâng quyền đợi cửa sổ Admin và trả mã của nó; công cụ khai `ketQua` có mã ghi theo chuẩn `tramtool.ketqua/1` |
| `tram` | lan can an toàn (điểm khôi phục, trả lại trạng thái, sửa winget), mã thoát qua Launcher, tham số từ `tool.json`, CaiDat; `5_KetQua`: đọc file kết quả (chuẩn và cách ghi cũ), gắn vào lần chạy, mã 2/3 trong Lịch sử, theo dõi công cụ tự nâng quyền, máy chủ giao diện web giả (`server.json`, mở lại, tắt, đang bận) |
| `new-windows` | mã hoá AES/HMAC, zip, xuất/nhập giữa hai "máy" giả, không lộ mật khẩu ra đĩa, chạy thử, hết đầu vào, hai `.bat` |
| `myexcelfix` | sửa rồi hoàn tác trên bộ MyExcel giả, hết đầu vào giữa chừng, manifest cũ, kiểm tra chỉ đọc; JSON kết quả theo chuẩn của trạm (gợi ý chạy tiếp, trạm đọc lại khớp); nơi lưu riêng của tài khoản (sao lưu, báo cáo, chuyển file cũ khỏi Public Documents), che số và tên chủ tài khoản, `HOAN_TAC.bat` không tham số liệt kê bản sao lưu |
| `office` | che khoá sản phẩm, đọc mẫu, gỡ, cài, kích hoạt (ODT, giấy phép, tiến trình đều giả); mọi chỗ ghi phát hiện của Kiểm tra có mã, JSON kết quả (thứ tự, nút chạy tiếp, chạy thử, thiếu quyền Admin, huỷ thì không ghi, lỗi lạ, khoá bị che) |
| `bitlocker` | lưu khoá, tạm dừng, bật lại, mở khoá, giải mã, hoàn tác trên ổ giả; khoá không lọt vào báo cáo, nhật ký, JSON kết quả; mỗi phát hiện của Kiểm tra có mã riêng, nút gợi ý trỏ tới chế độ có thật |
| `don-o-c` | danh sách cho phép xoá, xoá theo tuổi file, junction, trình duyệt, WinSxS (trong thư mục cát); mọi chỗ ghi phát hiện có mã, JSON kết quả (cùng mức thì mục lớn lên trước) |
| `github-logout` | đọc `cmdkey /list` (cả Windows tiếng Việt), chia mục Git / GitHub CLI / ứng dụng khác, xoá, đọc lại, chạy thử (Credential Manager giả) |
| `checkwinfix` | `3_ThuThap`: mọi cảnh báo có mã và mức, gợi ý chạy tiếp trỏ tới action có thật; lỗi ổ USB hoặc ổ đã rút chỉ là cảnh báo; kiểm tra sâu (DISM, chkdsk /scan giả); tham số từ trạm; JSON theo chuẩn mà trạm đọc được; `4_ChuyenSau`: bốn script chuyên sâu có mã riêng ở mọi kết luận, `cheDo` đúng action, file kết quả khai trong `tool.json` |
| `toi-uu` | tắt/bật dịch vụ (sc.exe giả), đổi BCD (bcdedit giả), BitLocker; phát hiện có mã cho Kiểm tra chung; chuyển file trạng thái gốc từ chỗ cũ (`service-optimizer`); `ToiUu.ps1` gộp hai phần, mã thoát chung, gọi script con thật trong cùng cửa sổ |
| `gio-chu-ky-so` | độ lệch giờ, múi giờ, dịch vụ, token, chứng thư (giả lập); sửa giờ (đặt giờ khi đồng bộ xong vẫn lệch, máy trong domain không đổi cấu hình), sửa dịch vụ token, trả lại như cũ, giữ giá trị của lần sửa đầu; JSON kết quả mà trạm đọc được |
| `bo-ung-dung` | danh sách `DanhSach.json` khớp ô chọn trong `tool.json`, khoá không trùng tiền tố tham số của script; chọn bằng cờ; cài (bỏ qua ứng dụng đã có, bộ gõ cùng nhóm chỉ cài một, đọc lại danh sách đã cài thay vì tin mã thoát, cần khởi động lại), cập nhật (đã mới nhất, lỗi); winget giả; JSON kết quả mà trạm đọc được |
| `ghi-am-sang-word` | tên kết quả giữ đuôi file gốc, nhận kết quả bản cũ, `--ra` (Python của máy, không nạp mô hình) |
| `may-in-lan` | mã lỗi Windows và cách xử lý, tách UNC, máy in bản sao; nhật ký hoàn tác (registry thử); mỗi phát hiện của Chẩn đoán có mã cố định, nút sửa trỏ tới action có thật, JSON kết quả mà trạm đọc được |
| `fix-win` | DISM, SFC (CBS.log giả), mạng, tường lửa, ổ đĩa, RAM, Windows Update với lệnh giả; mỗi kết quả có mã, nút gợi ý trỏ tới action có thật, JSON kết quả từng chế độ |
| các bộ khác | `the-xe-nt` |
| `mdf2sql` | `1_ChayTool`: hai `.bat` với `python.exe` giả (lối tắt Store, thiếu pyodbc, pip lỗi); `tools\mdf2sql\tests` (unittest): doctor, cổng riêng, `/api/health`, `/api/shutdown`, từ chối khi thiếu mã vẫn trả 403 (không mất câu trả lời), `doctor --ket-qua` theo chuẩn của trạm, hộp thoại chọn file trong tiến trình con, CLI |

## Viết bài thử mới

```powershell
# Mô tả ngắn: thử gì, giả lập gì, có đụng máy thật không.
# KiemThu: doc-may          (chỉ khi có đọc máy thật; thêm 32bit nếu cần PowerShell 32 bit)
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$env:TRAMTOOL_<CONGCU>_TEST = '1'          # công cụ dừng trước phần chính khi biến này có
. "$ToolsDir\<id>\<Script>.ps1"
function Invoke-LenhDoiMay { ... }         # ghi đè hàm đổi máy bằng hàm giả TRƯỚC khi gọi
Check ($r -eq 0) 'mô tả'                   # hoặc: Check 'tên' ($r -eq 0) 'thông tin khi hỏng'
Skip-Test 'lý do'                          # khi máy thiếu điều kiện
Complete-Test                              # in tổng kết, thoát 0/1
```

- File `tests\<bộ>\<số>_<Tên>.ps1`; file bắt đầu bằng `_` là thư viện riêng của bộ, không tự chạy.
- Đầu vào chuyển hướng (câu trả lời, mật khẩu giả): `<số>_<Tên>.dauvao.txt` cạnh bài, mỗi dòng một lần hỏi.
- Biến có sẵn: `$RepoRoot`, `$ToolsDir`, `$HubDir`, `$TestRoot` (thư mục tạm sạch riêng của bài); hàm `New-TestDir`,
  `Clear-TestRegistry`, `Test-Is32BitHost`, `Invoke-Bat` (chạy `.bat`, đọc đầu ra, đóng đầu vào để `pause` không
  treo), `New-FakeExe` (biên dịch `.exe` giả để `.bat` gọi qua `PATH`: `.bat` gọi một `.cmd` khác mà không có `call`
  thì không quay lại), `Find-Python` (bỏ qua lối tắt Microsoft Store).
- Dữ liệu trong bài thử là giả (khoá BitLocker, mật khẩu Wi-Fi, khoá Office, mã thẻ); không chép dữ liệu khách vào đây.
- Sau khi sửa: `powershell -ExecutionPolicy Bypass -File hub\dev\Normalize-Encoding.ps1 -Path tests`.
