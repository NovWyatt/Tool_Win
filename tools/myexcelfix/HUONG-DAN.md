# MyExcel VietQR – kiểm tra và sửa lỗi

Dùng khi add-in **MyExcel** không bật hoặc không tạo được **VietQR** trên một tài khoản Windows, trong khi
tài khoản khác (hoặc tài khoản mới tạo) trên cùng máy vẫn chạy được.

| File | Dùng khi nào |
|---|---|
| `CheckMyExcel_VietQR.bat` | **Luôn chạy trước.** Chỉ đọc, không sửa gì. Chạy ở tài khoản bị lỗi và ở một tài khoản chạy được để so sánh |
| `FixMyExcel_VietQR.bat` | Sửa tài khoản bị lỗi. Có sao lưu trước khi sửa và hoàn tác được |
| `HOAN_TAC.bat` | Hoàn tác một lần sửa: liệt kê các bản sao lưu của tài khoản để chọn. Trong Trạm Tool: nút **Hoàn tác lần sửa** |

**Chạy bằng đúng tài khoản Windows đang bị lỗi, không chạy quyền Admin.** Cả hai công cụ làm việc trên
cấu hình riêng của tài khoản (HKCU, %APPDATA%); chạy bằng tài khoản Admin khác sẽ kiểm tra/sửa nhầm tài khoản.

## 1. Kiểm tra (chỉ đọc)

Kiểm tra 12 nhóm nguyên nhân: Excel/Office, add-in đang nạp, Trust Center, Trusted Locations, file bị Windows
chặn, dữ liệu MyExcel theo tài khoản, TEMP và cache `.exd`, Defender, mạng tới myexcel.vn và api.vietqr.io.
Mất 5–60 giây, không hỏi gì.

Kết quả:

- `%LOCALAPPDATA%\MyExcelFix\BaoCao\BaoCao_MyExcel_<máy>_<tài khoản>_<giờ>.txt` (mở sẵn bằng Notepad) và một
  bản sao trên Desktop để gửi kỹ thuật. Báo cáo đã che số tài khoản ngân hàng (chỉ còn 4 số cuối) và tên chủ tài
  khoản (chỉ còn chữ đầu mỗi từ).
- `%PUBLIC%\Documents\MyExcelCheck\snapshot_<máy>_<tài khoản>.json`: cấu hình đo được (không có dữ liệu ngân hàng),
  để ở thư mục chung để lần kiểm tra ở tài khoản khác tự so sánh, chỉ ra khác biệt giữa tài khoản lỗi và tài khoản
  chạy được. Snapshot hỏng của tài khoản khác chỉ bị bỏ qua.
- `KetQua_MyExcel_KiemTra_<máy>_<tài khoản>_<giờ>.json` cạnh báo cáo, theo chuẩn kết quả của Trạm Tool
  (`tramtool.ketqua/1`): mỗi phát hiện có mã cố định (vd `ADDIN_CHUA_BAT`, `THU_MUC_CHUA_TIN_CAY`), mức độ (`loi`,
  `canh-bao`, `thong-tin`) và cách sửa. Mã không đổi khi sửa câu chữ; mã cũng in trong ngoặc ở phần *Kết luận* của
  báo cáo. Lỗi mà bản Sửa xử lý được có thêm `chayTiep` trỏ tới nút *Sửa lỗi*: Trạm Tool hiện nút đó ngay cạnh phát
  hiện. File kết quả của Sửa, Hoàn tác cũng theo chuẩn này (cảnh báo, file giữ lại thành `phatHien`).

Mã thoát: `0` kiểm tra xong (kể cả khi có phát hiện), `1` không ghi được báo cáo, `2` chạy sai tài khoản (kết quả
không phải của tài khoản bị lỗi).

## 2. Sửa lỗi

Lưu và **đóng Excel** trước khi chạy. Công cụ hỏi từng bước (Y/C = có, N/K = không):

1. Sao lưu cấu hình Excel và dữ liệu MyExcel vào `%LOCALAPPDATA%\MyExcelFix\SaoLuu\MyExcelFix_SaoLuu_<giờ>\`
   (dừng lại nếu sao lưu lỗi).
2. Hỏi đổi tên các bộ cài MyExcel thừa thành `*_cu` (ảnh hưởng mọi tài khoản trên máy).
3. Nạp lại add-in đúng bộ cài, thêm Trusted Location, bật lại add-in bị vô hiệu hoá, sửa đường dẫn MyExcel
   tự lưu, xoá cache `.exd`, bỏ dấu "tải từ Internet" trên các file của bộ cài.
4. Hỏi sửa liên kết trong các file Excel ở Desktop, Documents, Downloads, OneDrive (chép bản sao trước).
5. Hỏi đặt lại dữ liệu MyExcel (phải khai báo lại tài khoản ngân hàng). Chỉ khi đặt lại thật, thông tin cũ mới
   được ghi ra `ThongTinKhaiBao.txt` trong thư mục sao lưu; công cụ in đường dẫn file đó để mở bằng Notepad.
6. Mở Excel để thử tạo VietQR.

Không bao giờ: tắt Excel giữa chừng, sửa registry toàn máy, đổi Macro Settings, Protected View, ActiveX.

Chạy không có cửa sổ dòng lệnh (đầu vào bị chuyển hướng) thì công cụ đọc từng dòng trả lời; hết dòng thì dừng hẳn
và báo *Hết đầu vào*, không hỏi lại mãi.

Mã thoát: `0` xong, `1` lỗi (không sao lưu được, lỗi bất ngờ), `2` chưa sửa gì (sai tài khoản, chọn không sửa,
Excel chưa đóng, không có bộ MyExcel đủ file QR, hết đầu vào trước khi sửa), `3` làm được một phần (có cảnh báo,
VietQR vẫn lỗi, hết đầu vào giữa chừng). Kết quả ghi thêm ra
`%LOCALAPPDATA%\MyExcelFix\BaoCao\KetQua_MyExcel_Sua_<máy>_<tài khoản>_<giờ>.json`.

## 3. Hoàn tác

Bấm đúp `HOAN_TAC.bat` (hoặc nút **Hoàn tác lần sửa** trong Trạm Tool, bỏ trống ô thư mục): công cụ liệt kê các bản
sao lưu của tài khoản đang chạy, mới nhất trước, gồm cả bản cũ trên Desktop (đánh dấu `[Desktop]`), rồi hỏi chọn bản
nào. `HOAN_TAC.bat "<thư mục sao lưu>"` hoàn tác thẳng thư mục đó. Cả hai chạy bản `FixMyExcel_VietQR.bat` mới nhất
cạnh `HOAN_TAC.bat` ở chế độ hoàn tác. Bấm đúp `HoanTac_FixMyExcel.bat` trong thư mục sao lưu cũng được, nhưng file
đó là bản của lần sửa: thư mục sao lưu tạo trước bản 2026.10.1 nên hoàn tác bằng `HOAN_TAC.bat`.

1. Liệt kê từng file Excel đã sửa liên kết và việc sẽ làm với nó, rồi hỏi.
2. Lưu cấu hình hiện tại (registry Excel, dữ liệu MyExcel) vào `TruocHoanTac_<giờ>\` trong thư mục sao lưu. Không
   lưu được thì dừng, chưa đổi gì.
3. Xoá khoá do lần sửa tạo, nạp lại cấu hình Excel và dữ liệu MyExcel từ file `.reg`, đổi tên lại thư mục bộ cài.
4. File Excel: lần sửa ghi dấu SHA-256 của từng file sau khi sửa (`HashAfter` trong `manifest.json`).
   - File chưa đổi từ đó: chép lại bản trước khi sửa.
   - File đã được sửa tiếp (hoặc thư mục sao lưu cũ không có dấu): bản hiện tại được giữ thành
     `<tên>.truoc_hoantac.xlsx` cạnh file, rồi mới chép bản trước khi sửa. Dữ liệu nhập thêm nằm trong file giữ lại.
   - File đã bị chuyển hoặc xoá, bản sao lưu bị thay đổi: bỏ qua và cảnh báo.

Đường dẫn bản sao lưu trong `manifest.json` là tương đối, nên chép cả thư mục sao lưu sang chỗ khác vẫn hoàn tác
được. Mã thoát: `0` xong, `1` lỗi (manifest hỏng, không lưu được cấu hình hiện tại), `2` chưa hoàn tác gì, `3` một
phần (có file bỏ qua), `2` cũng khi không thấy bản sao lưu nào của tài khoản (`KHONG_CO_SAO_LUU`). Kết quả ghi thêm
ra `KetQua_MyExcel_HoanTac_<máy>_<tài khoản>_<giờ>.json`.

## Dữ liệu cá nhân

Thư mục sao lưu (`VBA_Settings.reg`, `ThongTinKhaiBao.txt`, bản sao file Excel) chứa số tài khoản ngân hàng, tên chủ
tài khoản và dữ liệu sổ sách. Từ bản 2026.10.2 mọi thứ của tài khoản nằm trong `%LOCALAPPDATA%\MyExcelFix\`:

| Thư mục | Có gì |
|---|---|
| `%LOCALAPPDATA%\MyExcelFix\SaoLuu\` | Bản sao lưu của từng lần sửa, nhật ký sửa và hoàn tác |
| `%LOCALAPPDATA%\MyExcelFix\BaoCao\` | Báo cáo kiểm tra, JSON kết quả kiểm tra, sửa, hoàn tác |
| `%PUBLIC%\Documents\MyExcelCheck\` | Chỉ snapshot cấu hình để so sánh giữa các tài khoản |

`%LOCALAPPDATA%` không đồng bộ OneDrive như Desktop và tài khoản khác (không phải Admin) không đọc được như Public
Documents. Bản cũ hơn để sao lưu trên Desktop và báo cáo ở Public Documents: bản mới tự chuyển báo cáo, JSON của tài
khoản đang chạy sang thư mục riêng; sao lưu cũ trên Desktop thì để nguyên (`HOAN_TAC.bat` vẫn dùng được), nên xoá khi
không cần hoàn tác nữa (Trạm Tool liệt kê ở phần kết quả). Bản báo cáo trên Desktop là để gửi: đã che số và tên. Không
đưa báo cáo, snapshot hay thư mục sao lưu lên git.

## Sửa mã nguồn

`CheckMyExcel_VietQR.bat` và `FixMyExcel_VietQR.bat` được ghép từ các phần trong `src\` và `src_fix\` bằng
`build.ps1` của từng thư mục (ghi đè file .bat ở thư mục này). `build.ps1` thay mọi `__MYX_VERSION__` (tiêu đề cửa
sổ, dòng đầu file, `$script:Version`) bằng `version` trong `tool.json`, kiểm tra cú pháp PowerShell và phần đầu cmd
chỉ có ASCII rồi mới ghi file. Đổi `version` trong `tool.json` trước khi build bản phát hành. `LuuTru\` giữ bản sửa
cũ v1, không dùng nữa.

Thử không đụng máy thật: các biến `MYX_*` trong `src_fix\10_core.ps1` (registry thử qua `MYX_REGBASE`, bộ MyExcel giả
qua `MYX_CANDIDATES`, `MYX_PREFERRED`, thư mục quét `MYX_SCANROOT`, trả lời tự động `MYX_AUTO`), cùng `TEMP` và
`APPDATA` trỏ sang thư mục nháp để bước dọn `.exd` không xoá cache thật. Nơi ghi: `MYX_OUT` gom mọi thứ vào một thư
mục; hoặc đặt `LOCALAPPDATA`, `PUBLIC` và `MYX_DESKTOP` sang thư mục nháp để thử đúng cách sắp xếp thật
(`tests\myexcelfix\4_NoiLuu.ps1`, `5_KiemTraNoiLuu.ps1`).
