# MyExcel VietQR – kiểm tra và sửa lỗi

Dùng khi add-in **MyExcel** không bật hoặc không tạo được **VietQR** trên một tài khoản Windows, trong khi
tài khoản khác (hoặc tài khoản mới tạo) trên cùng máy vẫn chạy được.

| File | Dùng khi nào |
|---|---|
| `CheckMyExcel_VietQR.bat` | **Luôn chạy trước.** Chỉ đọc, không sửa gì. Chạy ở tài khoản bị lỗi và ở một tài khoản chạy được để so sánh |
| `FixMyExcel_VietQR.bat` | Sửa tài khoản bị lỗi. Có sao lưu trước khi sửa và hoàn tác được |
| `HoanTac_FixMyExcel.bat` (trong thư mục sao lưu) | Hoàn tác một lần sửa. Trong Trạm Tool: nút **Hoàn tác lần sửa**, chọn thư mục sao lưu |

**Chạy bằng đúng tài khoản Windows đang bị lỗi, không chạy quyền Admin.** Cả hai công cụ làm việc trên
cấu hình riêng của tài khoản (HKCU, %APPDATA%); chạy bằng tài khoản Admin khác sẽ kiểm tra/sửa nhầm tài khoản.

## 1. Kiểm tra (chỉ đọc)

Kiểm tra 12 nhóm nguyên nhân: Excel/Office, add-in đang nạp, Trust Center, Trusted Locations, file bị Windows
chặn, dữ liệu MyExcel theo tài khoản, TEMP và cache `.exd`, Defender, mạng tới myexcel.vn và api.vietqr.io.
Mất 5–60 giây, không hỏi gì.

Kết quả:

- `%PUBLIC%\Documents\MyExcelCheck\BaoCao_MyExcel_<máy>_<tài khoản>_<giờ>.txt` (mở sẵn bằng Notepad) và một
  bản sao trên Desktop.
- `snapshot_<máy>_<tài khoản>.json` cạnh báo cáo: lần kiểm tra sau tự so sánh giữa các tài khoản để chỉ ra
  khác biệt giữa tài khoản lỗi và tài khoản chạy được.

## 2. Sửa lỗi

Lưu và **đóng Excel** trước khi chạy. Công cụ hỏi từng bước (Y/C = có, N/K = không):

1. Sao lưu cấu hình Excel và dữ liệu MyExcel ra `Desktop\MyExcelFix_SaoLuu_<giờ>\` (dừng lại nếu sao lưu lỗi).
2. Hỏi đổi tên các bộ cài MyExcel thừa thành `*_cu` (ảnh hưởng mọi tài khoản trên máy).
3. Nạp lại add-in đúng bộ cài, thêm Trusted Location, bật lại add-in bị vô hiệu hoá, sửa đường dẫn MyExcel
   tự lưu, xoá cache `.exd`, bỏ dấu "tải từ Internet" trên các file của bộ cài.
4. Hỏi sửa liên kết trong các file Excel ở Desktop, Documents, Downloads, OneDrive (chép bản sao trước).
5. Hỏi đặt lại dữ liệu MyExcel (phải khai báo lại tài khoản ngân hàng; thông tin cũ ghi ra `ThongTinKhaiBao.txt`).
6. Mở Excel để thử tạo VietQR.

Không bao giờ: tắt Excel giữa chừng, sửa registry toàn máy, đổi Macro Settings, Protected View, ActiveX.

## 3. Hoàn tác

Chạy `HoanTac_FixMyExcel.bat` trong thư mục sao lưu của lần sửa (hoặc nút **Hoàn tác lần sửa** trong Trạm
Tool). Cấu hình Excel và dữ liệu MyExcel được nạp lại từ file `.reg`, thư mục bộ cài được đổi tên lại.

> **Cẩn thận:** hoàn tác chép bản sao lưu đè lên các file Excel đã được sửa liên kết. Nếu người dùng đã nhập
> thêm dữ liệu vào các file đó sau lần sửa thì phần nhập thêm sẽ mất: sao lưu các file đó trước khi hoàn tác.

## Dữ liệu cá nhân

Thư mục sao lưu và `ThongTinKhaiBao.txt` chứa số tài khoản ngân hàng và tên chủ tài khoản. Desktop thường
được đồng bộ lên OneDrive: xong việc thì chép thư mục sao lưu ra chỗ an toàn hoặc xoá đi. Không đưa báo cáo,
snapshot hay thư mục sao lưu lên git.

## Sửa mã nguồn

`CheckMyExcel_VietQR.bat` và `FixMyExcel_VietQR.bat` được ghép từ các phần trong `src\` và `src_fix\` bằng
`build.ps1` của từng thư mục (ghi đè file .bat ở thư mục này). `LuuTru\` giữ bản sửa cũ v1, không dùng nữa.
