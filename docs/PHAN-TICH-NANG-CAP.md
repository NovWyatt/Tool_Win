# Phân tích và hướng nâng cấp

Cập nhật 20/10/2026. Đánh giá 19 công cụ trong `tools\`, những gì đã sửa trong đợt gom vào Trạm Tool,
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
- **Cần sửa trước khi đưa người khác dùng (P0)**: đã sửa hết (giai đoạn 1 của *Lộ trình*). Phần lớn nút đổi máy
  mới thử bằng giả lập: nên chạy thật trên một máy thử trước khi đưa cho khách.
- **CheckWinFix 2026.10.2**: *Cứu dữ liệu* chọn nơi lưu trên ổ vật lý khác, dừng mọi instance SQL Server, đối chiếu
  MD5 khi SQL còn dừng, luôn bật lại dịch vụ (nhớ cả khi cửa sổ bị đóng), luôn ghi vào thư mục mới; bảng cảnh báo so
  theo nguồn + mã sự kiện, đọc cả mức Warning, tách lỗi ổ đĩa theo từng Disk; kiểm tra Admin bằng `fltmc`. Cứu dữ
  liệu mới thử bằng giả lập.
- **Sửa lỗi Windows 2.0**: mỗi lệnh kiểm tra kết quả thật (DISM đọc trạng thái ảnh, SFC đọc CBS.log, ổ đĩa dùng
  `Repair-Volume`); đặt lại tường lửa tách riêng, sao lưu trước và hỏi lại; bỏ *Registry Cleanup*, *Clean Temp*. Mới
  thử bằng giả lập, chưa chạy sửa thật.
- **Tắt/bật dịch vụ nền 2.0**: xét kiểu khởi động thay vì đang chạy hay dừng, lưu kiểu khởi động gốc trước khi tắt để
  bật lại đúng như cũ, đọc lại sau mỗi lần đổi. Mới thử bằng giả lập, chưa đổi dịch vụ thật.
- **Tối ưu đồng hồ hệ thống 2.0**: bản cũ ghi thiết lập vào registry trong khi Windows đọc từ BCD nên không có tác
  dụng; bản mới đổi thẳng trong BCD (`bcdedit`), đọc lại sau khi đổi, tạm dừng BitLocker 1 lần khởi động khi cần. Mới
  thử bằng giả lập, chưa đổi BCD thật.
- **MyExcelFix 2026.10.1**: hết đầu vào thì dừng có thông báo thay vì hỏi lại mãi; mã thoát cho Kiểm tra, Sửa,
  Hoàn tác; hoàn tác lưu cấu hình hiện tại trước, so dấu SHA-256 từng file Excel và giữ bản đã sửa tiếp thành
  `*.truoc_hoantac.xlsx`; JSON kết quả với mã phát hiện cố định; `build.ps1` đóng dấu phiên bản. Mới thử bằng giả
  lập (registry thử, bộ MyExcel giả), chưa chạy trên máy có MyExcel thật.
- **Chuyển dữ liệu khi cài lại Windows 2.0**: chọn nơi lưu (gợi ý USB, ổ dữ liệu; không cho để trong thư mục Trạm
  Tool), tuỳ chọn mã hoá mật khẩu Wi-Fi và cấu hình Claude vào `BiMat.aes` (AES-256, PBKDF2-SHA256, HMAC; không ghi ra
  đĩa dạng chữ); `manifest.json` ghi đang làm/xong/một phần/lỗi, bước nhập bỏ bản chưa xong và hỏi trước khi dùng
  bản `_cu_`; `-Mode -Target -DryRun -Yes -NoPause`, mã thoát 0/1/2/3, JSON kết quả; các bước chép lỗi không còn
  báo [OK]. Mới thử bằng giả lập (Wi-Fi, máy in, BitLocker, driver, Claude giả) và chạy thử chỉ đọc trên máy thật.
- **Khôi phục .mdf sang .sql**: máy phát triển nay đã có ODBC Driver 17 và SQL Server Express (09/10/2026), trạm báo
  đủ yêu cầu; máy mới thì `CAI_DAT.bat` cài ODBC Driver 18 và LocalDB (cần quyền Admin).
- **Khôi phục .mdf sang .sql 2026.10.1 (mdf2sql 1.1.0)**: lệnh `doctor` (nút *Kiểm tra máy đủ điều kiện chưa*) kiểm
  tra pyodbc, driver ODBC, SQL Server (kết nối thử, quyền tạo database), database tạm và thư mục làm việc còn sót, in
  cách sửa; máy chủ giao diện giữ cổng riêng, cổng 8760 bận thì tự lùi, nhận `--port 0`; `/api/health`,
  `/api/shutdown` và `server.json` để trạm quản lý. `doctor` đã chạy thật với SQL Server Express của máy phát triển.
- **Đợt sửa nhanh P1 (09/10/2026)**: Đăng xuất GitHub 1.1 xoá mọi mục GitHub của Git (cả mục lưu kèm tên tài khoản),
  hỏi trước với mục của ứng dụng khác, có Chạy thử; Báo cáo sức khoẻ 1.1 không có sự kiện thì in [OK] thay vì [LOI],
  tự nâng quyền đúng khi thư mục có dấu `'`; Ghi âm sang Word 2026.10.1 giữ đuôi file gốc trong tên kết quả (vẫn nhận
  kết quả bản cũ), thêm `--ra`; mdf2sql 1.1.1 mở hộp thoại chọn file trong tiến trình riêng, `Chay_tool.bat` chạy thử
  Python thật. Thử bằng giả lập (cmdkey, `Get-WinEvent`, `python.exe`, tkinter giả); trên máy thật mới đọc
  Credential Manager (chỉ đếm), nhật ký Application và kết quả ghi âm có sẵn, chưa xoá đăng nhập thật.
- **MyExcelFix 2026.10.2 (bảo vệ dữ liệu khách)**: sao lưu (có số tài khoản ngân hàng) vào
  `%LOCALAPPDATA%\MyExcelFix\SaoLuu` thay vì Desktop (thường đồng bộ OneDrive); báo cáo, JSON kết quả vào
  `%LOCALAPPDATA%\MyExcelFix\BaoCao` thay vì Public Documents (mọi tài khoản đọc được), chỉ snapshot cấu hình còn ở thư
  mục chung để so giữa các tài khoản; báo cáo che cả tên chủ tài khoản; `ThongTinKhaiBao.txt` chỉ ghi khi đặt lại thật;
  `HOAN_TAC.bat` không tham số liệt kê bản sao lưu để chọn (cả bản cũ trên Desktop). Mới thử bằng giả lập.
- **Trạm 1.4.0 (kết quả máy đọc được)**: chuẩn JSON kết quả chung `tramtool.ketqua/1`; MyExcelFix 2026.10.3,
  Chuyển dữ liệu 2.1 và `mdf2sql doctor --ket-qua` ghi theo chuẩn. Trạm gắn kết quả vào Lịch sử, hiện từng phát
  hiện kèm cách sửa và nút chạy tiếp; mã 2 hiện *Chưa làm*, 3 hiện *Làm được một phần*; mở lại, tắt giao diện web của
  mdf2sql qua `server.json`. Đã thử trên trạm thử với công cụ giả, máy chủ giả và máy chủ mdf2sql thật; chưa xem kết
  quả MyExcelFix của một máy có MyExcel thật trong trạm.
- **Gộp công cụ trùng (CheckWinFix 2026.10.3, Tối ưu Windows 1.0)**: *Báo cáo sức khoẻ máy* gộp vào *Thu thập thông
  tin* của CheckWinFix: ô *Kiểm tra sâu* chạy `Repair-WindowsImage -ScanHealth` và `Repair-Volume -Scan` (đọc kết quả
  có cấu trúc thay cho chữ của `sfc /verifyonly`, đúng trên Windows mọi ngôn ngữ). Thu thập thông tin ghi JSON theo
  chuẩn của trạm: khoảng 60 cảnh báo, mỗi cảnh báo một mã cố định và một mức, gợi ý script chuyên sâu chạy tiếp; hai
  câu hỏi nằm trong form của trạm; lỗi ổ USB hoặc ổ đã rút chỉ là cảnh báo. *Tắt/bật dịch vụ nền* và *Tối ưu đồng hồ
  hệ thống* thành *Tối ưu Windows* (`tools\toi-uu`): một nút Kiểm tra xem cả hai, gợi ý nút sửa (bật lại Tối ưu ổ đĩa
  khi máy có SSD, trả đồng hồ về mặc định khi đang ép HPET); hai script đã thử kỹ giữ nguyên và chạy riêng được; file
  trạng thái gốc ở chỗ cũ tự chuyển sang. Thu thập thông tin đã chạy thật bằng quyền thường trên máy phát triển; Kiểm
  tra dịch vụ chạy thật, phần đồng hồ cần quyền Admin nên mới thử bằng giả lập.
- **Công cụ mới: Giờ máy và chữ ký số, Bộ ứng dụng văn phòng** (mục 6, 8 của *Công cụ Windows nên thêm*). Giờ máy và
  chữ ký số: ký số thuế, hoá đơn điện tử, BHXH báo lỗi thì Kiểm tra (quyền thường) đo độ lệch giờ với máy chủ giờ
  (NTP, mạng chặn thì đọc giờ của trang http), múi giờ, dịch vụ giờ, dịch vụ Smart Card, đầu đọc token, chứng thư ký
  số (hết hạn, chưa tới ngày hiệu lực vì giờ máy chậm, thiếu chứng thư gốc), phần mềm ký số; *Sửa giờ*, *Sửa token*
  lưu giá trị cũ để *Trả lại*; không hỏi PIN, không đọc khoá riêng. Bộ ứng dụng văn phòng: cài một lượt Zalo, bộ gõ
  tiếng Việt, 7-Zip, đọc PDF, UltraViewer, Chrome... từ nguồn winget, bỏ qua ứng dụng đã có, hai bộ gõ chỉ cài một,
  đọc lại danh sách đã cài (`winget export`) thay vì tin mã thoát của bộ cài; danh sách sửa được trong
  `DanhSach.json`. Cả hai ghi JSON theo chuẩn của trạm kèm nút sửa. Kiểm tra đã chạy thật bằng quyền thường trên máy
  phát triển; sửa giờ, sửa token, cài, cập nhật mới chạy thử và thử bằng giả lập.
- **JSON kết quả cho mọi công cụ chẩn đoán, sửa (10/10/2026)**: Máy in LAN 1.1, BitLocker 1.1, Dọn ổ C 1.1, Sửa lỗi
  Windows 2.1, Office 1.1 và bốn script chuyên sâu của CheckWinFix (bản 1.1) ghi theo chuẩn `tramtool.ketqua/1`: mỗi
  phát hiện một mã cố định, nút chạy tiếp trỏ tới nút sửa có thật; chạy thử, thiếu quyền Admin, làm được một phần có
  trạng thái riêng; khoá khôi phục BitLocker, khoá sản phẩm Office không vào JSON. Chẩn đoán phần cứng nay tách lỗi
  của ổ USB, ổ đã rút như Thu thập thông tin (bản cũ coi hơn 50 sự kiện ổ đĩa bất kỳ là ổ cứng hỏng, và đã báo nhầm
  như vậy trên máy phát triển). Kiểm tra, chẩn đoán đã chạy thật bằng quyền thường trên máy phát triển; nút sửa vẫn mới
  chạy thử và thử bằng giả lập.
- **CheckWinFix 2026.10.4 (gói kiểm tra chỉ đọc)**: *Thu thập thông tin* thêm Secure Boot (chứng chỉ 2023, sự kiện
  TPM-WMI 1795, 1796, 1801, 1808, firmware từ chối ghi), bản quyền Windows (chỉ tên, kênh, trạng thái, máy chủ KMS;
  không đọc khoá; dấu vết phần mềm kích hoạt lậu), WinRE, chương trình giữ máy thức, kết quả test RAM. Phần dùng chung
  (`src\Chung.ps1`: kiểm tra Admin, ghi JSON, đọc SMART) dựng vào từng `.bat` bằng `src\build.ps1`; mỗi `.bat` vẫn gửi
  riêng cho khách được. Đã chạy thật bằng quyền thường trên máy phát triển.
- **Trạm 1.5.0 (tiến độ, cập nhật công cụ, gợi ý cho ô chọn)**: chuẩn tiến độ `tramtool.tiendo/1`; thanh *Đang chạy*
  hiện phần trăm, bước, thời gian còn lại của DWG sang PDF, Ghi âm sang Word, Chuyển tài liệu sang Unicode. *Cập nhật
  công cụ* từ git (chỉ fast-forward, dừng khi có file đang sửa). Ô chọn thư mục có danh sách gợi ý (`goiY`), dùng cho
  form Hoàn tác của MyExcelFix (liệt kê bản sao lưu của đúng tài khoản). Ghi âm sang Word 2026.10.2 làm tiếp từ khúc
  đã xong khi bị ngắt; card hết bộ nhớ thì thử lại khúc đó. mdf2sql 1.3.0 cài pyodbc 5.3.0 vào `.venv` riêng.
- **Công cụ mới: Gói tiếng Việt** (mục 4 của *Công cụ Windows nên thêm*):
  - *Kiểm tra* (quyền thường): bộ gõ (hai bộ cùng chạy, khởi động trùng, bàn phím tiếng Việt của Windows bật cùng),
    font VNI và TCVN3, định dạng số và ngày, Excel dùng dấu riêng, chế độ UTF-8 (Beta).
  - *Đặt định dạng* kiểu Việt Nam hoặc quốc tế cho tài khoản; lưu giá trị cũ để *Trả lại*.
  - *Chuyển tài liệu sang Unicode*: chép `.docx`, `.xlsx` font VNI, TCVN3 thành bản Unicode; giải mã theo font của
    từng đoạn chữ; file gốc giữ nguyên.
  - Đã thử: *Kiểm tra* chạy thật; bản chuyển mở được bằng Word, Excel thật; *Đặt định dạng* chạy thật trên khoá
    registry thử.
  - Chưa thử: đổi định dạng thật trên một máy.
- **Công cụ mới: Đồng bộ phiên Claude giữa các tài khoản** (Wyatt đề nghị 17/10/2026):
  - Claude Desktop lưu danh sách phiên tab Code theo tài khoản (`claude-code-sessions\<tài khoản>\<tổ chức>`), nội
    dung hội thoại dùng chung (`~\.claude\projects`), nên đổi tài khoản là thanh bên trống.
  - *Đồng bộ* chép các mục danh sách của tài khoản khác trên máy (hoặc từ gói sao lưu) vào tài khoản đang đăng nhập;
    bản mới hơn thắng, phiên đã xoá không thêm lại, bỏ kết nối claude.ai và Remote Control của tài khoản cũ.
    *Sao lưu* gói danh sách kèm nội dung để mang sang máy khác. *Hoàn tác* có nhật ký.
  - Đã thử: giả lập đủ các trường hợp; Kiểm tra, Sao lưu và Đồng bộ chạy thử trên dữ liệu thật (12 phiên).
  - Chưa thử: đồng bộ thật sang tài khoản thứ hai.
- **Đồng bộ phiên Claude 1.1** (Wyatt bảo làm hết các hướng nâng cấp, 20/10/2026):
  - Đi kèm phiên: tác vụ hẹn giờ (`scheduled-tasks.json`, `~\.claude\scheduled-tasks`), mẫu phiên, nhóm tự tạo trên
    thanh bên (chỉ thêm nhóm, không đổi nhóm có sẵn), trí nhớ dự án (`~\.claude\projects\<dự án>\memory`, sửa đường
    dẫn khi đổi máy); Cowork khi chọn `-KemCowork`. Mục đã xoá ở tài khoản này không bị thêm lại ở lần sau.
  - Gói sao lưu cập nhật dần (chỉ chép file đổi), đánh dấu đang ghi dở; `-Nen` thành `.zip`, `-MaHoa` thành `.aes`
    (cùng định dạng với `BiMat.aes` của new-windows, mật khẩu gõ trong cửa sổ công cụ, không qua tham số).
  - Ghi bản Claude Desktop đã xem; kiểm cấu trúc từng mục danh sách, bỏ mục lạ, đa số sai thì dừng
    (`CACH_LUU_DA_DOI`) thay vì ghi vào cách lưu mới. Đọc danh sách có bộ đệm.
  - *Mở Claude*: đồng bộ (khi Claude đang tắt) rồi mở Claude; *Tạo lối tắt* trên màn hình; `-MoClaude` cho *Đồng bộ*.
    *Kiểm tra* báo lần đồng bộ gần nhất và phiên đã đồng bộ mà nay mất khỏi danh sách (để kiểm sau lần thử thật).
  - Chuyển dữ liệu khi cài lại Windows 2.2: nhập Claude xong mà tài khoản đang đăng nhập không có phiên nào thì gợi ý
    chạy *Đồng bộ* (nút chạy tiếp trong trạm).
  - Đã thử: 133 mục giả lập (gồm mã hoá, zip slip, máy thứ hai qua `.aes`, `.zip`); chạy thử trên dữ liệu thật (16
    phiên, đúng cấu trúc). Chưa thử: đồng bộ thật sang tài khoản thứ hai, lối tắt thật.

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
| `8aff9e2` | File thẻ xe .nt | Bản 1.1: chuyển file .nt sang Excel (mỗi thẻ một dòng, mã phần mềm đọc được, kết quả từng thẻ, ô có vấn đề tô đỏ; sửa xong chuyển ngược lại ra .nt); kiểm tra file .nt so với danh sách Excel (khớp, mất số 0, khác mã, thiếu, thừa); đọc, ghi .xlsx thẳng nên không cần Excel cả khi danh sách là .xlsx; nhận ra .xlsx bị đổi đuôi .nt. |
| `cc3b8e8` | Trạm, mọi `tool.json` | Trạm 1.3.0: giao diện làm lại không dùng Fluent UI (hệ màu riêng, chữ Be Vietnam Pro, biểu tượng Phosphor, danh mục dạng mục lục, một nút chính mỗi vùng); `CAI_DAT.bat` cài một lần mọi thứ các công cụ cần trên máy mới, rồi tạo lối tắt và mở trạm; `tool.json` bỏ gạch dài. |
| `7e54901` | Tối ưu đồng hồ hệ thống | Bản 2.0: bản cũ ghi vào registry (Windows không đọc) nên không có tác dụng; nay đổi thẳng trong BCD bằng `bcdedit`, đọc lại sau khi đổi, tạm dừng BitLocker 1 lần khởi động khi cần, dọn giá trị registry bản cũ. |
| `19136e0` | Tắt/bật dịch vụ nền | Bản 2.0: xét kiểu khởi động thay vì đang chạy hay dừng, lưu kiểu khởi động gốc trước khi tắt để *Bật lại* trả đúng như cũ, đọc lại sau mỗi lần đổi. |
| `43b7a27` | Sửa lỗi Windows | Bản 2.0: mỗi lệnh kiểm tra kết quả thật (DISM, SFC đọc CBS.log, `Repair-Volume`); đặt lại tường lửa tách riêng, sao lưu `.wfw` và hỏi lại; bỏ *Registry Cleanup*, *Clean Temp*. |
| `acc7e46` | CheckWinFix, Kiểm tra và sửa lỗi Wi-Fi | CheckWinFix 2026.10.2: *Cứu dữ liệu* lưu sang ổ vật lý khác, dừng mọi instance SQL Server, đối chiếu MD5 khi SQL còn dừng, luôn bật lại dịch vụ; cảnh báo so theo nguồn + mã, đọc cả mức Warning. Cả CheckWinFix và `fixwf.bat` kiểm tra Admin bằng `fltmc`, mã thoát 0/1/2/3. |
| `330017a` | MyExcelFix | 2026.10.1: hết đầu vào thì dừng; hoàn tác lưu cấu hình hiện tại trước, so SHA-256 từng file Excel, giữ bản đã sửa tiếp; mã thoát và JSON kết quả có mã phát hiện cố định. |
| `72eb0f2` | Chuyển dữ liệu khi cài lại Windows | Bản 2.0: chọn nơi lưu (USB trước, không cho thư mục Trạm Tool); tuỳ chọn mã hoá mật khẩu Wi-Fi, cấu hình Claude vào `BiMat.aes`; `manifest.json` đánh dấu đang làm/xong, bước nhập bỏ bản dở, hỏi trước bản `_cu_`; tham số, chạy thử, mã thoát, JSON kết quả. |
| `48f44a8` (submodule) | Khôi phục .mdf sang .sql | mdf2sql 1.1.0: lệnh `doctor`; máy chủ giao diện giữ cổng riêng (`SO_EXCLUSIVEADDRUSE`), cổng bận thì tự lùi, `--port 0`, in URL thật; `/api/health`, `/api/shutdown`, `server.json`; gợi ý cài ODBC 18 khi chỉ có driver cũ. |
| `5db1af3`, `4d636be` (submodule) | Tất cả | Bài thử giả lập vào repo: `tests\ChayTatCa.ps1`, mỗi bộ một thư mục, unittest cho mdf2sql (xem *Vấn đề chung* số 9). |
| `1ee6752` | Đăng xuất GitHub | Bản 1.1: đọc `cmdkey /list` theo phần `target=` (không phụ thuộc ngôn ngữ), xoá mọi mục GitHub của Git kể cả mục kèm tên tài khoản, mục của VS Code, GitHub Desktop hỏi trước, GitHub CLI qua `gh auth logout`; đọc lại sau khi xoá, không có gì thì nói rõ; Chạy thử, mã thoát 0/1/3. |
| `15bedfb` | Báo cáo sức khoẻ | Bản 1.1: không có sự kiện thì in [OK] thay vì [LOI]; tự nâng quyền bằng `fltmc`, đường dẫn qua biến môi trường (thư mục có dấu `'` chạy được), đợi cửa sổ Admin để trả mã thoát; bỏ lời khuyên gửi file cho ChatGPT. |
| `e198820` | Ghi âm sang Word | 2026.10.1: tên kết quả giữ đuôi file gốc (`hop.m4a - ban tho.docx`), `hop.m4a` và `hop.mp4` không ghi đè nhau; kết quả bản cũ vẫn được nhận nên không làm lại; `--ra` chọn thư mục kết quả. |
| `2bfd956`, `d0e8d92` (submodule) | Khôi phục .mdf sang .sql | mdf2sql 1.1.1: hộp thoại chọn file (Tk) chạy trong tiến trình riêng thay vì trên luồng HTTP (có thể làm sập máy chủ); `Chay_tool.bat` chạy thử Python thay cho `where python` (lối tắt Microsoft Store không còn qua được); pyodbc 5.x theo `requirements.txt`. |
| `ac49ded` | Trạm, MyExcelFix, Chuyển dữ liệu khi cài lại Windows | Trạm 1.4.0: chuẩn JSON kết quả `tramtool.ketqua/1` (`hub\lib\KetQua.ps1`), Lịch sử gắn kết quả từng lần chạy, hộp thoại *Xem chi tiết* có nút chạy tiếp; mã 2/3 có nhãn riêng; theo dõi công cụ tự nâng quyền khi mở bằng quyền thường; `webServer` trong `tool.json` để mở lại, tắt giao diện web. MyExcelFix 2026.10.3, Chuyển dữ liệu 2.1 ghi theo chuẩn. |
| `31fe2b4` (submodule) | Khôi phục .mdf sang .sql | mdf2sql 1.2.0: `doctor --ket-qua` theo chuẩn của trạm; `tool.json` khai `webServer`; máy chủ đọc hết thân yêu cầu rồi mới trả 403 (trước đó Windows cắt kết nối, bài thử chập chờn WinError 10053); `Chay_tool.bat` tự đóng khi tắt bình thường. |
| `389c4e1` | CheckWinFix | 2026.10.3: *Thu thập thông tin* ghi `KetQua_CheckWinFix_ThuThap_*.json` theo chuẩn của trạm (mỗi cảnh báo một mã cố định, một mức, gợi ý script chạy tiếp), cảnh báo nghiêm trọng lên đầu báo cáo; hai câu hỏi lấy từ form của trạm; lỗi nguồn `disk` trên ổ USB hoặc ổ đã rút chỉ là cảnh báo; *Kiểm tra sâu* (DISM ScanHealth, `Repair-Volume -Scan`) thay *Báo cáo sức khoẻ máy* (đã xoá). |
| `389c4e1` | Tối ưu Windows | Gộp *Tắt/bật dịch vụ nền* và *Tối ưu đồng hồ hệ thống* vào `tools\toi-uu` (giữ lịch sử file): Kiểm tra chung ghi JSON kèm nút sửa, menu chung có hai menu con; *Bật lại dịch vụ* chọn được từng dịch vụ; file trạng thái gốc ở chỗ cũ tự chuyển sang. |
| `6a2b7d1` | Giờ máy và chữ ký số (mới) | Công cụ mới `tools\gio-chu-ky-so`: Kiểm tra (quyền thường) đo độ lệch giờ bằng NTP, dự phòng giờ của trang http; múi giờ; Windows Time; Smart Card, Certificate Propagation; đầu đọc thẻ qua WinSCard; chứng thư ký số trong kho của tài khoản (chỉ xem có khoá riêng, không mở); phần mềm ký số. *Sửa giờ* (bật dịch vụ, đồng bộ, đặt múi giờ Việt Nam, đồng bộ xong vẫn lệch thì đặt giờ; máy trong domain không đổi cấu hình), *Sửa token*, *Trả lại* giá trị của lần sửa đầu. |
| `3220163` | Bộ ứng dụng văn phòng (mới) | Công cụ mới `tools\bo-ung-dung`: Kiểm tra (`winget export`, nhận cả ứng dụng không cài bằng winget), *Cài ứng dụng* (ô chọn từng ứng dụng, mặc định theo `DanhSach.json`, bỏ qua ứng dụng đã có, bộ gõ cùng nhóm chỉ cài một, đọc lại danh sách đã cài sau khi cài), *Cập nhật ứng dụng* (tách đã cập nhật, đã mới nhất, lỗi); bài thử kiểm danh sách khớp ô chọn và tên cờ không trùng tiền tố tham số của script. |
| `a5ef3e4` | MyExcelFix | 2026.10.2: sao lưu, báo cáo, JSON kết quả vào `%LOCALAPPDATA%\MyExcelFix` (riêng từng tài khoản, không đồng bộ OneDrive); Public Documents chỉ còn snapshot cấu hình, báo cáo cũ của tài khoản đang chạy tự chuyển sang; che tên chủ tài khoản; `ThongTinKhaiBao.txt` chỉ khi đặt lại; `HOAN_TAC.bat` không tham số liệt kê bản sao lưu. |
| `b10a66d` | Máy in mạng LAN | 1.1: Chẩn đoán ghi `KetQua_MayIn_ChanDoan_*.json` (42 mã cố định, nút sửa trỏ tới các nút sửa của công cụ). |
| `b6f4435` | BitLocker | 1.1: Kiểm tra ghi `KetQua_BitLocker_KiemTra_*.json` (16 mã; chỉ có Mã khoá, không có khoá khôi phục); chạy bằng quyền thường thì không kết luận ổn. |
| `37af08d` | Dọn ổ C an toàn | 1.1: mọi chế độ ghi `KetQua_DonOC_*.json` (mục chiếm từ 1 GB, rác dọn được, kết quả dọn, WinSxS; cùng mức thì mục lớn lên trước). |
| `d434eb4` | Sửa lỗi Windows | 2.1: mọi chế độ ghi `KetQua_SuaLoi_*.json` (44 mã: ảnh Windows hỏng sửa được, SFC còn file hỏng, ổ đĩa có lỗi, IP/DNS đặt tay...), gợi ý chạy tiếp, kèm file sao lưu tường lửa, thiết lập mạng cũ. |
| `4feccd6` | Gỡ sạch và cài Office theo mẫu | 1.1: Kiểm tra ghi 20 mã cố định; gỡ, cài, kích hoạt, trả lại chưa xong thì tóm các dòng lỗi đã in; JSON qua cùng bộ lọc che khoá như báo cáo. |
| `a82cec4` | CheckWinFix | Chẩn đoán phần cứng, Giải mã WHEA, Xuất bằng chứng, Sụp nguồn bản 1.1 ghi `KetQua_CheckWinFix_PhanCung_*.json` (và `_GiaiMaWhea_`, `_BangChung_`, `_SupNguon_`), mã in kèm trong báo cáo; Chẩn đoán phần cứng tách lỗi ổ USB, ổ đã rút; `.gitignore` bỏ qua `KetQua_CheckWinFix_*.json` (cả file của Thu thập thông tin, trước đó chưa bỏ qua). |
| `a8d1fad` | CheckWinFix | 2026.10.4: *Thu thập thông tin* thêm Secure Boot (kiểu firmware, `UEFICA2023Status`, sự kiện TPM-WMI 1795, 1796, 1801, 1808 trong 90 ngày, số ngày tới 19/10/2026), bản quyền Windows qua `SoftwareLicensingProduct` (không đọc khoá, không `slmgr`; KMS lạ, dấu vết KMSpico, KMSAuto, AAct...), WinRE từ `ReAgent.xml`, `powercfg /requests`, `/lastwake`, SleepStudy, kết quả test RAM (MemoryDiagnostics-Results). |
| `e758fbc` | Trạm, DWG sang PDF, Ghi âm sang Word | Trạm 1.5.0: tiến độ `tramtool.tiendo/1` (action khai `tienDo`), *Cập nhật công cụ* từ git (chỉ fast-forward, rồi submodule). DWG sang PDF 2026.10.1, Ghi âm sang Word 2026.10.2 báo tiến độ; Ghi âm lưu khúc đã xong để làm tiếp, card hết bộ nhớ thì thử lại khúc đó (lần ba beam 1), chuyển sang CPU cũng làm tiếp. |
| `892eca8` | Trạm, MyExcelFix | Ô chọn file, thư mục có `goiY` (nguồn, đọc JSON trong thư mục, lọc theo tài khoản, mô tả theo mẫu); `GET /api/suggest`. Form Hoàn tác của MyExcelFix liệt kê bản sao lưu của tài khoản đang mở trạm, chọn sẵn bản mới nhất. |
| `3d9ce5d` (submodule `1a7afff`) | Khôi phục .mdf sang .sql | mdf2sql 1.3.0: hai `.bat` tạo `.venv` riêng và cài pyodbc 5.3.0 vào đó (không còn `pip install --user` vào Python chung); nút *Cài hoặc sửa môi trường chạy*. |
| `5c4a53f` | CheckWinFix | Phần dùng chung `src\Chung.ps1` (kiểm tra Admin, ghi JSON, đọc và giải mã SMART) dựng vào `ThuThapThongTin.bat` và script 2 đến 5 bằng `src\build.ps1`; bài thử bắt `.bat` sửa tay lệch bản chung. |
| `4f2e279` | Gói tiếng Việt (mới) | Công cụ mới `tools\tieng-viet`: Kiểm tra bộ gõ, khởi động cùng Windows, bàn phím của Windows, font cũ, định dạng số và ngày, Excel, bảng mã; *Đặt định dạng* (`SetLocaleInfo`, cho tài khoản đang dùng), *Trả lại*; *Chuyển tài liệu sang Unicode* (`chuyen_unicode.py`, chỉ thư viện chuẩn của Python, sửa thẳng XML của `.docx`, `.xlsx`). |
| `9c3f246` | Đồng bộ phiên Claude (mới) | Công cụ mới `tools\claude-dong-bo`: *Đồng bộ* các phiên tab Code của tài khoản khác trên máy hoặc từ gói vào tài khoản đang đăng nhập (bản mới hơn thắng, bỏ kết nối của tài khoản cũ, sửa đường dẫn khi đổi máy), *Sao lưu*, *Kiểm tra*, *Hoàn tác*. |
| `adfc8ea` | Office (bài thử) | Hạn hỗ trợ Office thử bằng ngày giả: Office LTSC 2021 hết hỗ trợ 13/10/2026 làm bài thử viết cứng "sắp hết" hỏng dù công cụ đúng. |
| `94f3581` | Đồng bộ phiên Claude | Bản 1.1: tác vụ hẹn giờ, mẫu phiên, nhóm tự tạo trên thanh bên, trí nhớ dự án, Cowork (`-KemCowork`) đi kèm phiên, mục đã xoá không thêm lại; gói cập nhật dần, `-Nen`, `-MaHoa`; kiểm cấu trúc trước khi ghi (`CACH_LUU_DA_DOI`); *Mở Claude*, *Tạo lối tắt*, `-MoClaude`; Kiểm tra báo lần đồng bộ gần nhất. |
| `2b11e78` | Chuyển dữ liệu khi cài lại Windows | Bản 2.2: nhập Claude xong mà tài khoản đang đăng nhập không có phiên thì gợi ý chạy Đồng bộ phiên Claude (nút chạy tiếp). |
| `541dc24` | Máy ảo thử (`hub\dev`) | `TaoMayAoThu.ps1 -KhongMo` tạo máy ảo mà chưa bật, `-Mo` bật sau; cảnh báo khi RAM trống ít. |

## Bảng tổng quan

| Công cụ | Dành cho | Đánh giá | Việc nên làm trước |
|---|---|---|---|
| CheckWinFix | Mọi người | Bộ chẩn đoán đầy đủ nhất: 26 nhóm thông tin (cả Secure Boot 2023, bản quyền, WinRE, giấc ngủ, test RAM), khoảng 60 cảnh báo tự động có mã cố định (lỗi sự kiện so theo nguồn + mã, cả mức Warning), trạm hiện từng cảnh báo và gợi ý script chạy tiếp; tuỳ chọn kiểm tra sâu (DISM, `chkdsk /scan`); chạy đúng với mọi đường dẫn. Bốn script chuyên sâu (phần cứng, WHEA, bằng chứng, sụp nguồn) cũng ghi kết luận có mã cho trạm. *Cứu dữ liệu* bản 2.0 an toàn hơn (ổ vật lý khác, MD5 khi SQL dừng, luôn bật lại dịch vụ), mới thử bằng giả lập. | P1: đọc EventData ở các mục còn lại; gom minidump, WHEA, chọn nơi lưu vào phần dùng chung `src\Chung.ps1`. |
| Sửa lỗi Windows | Kỹ thuật | Bản 2.0: DISM rồi SFC, đặt lại mạng (ghi lại IP/DNS đặt tay trước), đặt lại tường lửa (sao lưu `.wfw`, hỏi lại, khôi phục được), quét và sửa ổ đĩa (xem sức khoẻ ổ trước), kiểm tra RAM, đặt lại Windows Update (đổi tên có thời gian); mỗi lệnh kiểm tra kết quả thật. Bản 2.1: trạm hiện kết quả từng việc có mã, gợi ý chạy tiếp. Mới thử bằng giả lập. | P1: nhật ký tóm tắt CBS/DISM; DISM dùng ISO khi Windows Update không tải được. |
| Kiểm tra và sửa lỗi Wi-Fi | Mọi người | Bản 1.1 thêm `KET_NOI_WIFI.bat`: gọi thẳng API Wi-Fi (không phụ thuộc ngôn ngữ Windows), sửa lỗi *Can't connect to this network* khi vào mạng mới sau khi máy thức dậy, chẩn đoán từ nhật ký WLAN theo mã lý do. Phần kết nối mới chạy thử, chưa chạy thật. Menu cũ `fixwf.bat` vẫn tìm card bằng chữ. | P1: tự sửa sau khi máy thức dậy; gộp menu cũ vào `KetNoiWifi.ps1`. |
| Máy in mạng LAN và thư mục chia sẻ | Mọi người | Chẩn đoán 11 nhóm, chỉ nút sửa theo mã lỗi; 8 nút sửa in việc sẽ làm, hỏi trước, có Chạy thử, ghi nhật ký hoàn tác; nới bảo mật tách riêng, hỏi 2 lần; không bật SMB1. Mới kiểm chứng trên máy phát triển. | P1: chạy các nút sửa ở văn phòng thật; Local Port `\\MÁY\máy-in` thay cho nới RPC; dò máy in trong mạng. |
| Tối ưu Windows | Kỹ thuật | Gộp *Tắt/bật dịch vụ nền* và *Tối ưu đồng hồ hệ thống* (bản 2.0 của cả hai giữ nguyên). Một nút Kiểm tra xem cả dịch vụ lẫn đồng hồ, trạm hiện phát hiện kèm nút sửa. Dịch vụ: xét kiểu khởi động thật, lưu kiểu khởi động gốc trước khi tắt, *Bật lại* trả đúng giá trị cũ (kể cả Tự động trễ); Tối ưu ổ đĩa (TRIM cho SSD) và wisvc trên máy Insider phải đồng ý riêng. Đồng hồ: đổi thẳng trong BCD, đọc lại sau khi đổi, *Trả về mặc định* xoá sạch cả ba thiết lập, tạm dừng BitLocker 1 lần khởi động khi cần. Phần đổi máy mới thử bằng giả lập. | P1: kiểm tra TRIM thật thay vì chỉ cảnh báo; đo trước/sau (LatencyMon) rồi mới khuyên tối ưu đồng hồ. |
| Gỡ sạch và cài Office theo mẫu | Kỹ thuật | Kiểm tra Office, giấy phép, bộ cài mẫu (ODT) trước; gỡ mọi bản Office rồi cài theo mẫu, mẫu hỏng thì không gỡ gì; sao lưu mẫu Word, macro, chữ ký; khoá trong mẫu không bao giờ in ra, kích hoạt chỉ theo cách của Microsoft. Kiểm tra và Chạy thử đã chạy thật; gỡ, cài, kích hoạt mới thử bằng giả lập. | P1: gỡ, cài thật trên một máy thử; tạo mẫu mới (LTSC 2024, Microsoft 365) ngay trong công cụ; Quick Repair trước khi phải gỡ. |
| Dọn ổ C an toàn | Mọi người | Xem ổ C đầy vì đâu (rác dọn được và thứ chiếm chỗ bạn tự quyết: thùng rác, Windows.old, file ngủ đông, Zalo, Downloads); dọn file tạm cũ hơn N ngày, bộ nhớ đệm trình duyệt khi đã tắt, file tải về của Windows Update, Delivery Optimization, WinSxS. Xem trước, gõ C mới xoá; danh sách thư mục được phép. Xem và Chạy thử đã chạy thật; phần xoá mới thử trong thư mục cát. | P1: dọn thật trên một máy; dọn Teams, bộ cài cập nhật Zalo; liệt kê thư mục lớn nhất. |
| File thẻ xe .nt | Mọi người | Chuyển danh sách Excel sang .nt, kiểm tra file .nt như phần mềm giữ xe đọc và so từng thẻ với danh sách Excel, chuyển .nt sang Excel kèm kết quả từng thẻ, sửa CardID mất số 0; bản sửa lô 3257-3426 khớp từng thẻ với bản sửa tay. Không cần Excel. | P1: nạp thử file do công cụ ghi vào phần mềm thật; so với danh sách thẻ đang có trong phần mềm trước khi nạp. |
| MyExcelFix | Mọi người | Chẩn đoán kỹ theo từng tài khoản Windows, có sao lưu và hoàn tác an toàn (giữ bản đã sửa tiếp), mã thoát và JSON kết quả có mã phát hiện cố định; sao lưu, báo cáo nằm trong thư mục riêng của tài khoản, bản gửi đi đã che số và tên; mã nguồn chia module và build ra một file `.bat`. Trạm hiện từng phát hiện, gợi ý chạy *Sửa lỗi* khi bản Sửa xử lý được; form Hoàn tác liệt kê bản sao lưu của tài khoản. | P1: `common\` dùng chung cho hai bản build. |
| DWG sang PDF | Mọi người | Không cần AutoCAD; mỗi khung bản vẽ một trang; giải mã chữ VNI và TCVN3. Bản vẽ lớn chậm (5-35 phút); trạm hiện phần trăm, tờ đang vẽ. | P1: bộ bản vẽ mẫu để kiểm tra khi nâng thư viện. |
| Ghi âm sang Word | Mọi người | Chạy offline trên card NVIDIA, nhanh khoảng 5 lần thời gian thực, đánh dấu chỗ máy nghe kém chắc chắn; tên kết quả giữ đuôi file gốc, chọn được thư mục kết quả; trạm hiện phần trăm, thời gian còn lại; bị ngắt thì làm tiếp từ khúc đã xong, card hết bộ nhớ thì thử lại khúc đó. | P1: mã thoát riêng cho lỗi card; chỉ chạy lại bằng CPU các file chưa xong. |
| Khôi phục .mdf sang .sql | Kỹ thuật | Khôi phục được file tắt đột ngột hoặc thiếu `.ldf`, xuất cho cả SQL Server và MySQL; luôn làm trên bản sao. Có `doctor` kiểm tra môi trường; giao diện giữ cổng riêng, tự lùi khi cổng bận; hộp thoại chọn file chạy trong tiến trình riêng; Trạm mở lại, tắt giao diện đang chạy và hiện kết quả `doctor`; pyodbc ghim bản trong `.venv` riêng. | P1: dọn database tạm, thư mục làm việc bị bỏ lại. |
| Chuyển dữ liệu khi cài lại Windows | Kỹ thuật | Bản 2.2: sao lưu Wi-Fi kèm mật khẩu, máy in kèm driver, dữ liệu Claude, khoá BitLocker, driver mạng ra nơi chọn (USB trước), tuỳ chọn mã hoá phần bí mật; manifest đánh dấu đã xong, bước nhập không dùng bản dở; có Chạy thử; nhập Claude xong gợi ý Đồng bộ phiên Claude khi đổi tài khoản. Mới thử bằng giả lập. | P1: kiểm đếm file và SHA-256; hỏi bật tự mở khoá ổ BitLocker sau khi mở. |
| BitLocker và khoá khôi phục | Mọi người | Kiểm tra từng ổ (mã hoá, tạm dừng, bị khoá), khoá khôi phục đã lưu ở đâu, TPM, các lần máy phải nhập khoá; kết luận theo thứ tự nên làm. 6 nút đổi máy có Chạy thử, nhật ký hoàn tác; khoá 48 số không bao giờ vào báo cáo, nhật ký. Chưa chạy trên ổ mã hoá thật, mới thử bằng giả lập. | P1: chạy thật trên máy có BitLocker; sao lưu khoá lên tài khoản Microsoft; lưu gói khoá `.KPG`. |
| Giờ máy và chữ ký số (USB token) | Mọi người | Kiểm tra chỉ đọc bằng quyền thường: độ lệch giờ (NTP, dự phòng http), múi giờ, dịch vụ giờ, dịch vụ Smart Card, đầu đọc token, chứng thư ký số, phần mềm ký số; trạm hiện từng phát hiện kèm nút sửa. Sửa giờ, sửa dịch vụ token lưu giá trị cũ để trả lại. Không hỏi PIN. Chưa thử với token thật; token chỉ dùng PKCS#11 thì không thấy. | P1: đọc chứng thư trong token (`certutil -scinfo`) khi kho của tài khoản chưa có; kiểm tra tiện ích ký số của trình duyệt. |
| Bộ ứng dụng văn phòng (winget) | Mọi người | Cài một lượt ứng dụng hay dùng từ nguồn winget, bỏ qua ứng dụng đã có, đọc lại danh sách đã cài để chắc cài xong; Kiểm tra xem ứng dụng nào đã có, Cập nhật cả bộ. Danh sách sửa được. Mới chạy thật Kiểm tra và chạy thử; cài, cập nhật thử bằng giả lập. | P1: báo ứng dụng có bản mới ngay trong Kiểm tra; cài thật trên một máy mới. |
| Gói tiếng Việt | Mọi người | Kiểm tra chỉ đọc bằng quyền thường: bộ gõ (hai bộ cùng chạy, chạy hai bản, khởi động trùng, bàn phím tiếng Việt của Windows bật cùng), font VNI, TCVN3, định dạng số và ngày, Excel dùng dấu riêng, chế độ UTF-8 (Beta); trạm hiện từng phát hiện kèm nút sửa. *Đặt định dạng* cho tài khoản, không cần Admin, lưu giá trị cũ để trả lại. *Chuyển tài liệu sang Unicode* tạo bản sao `.docx`, `.xlsx`, giải mã theo font của từng đoạn chữ. Chưa đổi định dạng thật của máy nào. | P1: chuyển cả `.doc`, `.xls` cũ qua Word, Excel; đổi chữ trong hình, biểu đồ, SmartArt; đổi định dạng thật trên máy ảo. |
| Đồng bộ phiên Claude | Kỹ thuật | Đổi tài khoản Claude Desktop là thanh bên tab Code trống dù nội dung còn trên máy. *Đồng bộ* đưa các phiên của tài khoản khác trên máy hoặc từ gói sao lưu vào tài khoản đang đăng nhập (bản mới hơn thắng, không thêm lại phiên đã xoá, bỏ kết nối của tài khoản cũ, sửa đường dẫn khi đổi máy), có nhật ký *Hoàn tác*; phải tắt Claude Desktop trong lúc ghi. Bản 1.1 kèm tác vụ hẹn giờ, mẫu phiên, nhóm thanh bên, trí nhớ dự án, Cowork (tuỳ chọn); gói cập nhật dần, nén hoặc mã hoá; lối tắt *Mở Claude*; dừng khi cách lưu của Claude khác cách công cụ biết. Dựa trên cách lưu quan sát được, chưa có tài liệu; chưa đồng bộ thật sang tài khoản thứ hai. | P1: đồng bộ thật một lần với tài khoản thứ hai; đồng bộ nhóm tự tạo kèm phiên trong nhóm khi biết nơi Claude lưu. |
| Đăng xuất GitHub | Kỹ thuật | Bản 1.1: xoá mọi mục GitHub của Git trong Credential Manager (cả mục kèm tên tài khoản), hỏi trước với mục của ứng dụng khác và GitHub CLI, có Chạy thử. | P2: chọn tài khoản cần xoá thay vì xoá hết. |

## Vấn đề chung

Các lỗi lặp lại ở nhiều công cụ, nên sửa một lần bằng quy ước chung thay vì vá từng nơi.

1. **Kiểm tra quyền Admin sai cách hoặc không kiểm tra.** CheckWinFix, Wi-Fi dùng `net session` (cần dịch vụ Server,
   bị tắt là báo nhầm hoặc tự mở lại không dừng; nay đã đổi sang `fltmc`, cả Báo cáo sức khoẻ 1.1; Chuyển dữ liệu khi
   cài lại Windows 2.0 kiểm tra trong PowerShell). Sửa lỗi Windows, Tắt/bật dịch vụ, Tối ưu đồng hồ không kiểm tra gì (đã sửa ở bản 2.0 của cả ba).
   Quy ước: `fltmc >nul 2>&1` để kiểm tra, tự nâng quyền đúng một lần, không được thì báo rõ và thoát.
2. **Báo thành công giả.** Lỗi bị giấu bằng `>nul 2>&1` rồi in *thành công*; mã thoát luôn 0. Quy ước: kiểm tra
   `errorlevel` (hoặc `$LASTEXITCODE`) sau mỗi lệnh thay đổi máy; mã thoát `0` xong, `1` lỗi, `2` thiếu điều kiện,
   `3` thành công một phần.
3. **Bí mật và dữ liệu khách nằm cạnh script.** Bản sao lưu cài lại máy có mật khẩu Wi-Fi, token và hội thoại Claude;
   sao lưu MyExcelFix trên Desktop (thường đồng bộ OneDrive) có số tài khoản ngân hàng; báo cáo có tên máy khách.
   Quy ước: dữ liệu khách để trong `ket_qua\` hoặc `du-lieu\` (git bỏ qua), cho chọn nơi lưu, có tuỳ chọn nén mật khẩu
   (đã làm ở Chuyển dữ liệu khi cài lại Windows 2.0: chọn nơi lưu, mã hoá `BiMat.aes`). Dữ liệu của một tài khoản
   Windows để trong `%LOCALAPPDATA%\<công cụ>`, không để Desktop hay Public Documents; bản để gửi đi thì che số, tên
   (đã làm ở MyExcelFix 2026.10.2).
4. **Trùng lặp.** Đã gộp: Báo cáo sức khoẻ vào CheckWinFix (*Kiểm tra sâu*), Tắt/bật dịch vụ và Tối ưu đồng hồ thành
   *Tối ưu Windows*. Còn: Sửa lỗi Windows là bước *Sửa* sau khi CheckWinFix chẩn đoán ra bệnh; nay cảnh báo của
   CheckWinFix đã gợi ý thẳng nút của Sửa lỗi Windows (`chayTiep`).
5. **Phụ thuộc ngôn ngữ Windows.** Đọc chữ trong thông điệp sự kiện, output `netsh` tiếng Anh. Windows tiếng Việt hoặc
   card mạng đã đổi tên là hụt. Quy ước: đọc trường `EventData`, dùng cmdlet (`Get-NetAdapter`) thay vì tách chữ.
6. **Mã hoá file.** `.ps1` cần UTF-8 có BOM, `.bat` cần không BOM, cả hai CRLF. Đã có `.editorconfig`, `.gitattributes`
   và `hub\dev\Normalize-Encoding.ps1` để giữ đúng.
7. **Môi trường Python tự phát.** Mỗi công cụ một kiểu cài. Quy ước (đã áp dụng cho DWG sang PDF, Ghi âm sang Word, Khôi phục .mdf 1.3.0):
   `.venv` riêng, `requirements-lock.txt` khoá phiên bản, `CAI_DAT.ps1` tự cài lại được trên máy mới. Công cụ chỉ dùng
   thư viện chuẩn (Gói tiếng Việt) thì chạy bằng Python của máy, không cần `.venv`.
8. **Kết quả chỉ là chữ.** Trạm không biết công cụ chạy xong hay lỗi, tìm thấy gì. Quy ước: mỗi lần chạy ghi thêm
   một file JSON theo chuẩn `tramtool.ketqua/1` (máy, thời gian, mã thoát, trạng thái, phát hiện, mức độ, cách sửa,
   công cụ chạy tiếp, file liên quan; xem `docs\THEM-CONG-CU.md`). Đã làm cho mọi công cụ chẩn đoán, sửa: MyExcelFix,
   Chuyển dữ liệu khi cài lại Windows, `mdf2sql doctor`, CheckWinFix (Thu thập thông tin và bốn script chuyên sâu), Tối
   ưu Windows, Giờ máy và chữ ký số, Bộ ứng dụng văn phòng, Sửa lỗi Windows, Máy in LAN, BitLocker, Dọn ổ C, Office, Gói tiếng Việt,
   Đồng bộ phiên Claude;
   Trạm 1.4.0 đọc và hiện trong Lịch sử. Chưa ghi: Wi-Fi, DWG sang PDF, Ghi âm sang Word, File thẻ xe .nt, Đăng xuất
   GitHub (kết quả là file đầu ra hoặc thao tác một lần, mã thoát đã đủ cho Lịch sử).
9. **Bài thử không nằm trong repo.** Các nút đổi máy chủ yếu được thử bằng giả lập, nhưng bài thử chỉ nằm ở thư mục
   tạm của phiên làm việc nên sửa sau không chạy lại được. Đã làm: `tests\` với một trình chạy chung
   (`tests\ChayTatCa.ps1`, `tests\CHAY_KIEM_THU.bat`), 58 bài cho 20 bộ (cú pháp, mã hoá file, danh mục và lược đồ
   `tool.json`, không commit dữ liệu khách, lan can và kết quả JSON của trạm, new-windows, MyExcelFix, Office, BitLocker, Dọn ổ C,
   Tối ưu Windows, Giờ máy và chữ ký số, Bộ ứng dụng văn phòng, sửa lỗi Windows, CheckWinFix, máy in LAN, thẻ xe,
   Đăng xuất GitHub, Ghi âm sang Word, DWG sang PDF, Gói tiếng Việt, Đồng bộ phiên Claude, `.bat` của mdf2sql) và
   `tools\mdf2sql\tests` (unittest).
   Chạy bằng quyền thường, thư mục tạm ngoài repo, registry chỉ trong `HKCU\Software\TramToolTest`. Quy ước: chạy
   trước mỗi lần commit; thêm, sửa công cụ thì thêm bài thử. Giả lập không thay được chạy thật trên máy thử.

## Lộ trình

### Giai đoạn 1: an toàn (P0)

- [x] Quy ước Admin + mã thoát (mục 1, 2 ở trên) cho Sửa lỗi Windows, Tắt/bật dịch vụ, Wi-Fi, CheckWinFix.
- [x] Tối ưu đồng hồ: viết lại bằng `bcdedit /set {current} disabledynamictick yes` và
      `bcdedit /deletevalue {current} useplatformclock`, đọc trạng thái thật bằng `bcdedit /enum {current}` (bản 2.0).
- [x] CheckWinFix *Cứu dữ liệu*: đối chiếu MD5 khi SQL còn dừng, so ổ vật lý nguồn/đích, dò mọi instance `MSSQL*`,
      luôn bật lại SQL Server kể cả khi lỗi giữa chừng.
- [x] CheckWinFix cảnh báo: so theo nguồn sự kiện + mã, thêm disk 154, WHEA 1/18 và mức Warning.
- [x] Sửa lỗi Windows: tách đặt lại tường lửa và hỏi lại; bỏ *Registry Cleanup* (bản 2.0).
- [x] Tắt/bật dịch vụ: xét kiểu khởi động, lưu trạng thái gốc ra file để *bật lại* trả đúng giá trị cũ (bản 2.0).
- [x] MyExcelFix: dừng có thông báo khi hết đầu vào; hoàn tác giữ bản hiện tại nếu file đã đổi sau khi sửa; mã thoát
      (bản 2026.10.1, kèm JSON kết quả).
- [x] Chuyển dữ liệu khi cài lại Windows: chọn nơi lưu, `manifest.json` đánh dấu đang làm/xong, `-DryRun`, mã thoát
      (bản 2.0, kèm tuỳ chọn mã hoá `BiMat.aes` và JSON kết quả).
- [x] Khôi phục .mdf: `mdf2sql doctor`; tự lùi sang cổng trống, không dùng chung cổng (mdf2sql 1.1.0, kèm
      `/api/health`, `/api/shutdown`).

### Giai đoạn 2: chuẩn hoá (P1)

- [x] Chuẩn JSON kết quả chung; Trạm đọc để hiện *tìm thấy gì* và gợi ý công cụ chạy tiếp (Trạm 1.4.0; MyExcelFix,
      Chuyển dữ liệu khi cài lại Windows, `mdf2sql doctor` đã ghi theo chuẩn).
- [x] JSON kết quả theo chuẩn cho *Thu thập thông tin* của CheckWinFix (2026.10.3) và Kiểm tra của Tối ưu Windows.
- [x] JSON kết quả theo chuẩn cho Sửa lỗi Windows (2.1), Máy in LAN (1.1), BitLocker (1.1), Dọn ổ C (1.1), Office
      (1.1), các script chuyên sâu của CheckWinFix (1.1).
- [x] Trạm đợi tiến trình xong trong nền, ghi mã thoát và thời gian chạy vào Lịch sử (Trạm 1.1.0). Công cụ tự nâng
      quyền: cửa sổ đầu đợi cửa sổ Admin và trả mã của nó (bài thử tĩnh kiểm), trạm theo dõi cả khi mở bằng quyền
      thường (Trạm 1.4.0).
- [x] Lõi PowerShell dùng chung cho CheckWinFix: `src\Chung.ps1` (kiểm tra Admin, ghi JSON, đọc và giải mã SMART),
      `src\build.ps1` dựng vào từng `.bat` nên vẫn gửi khách được một file (commit `5c4a53f`).
- [ ] Gom thêm vào phần dùng chung của CheckWinFix: minidump, WHEA, chọn nơi lưu.
- [x] Gộp: Báo cáo sức khoẻ thành *Kiểm tra sâu* của CheckWinFix (2026.10.3); Tắt/bật dịch vụ + Tối ưu đồng hồ thành
      *Tối ưu Windows* có một nút Kiểm tra chung (1.0).
- [x] Khôi phục .mdf: `.venv` riêng có pyodbc ghim bản 5.3.0 (mdf2sql 1.3.0).
- [ ] Khôi phục .mdf: dọn database tạm, thư mục làm việc bị bỏ lại.
- [x] Khôi phục .mdf: hộp thoại chọn file trong tiến trình riêng; `Chay_tool.bat` chạy thử Python thật (mdf2sql 1.1.1).
- [x] Khôi phục .mdf: trạm đọc `server.json` để mở lại, tắt giao diện; `doctor --ket-qua` (mdf2sql 1.2.0, Trạm 1.4.0).
- [x] Ghi âm sang Word: tên kết quả giữ đuôi file gốc, `--ra` (2026.10.1).
- [x] Ghi âm sang Word: lưu tiến độ từng khúc; hết bộ nhớ card thì thử lại khúc đó với beam nhỏ (2026.10.2).
- [x] MyExcelFix: sao lưu, báo cáo theo tài khoản (`%LOCALAPPDATA%`) thay vì Desktop, Public Documents; che tên chủ
      tài khoản; `HOAN_TAC.bat` liệt kê bản sao lưu (2026.10.2).
- [x] MyExcelFix: Trạm hiện phát hiện từ `KetQua_MyExcel_*.json`, gợi ý *Sửa lỗi* (2026.10.3, Trạm 1.4.0).
- [x] MyExcelFix: Trạm liệt kê bản sao lưu trong form Hoàn tác (`goiY`, commit `892eca8`).
- [x] Đăng xuất GitHub: lọc `cmdkey /list` theo `github` (bản 1.1).
- [x] Báo cáo sức khoẻ: không có sự kiện thì [OK]; nâng quyền bằng `fltmc`, đường dẫn qua biến môi trường (bản 1.1).
- [x] DWG sang PDF: giải mã TCVN3 (`.VnTime`, `.VnArial`...) giống cách đã làm với VNI.
- [ ] DWG sang PDF: bộ bản vẽ mẫu + so ảnh từng trang khi nâng ezdxf, PyMuPDF, LibreDWG.

### Giai đoạn 3: mở rộng (P2)

- [x] Tiến độ phần trăm cho DWG sang PDF và Ghi âm sang Word, Trạm hiện thanh tiến độ (file `tramtool.tiendo/1`,
      Trạm 1.5.0).
- [ ] DWG sang PDF: chọn khổ giấy, bảng nét in `.ctb`, in màu trên form chạy.
- [ ] Chuyển dữ liệu khi cài lại Windows: thêm `winget export`, thư mục người dùng (xem trước dung lượng), dấu trang, font.
- [ ] Sửa lỗi Windows thành bước *Sửa* trong CheckWinFix, chỉ đề xuất lệnh hợp với bệnh tìm thấy.
- [x] Trạm: nút *Cập nhật công cụ* (chỉ fast-forward, Trạm 1.5.0).
- [ ] Trạm: xuất/nhập cài đặt.
- [x] Công cụ mới: Giờ máy và chữ ký số (1.0), Bộ ứng dụng văn phòng bằng winget (1.0), mục 6, 8 của *Công cụ Windows
      nên thêm*.
- [x] Công cụ mới: Gói tiếng Việt (1.0), mục 4 của *Công cụ Windows nên thêm*.
- [x] Công cụ mới: Đồng bộ phiên Claude giữa các tài khoản (1.0; 1.1 thêm tác vụ hẹn giờ, mẫu phiên, nhóm thanh bên,
      trí nhớ dự án, Cowork, gói nén/mã hoá cập nhật dần, lối tắt *Mở Claude*). Còn: đồng bộ thật sang tài khoản thứ hai.
- [ ] Máy ảo Windows 11 (VirtualBox, ổ D) để chạy thật các nút sửa trước khi đưa cho khách: `hub\dev\TaoMayAoThu.ps1`
      tạo máy ảo (EFI, TPM 2.0, Secure Boot, NAT, repo chia sẻ chỉ đọc, cài tự động), chụp nhanh và trả về bản sạch;
      đã cài VirtualBox, đã tạo máy ảo `TramTool-Win11` nhưng chưa bật (`-KhongMo`, máy thiếu RAM); còn bật bằng `-Mo`,
      cài xong thì `-ChupNhanh`.

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

**Bản 1.3.0 (09/10/2026): giao diện mới, cài một lần bằng `CAI_DAT.bat`**

- **Giao diện** làm lại, bỏ Fluent UI (308 KB). *Tổng quan*: dòng thông tin máy (tên, Windows, ổ C còn trống, thời gian
  đã bật), ô tìm, *Cần chú ý* có vạch màu theo mức, *Đã ghim* và *Dùng gần đây* hai cột, rồi danh mục dạng mục lục:
  bấm cả dòng để mở công cụ, nút *Chạy* và ghim hiện rõ khi rê chuột. Trang công cụ: một nút chính, dòng sẵn sàng, các
  việc trong một khung kẻ dòng; công cụ chỉ có một việc thì không lặp nút *Chạy*. *Máy này* chia nhóm Máy, Ổ đĩa (thanh
  dung lượng), An toàn và cài đặt. *Lịch sử*, *Kết quả gần đây*: cột giờ, lọc dạng tab. Hộp thoại dùng `<dialog>` gốc:
  *Huỷ* bên trái, nút chính bên phải, mở ra thì con trỏ ở ô nhập đầu tiên, không có ô nhập thì ở *Huỷ*.
- Chữ trong `tool.json` bỏ gạch dài: hướng nâng cấp viết `P1: ...` (schema đổi theo), khoảng thời gian `1-2 phút`.
- **`CAI_DAT.bat`** (`hub\CaiDat.ps1`) cho máy mới: dùng đúng các kiểm tra của mục *Yêu cầu để chạy*, gom phần còn
  thiếu theo cách cài (hai yêu cầu cùng một script chỉ chạy một lần), in cách cài, thời gian, quyền Admin, mục tải vài GB;
  cài gói winget, script cài của công cụ, script của trạm (cửa sổ Admin riêng); kiểm tra lại, tạo lối tắt, mở trạm. Bỏ
  dấu tải từ Internet của file trong thư mục trạm (trừ `.venv`, mô hình, kết quả), lấy `tools\mdf2sql` khi trống (git
  nếu có, không thì .zip của repo công khai). winget hỏng thì hỏi chạy *Sửa winget* trước. `-ChayThu`, `-TatCa`,
  `-KhongMo`, `-KhongLoiTat`. Chọn `.bat` thay vì `.exe`: `.exe` đóng gói từ PowerShell không có chữ ký số hay bị diệt
  virus, SmartScreen chặn.
- Đã thử: ảnh chụp mọi trang ở sáng, tối, màn hình hẹp; form chạy báo lỗi đúng ô mà không chạy; bộ cài chạy thử trên
  máy phát triển (đủ hết), với công cụ giả (gom yêu cầu, mục cài tay, mục không bắt buộc; cài thật tạo đúng file), thư
  mục `mdf2sql` trống và file có dấu tải từ Internet bằng giả lập. Chưa chạy bộ cài trên máy mới thật.

Hướng thiết kế (Trạm 1.3.0): bỏ bộ thành phần Fluent UI vì để mặc định trông như mọi ứng dụng mẫu của Microsoft (thẻ
trắng giống hệt nhau, nút xanh khắp nơi). Nay là phần tử HTML gốc với hệ biến màu riêng: nền xám lạnh, một màu nhấn
xanh dầu, chữ Be Vietnam Pro (dựng riêng cho tiếng Việt) và JetBrains Mono cho tên file, giờ, số; biểu tượng Phosphor.
Danh mục là bảng mục lục (tên nhóm bên trái, dòng công cụ có đường kẻ mảnh) thay cho lưới thẻ; mỗi vùng một nút chính.
Áp dụng các quy tắc của [taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT) hợp với ứng dụng công cụ: đủ
trạng thái đang tải, trống, lỗi; một hệ bo góc; chữ số thẳng cột; không gạch dài trong chữ giao diện. Tham khảo cách làm của
PowerToys Command Palette, Raycast, Linear (ô Ctrl+K), UniGetUI (bảng tác vụ đang chạy, lịch sử), GitHub Desktop
(trạng thái trống có việc tiếp theo), hướng dẫn UAC và InfoBar của Microsoft.

**Bản 1.4.0 (09/10/2026): kết quả máy đọc được**

- **Chuẩn JSON kết quả** `tramtool.ketqua/1` (`docs\THEM-CONG-CU.md`): công cụ khai file kết quả trong `outputs`
  (`"ketQua": true`). Khi cửa sổ đóng, trạm tìm file của đúng công cụ, sửa trong lúc chạy, đọc (tên trường không phân
  biệt hoa thường, nhận cả cách ghi cũ) và gắn tóm tắt vào Lịch sử. Dòng Lịch sử, thông báo khi xong và *Cần chú ý* ở
  *Tổng quan* hiện câu tóm tắt; *Xem chi tiết* mở hộp thoại: trạng thái, số lỗi, cần xem, thông tin, từng phát hiện
  kèm mã và cách sửa, nút chạy tiếp (`chayTiep`, vẫn qua form và hộp xác nhận như chạy thường), file liên quan (chỉ
  mở thư mục trong Explorer, không chạy file). *Kết quả gần đây* có nút *Xem* cho file kết quả.
- **Mã thoát**: 2 hiện *Chưa làm*, 3 hiện *Làm được một phần* thay cho *Báo lỗi*, cả với bản ghi cũ; tab *Có lỗi* đổi
  thành *Cần xem* (lỗi, làm một phần, chưa làm, kết quả có lỗi). *Cần chú ý* chỉ xét lần chạy mới nhất của mỗi công cụ.
- **Công cụ tự nâng quyền**: cả 7 action `selfElevates` (CheckWinFix, Báo cáo sức khoẻ) đều khai `admin: true`,
  nên trạm vốn mở bằng quyền Admin và theo dõi được; phần thiếu nhỏ hơn đánh giá ban đầu. Nay: bài thử tĩnh kiểm cửa sổ
  đầu đợi cửa sổ Admin và trả mã của nó; trạm giữ handle ngay khi mở; action `selfElevates` không khai `admin` vẫn
  được theo dõi (trừ công cụ chưa có `tool.json`).
- **Giao diện web cục bộ** (`webServer`): trạm đọc file trạng thái (`%LOCALAPPDATA%\mdf2sql\server.json`), chỉ
  tin khi `/api/health` trả đúng ứng dụng và tiến trình. Bấm *Chạy* khi giao diện đang chạy thì mở lại trang cũ; trang
  công cụ hiện *Đang chạy ở cổng N từ HH:MM* với *Mở lại*, *Tắt* (đang chuyển đổi thì mdf2sql từ chối, trạm báo lại).
  Địa chỉ kèm mã không gửi lên trình duyệt của trạm.
- Đã thử: 56 mục trong `tram/5_KetQua` (gồm máy chủ web giả), toàn bộ 35 bài; trạm thử với công cụ giả (Lịch sử,
  hộp thoại ở sáng, tối, màn hình hẹp, nút chạy tiếp), tắt máy chủ giả và máy chủ mdf2sql thật (`LOCALAPPDATA` tạm,
  `--no-browser`). Lần thử đó tìm ra lỗi: trạm gửi thân `{}` kèm lệnh tắt, máy chủ tắt ngay nên Windows cắt kết nối
  giữa lúc trạm đang ghi (trạm báo lỗi dù đã tắt); nay gửi POST rỗng, bài thử kiểm độ dài thân bằng 0.

**Bản 1.5.0 (10/10/2026): tiến độ, cập nhật công cụ, gợi ý cho ô chọn**

- **Tiến độ** `tramtool.tiendo/1`: action khai `"tienDo": {"flag": "--tien-do"}` thì trạm thêm đường dẫn file tiến
  độ (`hub\data\tien-do\<guid>.json`), công cụ ghi đè file đó; thanh *Đang chạy* hiện phần trăm, bước đang làm, thời
  gian còn lại. File xoá khi cửa sổ đóng, file sót quá 2 ngày dọn lúc mở trạm; cờ tiến độ không vào Lịch sử. Đang
  dùng: DWG sang PDF, Ghi âm sang Word, Chuyển tài liệu sang Unicode.
- **Cập nhật công cụ** (*Cài đặt > Công cụ*): xem kho git có commit mới, file đang sửa; nút *Cập nhật* chạy
  `hub\fixes\CapNhat-TramTool.ps1` trong cửa sổ riêng: chỉ fast-forward rồi cập nhật submodule; dừng khi có file đang
  sửa, nhánh lệch, không ở nhánh nào; file không theo dõi giữ nguyên. Xong thì đọc lại danh mục, báo khi phần máy chủ
  đổi (cần mở lại trạm) hoặc công cụ đổi thư viện.
- **Gợi ý cho ô chọn** (`goiY` trong `tool.json`): ô file, thư mục hiện danh sách chọn từ các nguồn khai báo (nhận
  `%BIEN%`, `{Desktop}`), đọc file JSON trong từng thư mục để lọc (vd theo tài khoản) và viết dòng mô tả; chưa có giá
  trị thì chọn sẵn mục mới nhất. Máy chủ chỉ trả đường dẫn, tên, nhãn, mô tả. Dùng cho form Hoàn tác của MyExcelFix.
- Đã thử: `tram/6_TienDoCapNhat` (kho git giả: mới nhất, có bản mới, file đang sửa, nhánh lệch, submodule),
  `tram/7_GoiY`; trạm thử với form Hoàn tác của MyExcelFix (bản sao lưu giả).

**Hướng tiếp**: xuất/nhập cài đặt; loại probe `script` chỉ đọc (BitLocker, SMB); thư viện nhật ký hoàn tác chung.

## Công cụ Windows nên thêm

Nghiên cứu ngày 04/10/2026, chủ yếu từ tài liệu của Microsoft và trang chính thức của từng phần mềm. Đã làm mục 1
(`tools\may-in-lan`), mục 2 (`tools\bitlocker`), mục 3 (`tools\don-o-c`), phần gỡ, cài của mục 5
(`tools\office`), mục 4 (`tools\tieng-viet`), mục 6 (`tools\gio-chu-ky-so`) và mục 8 (`tools\bo-ung-dung`); các mục khác chọn mục nào thì làm
mục đó. Không lặp lại những thứ đã có hoặc đã nằm trong lộ trình
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
   - **Đã làm** (`tools\tieng-viet` 1.0, commit `4f2e279`, tên *Gói tiếng Việt*):
     - Bộ gõ: không dùng lại phần dò của MyExcelFix (chỉ dò tên tiến trình). Đọc thêm khởi động cùng Windows (khoá
       Run, thư mục Startup, Task Scheduler; bỏ mục đã tắt trong Task Manager), quyền chạy của bộ gõ, bàn phím tiếng
       Việt của Windows (`0000042A`, bộ gõ Telex của Windows 11).
     - Định dạng: đổi qua `SetLocaleInfo` như Control Panel, rồi báo `WM_SETTINGCHANGE`. Excel dùng dấu riêng thì bật
       lại *Use system separators*, chỉ khi Excel đang tắt.
     - Chuyển tài liệu: giải mã theo font của từng đoạn chữ (đúng thứ tự Word tìm font, Excel theo font của ô) thay vì
       đoán theo nội dung. Chưa đổi biểu đồ, hình vẽ, SmartArt.
     - Đã chạy thật Kiểm tra. Chưa đổi định dạng thật.
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
   - **Đã làm** (`tools\gio-chu-ky-so` 1.0, commit `6a2b7d1`, tên *Giờ máy và chữ ký số*): đo lệch giờ bằng gói NTP
     tự gửi (time.windows.com, time.google.com, pool.ntp.org) thay vì tách chữ của `w32tm /stripchart`, mạng chặn cổng
     123 thì đọc giờ của trang http; đầu đọc thẻ qua WinSCard thay cho `certutil -scinfo` (lệnh này có thể hỏi PIN);
     thêm Certificate Propagation, driver token lỗi, chứng thư chưa tới ngày hiệu lực (giờ chậm), thiếu chứng thư gốc.
     Sửa giờ lưu cấu hình cũ (dịch vụ, kiểu đồng bộ, máy chủ giờ, múi giờ) để *Trả lại*; máy trong domain chỉ đồng bộ
     lại, không đổi cấu hình. Đã chạy thật Kiểm tra và chạy thử trên máy phát triển (không có token); chưa thử token
     thật.
7. **Hỗ trợ từ xa.** Chỉ cần Admin khi cài. Quick Assist có sẵn trong Windows (người hỗ trợ cần tài khoản Microsoft,
   người được hỗ trợ phải tự bấm UAC); thêm UltraViewer (`DucFabulous.UltraViewer`) và RustDesk (AGPL-3.0, dùng lâu dài
   thì tự dựng máy chủ). Hiện cảnh báo lừa đảo của Microsoft trước khi mở.
   Nguồn: [Quick Assist](https://learn.microsoft.com/en-us/windows/client-management/client-tools/quick-assist).
8. **Bộ ứng dụng chuẩn bằng winget.** Danh sách JSON: Zalo (`VNGCorp.Zalo`), UniKey (`UniKey.UniKey`) hoặc EVKey
   (`lamquangminh.EVKey`), 7-Zip, Foxit Reader, UltraViewer, Cốc Cốc (bản trên winget dừng ở v120, ứng dụng tự cập
   nhật). Cài bằng `winget install --id X -e --silent --accept-package-agreements --accept-source-agreements`, giữ mới
   bằng `upgrade` và `pin`. Giao diện tuỳ chọn: [UniGetUI](https://github.com/Devolutions/UniGetUI) (MIT; các trang
   wingetui, unigetui đuôi .com là trang giả).
   - **Đã làm** (`tools\bo-ung-dung` 1.0, commit `3220163`, tên *Bộ ứng dụng văn phòng*): `DanhSach.json` 14 ứng dụng (6
     mặc định: Zalo, UniKey, 7-Zip, Foxit, UltraViewer, Chrome; thêm EVKey, Cốc Cốc, Firefox, Adobe Reader, VLC,
     Notepad++, TeamViewer, Telegram), trạm có ô chọn từng ứng dụng. Đọc ứng dụng đã cài bằng `winget export` (JSON)
     thay vì tách chữ của `winget list` (đổi theo ngôn ngữ); sau khi cài đọc lại để chắc đã cài. Chưa có `pin`,
     UniGetUI. Đã chạy thật Kiểm tra và chạy thử; chưa cài thật.

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
  - **Đã làm** (CheckWinFix 2026.10.4, commit `a8d1fad`): cả bốn mục trong *Thu thập thông tin*, thêm sự kiện 1795,
    1796 (firmware từ chối ghi) và `powercfg /lastwake`; bản quyền chỉ đọc tên, kênh, trạng thái, máy chủ KMS. Nguồn
    đọc sự kiện Secure Boot: [KB5016061](https://support.microsoft.com/kb/5016061),
    [Dell: sự kiện 1801](https://www.dell.com/support/kbdoc/en-us/000429711/windows-server-tpm-wmi-event-id-1801-secure-boot-certificates),
    [Microsoft Q&A: UEFICA2023Status đứng ở InProgress](https://learn.microsoft.com/en-us/answers/questions/5876964/uefica2023status-stuck-at-inprogress-and-secure-bo).
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
5. ~~**Gói kiểm tra chỉ đọc cho CheckWinFix**~~: đã làm (CheckWinFix 2026.10.4, commit `a8d1fad`).
6. ~~**Gói tiếng Việt**~~: đã làm (`tools\tieng-viet`, commit `4f2e279`); còn đổi định dạng thật trên máy ảo.

Tiếp theo: máy ảo Windows 11 (VirtualBox, ổ D, có TPM 2.0 và Secure Boot) để chạy thật các nút sửa đang chỉ thử bằng
giả lập; sau đó Sửa Office (mục 5) hoặc Hỗ trợ từ xa (mục 7).

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
- Test RAM báo lỗi thật: mã sự kiện MemoryDiagnostics-Results đã đối chiếu (1101, 1201 không lỗi; 1102, 1202 có lỗi),
  Chẩn đoán phần cứng và *Thu thập thông tin* đọc theo đó; chưa có máy RAM lỗi để thử.
- Byte đầu của giá trị `StartupApproved` lẻ là mục khởi động đã tắt trong Task Manager (tài liệu cộng đồng; Microsoft
  không công bố). Gói tiếng Việt dựa vào đó để không báo trùng mục đã tắt.
- `SetLocaleInfo` với `LOCALE_SSHORTDATE` tự cập nhật `sDate`, `iDate` cũ; chương trình đang mở nhận định dạng mới sau
  `WM_SETTINGCHANGE`. Gói tiếng Việt chưa đổi định dạng thật.
- `UseSystemSeparators` = 0 trong `HKCU\Software\Microsoft\Office\<bản>\Excel\Options` là Excel dùng dấu riêng (theo
  mẫu chính sách nhóm của Office; chưa đối chiếu bằng cách bỏ dấu trong Excel).
- Cách Claude Desktop lưu phiên tab Code (xem trên bản 2.42304, không có tài liệu): danh sách ở
  `claude-code-sessions\<accountUuid>\<organizationUuid>\local_<mã>.json`, tài khoản đang đăng nhập là
  `lastKnownAccountUuid` trong `config.json`, phiên đã xoá để lại `deleted_<mã>`; Claude đọc lại danh sách khi mở.
  Đồng bộ phiên Claude dựa vào các điều này; chưa thử mở phiên đã đồng bộ bằng tài khoản thứ hai.
- Phần ngoài danh sách phiên (bản 2.42304): mẫu phiên ở `ccd-session-presets.json` (`byAccount`), nhóm thanh bên ở
  `claude_desktop_config.json` → `preferences.epitaxyPrefs["dframe-code-sections"]["<tài khoản>/<tổ chức>"]`, tác vụ
  hẹn giờ ở `claude-code-sessions\<tài khoản>\<tổ chức>\scheduled-tasks.json` và `~\.claude\scheduled-tasks\<tên>\SKILL.md`,
  Cowork ở `local-agent-mode-sessions\<tài khoản>\<tổ chức>`. Claude Desktop bản Microsoft Store mở bằng
  `shell:AppsFolder\Claude_<mã>!Claude`. Công cụ chỉ đổi khoá của các mục này, không chép cả file cấu hình (có thể có
  token của máy chủ MCP).

## Thư viện bên thứ ba

Tất cả miễn phí. Thư viện của giao diện trạm nằm sẵn trong `hub\web\vendor\` (chạy không cần mạng);
thư viện của công cụ được script cài đặt tải về, không đưa vào git.

| Thư viện | Dùng cho | Giấy phép |
|---|---|---|
| Phosphor Icons | Biểu tượng của giao diện trạm (`hub\web\icons.svg`) | MIT |
| Be Vietnam Pro, JetBrains Mono | Chữ của giao diện trạm (`hub\web\vendor\fonts\`, bản dựng của Fontsource) | SIL OFL 1.1 |
| lit-html | Giao diện trạm: vẽ và cập nhật trang | BSD-3-Clause |
| marked | Hiển thị tài liệu Markdown trong trạm | MIT |
| DOMPurify | Lọc HTML trước khi hiển thị | Apache-2.0 hoặc MPL-2.0 |
| LibreDWG | DWG sang PDF: đọc file .dwg | GPL-3.0 |
| ezdxf | DWG sang PDF: đọc bản vẽ DXF | MIT |
| PyMuPDF | DWG sang PDF: vẽ PDF | AGPL-3.0 |
| faster-whisper, CTranslate2 | Ghi âm sang Word: nhận dạng giọng nói | MIT |
| Whisper large-v3 (bản CTranslate2 của Systran) | Ghi âm sang Word: mô hình | MIT |
| pyodbc | Khôi phục .mdf: kết nối SQL Server (bản 5.3.0, cài vào `.venv` của công cụ) | MIT |
| SQL Server Express LocalDB, ODBC Driver 18 | Khôi phục .mdf | Miễn phí của Microsoft |
| Ajv, ajv-formats | Bài thử: kiểm `tool.json` theo lược đồ (`tests\package.json`, chỉ cài trên máy dev) | MIT |

Dùng nội bộ thì không vướng gì. Nếu sau này muốn bán hoặc đóng gói công cụ DWG sang PDF thành phần mềm đóng
thì cần xem lại giấy phép GPL-3.0 của LibreDWG và AGPL-3.0 của PyMuPDF trước.
