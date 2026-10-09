# Gói tiếng Việt

Gõ ra dấu lặp hoặc mất dấu, số trong Excel bị lệch (1.500 thành 1,5), ngày bị đảo, tài liệu cũ hiện chữ kiểu
"Coäng hoøa", "Céng hoµ": chạy **Kiểm tra** trước. Bấm đúp `TIENG_VIET.bat` để mở menu, hoặc chạy từ Trạm Tool.
Không mục nào cần quyền Admin.

## Kiểm tra (chỉ đọc)

| Mục | Cách đọc | Báo khi |
|---|---|---|
| Bộ gõ đang chạy | Tên tiến trình của UniKey, EVKey, OpenKey, Vietkey, GoTiengViet, Laban Key, VPSKeys; quyền chạy của tiến trình | hai bộ gõ cùng chạy (lỗi), một bộ chạy hai bản, không có bộ gõ nào; bộ gõ chạy bằng quyền thường thì nhắc phần mềm chạy bằng quyền Admin sẽ không gõ được dấu |
| Khởi động cùng Windows | Khoá Run (tài khoản, cả máy, 32-bit), thư mục Startup (đọc đích lối tắt), Task Scheduler; bỏ qua mục đã tắt trong Task Manager | hai bộ gõ cùng khởi động, một bộ đặt khởi động ở hai chỗ, có khởi động mà đang không chạy |
| Bàn phím của Windows | Danh sách ngôn ngữ của tài khoản: bàn phím Vietnamese (`0000042A`), bộ gõ Telex của Windows 11 | bật cùng một bộ gõ ngoài |
| Font cũ | Font đã cài (cả máy và riêng tài khoản) tên `VNI-...`, `.Vn...` | chỉ để biết; gợi ý chuyển tài liệu sang Unicode |
| Định dạng số | `HKCU\Control Panel\International`: dấu thập phân, dấu nghìn, dấu ngăn danh sách, định dạng tiền | dấu thập phân trùng dấu nghìn hoặc trùng dấu ngăn danh sách (lỗi), định dạng tiền khác định dạng số |
| Định dạng ngày | Mẫu ngày ngắn | tháng đứng trước (`M/d/yyyy`: 05/10 là ngày 10 tháng 5), năm chỉ có 2 số |
| Excel | `UseSystemSeparators` của Excel 2010 trở về sau | Excel dùng dấu riêng, đổi định dạng của Windows không có tác dụng |
| Phần mềm cũ | Ngôn ngữ cho chương trình không Unicode, bảng mã | đang bật *Beta: Use Unicode UTF-8* (phần mềm cũ có thể lỗi chữ) |

## Đặt định dạng số và ngày

Chọn một kiểu, đổi cho tài khoản đang dùng (như chỉnh ở Control Panel > Region, qua `SetLocaleInfo` rồi báo cho các
cửa sổ đọc lại):

| | Số | Công thức Excel | Ngày |
|---|---|---|---|
| Việt Nam (`-Mau vn`, mặc định) | 1.234.567,89 | `=SUM(A1;B1)` | 31/12/2026 |
| Quốc tế (`-Mau quoc-te`) | 1,234,567.89 | `=SUM(A1,B1)` | 31/12/2026 |

Định dạng tiền đổi theo định dạng số. Đánh dấu *Excel dùng dấu của Windows* (`-ExcelTheoWindows`) thì Excel đang dùng
dấu riêng sẽ dùng lại dấu của Windows; Excel phải đang tắt (Excel ghi đè tuỳ chọn khi đóng), đang mở thì công cụ bỏ
qua mục này và báo làm được một phần. Excel, Word, phần mềm kế toán đang mở cần mở lại mới thấy định dạng mới.

Công ty dùng chung file Excel, phần mềm kế toán thì chọn giống các máy khác: đổi dấu ngăn danh sách làm file CSV xuất
ra khác trước (cột ngăn bằng dấu `;` thay cho `,`).

**Trả lại**: trước lần đổi đầu tiên, giá trị cũ được lưu vào `ket_qua\TrangThaiGoc_TiengViet_<tên máy>_<tài khoản>.json`
(đổi nhiều lần vẫn giữ giá trị lúc đầu); nút *Trả định dạng như trước khi đổi* trả về đúng các giá trị đó rồi xoá file.
Mọi nút đổi in việc sẽ làm trước; ô *Chạy thử* (hoặc `-ChayThu`) chỉ xem, không đổi máy.

## Chuyển tài liệu font VNI, TCVN3 sang Unicode

Kéo thả file `.docx`, `.xlsx` (hoặc cả thư mục) vào `CHUYEN_UNICODE.bat`, hoặc dùng nút *Chuyển tài liệu sang Unicode*
trong Trạm, hoặc mục 4 của menu. Mỗi file có chữ font cũ được chép thành `<tên>_Unicode.docx` cạnh file gốc (đã có thì
`<tên>_Unicode (2).docx`); file gốc không bị đổi. File `.doc`, `.xls`, `.rtf` cũ thì mở bằng Word, Excel, lưu lại dạng
`.docx`, `.xlsx` trước.

- Chữ được giải mã theo **font của đoạn chữ**, đúng thứ tự Word tìm font (font đặt thẳng, kiểu ký tự, kiểu đoạn, mặc
  định của tài liệu); Excel theo font của ô, chữ nhiều định dạng theo font từng đoạn. Không đoán theo nội dung nên chữ
  tiếng Anh trong font Unicode không bị đổi nhầm; chữ đã là Unicode trong font cũ thì bỏ qua.
- Font cũ đổi sang font có sẵn trong Windows: `VNI-Times`, `.VnTime` thành Times New Roman; `VNI-Helve`, `.VnArial`
  thành Arial; font gõ máy thành Courier New. Chữ hoa của font TCVN3 dạng `H` (`.VnTimeH`...) giữ chữ hoa.
- Word: thân văn bản (cả hộp văn bản, bảng), đầu trang, chân trang, chú thích, ghi chú. Excel: ô chữ, kết quả công thức
  dạng chữ, ghi chú. Chữ dùng chung vừa ở ô font cũ vừa ở ô font Unicode thì tách thành hai bản.
- Chưa đổi: chữ trong biểu đồ, hình vẽ, SmartArt, tên trang tính, đầu trang Excel, chuỗi trong công thức.
- *Chỉ xem* (`--chi-xem`): liệt kê file nào có chữ font cũ, font gì, chưa tạo bản sao.

Cần Python 3.9 trở lên (chỉ dùng thư viện chuẩn, không cài thêm gì). Máy chưa có thì bấm *Cài Python 3.12* trong Trạm,
hoặc `winget install -e --id Python.Python.3.12 --scope user`.

Chạy thẳng: `CHUYEN_UNICODE.bat <file hoặc thư mục>... [--thu-muc <thư mục>] [--de-quy] [--ra <thư mục>] [--chi-xem]`.
Mã thoát: 0 xong, 2 không có file `.docx`, `.xlsx` nào hoặc thiếu Python, 3 có file lỗi.

## Gặp thường

- **Gõ ra "tiêếng", dấu lặp, chữ nhảy**: hai bộ gõ cùng chạy, hoặc bàn phím tiếng Việt của Windows đang bật cùng
  UniKey. Thoát bớt một bộ, bỏ bàn phím Vietnamese ở Cài đặt > Thời gian và ngôn ngữ > Ngôn ngữ và vùng.
- **Phần mềm kế toán không gõ được dấu**: phần mềm chạy bằng quyền Admin mà bộ gõ chạy bằng quyền thường; cho bộ gõ
  chạy bằng quyền Admin (EVKey, OpenKey có tuỳ chọn này).
- **Excel báo lỗi công thức sau khi đổi kiểu**: công thức gõ tay theo kiểu cũ (`=SUM(A1,B1)`) cần đổi dấu ngăn; công
  thức đã có trong file thì Excel tự đổi.

## Kết quả cho Trạm Tool

Mỗi lần chạy `TiengViet.ps1` ghi `ket_qua\KetQua_TiengViet_<tên máy>_<giờ>.json`, mỗi lần chuyển tài liệu ghi
`ket_qua\KetQua_TiengViet_ChuyenUnicode_<tên máy>_<giờ>.json`, theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`). Mã phát hiện cố định: `BO_GO_TRUNG`, `BO_GO_KHOI_DONG_TRUNG`, `BAN_PHIM_WINDOWS_TRUNG`,
`SO_TRUNG_DAU`, `NGAY_THANG_TRUOC`, `EXCEL_DAU_RIENG`, `UTF8_BETA`, `DA_CHUYEN`, `CO_CHU_FONT_CU`...; phát hiện có nút
sửa thì kèm nút chạy tiếp.

Chạy thẳng: `TIENG_VIET.bat -Mode kiem-tra|dinh-dang|tra-lai [-Mau vn|quoc-te] [-ExcelTheoWindows] [-ChayThu] [-KhongDung]`.
Mã thoát: 0 xong (kể cả khi Kiểm tra có cảnh báo), 1 lỗi, 2 đã huỷ, 3 làm được một phần.
