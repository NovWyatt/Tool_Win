# Trạm Tool

Bộ công cụ Windows của Wyatt (chẩn đoán, sửa lỗi, tối ưu, văn phòng, chuyển đổi dữ liệu, cài lại máy) và một
**trạm** để tìm, chạy và theo dõi tất cả từ một chỗ.

## Cài trên máy mới

Chép cả thư mục `Tool_Win` sang máy (hoặc giải nén file .zip), rồi bấm đúp **`CAI_DAT.bat`** một lần.

- Bộ cài kiểm tra từng công cụ cần gì (giống mục *Yêu cầu để chạy* trong trạm), in danh sách còn thiếu kèm cách cài,
  thời gian, có cần quyền Admin không; gõ `C` để cài tất cả hoặc `T` để chọn từng mục.
- Cài theo thứ tự: gói winget (Python 3.12, ODBC Driver 18), script cài của từng công cụ (`.venv`, LibreDWG, mô hình
  ghi âm khoảng 5 GB), script của trạm cần Admin (SQL Server LocalDB). Xong thì kiểm tra lại, tạo lối tắt **Trạm Tool**
  trên Desktop và mở trạm.
- Tự bỏ dấu "tải từ Internet" của file trong thư mục trạm (Windows hay chặn `.bat`, `.ps1` giải nén từ .zip tải về), tự
  lấy `tools\mdf2sql` khi thư mục này trống (bản .zip của GitHub không kèm submodule).
- Chạy lại bao nhiêu lần cũng được: thứ đã có thì bỏ qua. `CAI_DAT.bat -ChayThu` chỉ kiểm tra, không cài gì;
  `CAI_DAT.bat -TatCa` không hỏi.
- Dùng `.bat` thay vì đóng thành `.exe`: file `.exe` tự đóng gói từ script PowerShell (không có chữ ký số) thường bị
  phần mềm diệt virus và SmartScreen chặn, còn `.bat` mở ra đọc được từng dòng.

## Mở trạm

Bấm đúp **`TramTool.bat`**.

- Giao diện mở trong Brave dạng cửa sổ ứng dụng (không có Brave thì Edge, rồi Chrome). Đổi trong *Cài đặt*.
- Cửa sổ PowerShell thu nhỏ trên thanh tác vụ là máy chủ của trạm: đóng nó là tắt trạm. Trạm cũng tự tắt khi đã đóng
  hết cửa sổ giao diện quá 10 phút (đổi trong *Cài đặt*).
- Bấm `TramTool.bat` lần nữa khi trạm đang chạy thì chỉ mở lại giao diện, không chạy thêm máy chủ.
- *Cài đặt → Tạo lối tắt* để có biểu tượng **Trạm Tool** trên Desktop.
- Tuỳ chọn dòng lệnh: `TramTool.bat -Browser edge`, `TramTool.bat -NoBrowser`, `TramTool.bat -Port 47800`.

Trong trạm:

- **Ctrl+K** (hoặc `/`): tìm và chạy nhanh công cụ, việc, trang, kết quả. Gõ `>` để chỉ hiện việc chạy được.
- **Tổng quan**: mục *Cần chú ý* (thiếu thư viện, ổ gần đầy, máy bật quá lâu, lần chạy báo lỗi, Secure Boot, Bảo vệ
  hệ thống đang tắt, winget hỏng), công cụ đã ghim, việc dùng gần đây.
- Thanh **Đang chạy** ở cuối trang theo dõi cửa sổ công cụ mở từ trạm; **Lịch sử chạy** ghi kết quả (xong, báo lỗi kèm
  mã, đã đóng cửa sổ), thời gian chạy, điểm khôi phục đã tạo, các mục đã đổi so với trước khi chạy, và chạy lại với
  tham số cũ.
- **Máy này**: thông tin máy, Bảo vệ hệ thống (bật được ngay tại đây), winget (có nút *Sửa winget*).
- **Kết quả gần đây**: mở file, mở thư mục, chọn nhiều để xoá. Xoá là chuyển vào Thùng rác; bản sao lưu có cảnh báo
  phải đánh dấu đã đọc mới xoá được.

Trạm chỉ cần Windows 10/11 với Windows PowerShell 5.1 có sẵn. Mỗi công cụ có điều kiện riêng (Python, mô hình,
driver...): trạm kiểm tra khi mở trang công cụ và có nút **Cài** cho thứ còn thiếu.

## Công cụ

| Thư mục | Công cụ | Làm gì |
|---|---|---|
| `tools\checkwinfix` | CheckWinFix | Chẩn đoán máy chậm, ổ cứng sắp hỏng, lỗi WHEA, màn hình xanh, sụp nguồn; xuất báo cáo gửi người hỗ trợ; cứu dữ liệu SQL Server. |
| `tools\health-report` | Báo cáo sức khoẻ máy | Kiểm tra nhanh CPU, RAM, ổ đĩa, SMART, nhật ký lỗi, ghi ra Desktop. |
| `tools\fix-win` | Sửa lỗi Windows | DISM rồi SFC, đặt lại mạng, đặt lại tường lửa (có sao lưu), quét và sửa ổ đĩa, kiểm tra RAM, đặt lại Windows Update. |
| `tools\wifi-fix` | Kiểm tra và sửa lỗi Wi-Fi | `KET_NOI_WIFI.bat`: sửa lỗi "Can't connect to this network" khi vào mạng mới, xem vì sao Wi-Fi không kết nối (nhật ký 7 ngày), mở trang driver. Menu cũ: đặt lại IP, DNS, Winsock. |
| `tools\may-in-lan` | Máy in mạng LAN và thư mục chia sẻ | Chẩn đoán in, chia sẻ, SMB; sửa hàng đợi kẹt, máy in trùng, lỗi 0x0000011B, 0x00000709, 0x00000BCB; thêm máy in bằng IP, gắn ổ mạng; có hoàn tác. |
| `tools\don-o-c` | Dọn ổ C an toàn | Xem ổ C đầy vì đâu; dọn file tạm cũ, bộ nhớ đệm trình duyệt, file tải về của Windows Update, WinSxS. Xem trước rồi mới xoá, không đụng dữ liệu cá nhân, thùng rác. |
| `tools\service-optimizer` | Tắt/bật dịch vụ nền | DiagTrack, Windows Insider, SysMain, Tối ưu ổ đĩa; lưu kiểu khởi động cũ để bật lại đúng. |
| `tools\clock-optimizer` | Tối ưu đồng hồ hệ thống | Dynamic Tick, ép HPET trong BCD (`bcdedit`); trả về mặc định của Windows. |
| `tools\office` | Gỡ sạch và cài Office theo mẫu | Gỡ mọi bản Office (Click-to-Run, MSI, Microsoft Store, phần sót, khoá cũ), sao lưu mẫu Word, macro, chữ ký; cài theo bộ cài mẫu ODT của bạn, kiểm tra và kích hoạt. Khoá trong mẫu không bao giờ hiện ra. |
| `tools\myexcelfix` | MyExcel VietQR | Chẩn đoán và sửa add-in MyExcel không bật hoặc không tạo được VietQR; hoàn tác an toàn (giữ bản file Excel đã sửa tiếp), mã thoát và JSON kết quả. |
| `tools\dwg2pdf` | Bản vẽ DWG sang PDF | Chuyển .dwg sang PDF đen trắng, mỗi khung bản vẽ một trang, không cần AutoCAD. |
| `tools\ghi-am-sang-word` | Ghi âm sang Word | Nhận dạng giọng nói tiếng Việt offline trên card NVIDIA, xuất Word có mốc thời gian. |
| `tools\mdf2sql` | Khôi phục .mdf sang .sql | Đọc file SQL Server .mdf (kể cả tắt đột ngột, thiếu .ldf), xuất .sql cho SQL Server hoặc MySQL; nút kiểm tra máy đủ điều kiện (pyodbc, ODBC, SQL Server) và in cách sửa. Git submodule. |
| `tools\the-xe-nt` | File thẻ xe .nt | Chuyển danh sách Excel sang file .nt cho phần mềm giữ xe (ITS Pro), kèm file thử 1 thẻ; kiểm tra file .nt như phần mềm đọc, so từng thẻ với danh sách Excel; chuyển file .nt sang Excel kèm kết quả từng thẻ; sửa file của bên bán bị mất số 0 ở CardID. Không cần Excel. |
| `tools\new-windows` | Chuyển dữ liệu khi cài lại Windows | Sao lưu ra USB hoặc ổ chọn rồi khôi phục Wi-Fi, máy in, khoá BitLocker, driver mạng, dữ liệu Claude; tuỳ chọn mã hoá mật khẩu Wi-Fi và cấu hình Claude; không dùng bản sao lưu dở dang. |
| `tools\bitlocker` | BitLocker và khoá khôi phục | Kiểm tra ổ mã hoá, khoá khôi phục đã lưu ở đâu; lưu khoá ra file, USB; tạm dừng trước khi cập nhật BIOS; mở khoá, giải mã ổ dữ liệu; có hoàn tác. |
| `tools\github-logout` | Đăng xuất GitHub | Xoá thông tin đăng nhập GitHub mà Git lưu trong Windows. |

Mọi công cụ vẫn chạy được khi bấm đúp script trong thư mục của nó; trạm chỉ là nơi mở cho tiện.
Đánh giá, lỗi đã biết và lộ trình nâng cấp: [docs/PHAN-TICH-NANG-CAP.md](docs/PHAN-TICH-NANG-CAP.md)
(trong trạm: mục *Phân tích và nâng cấp*).

## Thêm công cụ

Thả thư mục công cụ vào `tools\`, bấm *Làm mới* trong trạm. Viết `tool.json` để đặt tên, nhóm, mức rủi ro, form tham số,
điều kiện cần cài: xem [docs/THEM-CONG-CU.md](docs/THEM-CONG-CU.md). Schema cho VS Code: `hub\schema\tool.schema.json`.

## Cấu trúc

```
TramTool.bat              mở trạm
CAI_DAT.bat               cài một lần cho máy mới (hub\CaiDat.ps1)
hub\
  TramTool.ps1            máy chủ HTTP cục bộ và API
  lib\                    Catalog (đọc tool.json), Launcher (chạy công cụ), Checks (điều kiện, kết quả, thông tin máy),
                          AnToan (điểm khôi phục, ghi trạng thái trước khi chạy, kiểm tra winget)
  safety\                 script lan can chạy bằng quyền Admin: tạo điểm khôi phục, trả lại trạng thái, bật Bảo vệ hệ thống
  web\                    giao diện; thư viện ngoài nằm sẵn trong web\vendor\ (chạy không cần mạng)
  schema\                 tool.schema.json
  fixes\                  script cài đặt, sửa dùng chung (SQL Server LocalDB, winget...)
  dev\                    Normalize-Encoding.ps1
  data\                   lịch sử chạy, cài đặt, mã phiên, trạng thái trước khi chạy (máy nào giữ máy đó, không commit)
tools\<id>\               mỗi công cụ một thư mục, có tool.json
tests\                    bài thử giả lập: ChayTatCa.ps1 chạy hết, mỗi bộ một thư mục (xem tests\README.md)
docs\                     phân tích nâng cấp, hướng dẫn thêm công cụ
```

## An toàn

- Máy chủ chỉ nghe `127.0.0.1`. Mỗi lần mở trạm sinh một mã thông hành ngẫu nhiên; trang web khác trên máy không gọi
  được API vì không có mã và bị chặn theo Host/Origin.
- Trạm chỉ chạy các action khai báo trong `tool.json`, với file nằm trong thư mục công cụ. Giá trị người dùng nhập được
  kiểm tra kiểu và ký tự trước khi truyền vào script.
- Action thay đổi máy hiện hộp xác nhận liệt kê thay đổi; action cần Admin đi qua hộp thoại UAC của Windows.
- Trước action thay đổi máy bằng quyền Admin, trạm tạo điểm khôi phục hệ thống ngay trong cửa sổ công cụ (bỏ chọn được
  ở hộp xác nhận, tắt hẳn trong *Cài đặt*). Không tạo được thì hỏi chạy tiếp hay huỷ, không tự quyết.
- Trạm ghi kiểu khởi động dịch vụ và giá trị registry HKLM công cụ khai báo (`probes`) ngay trước khi chạy; trang
  *Lịch sử* so với hiện tại và trả lại được mục đã đổi (cửa sổ Admin ghi rõ từng mục).
- Trạm không tự cài gì: nút *Cài* mở cửa sổ cài đặt để người dùng thấy và đồng ý; trước đó trạm kiểm tra winget còn
  dùng được.
- Xoá kết quả chỉ nhận đúng file, thư mục đang được liệt kê là kết quả của công cụ, và chỉ chuyển vào Thùng rác.

## Dữ liệu khách

Không bao giờ commit báo cáo có tên máy khách, file ghi âm, bản vẽ, cơ sở dữ liệu, bản sao lưu (chứa mật khẩu Wi-Fi,
dữ liệu Claude). Kết quả để trong `ket_qua\` hoặc `du-lieu\` của từng công cụ; `.gitignore` đã chặn các thư mục đó và
các mẫu tên báo cáo. Thêm công cụ mới có mẫu tên kết quả mới thì bổ sung `.gitignore` trước khi commit.

## Phát triển

- Lấy cả submodule: `git clone --recurse-submodules`, hoặc `git submodule update --init` sau khi clone.
  Commit trong `tools\mdf2sql` phải push lên repo `mdf2sql` trước khi push repo này.
- Sau khi sửa `.ps1`/`.bat`: `powershell -ExecutionPolicy Bypass -File hub\dev\Normalize-Encoding.ps1` (`.ps1` UTF-8 có BOM,
  `.bat` không BOM, CRLF).
- Trước khi commit chạy bài thử: `tests\CHAY_KIEM_THU.bat` hoặc
  `powershell -ExecutionPolicy Bypass -File tests\ChayTatCa.ps1 [-Chi <bộ>]` (quyền thường, khoảng 6 phút cả lượt; lệnh đổi
  máy đều là hàm giả). Thêm, sửa công cụ thì thêm bài thử vào `tests\<id>\`; cách viết ở `tests\README.md`.
- Chạy máy chủ không mở trình duyệt: `TramTool.bat -NoBrowser`. Cổng và mã thông hành nằm trong `hub\data\runtime.json`;
  mở `http://127.0.0.1:<port>/#t=<token>`.
- Thử giao diện mà không đụng lịch sử, cài đặt thật: thêm `-DataDir <thư mục tạm>\data`, và `-ToolsDir <thư mục tạm>\tools`
  để dùng công cụ giả (một `tool.json` trỏ tới `.bat` chờ vài giây rồi thoát) khi thử nút Chạy, Xoá.
- Giao diện là ES module chạy thẳng, không cần build: `hub\web\app.js` (định tuyến), `hub\web\js\` (dữ liệu, hộp thoại,
  ô tìm nhanh, thanh Đang chạy), `hub\web\js\pages\` (mỗi trang một file), vẽ bằng lit-html trên phần tử HTML gốc.
  Màu, chữ, hình dạng nằm hết trong `hub\web\app.css` (biến màu cho sáng và tối, một màu nhấn xanh dầu, bo góc 8px).
  Chữ Be Vietnam Pro, JetBrains Mono và biểu tượng Phosphor nằm sẵn trong `hub\web\vendor\`, `hub\web\icons.svg`.
- Môi trường Python của công cụ cài bằng `CAI_DAT.ps1` trong thư mục công cụ (DWG sang PDF, Ghi âm sang Word),
  phiên bản khoá trong `requirements-lock.txt`.
