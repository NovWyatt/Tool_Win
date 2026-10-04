# Phân tích và hướng nâng cấp

Cập nhật 04/10/2026. Đánh giá 12 công cụ trong `tools\`, những gì đã sửa trong đợt gom vào Trạm Tool,
và lộ trình nâng cấp theo mức ưu tiên.

Danh sách lỗi và hướng nâng cấp đầy đủ của từng công cụ nằm trong `issues` và `upgrades` của `tool.json`,
hiển thị ở trang công cụ (mục *Lỗi đã biết và hướng nâng cấp*). Sửa xong mục nào thì xoá mục đó trong `tool.json`
và cập nhật bảng dưới đây.

Mức ưu tiên:

- **P0**: làm trước khi đưa công cụ cho khách hoặc nhân viên dùng. Lỗi gây mất dữ liệu, báo thành công giả hoặc lộ bí mật.
- **P1**: làm cho công cụ đáng tin và dễ bảo trì hơn.
- **P2**: tính năng thêm.

## Tóm tắt

- **Trước đợt này**: 12 công cụ nằm rải rác ở gốc repo (`CheckWinFIx\`, `MyExcelFix\`, `New_w\`, các file `.bat` lẻ,
  `convert_ghiam_to_word\`, `mdf2sql\`), mỗi cái một kiểu chạy, một kiểu ghi kết quả. Script chuyển DWG sang PDF
  chỉ còn trong lịch sử phiên làm việc trước. Môi trường Python của công cụ ghi âm hỏng vì Python gốc đã bị gỡ.
- **Bây giờ**: mỗi công cụ một thư mục trong `tools\` có `tool.json`. Trạm Tool (`TramTool.bat`) cho chọn, chạy,
  nhập tham số bằng form, kiểm tra điều kiện cần cài, xem trạng thái máy, mở kết quả và đóng gói gửi khách.
- **Dùng tốt ngay**: CheckWinFix (phần chẩn đoán), MyExcelFix, Ghi âm sang Word, DWG sang PDF.
- **Cần sửa trước khi đưa người khác dùng (P0)**: Sửa lỗi Windows, Tắt/bật dịch vụ, Chuyển dữ liệu khi cài lại Windows,
  phần *Cứu dữ liệu* của CheckWinFix.
- **Không có tác dụng**: Tối ưu đồng hồ hệ thống ghi thiết lập vào registry trong khi Windows đọc từ BCD (`bcdedit`).
  Trạm đánh dấu *Cần xem lại* và cảnh báo trước khi chạy.
- **Máy này chưa chạy được**: Khôi phục .mdf sang .sql (thiếu ODBC Driver 17/18 và SQL Server LocalDB). Trang công cụ
  có nút *Cài* cho từng thứ; cả hai cần quyền Admin.

## Đã sửa trong đợt này

| Commit | Công cụ | Nội dung |
|---|---|---|
| `df32b99`, `74a6c63` | Tất cả | Lưu nguyên trạng, rồi gom mỗi công cụ vào một thư mục trong `tools\`. `mdf2sql` thành git submodule. |
| `b4c8dea` | DWG sang PDF | Khôi phục `convert.py`, `vni.py` từ lịch sử phiên trước (khớp từng byte với bản cuối). |
| `e088962` | DWG sang PDF | Chuyển cả thư mục bản vẽ; `CAI_DAT.ps1` tự cài Python 3.12, `.venv`, LibreDWG (kiểm tra SHA-256); khoá phiên bản thư viện. Đã chạy thử trọn quy trình với bản vẽ thật. |
| `606d359` | Ghi âm sang Word | `CAI_DAT.ps1` dựng lại `.venv`, thư viện CUDA, tải mô hình theo bản cố định; `.bat` tự hỏi cài khi thiếu; khoá phiên bản. |
| `a05ee68` | CheckWinFix | Dấu `>` không escape làm dòng nhắc giờ chạy *Cứu dữ liệu* bị ghi ra file rác thay vì hiện lên màn hình. |
| `428d6fd` | Chuyển dữ liệu khi cài lại Windows | Khôi phục không còn chép đè hội thoại Claude và file Cowork mới hơn bằng bản sao lưu cũ (mất dữ liệu khi chạy lại bước nhập). |
| `a56f838` | Báo cáo sức khoẻ | `wmic` đã bị gỡ khỏi Windows 11 mới; đọc ổ đĩa bằng `Get-CimInstance`. |
| `dcd7d61` | Tắt/bật dịch vụ, Tối ưu đồng hồ | Dấu `&` trong tiêu đề, menu làm cmd chạy phần sau như một lệnh; *bật lại* Optimize Drives trả về Manual (mặc định) thay vì Automatic. |
| (đợt này) | MyExcelFix, mdf2sql | Thêm `HOAN_TAC.bat` (hoàn tác từ trạm) và `CHAY_DONG_LENH.bat` (xem thông tin, chuyển đổi không cần trình duyệt). |

## Bảng tổng quan

| Công cụ | Dành cho | Đánh giá | Việc nên làm trước |
|---|---|---|---|
| CheckWinFix | Mọi người | Bộ chẩn đoán đầy đủ nhất: 24 nhóm thông tin, khoảng 45 cảnh báo tự động, chạy đúng với mọi đường dẫn. | P0: sửa *Cứu dữ liệu* (đối chiếu MD5 khi SQL còn dừng, so ổ vật lý), bổ sung mã sự kiện mức Warning. |
| Báo cáo sức khoẻ | Mọi người | Chạy được, nhưng trùng phần lớn với *Thu thập thông tin* của CheckWinFix. | P1: gộp vào CheckWinFix thành chế độ nhanh. |
| Sửa lỗi Windows | Kỹ thuật | Đủ lệnh thường dùng nhưng không kiểm tra quyền Admin, báo *hoàn tất* cả khi thất bại; *Reset Network* âm thầm xoá luật tường lửa. | P0: tự nâng quyền, kiểm tra mã lỗi; tách đặt lại tường lửa, bỏ *Registry Cleanup*. |
| Kiểm tra và sửa lỗi Wi-Fi | Mọi người | Dùng được, hỏi trước khi sửa. Tìm card bằng chữ trong output nên hụt khi card đổi tên hoặc Windows khác ngôn ngữ. | P1: `Get-NetAdapter`, `fltmc` thay `net session`. |
| Tắt/bật dịch vụ nền | Kỹ thuật | Báo *thành công* cả khi `sc config` bị từ chối; coi *đã dừng* là *đã tắt*. Tắt Optimize Drives làm mất TRIM cho SSD. | P0: tự nâng quyền, xét kiểu khởi động, lưu trạng thái gốc để khôi phục đúng. |
| Tối ưu đồng hồ hệ thống | Kỹ thuật | Không có tác dụng (ghi sai chỗ). | P0: bỏ khỏi trạm, hoặc viết lại bằng `bcdedit` và đo trước/sau. |
| MyExcelFix | Mọi người | Chẩn đoán kỹ theo từng tài khoản Windows, có sao lưu và hoàn tác, mã nguồn chia module và build ra một file `.bat`. | P0: không treo khi thiếu cửa sổ dòng lệnh, hoàn tác không đè file đã sửa sau đó, mã thoát. |
| DWG sang PDF | Mọi người | Không cần AutoCAD; mỗi khung bản vẽ một trang; giải mã chữ VNI. Bản vẽ lớn chậm (5–35 phút). | P1: giải mã TCVN3; bộ bản vẽ mẫu để kiểm tra khi nâng thư viện. |
| Ghi âm sang Word | Mọi người | Chạy offline trên card NVIDIA, nhanh khoảng 5 lần thời gian thực, đánh dấu chỗ máy nghe kém chắc chắn. | P1: tên kết quả giữ đuôi file gốc, lưu tiến độ để chạy tiếp, chỉ chạy lại bằng CPU khi đúng là lỗi card. |
| Khôi phục .mdf sang .sql | Kỹ thuật | Khôi phục được file tắt đột ngột hoặc thiếu `.ldf`, xuất cho cả SQL Server và MySQL; luôn làm trên bản sao. | P0: lệnh `doctor` kiểm tra môi trường, không dùng chung cổng 8760. |
| Chuyển dữ liệu khi cài lại Windows | Kỹ thuật | Sao lưu Wi-Fi kèm mật khẩu, máy in kèm driver, dữ liệu Claude. Bản sao lưu nằm cạnh script, chứa bí mật dạng chữ thường. | P0: chọn nơi lưu ngoài thư mục công cụ, đánh dấu sao lưu đã xong, chạy thử trước. |
| Đăng xuất GitHub | Kỹ thuật | Nhỏ, đúng việc; có thể sót mục đăng nhập lưu theo tài khoản. | P1: lọc `cmdkey /list` theo `github`. |

## Vấn đề chung

Các lỗi lặp lại ở nhiều công cụ, nên sửa một lần bằng quy ước chung thay vì vá từng nơi.

1. **Kiểm tra quyền Admin sai cách hoặc không kiểm tra.** CheckWinFix, Wi-Fi dùng `net session` (cần dịch vụ Server,
   bị tắt là báo nhầm hoặc tự mở lại không dừng). Sửa lỗi Windows, Tắt/bật dịch vụ, Tối ưu đồng hồ không kiểm tra gì.
   Quy ước: `fltmc >nul 2>&1` để kiểm tra, tự nâng quyền đúng một lần, không được thì báo rõ và thoát.
2. **Báo thành công giả.** Lỗi bị giấu bằng `>nul 2>&1` rồi in *thành công*; mã thoát luôn 0. Quy ước: kiểm tra
   `errorlevel` (hoặc `$LASTEXITCODE`) sau mỗi lệnh thay đổi máy; mã thoát `0` xong, `1` lỗi, `2` thiếu điều kiện,
   `3` thành công một phần.
3. **Bí mật và dữ liệu khách nằm cạnh script.** Bản sao lưu cài lại máy có mật khẩu Wi-Fi, token và hội thoại Claude;
   sao lưu MyExcelFix trên Desktop (thường đồng bộ OneDrive) có số tài khoản ngân hàng; báo cáo có tên máy khách.
   Quy ước: dữ liệu khách để trong `ket_qua\` hoặc `du-lieu\` (git bỏ qua), cho chọn nơi lưu, có tuỳ chọn nén mật khẩu.
4. **Trùng lặp.** Báo cáo sức khoẻ trùng CheckWinFix; Tắt/bật dịch vụ và Tối ưu đồng hồ cùng là *tối ưu*;
   Sửa lỗi Windows nên là bước *Sửa* sau khi CheckWinFix chẩn đoán ra bệnh.
5. **Phụ thuộc ngôn ngữ Windows.** Đọc chữ trong thông điệp sự kiện, output `netsh` tiếng Anh. Windows tiếng Việt hoặc
   card mạng đã đổi tên là hụt. Quy ước: đọc trường `EventData`, dùng cmdlet (`Get-NetAdapter`) thay vì tách chữ.
6. **Mã hoá file.** `.ps1` cần UTF-8 có BOM, `.bat` cần không BOM, cả hai CRLF. Đã có `.editorconfig`, `.gitattributes`
   và `hub\dev\Normalize-Encoding.ps1` để giữ đúng.
7. **Môi trường Python tự phát.** Mỗi công cụ một kiểu cài. Quy ước (đã áp dụng cho DWG sang PDF, Ghi âm sang Word):
   `.venv` riêng, `requirements-lock.txt` khoá phiên bản, `CAI_DAT.ps1` tự cài lại được trên máy mới.
8. **Kết quả chỉ là chữ.** Trạm không biết công cụ chạy xong hay lỗi, tìm thấy gì. Quy ước (P1): mỗi lần chạy ghi thêm
   một file JSON tóm tắt (máy, thời gian, trạng thái, phát hiện, mức độ, cách sửa, đường dẫn kết quả).

## Lộ trình

### Giai đoạn 1: an toàn (P0)

- [ ] Quy ước Admin + mã thoát (mục 1, 2 ở trên) cho Sửa lỗi Windows, Tắt/bật dịch vụ, Wi-Fi, CheckWinFix.
- [ ] Tối ưu đồng hồ: bỏ khỏi trạm, hoặc viết lại bằng `bcdedit /set {current} disabledynamictick yes` và
      `bcdedit /deletevalue {current} useplatformclock`, đọc trạng thái thật bằng `bcdedit /enum {current}`.
- [ ] CheckWinFix *Cứu dữ liệu*: đối chiếu MD5 khi SQL còn dừng, so ổ vật lý nguồn/đích, dò mọi instance `MSSQL*`,
      luôn bật lại SQL Server kể cả khi lỗi giữa chừng.
- [ ] CheckWinFix cảnh báo: so theo nguồn sự kiện + mã, thêm disk 154, WHEA 1/18 và mức Warning.
- [ ] Sửa lỗi Windows: tách đặt lại tường lửa và hỏi lại; bỏ *Registry Cleanup*.
- [ ] Tắt/bật dịch vụ: xét kiểu khởi động, lưu trạng thái gốc ra file để *bật lại* trả đúng giá trị cũ.
- [ ] MyExcelFix: dừng có thông báo khi hết đầu vào; hoàn tác giữ bản hiện tại nếu file đã đổi sau khi sửa; mã thoát.
- [ ] Chuyển dữ liệu khi cài lại Windows: chọn nơi lưu, `manifest.json` đánh dấu đang làm/xong, `-DryRun`, mã thoát.
- [ ] Khôi phục .mdf: `mdf2sql doctor`; tự lùi sang cổng trống, không dùng chung cổng.

### Giai đoạn 2: chuẩn hoá (P1)

- [ ] File JSON kết quả chung cho mọi công cụ; Trạm đọc để hiện *tìm thấy gì* và gợi ý công cụ chạy tiếp.
- [ ] Trạm đợi tiến trình xong trong nền, ghi mã thoát và thời gian chạy vào Lịch sử.
- [ ] Lõi PowerShell dùng chung (kiểm tra Admin, ghi log, đọc SMART, minidump, WHEA, chọn nơi lưu), build ra từng `.bat`
      một file như MyExcelFix để vẫn gửi khách được một file.
- [ ] Gộp: Báo cáo sức khoẻ thành chế độ nhanh của CheckWinFix; Tắt/bật dịch vụ + Tối ưu đồng hồ thành một công cụ
      *Tối ưu* có trang trạng thái.
- [ ] Khôi phục .mdf: `.venv` riêng có pyodbc khoá phiên bản; dọn database tạm, thư mục làm việc bị bỏ lại.
- [ ] Ghi âm sang Word: tên kết quả giữ đuôi file gốc; lưu tiến độ từng khúc; hết bộ nhớ card thì thử lại khúc đó với beam nhỏ.
- [ ] DWG sang PDF: giải mã TCVN3 (`.VnTime`, `.VnArial`...) giống cách đã làm với VNI; bộ bản vẽ mẫu + so ảnh từng trang
      khi nâng ezdxf, PyMuPDF, LibreDWG.

### Giai đoạn 3: mở rộng (P2)

- [ ] Tiến độ phần trăm (in dòng JSON) cho DWG sang PDF và Ghi âm sang Word, Trạm hiện thanh tiến độ.
- [ ] DWG sang PDF: chọn khổ giấy, bảng nét in `.ctb`, in màu trên form chạy.
- [ ] Chuyển dữ liệu khi cài lại Windows: thêm `winget export`, thư mục người dùng (xem trước dung lượng), dấu trang, font.
- [ ] Sửa lỗi Windows thành bước *Sửa* trong CheckWinFix, chỉ đề xuất lệnh hợp với bệnh tìm thấy.
- [ ] Trạm: nút *Cập nhật công cụ* (git pull), xuất/nhập cài đặt.

## Trạm Tool

**Đã có**

- Danh mục tự đọc từ `tools\*\tool.json`; thư mục/script mới thả vào vẫn hiện ra, có nút *Tạo tool.json*.
- Tìm kiếm không dấu, nhóm, ghim, *Chế độ đơn giản* ẩn công cụ kỹ thuật cho nhân viên văn phòng.
- Chạy công cụ trong cửa sổ riêng; form nhập tham số (chọn file/thư mục bằng hộp thoại Windows, ô chữ, số, lựa chọn,
  công tắc); hộp xác nhận liệt kê thay đổi; nhãn mức rủi ro và quyền Admin.
- Kiểm tra điều kiện cần (Python, `.venv`, mô hình, driver ODBC, SQL Server, card đồ hoạ...) với nút *Cài*
  (winget, script cài của công cụ, hoặc script dùng chung trong `hub\fixes\`).
- Trạng thái máy hiện tại (dịch vụ, registry) cho công cụ tối ưu; kết quả gần đây; lịch sử chạy; trang *Máy này*.
- Đóng gói gửi khách thành `.zip` kèm hướng dẫn.
- Bảo mật: chỉ nghe `127.0.0.1`, mã thông hành ngẫu nhiên mỗi lần mở, kiểm tra Host/Origin, chỉ chạy action khai báo
  trong `tool.json`, không mở file ngoài thư mục công cụ và danh sách kết quả.

**Hướng tiếp**: các mục *Trạm* trong lộ trình ở trên (đọc mã thoát, JSON kết quả, tiến độ, cập nhật công cụ).

## Thư viện bên thứ ba

Tất cả miễn phí. Thư viện của giao diện trạm nằm sẵn trong `hub\web\vendor\` (chạy không cần mạng);
thư viện của công cụ được script cài đặt tải về, không đưa vào git.

| Thư viện | Dùng cho | Giấy phép |
|---|---|---|
| Fluent UI Web Components | Giao diện trạm | MIT |
| marked | Hiển thị tài liệu Markdown trong trạm | MIT |
| DOMPurify | Lọc HTML trước khi hiển thị | Apache-2.0 hoặc MPL-2.0 |
| LibreDWG | DWG sang PDF: đọc file .dwg | GPL-3.0 |
| ezdxf | DWG sang PDF: đọc bản vẽ DXF | MIT |
| PyMuPDF | DWG sang PDF: vẽ PDF | AGPL-3.0 |
| faster-whisper, CTranslate2 | Ghi âm sang Word: nhận dạng giọng nói | MIT |
| Whisper large-v3 (bản CTranslate2 của Systran) | Ghi âm sang Word: mô hình | MIT |
| pyodbc | Khôi phục .mdf: kết nối SQL Server | MIT |
| SQL Server Express LocalDB, ODBC Driver 18 | Khôi phục .mdf | Miễn phí của Microsoft |

Dùng nội bộ thì không vướng gì. Nếu sau này muốn bán hoặc đóng gói công cụ DWG sang PDF thành phần mềm đóng
thì cần xem lại giấy phép GPL-3.0 của LibreDWG và AGPL-3.0 của PyMuPDF trước.
