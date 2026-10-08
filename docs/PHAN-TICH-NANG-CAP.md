# Phân tích và hướng nâng cấp

Cập nhật 09/10/2026. Đánh giá 17 công cụ trong `tools\`, những gì đã sửa trong đợt gom vào Trạm Tool,
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
- **Mới**: Máy in mạng LAN và thư mục chia sẻ; BitLocker và khoá khôi phục (mục P0 số 1, 2 của *Công cụ Windows nên
  thêm*); *Kết nối Wi-Fi* trong công cụ Wi-Fi; Gỡ sạch và cài Office theo mẫu; Dọn ổ C an toàn; File thẻ xe .nt cho
  phần mềm giữ xe. Phần chẩn đoán đã chạy thật; các nút sửa mới chạy thử hoặc chạy trên giả lập, chưa chạy ở văn
  phòng có máy in mạng, NAS, máy chia sẻ, chưa chạy trên ổ mã hoá BitLocker thật, chưa gỡ hay cài Office thật, chưa
  dọn ổ C thật, chưa nạp file thẻ do công cụ ghi vào phần mềm giữ xe.
- **Lan can an toàn (Trạm 1.2.0)**: điểm khôi phục hệ thống trước công cụ đổi máy bằng quyền Admin, ghi dịch vụ và
  registry trước khi chạy để xem thay đổi và trả lại, kiểm tra và sửa winget. Đã thử bằng giả lập, chưa tạo điểm khôi
  phục thật (máy phát triển đang tắt Bảo vệ hệ thống).
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
| `0c73dc2`, `840a0ef` | MyExcelFix, mdf2sql | Thêm `HOAN_TAC.bat` (hoàn tác từ trạm) và `CHAY_DONG_LENH.bat` (xem thông tin, chuyển đổi không cần trình duyệt). |
| `cabde6b` | DWG sang PDF | Giải mã chữ font TCVN3 (`.VnTime`, `.VnArial`...); chuyển lại KT-02, trang KT01-02 hết lỗi chữ (`®-êng ®Êt` → "đường đất"). Đã quét 13 bản vẽ còn lại của bộ SAMSORA: không bản nào dùng TCVN3. |
| `4a1afe8` | Máy in mạng LAN (mới), Trạm | Công cụ mới `tools\may-in-lan`. Trạm 1.1.1: `.ps1` chạy qua `-Command` trả đúng mã thoát; trước đó `exit 2`, `exit 3` thành 1 nên Lịch sử không phân biệt được thiếu điều kiện, làm được một phần. |
| `97031b0` | Kiểm tra và sửa lỗi Wi-Fi | `KET_NOI_WIFI.bat` (bản 1.1): sửa lỗi *Can't connect to this network* khi vào mạng mới sau khi máy thức dậy; gọi thẳng API Wi-Fi, mật khẩu gõ trong cửa sổ công cụ và đi từ bộ nhớ vào Windows, không ghi file tạm. |
| `24b424a` | BitLocker (mới), Chuyển dữ liệu khi cài lại Windows | Công cụ mới `tools\bitlocker`. Bước xuất lưu khoá khôi phục BitLocker (màn hình, nhật ký chỉ có Mã khoá) và driver mạng; bước nhập cài lại driver, mở khoá ổ dữ liệu bằng khoá đã lưu. |
| `fba9675` | Trạm | Trạm 1.2.0, lan can an toàn: điểm khôi phục trước action đổi máy bằng quyền Admin, ghi trạng thái dịch vụ và registry trước khi chạy (xem thay đổi, trả lại), kiểm tra winget trước nút *Cài* và nút *Sửa winget*. |
| `d3cb987` | Gỡ sạch và cài Office theo mẫu (mới), Trạm | Công cụ mới `tools\office`: kiểm tra bộ cài mẫu (ODT) trước khi gỡ, gỡ mọi bản Office và phần sót, cài bằng file cấu hình của mẫu ngay tại chỗ, kích hoạt chỉ theo cách của Microsoft; khoá trong mẫu không bao giờ in ra. Trạm: probe `empty`, `badge`, `snapshot`. |
| `92da98a` | Dọn ổ C an toàn (mới), Sửa lỗi Windows | Công cụ mới `tools\don-o-c`: báo ổ C đầy vì đâu, dọn file tạm cũ, bộ nhớ đệm trình duyệt (khi đã tắt), file tải về của Windows Update, Delivery Optimization, WinSxS (không `/ResetBase`); in danh sách, gõ C mới xoá, danh sách thư mục được phép, không đi theo junction. *Clean Temp* của Sửa lỗi Windows chỉ sang công cụ này. |
| `9af2d8e` | File thẻ xe .nt (mới) | Công cụ mới `tools\the-xe-nt`: đọc file thẻ đúng cách phần mềm giữ xe ITS Pro đọc (Jet OLEDB 4.0), sửa file của bên bán có CardID dạng số bị mất số 0, tạo file .nt từ danh sách Excel; ghi CardID dạng chữ đủ 10 số, đọc lại so từng thẻ, kèm file thử 1 thẻ; không cần Excel. |

## Bảng tổng quan

| Công cụ | Dành cho | Đánh giá | Việc nên làm trước |
|---|---|---|---|
| CheckWinFix | Mọi người | Bộ chẩn đoán đầy đủ nhất: 24 nhóm thông tin, khoảng 45 cảnh báo tự động, chạy đúng với mọi đường dẫn. | P0: sửa *Cứu dữ liệu* (đối chiếu MD5 khi SQL còn dừng, so ổ vật lý), bổ sung mã sự kiện mức Warning. |
| Báo cáo sức khoẻ | Mọi người | Chạy được, nhưng trùng phần lớn với *Thu thập thông tin* của CheckWinFix. | P1: gộp vào CheckWinFix thành chế độ nhanh. |
| Sửa lỗi Windows | Kỹ thuật | Đủ lệnh thường dùng nhưng không kiểm tra quyền Admin, báo *hoàn tất* cả khi thất bại; *Reset Network* âm thầm xoá luật tường lửa. | P0: tự nâng quyền, kiểm tra mã lỗi; tách đặt lại tường lửa, bỏ *Registry Cleanup*. |
| Kiểm tra và sửa lỗi Wi-Fi | Mọi người | Bản 1.1 thêm `KET_NOI_WIFI.bat`: gọi thẳng API Wi-Fi (không phụ thuộc ngôn ngữ Windows), sửa lỗi *Can't connect to this network* khi vào mạng mới sau khi máy thức dậy, chẩn đoán từ nhật ký WLAN theo mã lý do. Phần kết nối mới chạy thử, chưa chạy thật. Menu cũ `fixwf.bat` vẫn tìm card bằng chữ. | P1: tự sửa sau khi máy thức dậy; gộp menu cũ vào `KetNoiWifi.ps1`. |
| Máy in mạng LAN và thư mục chia sẻ | Mọi người | Chẩn đoán 11 nhóm, chỉ nút sửa theo mã lỗi; 8 nút sửa in việc sẽ làm, hỏi trước, có Chạy thử, ghi nhật ký hoàn tác; nới bảo mật tách riêng, hỏi 2 lần; không bật SMB1. Mới kiểm chứng trên máy phát triển. | P1: chạy các nút sửa ở văn phòng thật; Local Port `\\MÁY\máy-in` thay cho nới RPC; dò máy in trong mạng. |
| Tắt/bật dịch vụ nền | Kỹ thuật | Báo *thành công* cả khi `sc config` bị từ chối; coi *đã dừng* là *đã tắt*. Tắt Optimize Drives làm mất TRIM cho SSD. | P0: tự nâng quyền, xét kiểu khởi động, lưu trạng thái gốc để khôi phục đúng. |
| Tối ưu đồng hồ hệ thống | Kỹ thuật | Không có tác dụng (ghi sai chỗ). | P0: bỏ khỏi trạm, hoặc viết lại bằng `bcdedit` và đo trước/sau. |
| Gỡ sạch và cài Office theo mẫu | Kỹ thuật | Kiểm tra Office, giấy phép, bộ cài mẫu (ODT) trước; gỡ mọi bản Office rồi cài theo mẫu, mẫu hỏng thì không gỡ gì; sao lưu mẫu Word, macro, chữ ký; khoá trong mẫu không bao giờ in ra, kích hoạt chỉ theo cách của Microsoft. Kiểm tra và Chạy thử đã chạy thật; gỡ, cài, kích hoạt mới thử bằng giả lập. | P1: gỡ, cài thật trên một máy thử; tạo mẫu mới (LTSC 2024, Microsoft 365) ngay trong công cụ; Quick Repair trước khi phải gỡ. |
| Dọn ổ C an toàn | Mọi người | Xem ổ C đầy vì đâu (rác dọn được và thứ chiếm chỗ bạn tự quyết: thùng rác, Windows.old, file ngủ đông, Zalo, Downloads); dọn file tạm cũ hơn N ngày, bộ nhớ đệm trình duyệt khi đã tắt, file tải về của Windows Update, Delivery Optimization, WinSxS. Xem trước, gõ C mới xoá; danh sách thư mục được phép. Xem và Chạy thử đã chạy thật; phần xoá mới thử trong thư mục cát. | P1: dọn thật trên một máy; dọn Teams, bộ cài cập nhật Zalo; liệt kê thư mục lớn nhất. |
| File thẻ xe .nt | Mọi người | Xem file thẻ như phần mềm giữ xe đọc, sửa CardID mất số 0, tạo file .nt từ danh sách; bản sửa lô 3257-3426 khớp từng thẻ với bản sửa tay. Không cần Excel. | P1: nạp thử file do công cụ ghi vào phần mềm thật; so với danh sách thẻ đang có trong phần mềm trước khi nạp. |
| MyExcelFix | Mọi người | Chẩn đoán kỹ theo từng tài khoản Windows, có sao lưu và hoàn tác, mã nguồn chia module và build ra một file `.bat`. | P0: không treo khi thiếu cửa sổ dòng lệnh, hoàn tác không đè file đã sửa sau đó, mã thoát. |
| DWG sang PDF | Mọi người | Không cần AutoCAD; mỗi khung bản vẽ một trang; giải mã chữ VNI và TCVN3. Bản vẽ lớn chậm (5–35 phút). | P1: bộ bản vẽ mẫu để kiểm tra khi nâng thư viện. |
| Ghi âm sang Word | Mọi người | Chạy offline trên card NVIDIA, nhanh khoảng 5 lần thời gian thực, đánh dấu chỗ máy nghe kém chắc chắn. | P1: tên kết quả giữ đuôi file gốc, lưu tiến độ để chạy tiếp, chỉ chạy lại bằng CPU khi đúng là lỗi card. |
| Khôi phục .mdf sang .sql | Kỹ thuật | Khôi phục được file tắt đột ngột hoặc thiếu `.ldf`, xuất cho cả SQL Server và MySQL; luôn làm trên bản sao. | P0: lệnh `doctor` kiểm tra môi trường, không dùng chung cổng 8760. |
| Chuyển dữ liệu khi cài lại Windows | Kỹ thuật | Sao lưu Wi-Fi kèm mật khẩu, máy in kèm driver, dữ liệu Claude, khoá BitLocker, driver mạng; bước nhập mở khoá ổ BitLocker, cài lại driver. Bản sao lưu nằm cạnh script, chứa bí mật dạng chữ thường. | P0: chọn nơi lưu ngoài thư mục công cụ, đánh dấu sao lưu đã xong, chạy thử trước. |
| BitLocker và khoá khôi phục | Mọi người | Kiểm tra từng ổ (mã hoá, tạm dừng, bị khoá), khoá khôi phục đã lưu ở đâu, TPM, các lần máy phải nhập khoá; kết luận theo thứ tự nên làm. 6 nút đổi máy có Chạy thử, nhật ký hoàn tác; khoá 48 số không bao giờ vào báo cáo, nhật ký. Chưa chạy trên ổ mã hoá thật, mới thử bằng giả lập. | P1: chạy thật trên máy có BitLocker; sao lưu khoá lên tài khoản Microsoft; lưu gói khoá `.KPG`. |
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
- [x] Trạm đợi tiến trình xong trong nền, ghi mã thoát và thời gian chạy vào Lịch sử (Trạm 1.1.0). Chưa theo dõi được
      công cụ tự nâng quyền (cửa sổ đầu thoát ngay, cửa sổ Admin là tiến trình khác).
- [ ] Lõi PowerShell dùng chung (kiểm tra Admin, ghi log, đọc SMART, minidump, WHEA, chọn nơi lưu), build ra từng `.bat`
      một file như MyExcelFix để vẫn gửi khách được một file.
- [ ] Gộp: Báo cáo sức khoẻ thành chế độ nhanh của CheckWinFix; Tắt/bật dịch vụ + Tối ưu đồng hồ thành một công cụ
      *Tối ưu* có trang trạng thái.
- [ ] Khôi phục .mdf: `.venv` riêng có pyodbc khoá phiên bản; dọn database tạm, thư mục làm việc bị bỏ lại.
- [ ] Ghi âm sang Word: tên kết quả giữ đuôi file gốc; lưu tiến độ từng khúc; hết bộ nhớ card thì thử lại khúc đó với beam nhỏ.
- [x] DWG sang PDF: giải mã TCVN3 (`.VnTime`, `.VnArial`...) giống cách đã làm với VNI.
- [ ] DWG sang PDF: bộ bản vẽ mẫu + so ảnh từng trang khi nâng ezdxf, PyMuPDF, LibreDWG.

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

**Bản 1.1.0 (04/10/2026): làm lại giao diện, theo dõi lần chạy, xoá kết quả**

- *Tổng quan* thành bảng điều khiển: *Cần chú ý* (công cụ hỏng hoặc thiếu yêu cầu, ổ còn dưới 12%, máy bật từ 14 ngày,
  lần chạy báo lỗi trong 24 giờ, Secure Boot chưa có chứng chỉ 2023), công cụ đã ghim, việc dùng gần đây có nút
  *Chạy lại*; toàn bộ công cụ theo nhóm ở dưới.
- Ô tìm nhanh **Ctrl+K**: công cụ, từng việc chạy được, trang, kết quả gần đây; Enter mở, Ctrl+Enter chạy ngay,
  gõ `>` để chỉ hiện việc chạy được.
- Thanh **Đang chạy**: trạm giữ tiến trình đã mở, đếm giờ, nút hiện cửa sổ; khi cửa sổ đóng thì ghi mã thoát và thời
  gian chạy vào lịch sử, báo ngay nếu lỗi, báo xong nếu chạy lâu (từ 30 giây).
- **Lịch sử** ghi kết quả thay vì chỉ ghi lần mở: *Xong*, *Báo lỗi, mã N*, *Đã đóng cửa sổ*, *Đã huỷ* (từ chối UAC);
  nhóm theo ngày, lọc lần lỗi, chạy lại với đúng tham số cũ, xoá từng dòng hoặc cả lịch sử.
- **Xoá kết quả**: chọn nhiều trong *Kết quả gần đây*, xoá là chuyển vào Thùng rác. Máy chủ chỉ nhận đúng mục đang
  được liệt kê là kết quả của công cụ. `tool.json` khai báo `deleteNote` (cảnh báo phải đánh dấu đã đọc, dùng cho bản
  sao lưu Wi-Fi, sao lưu để hoàn tác, hồ sơ bằng chứng) và `deletable: false` (file bên trong bản sao lưu).
- Form chạy: báo lỗi ngay dưới ô sai, điền sẵn giá trị lần trước; nút *Chạy* có biểu tượng khiên khi cần Admin; hộp
  xác nhận nêu rõ việc sẽ làm. Trang công cụ có dòng *sẵn sàng* (yêu cầu, quyền Admin, thời gian, lần chạy gần nhất).
- Ghim, giao diện sáng/tối, chế độ đơn giản lưu ở máy chủ (`hub\data\settings.json`) thay vì trình duyệt, vì trạm có
  thể đổi cổng khi cổng cũ bận và trình duyệt gắn dữ liệu theo cổng.
- *Máy này* hiện trạng thái Secure Boot và chứng chỉ 2023 (chỉ đọc registry).
- Mã giao diện chia theo trang (`hub\web\js\`), vẽ bằng lit-html; vẫn không cần build, chạy không cần mạng.

**Bản 1.1.1 (04/10/2026)**

- Script `.ps1` trả đúng mã thoát. Trạm chạy `.ps1` bằng `-Command` (để đặt thư mục làm việc), mà `-Command` chỉ trả
  0 hoặc 1; nay trạm tự chuyển mã của `exit N` ra ngoài, Lịch sử hiện đúng *Báo lỗi, mã 2* (thiếu điều kiện),
  *mã 3* (làm được một phần). Khi giữ cửa sổ (`keepOpen`) vẫn như cũ.
- Biểu tượng `print` cho công cụ máy in.

**Bản 1.2.0 (05/10/2026): lan can an toàn**

- **Điểm khôi phục hệ thống** trước action đổi máy bằng quyền Admin (`restorePoint` trong `tool.json`, mặc định khi
  `admin` và `modifies-system`). Hộp xác nhận có ô chọn (đánh dấu sẵn theo *Cài đặt*, mờ đi khi chọn chạy thử).
  `hub\safety\TaoDiemKhoiPhuc.ps1` chạy ngay trong cửa sổ Admin của công cụ nên chỉ hỏi UAC một lần. Windows lặng lẽ
  bỏ qua nếu đã có điểm trong 24 giờ, nên script tạm đặt `SystemRestorePointCreationFrequency=0` rồi trả lại, và xác
  nhận bằng số thứ tự điểm trước, sau. Bảo vệ hệ thống tắt thì hỏi bật (chỉ ổ Windows, giữ dung lượng tối đa mặc định),
  chạy tiếp không có điểm, hay huỷ; lỗi khi tạo thì hỏi chạy tiếp hay huỷ. Không có lựa chọn mặc định. Huỷ trả mã
  1223: công cụ không chạy, Lịch sử ghi *Đã huỷ*. Lịch sử hiện *Điểm khôi phục lúc ...* hoặc lý do không tạo.
- **Ghi trạng thái trước khi chạy**: dịch vụ và registry `HKLM` khai báo trong `probes` ghi ra
  `hub\data\snapshots\` ngay trước mỗi lần chạy có đổi máy (trừ chạy thử). Khi cửa sổ đóng, Lịch sử hiện số mục đã
  khác; *Xem thay đổi* so từng mục, *Trả lại* chạy `hub\safety\TraLaiTrangThai.ps1` (Admin) đặt lại kiểu khởi động và
  giá trị registry đúng kiểu cũ. Không tự gỡ dịch vụ mới cài thêm.
- **winget**: *Máy này* kiểm tra lệnh chạy được và có nguồn chính `winget` (không gọi mạng, giữ kết quả 5 phút). Nút
  *Cài* kiểm tra trước khi mở cửa sổ. *Sửa winget* (`hub\fixes\Sua-Winget.ps1`, quyền thường vì App Installer đăng
  ký theo tài khoản) làm từng bước, bước nào cũng hỏi: đăng ký lại App Installer, `winget source update`,
  `source reset --force` (cửa sổ Admin riêng), `Repair-WinGetPackageManager`, cuối cùng mở trang Store.
- *Máy này* có thẻ *Bảo vệ hệ thống* với nút bật (`hub\safety\BatBaoVeHeThong.ps1`, tạo luôn điểm đầu tiên) và nút mở
  *Khôi phục hệ thống*; *Cần chú ý* báo khi Bảo vệ hệ thống tắt hoặc winget hỏng.
- `probes` có thêm `empty` (registry: chữ hiện khi chưa có giá trị), `"badge": false` (mục chỉ để xem, không gắn nhãn
  *Đã đổi*), `"snapshot": false` (không ghi lại, không trả lại: registry, dịch vụ của phần mềm mà công cụ gỡ hoặc cài,
  như Office; trả lại những mục đó sẽ làm hỏng máy).
- Đã thử: 59 ca đơn vị (định dạng mã lỗi, ghi và trả registry đủ 6 kiểu qua JSON, dịch vụ bằng `sc.exe` giả lập),
  40 kịch bản cho các script `hub\safety` và *Sửa winget* với hàm giả lập (gồm ghép với `.bat`, `.ps1` như trạm gọi:
  huỷ thì công cụ không chạy, chạy tiếp thì giữ đúng mã thoát), trạm thử và ảnh chụp giao diện. Chưa tạo điểm khôi phục
  thật, chưa trả lại dịch vụ thật.

Ghi chú:

- Windows 11 24H2 trở đi (KB5060842) giữ điểm khôi phục tối đa 60 ngày. Tính năng *Point-in-time restore* mới của
  Windows 11 dùng chung chỗ của Volume Shadow Copy, nên trạm không đổi dung lượng tối đa của Bảo vệ hệ thống.
- Nhật ký hoàn tác riêng của từng công cụ (`tools\may-in-lan\lib\NhatKy.ps1`, bản chép trong `tools\bitlocker`) vẫn
  giữ: hai bản đã thử kỹ và ghi được thứ trạm chưa ghi (tường lửa, SMB, máy in, khoá bảo vệ BitLocker). Gộp thành thư
  viện chung để sau, khi có công cụ thứ ba cần.

Hướng thiết kế: giao diện kiểu *Cài đặt* của Windows 11 (Fluent 2), trầm, rõ, một màu nhấn, sáng tối như nhau. Áp dụng
các quy tắc của [taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT) hợp với ứng dụng công cụ: đủ trạng thái
đang tải, trống, lỗi; một hệ bo góc; chữ số thẳng cột; không gạch dài trong chữ giao diện. Tham khảo cách làm của
PowerToys Command Palette, Raycast, Linear (ô Ctrl+K), UniGetUI (bảng tác vụ đang chạy, lịch sử), GitHub Desktop
(trạng thái trống có việc tiếp theo), hướng dẫn UAC và InfoBar của Microsoft.

**Hướng tiếp**: các mục *Trạm* trong lộ trình ở trên (JSON kết quả, tiến độ, cập nhật công cụ); loại probe `script`
chỉ đọc (BitLocker, SMB); thư viện nhật ký hoàn tác chung.

## Công cụ Windows nên thêm

Nghiên cứu ngày 04/10/2026, chủ yếu từ tài liệu của Microsoft và trang chính thức của từng phần mềm. Đã làm mục 1
(`tools\may-in-lan`), mục 2 (`tools\bitlocker`), mục 3 (`tools\don-o-c`) và phần gỡ, cài của mục 5
(`tools\office`); các mục khác chọn mục nào thì làm mục đó. Không lặp lại những thứ đã có hoặc đã nằm trong lộ trình
(SFC, DISM, chkdsk, đặt lại Windows Update, Winsock, SMART, minidump, Defender, báo cáo pin, sao lưu Wi-Fi, máy in).

### Công cụ mới

**P0**

1. **Máy in mạng LAN và thư mục chia sẻ.** Cần Admin, rủi ro vừa.
   - Vì sao: việc hỏi nhiều nhất ở văn phòng, và Windows gần đây làm cách sửa cũ hết tác dụng. Windows 11 22H2 trở đi
     in qua RPC/TCP (máy chủ in cần cổng 135 và 49152 đến 65535). 24H2 bản Pro, Enterprise bắt buộc ký SMB và chặn
     đăng nhập khách, nên NAS và máy photocopy quét vào thư mục báo lỗi 0xc000a000, 0x80070035.
   - Chẩn đoán (chỉ đọc): `Get-Printer`, cổng, driver (đánh dấu *Microsoft IPP Class Driver*, Windows ưu tiên từ
     01/07/2026), khoá chính sách in RPC, `Get-SmbClientConfiguration`, `Test-NetConnection` cổng 135 và 445, sự kiện
     SMBClient 31017.
   - Sửa theo thứ tự, mỗi bước ghi nhật ký để hoàn tác: khởi động lại Spooler và dọn hàng đợi; xoá máy in "(Copy N)";
     cài sẵn driver bằng quyền Admin (lỗi 0x00000bcb); bật luật tường lửa *File and Printer Sharing* theo mã nhóm,
     không theo tên (tên đổi theo ngôn ngữ); dùng cổng TCP/IP, hoặc Local Port `\\MAY\share` kèm `cmdkey /add`.
     Các cách nới bảo mật (named pipe, `RpcAuthnLevelPrivacyEnabled=0`, nới ký SMB, cho khách) để cuối cùng và hỏi xác
     nhận. Không bao giờ bật SMB1.
   - Nguồn: [in qua RPC](https://learn.microsoft.com/en-us/troubleshoot/windows-client/printing/windows-11-rpc-connection-updates-for-print),
     [ký SMB](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing),
     [KB5005652](https://support.microsoft.com/kb/5005652),
     [lộ trình driver máy in](https://learn.microsoft.com/en-us/windows-hardware/drivers/print/end-of-servicing-plan-for-third-party-printer-drivers-on-windows).
   - **Đã làm** (`tools\may-in-lan` 1.0, commit `4a1afe8`): Chẩn đoán và 8 nút sửa, mỗi nút có Chạy thử và nhật ký
     hoàn tác; thêm *Thêm máy in bằng IP* (IPP không cần driver hãng, hoặc cổng 9100) và *Kết nối thư mục chia sẻ*
     (mật khẩu gõ trong cửa sổ công cụ, lưu bằng `cmdkey`). Chưa làm: Local Port `\\MAY\share` (đưa vào hướng nâng cấp
     của công cụ), đánh dấu máy in đang dùng *Microsoft IPP Class Driver*. Đã thử trên máy phát triển: Chẩn đoán, Chạy
     thử mọi nút, nhật ký và hoàn tác registry (khoá thử trong HKCU); chưa chạy các nút sửa với máy in, NAS thật.
2. **BitLocker và khoá khôi phục.** Cần Admin, rủi ro thấp (chỉ đọc và tạm dừng, không bao giờ giải mã).
   - Vì sao: từ 24H2, cài sạch Windows tự mã hoá ổ hệ thống và cả ổ dữ liệu. Máy chỉ có tài khoản cục bộ thì khoá
     không được lưu ở đâu; khoá lên tài khoản Microsoft Admin đầu tiên đăng nhập. Sau khi cập nhật BIOS, thay main hoặc
     TPM, cài lại máy thì gặp màn hình khôi phục hoặc ổ D: bị khoá.
   - Cách làm: `manage-bde -status`, `manage-bde -protectors -get C:` (dự phòng CIM `Win32_EncryptableVolume`),
     `Get-Tpm`; lưu khoá vào `ket_qua\`; trước khi sửa phần cứng, firmware thì `Suspend-BitLocker -MountPoint C: -RebootCount 1`.
   - Nguồn: [BitLocker](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/).
   - **Đã làm** (`tools\bitlocker` 1.0, commit `24b424a`): đọc qua CIM `Win32_EncryptableVolume` thay vì tách chữ
     của `manage-bde` (không phụ thuộc ngôn ngữ; `manage-bde.exe` có sẵn cả trên bản Home). *Kiểm tra* tìm nơi khoá
     đã lưu qua nhật ký sự kiện BitLocker (tài khoản Microsoft, Entra ID, AD) và file khoá. Nút đổi máy: lưu khoá ra
     file, USB, giấy; tạm dừng; bật lại; mở khoá (file khoá khớp Mã khoá, hoặc gõ tay) rồi cho tự mở khoá; hoàn tác.
     Khác đề xuất: có thêm *Giải mã ổ dữ liệu, USB* (hỏi gõ xác nhận; ổ Windows chỉ mở trang cài đặt mã hoá của
     Windows). Khoá 48 số không bao giờ vào báo cáo, nhật ký; trạm không nhận khoá qua tham số. *Chuyển dữ liệu khi
     cài lại Windows* lưu khoá khi xuất, mở khoá ổ khi nhập. Đã thử: *Kiểm tra* bằng quyền thường trên máy phát triển
     (Home, không còn ổ mã hoá), mọi nút trên ổ giả lập; chưa chạy trên ổ mã hoá thật.
3. **Dọn ổ C an toàn, xem trước rồi mới dọn.** Cần Admin, rủi ro thấp (chỉ xoá thứ tự sinh lại được).
   - Vì sao: ổ C đầy là chuyện thường ngày; *Clean Temp* của Sửa lỗi Windows chỉ dọn TEMP.
   - Báo cáo trước: TEMP, `Windows\Temp`, `SoftwareDistribution\Download`, Delivery Optimization, WinSxS
     (`Dism /Online /Cleanup-Image /AnalyzeComponentStore`), bộ nhớ đệm Chrome, Edge, Cốc Cốc, Brave, Teams mới,
     Windows.old, Zalo (chỉ báo dung lượng).
   - Dọn: file cũ hơn 7 ngày; `Delete-DeliveryOptimizationCache -Force`; `/StartComponentCleanup` (không dùng
     `/ResetBase` vì sau đó không gỡ được bản cập nhật đã cài); bộ nhớ đệm ứng dụng chỉ khi ứng dụng đã tắt; mở
     Storage Sense (`ms-settings:storagesense`); tuỳ chọn BleachBit `--preview` rồi `--clean`.
   - Nguồn: [dọn WinSxS](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder),
     [bộ nhớ đệm Teams](https://learn.microsoft.com/en-us/troubleshoot/microsoftteams/teams-administration/clear-teams-cache).
   - **Đã làm** (`tools\don-o-c` 1.0, commit `92da98a`): 4 nút (xem, dọn rác của bạn không cần Admin, dọn rác của
     Windows, WinSxS) và nút mở Storage Sense. Thư mục dọn tính từ đường dẫn chuẩn của Windows, kiểm tra với danh sách
     được phép trước mỗi lần xoá; file chỉ xoá khi cả ngày sửa lẫn ngày tạo cũ hơn N ngày; bộ nhớ đệm trình duyệt chỉ
     các thư mục Cache, Code Cache, GPUCache, Dawn*, ShaderCache (không đụng Service Worker, mật khẩu, lịch sử). Khác
     đề xuất: `SoftwareDistribution\Download` dọn theo tuổi file và bỏ qua khi Windows đang cài hoặc chờ khởi động lại,
     không dừng dịch vụ; Teams, Zalo, Windows.old, thùng rác chỉ báo dung lượng và cách xử lý; chưa có BleachBit. Đã
     thử: 92 phép thử trong thư mục cát, *Xem* và *Chạy thử* thật bằng quyền thường; chưa dọn thật.

**P1**

4. **Gói tiếng Việt.** Phần lớn không cần Admin, rủi ro thấp (sao lưu registry, hoàn tác được).
   - Bộ gõ: dùng lại phần dò của MyExcelFix (`tools\myexcelfix\src\50_user_env.ps1`) để báo hai bộ gõ cùng lúc
     (UniKey, EVKey, OpenKey cùng bàn phím Telex của Windows), bộ gõ không chạy quyền Admin nên không gõ được vào ứng
     dụng chạy Admin, tự khởi động trùng.
   - Tài liệu cũ: liệt kê font VNI, .Vn; chuyển *bản sao* .docx, .xlsx sang Unicode bằng `vni.py`, `tcvn3.py` của DWG
     sang PDF. Không kèm font VNI (có bản quyền).
   - Định dạng số, ngày: mẫu cài sẵn cho `HKCU\Control Panel\International` (dấu thập phân, dấu nghìn, dấu phân cách
     danh sách, ngày ngắn), hoặc chỉ trong Excel bằng
     [Use system separators](https://support.microsoft.com/office/c093b545-71cb-4903-b205-aebb9837bd1e).
5. **Sửa Office.** Cần Admin; Quick Repair rủi ro thấp, Online Repair rủi ro vừa (cài lại cả bộ).
   - Gỡ sạch, cài theo bộ cài mẫu, kích hoạt bằng khoá của người dùng: đã làm (`tools\office`). Còn các mục dưới.
   - Đọc Platform, ClientCulture trong `ClickToRun\Configuration`; Quick Repair bằng
     `OfficeClickToRun.exe scenario=Repair platform=<Platform> culture=<ClientCulture> RepairType=QuickRepair`;
     cập nhật bằng `OfficeC2RClient.exe /update user`.
   - Mở chế độ `/safe`; liệt kê add-in COM và Disabled Items; đổi tên OST (chỉ tài khoản IMAP, Exchange, không đụng
     `.pst` của POP); `Unblock-File` cho file macro tin cậy; tìm file chưa lưu.
   - Đặt lại kích hoạt: GetHelpCmdLine (bản dòng lệnh SaRA đã bị gỡ từ 10/03/2026).
   - Nguồn: [gỡ SaRA](https://support.microsoft.com/topic/5913939c-87ff-45b0-8e9b-14dc89bfdfee),
     [dòng lệnh Quick Repair (lưu trữ)](https://learn.microsoft.com/en-us/archive/blogs/office_resource_kit/automating-quick-repairs-in-office-365-proplus).
6. **Đồng hồ và chữ ký số (USB token).** Sửa thì cần Admin; rủi ro thấp (lưu `w32tm /query /configuration` trước).
   - Vì sao: sai giờ hoặc múi giờ làm hỏng HTTPS, kích hoạt, và ký số thuế điện tử, hoá đơn điện tử, BHXH.
   - Đồng hồ: `w32tm /stripchart /computer:time.windows.com /samples:3 /dataonly`, `tzutil /g` (cần
     *SE Asia Standard Time*), rồi `w32tm /resync /force`.
   - Token: dịch vụ SCardSvr đang chạy, `certutil -scinfo` đọc được token, chứng thư có khoá riêng trong
     `Cert:\CurrentUser\My` sắp hết hạn trong 30 ngày, đã cài eSigner chưa.
   - Nguồn: [gỡ lỗi thẻ thông minh](https://learn.microsoft.com/en-us/windows/security/identity-protection/smart-cards/smart-card-debugging-information).
7. **Hỗ trợ từ xa.** Chỉ cần Admin khi cài. Quick Assist có sẵn trong Windows (người hỗ trợ cần tài khoản Microsoft,
   người được hỗ trợ phải tự bấm UAC); thêm UltraViewer (`DucFabulous.UltraViewer`) và RustDesk (AGPL-3.0, dùng lâu dài
   thì tự dựng máy chủ). Hiện cảnh báo lừa đảo của Microsoft trước khi mở.
   Nguồn: [Quick Assist](https://learn.microsoft.com/en-us/windows/client-management/client-tools/quick-assist).
8. **Bộ ứng dụng chuẩn bằng winget.** Danh sách JSON: Zalo (`VNGCorp.Zalo`), UniKey (`UniKey.UniKey`) hoặc EVKey
   (`lamquangminh.EVKey`), 7-Zip, Foxit Reader, UltraViewer, Cốc Cốc (bản trên winget dừng ở v120, ứng dụng tự cập
   nhật). Cài bằng `winget install --id X -e --silent --accept-package-agreements --accept-source-agreements`, giữ mới
   bằng `upgrade` và `pin`. Giao diện tuỳ chọn: [UniGetUI](https://github.com/Devolutions/UniGetUI) (MIT; các trang
   wingetui, unigetui đuôi .com là trang giả).

**P2**

9. **Bộ đồ nghề kỹ thuật**, cài bằng winget trên máy cần sửa thay vì để trong repo (khỏi vướng nghĩa vụ GPL).
   - Sysinternals miễn phí nhưng [điều khoản](https://learn.microsoft.com/en-us/sysinternals/license-terms) cấm phát
     lại: không để trong repo, không đóng gói gửi khách.
   - Dùng được: CrystalDiskInfo (MIT), smartmontools 7.5 (`smartctl -j` ra JSON), BleachBit, 7-Zip, WinDirStat;
     Rufus, Ventoy cho USB cứu hộ của mình.
   - [BlueScreenView](https://www.nirsoft.net/utils/blue_screen_view.html) chỉ được phát lại miễn phí, nguyên bản.
     Bỏ HWiNFO: dùng thương mại cần [bản Pro](https://www.hwinfo.com/files/license.pdf). WinUtil (MIT) chỉ lấy ý
     tưởng vì nó chạy kiểu tải script rồi chạy thẳng (`irm | iex`).
10. **Mã độc và USB.** Defender: `Update-MpSignature`, `Start-MpScan`, `Start-MpWDOScan` (khởi động lại máy, hỏi
    trước). USB bị "virus shortcut": liệt kê `.lnk`, `autorun.inf`, rồi `attrib -h -s` trả lại file thật.
11. **Sẵn sàng lên Windows 11.** Kiểm tra như HardwareReadiness.ps1 và `mbr2gpt /validate /allowFullOS` (chỉ đọc).
    Windows 10 bản thường có cập nhật bảo mật mở rộng tới
    [12/10/2027](https://www.microsoft.com/windows/extended-security-updates) nên chưa gấp.

### Bổ sung cho trạm và công cụ đang có

- ~~**P0 Trạm**: điểm khôi phục, ghi trạng thái để hoàn tác, kiểm tra winget~~: đã làm (Trạm 1.2.0, commit
  `fba9675`, xem mục *Trạm Tool*). Còn: thư viện nhật ký hoàn tác chung (`tools\may-in-lan\lib\NhatKy.ps1` ghi được
  tường lửa, SMB, máy in; `tools\bitlocker` chép lại cho khoá bảo vệ), loại probe `script` chỉ đọc để hiện BitLocker,
  SMB.
- ~~**P0 Chuyển dữ liệu khi cài lại Windows**~~: đã làm (commit `24b424a`). Bước xuất ghi trạng thái BitLocker mọi ổ
  và lưu khoá, xuất driver bằng `pnputil /export-driver` (mặc định chỉ driver mạng của hãng, lớp NET, vì cần ngay sau
  khi cài lại; chọn [T] để xuất mọi driver); bước nhập dùng `pnputil /add-driver <thư mục>\*.inf /subdirs /install`
  và mở khoá ổ bằng khoá đã lưu.
- **P1 CheckWinFix (chỉ đọc)**:
  - Secure Boot: `UEFICA2023Status` và sự kiện TPM-WMI 1801, 1808. Chứng chỉ Windows Production PCA 2011 hết hạn
    **19/10/2026**; máy vẫn khởi động nhưng không nhận bản vá bảo mật khởi động nữa
    ([KB5062710](https://support.microsoft.com/help/5062710)). Trạm 1.1.0 đã hiện ở *Máy này* và *Cần chú ý*; máy
    này đã có chứng chỉ 2023.
  - Kích hoạt Windows qua CIM `SoftwareLicensingProduct`, đánh dấu máy chủ KMS lạ và dấu vết phần mềm kích hoạt lậu.
    Không dùng `slmgr.vbs`: Microsoft định tắt VBScript mặc định khoảng năm 2027.
  - Thêm `reagentc /info`, `powercfg /requests`, `powercfg /sleepstudy`, sự kiện MemoryDiagnostics-Results 1201, 1202.
- **P1 Sửa lỗi Windows**: `wsreset.exe -i`; dựng lại bộ nhớ đệm biểu tượng, ảnh thu nhỏ; dựng lại chỉ mục tìm kiếm
  (`SetupCompletedSuccessfully=0` rồi khởi động lại WSearch); `Repair-Volume -Scan`, `-SpotFix` trước `chkdsk /r`;
  bước cuối là [Fix problems using Windows Update](https://support.microsoft.com/windows/fix-issues-by-reinstalling-the-current-version-of-windows)
  (cài lại Windows, giữ ứng dụng và file). Không dùng `msdt.exe`: các trình gỡ rối của nó đã bị bỏ.
- **P1 Wi-Fi**: đặt lại proxy và hosts: `netsh winhttp reset proxy`, proxy trình duyệt của người dùng
  (`ProxyEnable=0`), khôi phục file hosts từ bản sao lưu.

### Nên làm trước

1. ~~**Máy in mạng LAN và thư mục chia sẻ**~~: đã làm (`tools\may-in-lan`); còn chạy thử các nút sửa ở một văn phòng
   thật.
2. ~~**BitLocker**, kèm xuất khoá và driver trong *Chuyển dữ liệu khi cài lại Windows*~~: đã làm (`tools\bitlocker`,
   commit `24b424a`); còn chạy thật trên máy có ổ mã hoá.
3. ~~**Lan can an toàn của trạm**: điểm khôi phục, nhật ký hoàn tác, kiểm tra winget~~: đã làm (Trạm 1.2.0, commit
   `fba9675`); còn tạo điểm khôi phục, trả lại dịch vụ thật trên một máy có bật Bảo vệ hệ thống.
4. ~~**Dọn ổ C an toàn**~~: đã làm (`tools\don-o-c`, commit `92da98a`); còn dọn thật trên một máy.
5. **Gói kiểm tra chỉ đọc cho CheckWinFix**: rẻ, nhanh (Secure Boot, kích hoạt, môi trường khôi phục, giấc ngủ).

Sau đó là **Gói tiếng Việt**.

### Chưa kiểm chứng

Mới có nguồn cộng đồng hoặc chưa thử; kiểm tra trên máy thật trước khi đưa vào công cụ:

- Tham số sửa Office Click-to-Run.
- GUID kênh PerpetualVL2021, PerpetualVL2024 trong `CDNBaseUrl` (công cụ Office đang nhận ra hai kênh này qua mã sản
  phẩm), dòng kết quả `NN: ...` của GetHelpCmd khi chạy thật (công cụ Office đọc theo tài liệu).
- Cách dựng lại chỉ mục tìm kiếm, bộ nhớ đệm biểu tượng, `wsreset -i`.
- Đường dẫn dữ liệu Zalo: thấy `%APPDATA%\ZaloData`, `%LOCALAPPDATA%\zalo-updater`, `%LOCALAPPDATA%\Programs\Zalo`
  trên máy phát triển, chưa có tài liệu của Zalo. Công cụ Dọn ổ C chỉ báo dung lượng, không xoá.
- Phần mềm giữ xe ITS Pro nạp file .nt do công cụ thẻ xe ghi (ghi bằng Jet từ file mẫu trống): đã đọc lại bằng đúng
  cách phần mềm đọc, chưa nạp vào phần mềm thật.
- `RpcAuthnLevelPrivacyEnabled=0` còn tác dụng trên máy chủ in 24H2, 25H2 không (diễn đàn báo còn; Microsoft chưa
  ghi rõ). Công cụ máy in để mục này ở *Nới bảo mật*, hoàn tác được.
- Mã winget `RustDesk.RustDesk`.
- UltraViewer bản miễn phí có cho dùng thương mại không.
- Yêu cầu eSigner của thuế điện tử.
- Giấy phép các font .Vn (TCVN3).

## Thư viện bên thứ ba

Tất cả miễn phí. Thư viện của giao diện trạm nằm sẵn trong `hub\web\vendor\` (chạy không cần mạng);
thư viện của công cụ được script cài đặt tải về, không đưa vào git.

| Thư viện | Dùng cho | Giấy phép |
|---|---|---|
| Fluent UI Web Components | Giao diện trạm | MIT |
| Fluent UI System Icons | Biểu tượng của giao diện trạm (`hub\web\icons.svg`) | MIT |
| lit-html | Giao diện trạm: vẽ và cập nhật trang | BSD-3-Clause |
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
