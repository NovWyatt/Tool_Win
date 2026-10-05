# Gỡ sạch và cài Office theo mẫu

Dùng khi: Office lỗi mà sửa không được; máy lẫn nhiều bản Office (cài bằng MSI, Click-to-Run, Microsoft Store);
chuyển sang bản khác (Office 2019 sang LTSC 2024 hay Microsoft 365); máy mới cần cài Office giống các máy khác.

**Bộ cài mẫu** là thư mục Office Deployment Tool (ODT) bạn đã dùng để cài Office: `setup.exe`, file cấu hình `.xml`
(thường là `Configuration.xml`: sản phẩm, 32/64 bit, ngôn ngữ, ứng dụng không cài, khoá) và thư mục `Office\Data`
(bộ cài đã tải sẵn; có thì cài không cần Internet).

| Nút trong Trạm Tool | Mục menu | Dùng khi nào |
|---|---|---|
| **Kiểm tra** | 1 | **Luôn chạy trước.** Chỉ đọc. Báo Office đang cài, giấy phép, mẫu có cài được không, việc nên làm |
| Gỡ sạch Office cũ rồi cài theo mẫu | 2 | Office lỗi, lẫn nhiều bản, đổi bản khác. 20–60 phút |
| Chỉ gỡ sạch Office | 3 | Bỏ hẳn Office, hoặc gỡ trước rồi cài bản khác không theo mẫu |
| Chỉ cài Office theo mẫu | 4 | Máy chưa có Office; sau khi gỡ xong và khởi động lại máy |
| Kích hoạt Office | 5 | Office báo chưa kích hoạt; cần nhập khoá MAK hoặc khoá bản quyền của bạn |
| Trả lại mẫu Word, macro, chữ ký đã sao lưu | 6 | Cài xong thấy thiếu Normal.dotm, PERSONAL.XLSB, chữ ký Outlook... |

Ngoài Trạm Tool: bấm đúp `OFFICE.bat` để mở menu. Mục 2–5 cần quyền Admin (Windows hỏi UAC, chọn **Có**); Kiểm tra
và Trả lại chạy bằng quyền thường. Mọi nút đổi máy có **Chạy thử** (`-ChayThu`): in việc sẽ làm, không đổi gì.

## 1. Bộ cài mẫu

Công cụ tìm mẫu theo thứ tự:

1. Thư mục chọn ở ô **Thư mục bộ cài mẫu** (`-Mau`). Chọn file `setup.exe` hay file `.xml` cũng được.
2. `tools\office\mau`: chép cả thư mục mẫu vào đây để mang theo cùng công cụ.
3. `<ổ>:\Program Files\Microsoft Office` trên mọi ổ cứng và USB, thư mục nào có `setup.exe`
   (ví dụ `D:\Program Files\Microsoft Office`).

File cấu hình: ô **File cấu hình** (`-CauHinh`). Bỏ trống thì dùng `Configuration.xml`, không có thì dùng file `.xml`
duy nhất có thẻ `<Add>`. Mẫu có nhiều file mà chưa chọn: Kiểm tra báo kèm danh sách, các nút gỡ, cài hỏi chọn trong
cửa sổ công cụ.

Nút gỡ rồi cài và nút chỉ cài kiểm tra mẫu trước. Mẫu hỏng thì dừng, chưa gỡ gì:

- `setup.exe` phải có chữ ký số hợp lệ của Microsoft. Bản cũ hơn 16.0.19426.20170 có lỗ hổng CVE-2026-20943: tải
  [ODT mới](https://www.microsoft.com/download/details.aspx?id=49117) rồi chép đè `setup.exe` trong mẫu.
- File cấu hình đọc được và có sản phẩm. Office 64 bit không cài được lên Windows 32 bit. Bản Volume 2019, 2021, 2024
  phải đi kênh PerpetualVL cùng năm.
- Bộ cài trong `Office\Data` phải khớp file cấu hình: bản dựng, kênh, sản phẩm, ngôn ngữ, 32/64 bit. Thiếu phần nào
  thì ODT tải phần đó từ Internet; máy không vào được máy chủ của Microsoft thì dừng.
- Báo các thẻ đáng chú ý: `<RemoveMSI>` (ODT gỡ Office cài bằng MSI trước khi cài), `<Remove>`, `AUTOACTIVATE`
  (tự kích hoạt), cập nhật tự động.
- Mẫu nằm trong thư mục cài Office thì gỡ Office sẽ xoá luôn mẫu: công cụ dừng, nhắc chép mẫu ra chỗ khác.

**Khoá sản phẩm trong file cấu hình** (`PIDKEY`) không bao giờ hiện lên màn hình, vào báo cáo, nhật ký hay bị chép đi
đâu: công cụ chạy `setup.exe /configure` ngay trong thư mục mẫu. Công cụ chỉ cho biết mẫu có khoá không, và khoá đó có
phải khoá KMS chung (GVLK) Microsoft công bố không (so bằng mã băm). `tools\office\mau` và các file `.xml` trong
`tools\office` đã có trong `.gitignore`; gói gửi khách của trạm cũng không kèm mẫu.

**Tạo mẫu mới.** Office 2016, 2019 hết hỗ trợ từ 14/10/2025, Office LTSC 2021 hết hỗ trợ ngày 13/10/2026, Office
LTSC 2024 được hỗ trợ đến 09/10/2029, Microsoft 365 cập nhật liên tục. Cách tạo:

1. Tạo file cấu hình ở [config.office.com](https://config.office.com) (Office Customization Tool): chọn sản phẩm,
   64 bit, ngôn ngữ, ứng dụng không cài, rồi xuất ra `Configuration.xml`. Office LTSC chỉ bán theo hợp đồng cấp phép
   số lượng lớn (Volume Licensing); máy lẻ thì chọn Microsoft 365, hoặc Office Home, Office Home & Business 2024 bán
   lẻ.
2. Tải [Office Deployment Tool](https://www.microsoft.com/download/details.aspx?id=49117), giải nén lấy `setup.exe`
   vào cùng thư mục.
3. Muốn cài không cần mạng: mở cmd trong thư mục mẫu, chạy `setup.exe /download Configuration.xml` (tải vài GB vào
   `Office\Data`).
4. Chạy **Kiểm tra**, chọn thư mục mẫu mới.

## 2. Kiểm tra (chỉ đọc)

1. Máy này: Windows, chỗ trống ổ Windows (cần ít nhất 4 GB), người đang dùng máy và tài khoản chạy công cụ.
2. Office trên máy: bản Click-to-Run (sản phẩm, phiên bản, 32/64 bit, ngôn ngữ, kênh, thư mục, ứng dụng), bản cài
   bằng MSI, bản từ Microsoft Store, hạn hỗ trợ. Access Database Engine không phải Office, công cụ giữ nguyên.
3. Giấy phép của từng sản phẩm Office trong Windows: đã kích hoạt chưa, loại khoá (MAK, KMS chung, bán lẻ), có trùng
   khoá trong mẫu không, máy chủ KMS. Báo cả dấu vết công cụ kích hoạt không chính thống (chỉ báo, không xoá).
4. Bộ cài mẫu, như mục 1.
5. Ứng dụng Office đang mở, dữ liệu sẽ sao lưu (mục 7), phần Click-to-Run còn sót khi máy đã hết Office.

Báo cáo: `ket_qua\BaoCao_Office_<tên máy>_<ngày giờ>.txt`. Đọc phần **KẾT LUẬN** trước: việc nên làm theo thứ tự,
kèm nút cần chạy. Báo cáo không chứa khoá sản phẩm.

## 3. Gỡ sạch Office cũ rồi cài theo mẫu

1. Kiểm tra mẫu. Mẫu hỏng, mẫu thiếu bộ cài mà máy không có mạng, mẫu nằm trong thư mục Office: dừng, máy chưa bị
   gỡ gì.
2. In mục **Sẽ làm** và cảnh báo về kích hoạt (mục 6). Phải gõ `DONG Y` mới làm tiếp.
3. Sao lưu dữ liệu Office của người đang dùng máy (mục 7).
4. Đóng ứng dụng Office. Công cụ không tự đóng mà hỏi: `T` bạn đã đóng hết, `D` đóng giúp (Office hỏi lưu file chưa
   lưu), `K` buộc đóng (mất phần chưa lưu), `H` huỷ.
5. Gỡ Office Click-to-Run bằng `setup.exe` của mẫu với file cấu hình gỡ tạm `<Remove All="TRUE"/>`. ODT chạy ngầm,
   nhật ký nằm trong `ket_qua\nhat-ky-odt`.
6. Gỡ Office cài bằng MSI (cửa sổ gỡ của Office hiện ra, làm theo) và Office từ Microsoft Store (mọi tài khoản).
7. Quét sâu, nếu đã đánh dấu (xem dưới).
8. Kiểm tra lại. Còn Office thì dừng ở đây: khởi động lại máy, chạy lại *Chỉ gỡ sạch Office*; vẫn còn thì đánh dấu
   *Quét sâu*.
9. Dọn phần Click-to-Run còn sót: dịch vụ ClickToRunSvc, tác vụ hẹn giờ `\Microsoft\Office\`, thư mục Click-to-Run
   trong Program Files, Common Files, ProgramData, khoá registry `ClickToRun`, `AppVISV`, mục gỡ cài đặt hỏng.
   Thư mục `Microsoft Office` còn thứ khác (Office cài bằng MSI, file của phần mềm khác) thì chỉ xoá các thư mục con
   của Click-to-Run. Công cụ chỉ xoá trong Program Files, Common Files, ProgramData và không bao giờ xoá thư mục mẫu,
   thư mục công cụ.
10. Gỡ khoá sản phẩm Office khỏi Windows (cả máy chủ KMS đã đặt cho Office). Xoá giấy phép và tài khoản đã đăng nhập
    Office của người đang dùng máy: lần sau mở Office thì đăng nhập lại. Đã chọn *Xoá cả thiết lập* thì xoá thiết lập
    (xem dưới).
11. Windows cần khởi động lại để xoá nốt file, hoặc ổ Windows còn dưới 4 GB trống: công cụ dừng ở đây. Khởi động lại
    (hoặc dọn bớt ổ) rồi chạy *Chỉ cài Office theo mẫu*.
12. Cài bằng `setup.exe /configure <file cấu hình>` trong thư mục mẫu. Cửa sổ cài của Office có hiện ra hay không
    tuỳ thẻ `<Display>` của mẫu.
13. Kiểm tra sau khi cài: đủ sản phẩm, đúng 32/64 bit, có Word, Excel, PowerPoint (trừ ứng dụng mẫu bỏ).
14. Kích hoạt (mục 6).

Gỡ rồi thì không hoàn tác được. Trạm tạo điểm khôi phục hệ thống trước khi chạy (khi Bảo vệ hệ thống đang bật), nhưng
đừng trông vào nó để lấy lại Office: cài lại theo mẫu chắc chắn hơn. Bước cài mà lỗi thì máy tạm không có Office: xử lý
lỗi rồi chạy *Chỉ cài Office theo mẫu*.

Công cụ không đụng tới tài liệu, file dữ liệu Outlook (`.pst`). Access Database Engine (phần mềm kế toán, nhập liệu
hay cần) được giữ, trừ khi mẫu có thẻ `<RemoveMSI>` (mục 5) hoặc chọn quét sâu: công cụ cảnh báo trước, và báo nếu nó
bị gỡ mất. Mẫu Word, macro, chữ ký cũng không bị gỡ Office xoá; công cụ vẫn sao lưu phòng khi.

Hai tuỳ chọn, mặc định tắt:

- **Quét sâu bằng công cụ gỡ Office của Microsoft.** Dùng khi lần gỡ trước còn sót hoặc Office hỏng nặng. Cần mạng,
  thêm 5–20 phút. Công cụ tải bản mới nhất của *Get Help* dòng lệnh (`GetHelpCmd.exe`, mỗi bản chỉ dùng được 90 ngày),
  kiểm chữ ký Microsoft, mở điều khoản sử dụng trong Notepad; bạn gõ `C` nếu đồng ý thì mới chạy. Công cụ của
  Microsoft tự quyết gỡ gì và có thể gỡ cả Access Database Engine; mất thì công cụ báo để cài lại. Kết quả: `00` xong
  (nên khởi động lại), `06` còn ứng dụng Office đang mở, `08`, `09` cần
  [Get Help bản đầy đủ](https://aka.ms/SaRA_Home), `66`, `68` không còn Office để gỡ.
- **Xoá cả thiết lập Office của người dùng.** Xuất `HKCU\Software\Microsoft\Office` ra `Office.reg` trong bản sao lưu
  rồi mới xoá; xuất không được thì không xoá. Mất cả hồ sơ Outlook (phải thêm lại tài khoản thư), danh sách file gần
  đây, tuỳ chỉnh. Chỉ dùng khi Office lỗi do thiết lập hỏng.

Người dùng máy không phải Admin, UAC hỏi mật khẩu của một Admin khác: cửa sổ công cụ chạy bằng tài khoản Admin đó nên
công cụ bỏ qua phần của từng người dùng (sao lưu, giấy phép tài khoản, thiết lập). Các file đó vẫn nằm nguyên, Office
mới dùng lại được.

## 4. Chỉ gỡ sạch Office

Như mục 3, từ bước 2 đến bước 10, không cài lại; Windows cần khởi động lại thì công cụ nhắc làm trước khi cài Office
mới. Có bộ cài mẫu thì gỡ Click-to-Run bằng ODT của mẫu (chạy ngầm; chỉ cần `setup.exe` có chữ ký, không cần mẫu cài
được). Không có mẫu thì chạy trình gỡ của Office ghi trong *Gỡ cài đặt chương trình*: cửa sổ của Microsoft hiện ra,
bấm **Uninstall**.

## 5. Chỉ cài Office theo mẫu

Cho máy chưa có Office, hoặc sau khi gỡ xong và khởi động lại. Không cài khi:

- máy đang có Office khác mẫu (khác sản phẩm, 32/64 bit, kênh): cài thêm sẽ lẫn hai bản;
- Office Click-to-Run trên máy bị hỏng, có Office từ Microsoft Store, hoặc có Office cài bằng MSI mà mẫu không có
  `<RemoveMSI>`;
- ổ Windows còn dưới 4 GB trống, hoặc mẫu thiếu bộ cài mà máy không có mạng.

Những trường hợp trên thì chạy *Gỡ sạch Office cũ rồi cài theo mẫu*. Office trên máy đã đúng như mẫu thì cài lại là
sửa Office (giữ file, thiết lập). Windows còn chờ khởi động lại sau lần gỡ trước: công cụ nhắc khởi động lại trước.

`<RemoveMSI>` gỡ cả Access Database Engine. Máy có phần mềm cần nó thì thêm `<IgnoreProduct ID="AceRedist" />` vào
trong `<RemoveMSI>` của file cấu hình; công cụ nhắc trước khi cài, và báo sau khi cài nếu nó đã bị gỡ.

## 6. Kích hoạt

Sau khi cài, mẫu có `AUTOACTIVATE` thì công cụ chờ Office tự kích hoạt tối đa 2 phút. Chưa được thì hỏi (nút
**Kích hoạt Office** hỏi y như vậy):

- `K` kích hoạt bằng khoá đã cài: khoá MAK, khoá bán lẻ kích hoạt qua Internet; khoá KMS chung (GVLK) chỉ kích hoạt
  được qua máy chủ KMS của tổ chức (máy phải nối mạng công ty).
- `N` nhập khoá Office của bạn (MAK hoặc khoá bán lẻ). Khoá chỉ gõ trong cửa sổ công cụ, không hiện lên khi gõ, không
  nhận qua trạm hay tham số, không ghi đi đâu. Công cụ cài khoá vào Windows, tìm sản phẩm Office nhận khoá rồi kích hoạt.
  Chỉ gõ khoá Office: khoá Windows gõ vào đây sẽ được cài cho Windows.
- `B` bỏ qua, kích hoạt sau bằng nút **Kích hoạt Office**.

Microsoft 365: mở Word, đăng nhập tài khoản có giấy phép.

**Trước khi gỡ, chuẩn bị sẵn khoá.** Gỡ Office là gỡ cả khoá khỏi Windows, mà Windows chỉ giữ 5 ký tự cuối nên công
cụ không lấy lại được khoá đầy đủ. Hay gặp nhất: mẫu chỉ có khoá KMS chung (bản Volume tải về thường như vậy), còn
Office trên máy đang kích hoạt bằng khoá MAK riêng. Cài lại từ mẫu đó thì Office chưa kích hoạt cho tới khi nhập lại
khoá MAK. Kiểm tra và mục **Sẽ làm** đều cảnh báo trường hợp này. Mỗi khoá MAK có số lần kích hoạt giới hạn và chỉ
dùng cho máy thuộc giấy phép của tổ chức bạn.

Công cụ chỉ kích hoạt theo cách của Microsoft. Không có, không hỗ trợ công cụ kích hoạt không chính thống (KMS giả
lập, crack): các công cụ này hay kèm mã độc. Kiểm tra thấy dấu vết thì quét virus toàn máy và gỡ chúng.

| Mã lỗi | Nghĩa | Cách xử lý |
|---|---|---|
| 0xC004C008, 0xC004C020 | Khoá đã hết số lần kích hoạt | Liên hệ nơi cấp khoá để thêm lượt, hoặc dùng khoá khác |
| 0xC004C003 | Khoá bị Microsoft chặn | Dùng khoá hợp lệ khác |
| 0xC004F050 | Khoá không hợp với sản phẩm này | Kiểm tra lại khoá có đúng sản phẩm, đúng năm không |
| 0xC004F074, 0x8007232B | Không liên lạc, không tìm thấy máy chủ KMS | Nối mạng công ty, hoặc nhập khoá MAK |
| 0x80072EE7, 0x80072EFD, 0x80072EE2 | Không tới được máy chủ kích hoạt | Kiểm tra Internet, tường lửa rồi thử lại |

## 7. Sao lưu và trả lại mẫu Word, macro, chữ ký

Trước khi gỡ, công cụ chép dữ liệu Office của người đang dùng máy vào
`ket_qua\sao-luu\SaoLuu_<tên máy>_<ngày giờ>\`, kèm `SaoLuu.json` ghi mục nào lấy từ đâu:

- mẫu Word, Excel, PowerPoint (`%APPDATA%\Microsoft\Templates`, có `Normal.dotm`), Building Blocks, Quick Parts,
  bộ kiểu (Style Set) của Word;
- từ điển riêng, danh sách AutoCorrect (`.acl`);
- add-in Word tự chạy (`Word\STARTUP`), macro Excel dùng chung (`XLSTART`, `PERSONAL.XLSB`), thanh công cụ Excel
  (`.xlb`), add-in Excel, PowerPoint (`AddIns`);
- Ribbon, Quick Access đã chỉnh (`.officeUI`), chữ ký Outlook;
- thiết lập Office trong registry (`Office.reg`), chỉ khi chọn *Xoá cả thiết lập*.

Bản sao lưu có chữ ký email, `Office.reg` có tên tài khoản, email: không gửi công khai.

**Trả lại mẫu Word, macro, chữ ký đã sao lưu**: chọn bản sao lưu (hoặc ghi tên ở ô *Tên bản sao lưu*), xem danh sách
sẽ chép rồi trả lời có. Công cụ hỏi đóng Office, sao lưu dữ liệu hiện tại trước (bản đó cũng trả lại được bằng chính
nút này), rồi chép đè; file chỉ có ở máy hiện tại được giữ nguyên. Thiết lập registry hỏi riêng, mặc định không nhập
vì sẽ đè thiết lập hiện tại (cả hồ sơ Outlook). Bản sao lưu của tài khoản khác thì công cụ cảnh báo trước.

## 8. Kết quả, nhật ký, khi có lỗi

| Mã thoát | Nghĩa |
|---|---|
| 0 | Xong |
| 1 | Lỗi (cài không đủ sản phẩm, ODT báo lỗi...) |
| 2 | Thiếu điều kiện: mẫu hỏng, mẫu nằm trong thư mục Office, thiếu quyền Admin, chưa có bản sao lưu |
| 3 | Làm được một phần: còn Office sau khi gỡ, cần khởi động lại giữa chừng, cài xong chưa kích hoạt |
| 1223 | Bạn huỷ (không gõ `DONG Y`, chọn huỷ, chọn *Không* ở UAC) |

- Mỗi lần gỡ, cài, kích hoạt, trả lại ghi nhật ký `ket_qua\NhatKy_Office_<tên máy>_<ngày giờ>.txt`, kể cả khi lỗi.
  Chạy thử không ghi nhật ký.
- Nhật ký của ODT khi gỡ: `ket_qua\nhat-ky-odt\`. Khi cài: thư mục ghi ở thẻ `<Logging>` của file cấu hình, không có
  thì `%TEMP%` của tài khoản chạy cài đặt. Nhật ký ODT có thể chứa khoá sản phẩm: đừng gửi công khai.
- ODT báo lỗi khi cài: thường do còn Office cũ (chạy *Gỡ sạch Office cũ rồi cài theo mẫu*), mẫu thiếu bộ cài mà mạng
  chập chờn, hoặc thiếu chỗ trống. Xem dòng lỗi cuối trong nhật ký ODT.
- Gỡ xong vẫn còn Office: khởi động lại máy, chạy lại *Chỉ gỡ sạch Office*; vẫn còn thì đánh dấu *Quét sâu*.

## Chạy không cần Trạm Tool

```bat
OFFICE.bat
OFFICE.bat -Mode kiem-tra -Mau "D:\MauOffice"
OFFICE.bat -Mode go-va-cai -Mau "D:\MauOffice" -ChayThu
OFFICE.bat -Mode cai-dat -Mau "D:\MauOffice" -CauHinh LTSC2024.xml
```

| Chế độ (`-Mode`) | Tham số |
|---|---|
| `kiem-tra` | `-Mau`, `-CauHinh` (đều không bắt buộc) |
| `go-va-cai` | `-Mau`, `-CauHinh`, `-QuetSau`, `-XoaThietLap` |
| `go-sach` | `-Mau` (chỉ để lấy `setup.exe` gỡ cho sạch), `-QuetSau`, `-XoaThietLap` |
| `cai-dat` | `-Mau`, `-CauHinh` |
| `kich-hoat` | không |
| `tra-lai` | `-SaoLuu SaoLuu_...` (không bắt buộc) |

Mọi chế độ nhận `-ChayThu` (chỉ xem) và `-KhongDung` (không chờ Enter khi xong). Chế độ cần Admin tự hỏi UAC, trừ
khi chạy thử. Không có tham số nhận khoá sản phẩm: khoá chỉ gõ trong cửa sổ công cụ.

Mã nguồn: `Office.ps1` (menu, chọn chế độ), `lib\Chung.ps1` (hiển thị, hỏi, che khoá), `lib\DocOffice.ps1` (đọc
Office, giấy phép, bộ cài mẫu), `lib\SaoLuu.ps1`, `lib\GoOffice.ps1`, `lib\CaiOffice.ps1` (cài, kích hoạt),
`lib\KiemTra.ps1`.

## Nguồn

- [Office Deployment Tool](https://learn.microsoft.com/microsoft-365-apps/deploy/overview-office-deployment-tool),
  [các thẻ trong file cấu hình](https://learn.microsoft.com/microsoft-365-apps/deploy/office-deployment-tool-configuration-options):
  `<Remove All="TRUE"/>`, `<Display>`, `<Logging>`, `AUTOACTIVATE`, `FORCEAPPSHUTDOWN`; không có `SourcePath` thì ODT
  tìm bộ cài trong thư mục của nó trước.
- [Gỡ Office cài bằng MSI khi nâng cấp](https://learn.microsoft.com/microsoft-365-apps/deploy/upgrade-from-msi-version):
  `<RemoveMSI>` gỡ cả Access Database Engine, giữ lại bằng `<IgnoreProduct ID="AceRedist" />`.
- [Triển khai Office 2019 bản Volume](https://learn.microsoft.com/office/2019/deploy): kênh PerpetualVL2019;
  [khoá KMS chung (GVLK)](https://learn.microsoft.com/office/volume-license-activation/gvlks);
  [kích hoạt bản Volume](https://learn.microsoft.com/office/volume-license-activation/tools-to-manage-volume-activation-of-office).
- [Mã sản phẩm ODT hỗ trợ](https://learn.microsoft.com/troubleshoot/microsoft-365-apps/office-suite-issues/product-ids-supported-office-deployment-click-to-run).
- [Get Help dòng lệnh](https://learn.microsoft.com/troubleshoot/microsoft-365/admin/miscellaneous/get-help-command-line-overview):
  `OfficeScrubScenario`, mã kết quả, bản dùng 90 ngày.
  [Gỡ Office khỏi máy](https://support.microsoft.com/office/uninstall-office-from-a-pc-9dd49b83-264a-477a-8fcc-2fdf5dbf61d8).
- [Lịch sử phát hành ODT](https://learn.microsoft.com/officeupdates/odt-release-history),
  [CVE-2026-20943](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-20943).
- Hạn hỗ trợ: [Office 2016, 2019](https://support.microsoft.com/office/end-of-support-for-office-2016-and-office-2019-818c68bc-d5e5-47e5-b52f-ddf636cf8e16),
  [Office LTSC 2021](https://learn.microsoft.com/lifecycle/announcements/office-ltsc-2021-end-of-support),
  [Office LTSC 2024](https://learn.microsoft.com/lifecycle/products/office-ltsc-2024).
- [SoftwareLicensingProduct](https://learn.microsoft.com/previous-versions/windows/desktop/sppwmi/softwarelicensingproduct):
  đọc giấy phép, kích hoạt, gỡ khoá qua WMI.
