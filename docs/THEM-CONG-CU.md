# Thêm công cụ vào Trạm Tool

Mỗi công cụ là một thư mục trong `tools\`. Trạm đọc `tools\<thư-mục>\tool.json` để biết tên, nhóm, các nút chạy,
form tham số, điều kiện cần cài, trạng thái máy và nơi lưu kết quả. Không cần sửa code của trạm.

## Cách nhanh: thả vào là chạy

1. Chép thư mục công cụ vào `tools\` (hoặc thả một file `.bat`, `.cmd`, `.ps1` lẻ vào `tools\`).
2. Trong trạm vào **Cài đặt → Làm mới** (hoặc mở lại trạm).
3. Công cụ hiện ở nhóm **Chưa phân loại**. Mỗi script ở cấp ngoài cùng của thư mục thành một nút chạy;
   trạm coi mọi nút là *Thay đổi hệ thống* nên luôn hỏi xác nhận trước khi chạy.
4. Mở trang công cụ, bấm **Tạo tool.json** để sinh file khởi đầu (script lẻ được chuyển vào thư mục riêng),
   rồi sửa lại theo các mục dưới đây.

Thư mục bắt đầu bằng `.` hoặc `_` bị bỏ qua: dùng cho bản nháp chưa muốn hiện trong trạm.

## tool.json tối thiểu

```json
{
  "$schema": "../../hub/schema/tool.schema.json",
  "id": "don-may-in",
  "name": "Dọn hàng đợi máy in",
  "version": "1.0",
  "category": "sua-loi",
  "icon": "wrench",
  "audience": "all",
  "summary": "Xoá lệnh in bị kẹt và khởi động lại dịch vụ Print Spooler.",
  "docs": "HUONG-DAN.md",
  "actions": [
    {
      "id": "don",
      "label": "Dọn hàng đợi in",
      "file": "DonMayIn.bat",
      "admin": true,
      "risk": "modifies-system",
      "duration": "Vài giây",
      "description": "Dừng Spooler, xoá file trong spool\\PRINTERS rồi bật lại Spooler.",
      "changes": ["Xoá các lệnh in đang chờ"]
    }
  ]
}
```

Mở file bằng VS Code: nhờ dòng `$schema`, trình soạn thảo gợi ý tên trường, giá trị hợp lệ và gạch đỏ chỗ sai.
Lỗi trạm phát hiện khi đọc (thiếu file, sai mức rủi ro, flag sai...) cũng hiện ở đầu trang công cụ.

## Thông tin chung

| Trường | Bắt buộc | Ý nghĩa |
|---|---|---|
| `id` | có | Chữ thường không dấu, nối bằng `-`. Dùng trong địa chỉ trang, ghim và lịch sử: đổi id là mất ghim, lịch sử cũ. |
| `name` | có | Tên hiển thị, viết cho người dùng cuối. |
| `summary` | có | Một câu: công cụ làm gì. Hiện trong danh sách và kết quả tìm kiếm. |
| `description` | | Khi nào dùng, cần chuẩn bị gì. |
| `version` | | Vd `1.0` hoặc `2026.10`. |
| `category` | | Nhóm ở thanh bên, xem `hub\categories.json`. Thiếu thì vào *Chưa phân loại*. |
| `icon` | | Tên biểu tượng trong `hub\web\icons.svg` (VS Code gợi ý danh sách). |
| `audience` | | `all` (mặc định) hoặc `tech`: công cụ kỹ thuật, ẩn khi bật *Chế độ đơn giản*. |
| `status`, `statusNote` | | `ok` / `warning` / `broken` và câu giải thích hiện ở đầu trang. |
| `tags` | | Từ khoá phụ cho ô tìm kiếm (gõ không dấu vẫn tìm ra). |
| `docs` | | File hướng dẫn `.md` hoặc `.txt` trong thư mục công cụ; trạm hiển thị ngay trong trang. |
| `issues`, `upgrades` | | Lỗi đã biết và hướng nâng cấp. `upgrades` mở đầu bằng `P0 – `, `P1 – ` hoặc `P2 – `. |

## Nút chạy (`actions`)

| Trường | Ý nghĩa |
|---|---|
| `id`, `label` | Mã nút (duy nhất trong công cụ) và chữ trên nút. |
| `type` | `console` (mặc định): chạy `.bat`/`.cmd`/`.ps1` trong cửa sổ riêng. `open`: mở file bằng chương trình mặc định. `url`: mở trang web (khai báo `url` thay cho `file`). |
| `file` | Đường dẫn tương đối trong thư mục công cụ. Trỏ ra ngoài thư mục công cụ thì trạm từ chối. |
| `admin` | `true`: trạm mở bằng quyền Admin, Windows hỏi UAC. Bấm "Không" thì trạm báo đã huỷ. |
| `selfElevates` | Script tự xin quyền Admin khi bấm đúp ngoài trạm. Chỉ để ghi nhận: trạm dựa vào `admin` để quyết định. |
| `risk` | `read-only` (chỉ đọc), `asks-before-change` (script tự hỏi trước khi sửa), `modifies-system` (thay đổi máy). Thiếu thì coi là `modifies-system`. |
| `confirm`, `changes` | Cảnh báo riêng và danh sách thay đổi, hiện trong hộp xác nhận. Hộp xác nhận hiện khi `risk` là `modifies-system` hoặc có `confirm`. |
| `primary` | Nút chính. Không khai báo thì nút đầu tiên là nút chính. |
| `duration` | Thời gian ước lượng, vd `Dưới 1 phút`. |
| `keepOpen` | Giữ cửa sổ sau khi script xong để người dùng đọc kết quả. |
| `restorePoint` | Tạo điểm khôi phục hệ thống trong cửa sổ Admin của công cụ trước khi chạy. Mặc định `true` khi `admin` là `true` và `risk` là `modifies-system`; đặt `false` khi điểm khôi phục không có ích hoặc có hại (vd giải mã BitLocker, cứu dữ liệu từ ổ đang hỏng). Chỉ dùng được cho action `console` `.bat`/`.cmd`/`.ps1` có `admin: true`. |
| `fixedArgs` | Tham số cố định truyền trước tham số người dùng nhập, vd `["convert"]`. |
| `args` | Ô nhập trong form trước khi chạy, xem mục dưới. |

Nên chọn `risk` thật sát: nhãn màu và hộp xác nhận giúp người dùng văn phòng biết nút nào an toàn để bấm.

Điểm khôi phục: hộp xác nhận có ô *Tạo điểm khôi phục hệ thống trước khi chạy* (đánh dấu sẵn theo *Cài đặt* của trạm).
Trạm chạy `hub\safety\TaoDiemKhoiPhuc.ps1` ngay trong cửa sổ Admin của công cụ, nên chỉ hỏi UAC một lần. Bảo vệ hệ
thống đang tắt thì script hỏi bật, chạy tiếp không có điểm, hay huỷ; lỗi khi tạo thì hỏi chạy tiếp hay huỷ, không có
lựa chọn mặc định. Chọn huỷ thì script trả mã `1223`, công cụ không chạy, Lịch sử ghi *Đã huỷ*. Script công cụ không
cần làm gì thêm.

## Tham số người dùng nhập (`args`)

Khi nút có `args`, bấm **Chạy** sẽ mở form. Trình duyệt chỉ gửi *giá trị*; tên cờ, thứ tự và kiểu đều lấy từ
`tool.json`, nên người dùng không chèn thêm lệnh được.

| Kiểu | Hiển thị | Truyền vào script |
|---|---|---|
| `file` | Nút chọn file của Windows (`multiple` cho chọn nhiều, `filter` vd `Bản vẽ|*.dwg`, `startIn`: `desktop`, `documents`, `tool`) | Đường dẫn đầy đủ; nhiều file thì mỗi file một tham số |
| `folder` | Nút chọn thư mục | Đường dẫn đầy đủ (`D:\` truyền thành `D:\.`) |
| `text` | Ô chữ (`placeholder`, `help`) | Chuỗi, tối đa 300 ký tự |
| `number` | Ô số (`min`, `max`) | Số nguyên |
| `choice` | Danh sách chọn (`options`: `[{ "value": "...", "label": "..." }]`) | `value` đã chọn |
| `bool` | Ô đánh dấu (bắt buộc có `flag`) | Chỉ truyền `flag` khi được đánh dấu |

- Có `flag` thì truyền `flag giá trị` (vd `--ra "D:\PDF"`), không có thì truyền theo thứ tự khai báo.
- `required: true` bắt nhập trước khi chạy; `default` là giá trị điền sẵn.
- Giá trị không được chứa `%` hoặc `"` (cmd không truyền an toàn được); ô chữ không được chứa `!` hoặc `^`.
  Trạm báo lỗi ngay trên form.
- `dryRun: true` trên một ô `bool` đánh dấu đó là chế độ chạy thử: khi được chọn, trạm không tạo điểm khôi phục và không
  ghi trạng thái. Ô `bool` có `id` là `chay-thu` tự được coi là chạy thử.

Script nhận tham số như khi gọi từ dòng lệnh:

- `.bat`/`.cmd`: `%1`, `%2`... (dùng `%~1` để bỏ dấu ngoặc kép). Trạm chạy `cmd /s /c` sau khi `cd` vào thư mục công cụ.
- `.ps1`: khai báo `param()`. Flag được truyền không ngoặc nên khớp tham số switch, vd `[switch]$LamLai` ↔ `"flag": "-LamLai"`;
  giá trị luôn nằm trong ngoặc đơn nên giá trị bắt đầu bằng `-` không bị hiểu nhầm thành tham số.

Ví dụ một nút có form (rút từ `tools\dwg2pdf\tool.json`):

```json
{
  "id": "chuyen-thu-muc",
  "label": "Chuyển cả thư mục bản vẽ",
  "file": "CHUYEN_DWG_SANG_PDF.bat",
  "risk": "read-only",
  "args": [
    { "id": "thu-muc", "type": "folder", "required": true, "label": "Thư mục chứa bản vẽ .dwg" },
    { "id": "lam-lai", "type": "bool", "flag": "--lam-lai", "label": "Làm lại cả bản vẽ đã có PDF" },
    { "id": "song-song", "type": "number", "flag": "--song-song", "label": "Số bản vẽ xử lý cùng lúc", "default": 1, "min": 1, "max": 4,
      "help": "Mỗi bản vẽ lớn tốn vài GB RAM; máy 8 GB nên để 1." }
  ]
}
```

## Điều kiện cần (`requires`)

Trạm kiểm tra các điều kiện này khi mở trang công cụ (và trên trang **Máy này**). Thiếu thì hiện lý do và nút **Cài**.

| `type` | Kiểm tra | Trường riêng |
|---|---|---|
| `python` | Python thật trên máy (bỏ qua lối tắt Microsoft Store) | `min`, `max` (vd `"3.9"`) |
| `venv` | `.venv` của công cụ chạy được và import được thư viện | `path` (mặc định `.venv`), `modules` |
| `file` | File/thư mục trong công cụ có tồn tại | `path`, `minSizeMB` (bắt file tải dở) |
| `pymodule` | Thư viện cài vào Python chung của máy | `module`, `min` |
| `path` | Một trong các đường dẫn tồn tại (nhận `%BIEN%`, `*`) | `paths` |
| `command` | Lệnh có trong PATH | `name` |
| `odbc` | Driver ODBC đã cài | `names` |
| `sqlserver` | Có SQL Server LocalDB hoặc dịch vụ `MSSQL*` | |
| `gpu` | Có card đồ hoạ | `vendor`, vd `NVIDIA` |
| `windows` | Build Windows tối thiểu | `minBuild` |

Trường chung: `id` (cần khi có hai yêu cầu cùng kiểu), `label`, `optional` (thiếu vẫn chạy được), `fix`.
`fix` chọn **một** trong ba cách:

- `{ "label": "Cài Python 3.12", "winget": "Python.Python.3.12", "args": "--scope user" }`: mở cửa sổ chạy `winget install`.
- `{ "label": "Cài môi trường", "action": "cai-dat" }`: chạy một nút của chính công cụ (thường là script cài đặt).
- `{ "label": "Cài LocalDB", "hubScript": "Cai-SqlLocalDB.ps1", "admin": true }`: chạy script cài dùng chung trong `hub\fixes\`.

Chỉ đưa vào cách cài **miễn phí**, tải từ nguồn chính thức, và kiểm tra chữ ký hoặc SHA-256 trong script cài
(xem `hub\fixes\Cai-SqlLocalDB.ps1`, `tools\dwg2pdf\CAI_DAT.ps1`).

## Trạng thái máy (`probes`)

Với công cụ thay đổi thiết lập Windows, khai báo `probes` để trang công cụ hiện trạng thái hiện tại (chỉ đọc):

```json
"probes": [
  { "type": "service", "name": "SysMain", "label": "SysMain (SuperFetch)", "default": "Automatic" },
  {
    "type": "registry", "label": "Dynamic Tick",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\kernel", "name": "disabledynamictick",
    "values": { "1": "Đã tắt" }, "note": "Không có giá trị là mặc định của Windows."
  }
]
```

`service` so kiểu khởi động với `default` để đánh dấu *Đã đổi* / *Mặc định*. `registry` dùng `values` để đổi giá trị
thô thành chữ dễ hiểu.

Trước mỗi lần chạy action không phải `read-only` (trừ khi chọn chạy thử), trạm ghi trạng thái các mục `service` và
`registry` dưới `HKLM:\` vào `hub\data\snapshots\TrangThai_<lần chạy>.json`. Khi cửa sổ công cụ đóng, Lịch sử hiện số
mục đã khác; *Xem thay đổi* so từng mục với hiện tại và *Trả lại* mở `hub\safety\TraLaiTrangThai.ps1` bằng quyền Admin
để đặt lại kiểu khởi động (`sc.exe config`) và giá trị registry (đúng kiểu cũ; trước đó chưa có thì xoá). Registry
`HKCU` không ghi lại vì tài khoản Admin nâng quyền có thể khác tài khoản đang dùng trạm. Nên khai báo trong `probes`
mọi dịch vụ, giá trị registry công cụ có thể đổi, kể cả khi công cụ đã có nhật ký hoàn tác riêng.

## Kết quả (`outputs`)

```json
"outputs": [
  { "label": "Báo cáo chẩn đoán", "glob": "LagReport_%COMPUTERNAME%_*.txt;HwDiag_%COMPUTERNAME%_*.txt" },
  { "label": "Bản sao lưu", "dir": "{Desktop}", "glob": "MyExcelFix_SaoLuu_*", "type": "folder",
    "deleteNote": "\"Hoàn tác lần sửa\" cần đúng thư mục này. Xoá rồi thì không hoàn tác được lần sửa đó nữa." },
  { "label": "Hướng dẫn trong bản sao lưu", "dir": "DuLieu_SaoLuu", "glob": "HUONG_DAN.txt", "deletable": false }
]
```

- `dir`: mặc định thư mục công cụ; nhận `%BIEN%`, `{Desktop}` và dấu `*` ở phần cuối (vd `C:\CUU_DU_LIEU_*`).
- `glob`: nhiều mẫu cách nhau bằng `;`. Nên lọc theo `%COMPUTERNAME%` khi báo cáo có tên máy.
- `type: "folder"` khi kết quả là cả thư mục; `recurse: true` để tìm cả thư mục con.
- `deleteNote`: cảnh báo hiện trong hộp thoại xoá, người dùng phải đánh dấu "đã đọc" mới xoá được. Dùng cho bản sao
  lưu để hoàn tác, dữ liệu có mật khẩu, bằng chứng còn cần gửi đi.
- `deletable: false`: không cho xoá từ trạm. Dùng cho file nằm bên trong một bản sao lưu (xoá lẻ làm hỏng cả bộ)
  hoặc file công cụ còn đọc lại.

Trạm liệt kê kết quả mới nhất ở trang công cụ và trang **Kết quả gần đây**, có nút Mở, Thư mục và Xoá.
Trạm chỉ mở, xoá file nằm trong danh sách kết quả đã khai báo. Xoá là chuyển vào Thùng rác (ổ USB, ổ mạng không có
Thùng rác thì Windows hỏi trước khi xoá hẳn).

## Đóng gói gửi khách (`pack`)

Nút **Đóng gói gửi khách** nén các file cần thiết thành `.zip` trên Desktop, kèm `DOC-TRUOC.txt` hướng dẫn cách chạy.

```json
"pack": { "name": "MyExcelFix", "include": ["CheckMyExcel_VietQR.bat", "FixMyExcel_VietQR.bat", "HUONG-DAN.md"] }
```

Không khai báo `include` thì trạm lấy các file của `actions` và `docs`. Dấu `*` chỉ dùng ở phần tên file
(vd `"*.ps1"`, `"lib/*.ps1"`); `exclude` loại bớt theo đường dẫn tương đối (vd `"exclude": ["*_test.ps1"]`).
Nên liệt kê tên file cụ thể để gói không lẫn báo cáo, dữ liệu của khách khác.

## Quy ước viết script

- `.ps1`: UTF-8 **có BOM** (PowerShell 5.1 cần BOM để đọc đúng tiếng Việt), xuống dòng CRLF.
- `.bat`/`.cmd`: UTF-8 **không BOM** (BOM làm hỏng dòng đầu), CRLF. Trong `echo` phải escape `^&`, `^>`, `^|`;
  tránh in `%~1` bên trong khối `( ... )` vì tên file có `)` hoặc `&` sẽ phá cú pháp.
- Chạy `powershell -ExecutionPolicy Bypass -File hub\dev\Normalize-Encoding.ps1 -Path tools\<thư-mục>` sau khi sửa
  để chuẩn hoá BOM và CRLF.
- Kiểm tra quyền Admin bằng `fltmc >nul 2>&1` thay cho `net session` (lệnh này cần dịch vụ Server).
- Kiểm tra mã lỗi của từng lệnh trước khi in "thành công"; thoát với mã khác 0 khi thất bại.
- Mã thoát: `0` xong, `1` lỗi, `2` thiếu điều kiện (quyền Admin, phần mềm, thiết bị), `3` làm được một phần. Trạm
  ghi mã vào Lịch sử (khác 0 hiện *Báo lỗi, mã N*). Từ Trạm 1.1.1, `.ps1` gọi `exit N` thì trạm nhận đúng `N`;
  trước đó mọi mã khác 0 thành 1. Mã `1223` (người dùng huỷ) Lịch sử hiện *Đã huỷ*: dùng khi người dùng chọn không
  làm nữa trước khi đổi gì.
- Script thay đổi máy nên có chế độ chạy thử (công tắc `-ChayThu` trong `args`, `id` là `chay-thu`): in việc sẽ làm
  rồi thoát, không đổi gì. Một script nhiều chế độ thì mỗi chế độ một action, chọn bằng `fixedArgs` (vd `["-Mode", "chan-doan"]`),
  như `tools\may-in-lan`.
- Script phải chạy được cả khi bấm đúp ngoài trạm: trạm chỉ là nơi mở, không thay thế script.
- Kết quả và dữ liệu của khách để trong thư mục con `ket_qua\` hoặc `du-lieu\` (git bỏ qua). Mẫu tên báo cáo mới
  thì thêm vào `.gitignore` trước khi commit.

## Thêm nhóm mới

Thêm một dòng vào `hub\categories.json` (`id`, `label`, `icon`, `description`), rồi bổ sung `id` đó vào danh sách
`examples` của `category` trong `hub\schema\tool.schema.json` để VS Code gợi ý.
