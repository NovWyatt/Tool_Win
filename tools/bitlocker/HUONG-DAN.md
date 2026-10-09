# BitLocker và khoá khôi phục

Dùng khi: máy hiện màn hình xanh **BitLocker recovery** đòi khoá 48 số; sắp cập nhật BIOS, thay bo mạch, đổi
cài đặt Secure Boot hay TPM; sắp cài lại Windows; ổ dữ liệu hoặc USB bị khoá sau khi cài lại; muốn biết máy có
đang mã hoá không và khoá đã lưu ở đâu.

Windows 11 bản Home cũng mã hoá ổ (gọi là **Mã hoá thiết bị**, *Device encryption*): khi đăng nhập bằng tài khoản
Microsoft, Windows tự bật và tải khoá lên tài khoản đó. Nhiều người không biết máy mình đang mã hoá cho tới khi bị
hỏi khoá.

| Nút trong Trạm Tool | Mục menu | Dùng khi nào |
|---|---|---|
| **Kiểm tra** | 1 | **Luôn chạy trước.** Chỉ đọc. Báo cáo có Mã khoá để đối chiếu, không có khoá |
| Lưu khoá khôi phục ra file | 2 | Trước khi cập nhật BIOS, thay phần cứng, cài lại Windows, mang máy đi sửa |
| Tạm dừng BitLocker | 3 | Ngay trước khi cập nhật BIOS/UEFI, đổi cài đặt trong BIOS, thay bo mạch |
| Bật lại BitLocker | 4 | Xong việc mà chưa hết số lần khởi động đã chọn, hoặc đã chọn "đến khi bật lại" |
| Mở khoá ổ bị BitLocker khoá | 5 | Ổ dữ liệu, ổ tháo từ máy khác, USB bị khoá |
| Giải mã ổ dữ liệu, USB | 6 | Không cần mã hoá ổ đó nữa. Hỏi lại 2 lần |
| Hoàn tác lần thay đổi trước | 7 | Trả lại như trước một lần tạm dừng, thêm khoá, bật tự mở khoá |

Ngoài Trạm Tool: bấm đúp `BITLOCKER.bat` để mở menu. Mọi mục cần quyền Admin (Windows hỏi UAC, chọn **Có**);
Kiểm tra chạy được bằng quyền thường nhưng không đọc được từng ổ.

## 1. Kiểm tra (chỉ đọc)

1. Máy này: phiên bản Windows (Home chỉ có Mã hoá thiết bị), tài khoản đang dùng là tài khoản Microsoft hay
   cục bộ, Admin nào đăng nhập bằng tài khoản Microsoft, máy có vào tài khoản công ty (Entra ID, domain) không.
2. TPM và Secure Boot.
3. Từng ổ: đang bảo vệ, tạm dừng, chờ kích hoạt, đang mã hoá hay giải mã, bị khoá; kiểu mã hoá; các khoá bảo vệ
   (TPM, mật khẩu, khoá khôi phục...) và PCR mà TPM kiểm tra; Mã khoá (Key ID) của từng khoá khôi phục và khoá
   đó **đã được lưu ở đâu**: file khoá tìm thấy trên máy, USB, hoặc sự kiện sao lưu lên tài khoản Microsoft,
   Entra ID, AD.
4. Nhật ký BitLocker 2 năm: bắt đầu mã hoá, giải mã, tạm dừng, sao lưu khoá thành công hay thất bại, các lần
   phải nhập khoá khi khởi động.
5. Chính sách BitLocker do công ty, phần mềm quản lý đặt.

Báo cáo: `ket_qua\BaoCao_BitLocker_<tên máy>_<ngày giờ>.txt`. Đọc phần **KẾT LUẬN** trước: việc nên làm theo
thứ tự, kèm nút cần chạy. Báo cáo **không bao giờ chứa khoá khôi phục**, chỉ có Mã khoá (gửi người khác được).
Kèm theo là `ket_qua\KetQua_BitLocker_KiemTra_<tên máy>_<ngày giờ>.json` theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`): mỗi việc một mã cố định (`O_BI_KHOA`, `KHONG_CO_KHOA_KHOI_PHUC`, `CHUA_THAY_NOI_LUU_KHOA`,
`KHOA_THEO_FIRMWARE`...), Trạm Tool hiện từng việc kèm nút xử lý. File này cũng không có khoá khôi phục.

Công cụ tìm file khoá ở: thư mục `ket_qua\khoa-bitlocker` của công cụ, gốc các ổ và USB, `DuLieu_SaoLuu\BitLocker`
(bản sao lưu của *Chuyển dữ liệu khi cài lại Windows*), Desktop, Documents, Downloads, OneDrive, và thư mục bạn
chỉ thêm. Nhận cả file "BitLocker Recovery Key ....TXT" Windows tự lưu lẫn file công cụ này lưu.

## 2. Các nút thay đổi

Mọi nút in mục **Sẽ làm** rồi hỏi trước. Đánh dấu **Chạy thử** (hoặc `-ChayThu` khi chạy dòng lệnh) để chỉ xem.

- **Lưu khoá khôi phục ra file**: đọc khoá 48 số của mọi ổ đang mã hoá (ổ đang khoá thì phải mở trước), ghi
  vào một file `BitLocker_KhoaKhoiPhuc_<tên máy>_<ngày giờ>.txt` kèm Mã khoá và cách dùng. Ổ đã mã hoá mà chưa
  có khoá khôi phục (chỉ có TPM hoặc mật khẩu) thì hỏi rồi thêm khoá. Sau đó hỏi: chép thêm vào USB đang cắm, in
  ra giấy, hiện khoá lên màn hình để chép tay, mở thư mục.
  **Khoá chỉ có ích khi nằm ngoài máy này**: chọn lưu thẳng vào USB, hoặc lưu xong chép ra USB, điện thoại,
  giấy. File nằm trên ổ đã mã hoá thì lúc Windows hỏi khoá không mở được nó.
- **Tạm dừng BitLocker**: chọn 1, 2, 3 lần khởi động hoặc "đến khi bật lại bằng tay". Trong thời gian đó ổ
  vẫn mã hoá nhưng khoá để trần trên ổ, Windows không kiểm tra TPM nên không hỏi khoá. Hết số lần, Windows tự bật
  lại và ghi nhận cấu hình mới (BIOS mới, bo mạch mới). Cập nhật qua Windows Update không cần làm gì; tự cập nhật
  BIOS bằng file, công cụ của hãng thì tạm dừng trước (nhiều công cụ của hãng tự tạm dừng, tạm dừng thêm cũng
  không sao). Công cụ nhắc nếu chưa thấy nơi lưu khoá.
- **Bật lại BitLocker**: bật lại các ổ đang tạm dừng. Lỗi 0x80310030 là đang cắm đĩa, USB khởi động: rút ra rồi
  chạy lại.
- **Mở khoá ổ bị BitLocker khoá**: với mỗi ổ bị khoá, công cụ in Mã khoá của ổ, tìm file khoá có Mã khoá khớp và
  mở bằng khoá đó; không thấy thì hỏi bạn gõ khoá 48 số **trong cửa sổ công cụ** (gõ sai dạng thì báo nhóm số
  nào sai; tối đa 3 lần). Mở xong hỏi có cho ổ tự mở khoá mỗi lần vào Windows trên máy này không. Ổ dữ liệu cố
  định chỉ tự mở khoá được khi ổ Windows cũng bật BitLocker; USB thì được, và gắn với tài khoản đang chạy công cụ.
- **Giải mã ổ dữ liệu, USB**: ổ phải đang mở khoá. Phải gõ `DONG Y`. Giải mã chạy nền, giữ nguyên dữ liệu, tắt
  máy giữa chừng thì lần sau Windows làm tiếp. Ổ Windows thì công cụ không tự giải mã mà mở trang cài đặt của
  Windows (Home: *Settings > Privacy & security > Device encryption*; bản khác: *BitLocker Drive Encryption*
  trong Control Panel); trước khi sửa phần cứng chỉ cần Tạm dừng.

## 3. Hoàn tác

Mỗi lần thay đổi ghi nhật ký `ket_qua\hoan-tac\HoanTac_<ngày giờ>_<chế độ>.json` (chỉ có mã ổ và Mã khoá,
không có khoá). Nút **Hoàn tác lần thay đổi trước** mặc định chọn lần mới nhất chưa hoàn tác:

| Đã làm | Hoàn tác |
|---|---|
| Tạm dừng | Bật lại (bỏ qua nếu đã bật lại) |
| Thêm khoá khôi phục | Xoá khoá đó, **hỏi lại riêng** vì file khoá đã lưu cho Mã khoá đó sẽ không mở được ổ nữa |
| Bật tự mở khoá | Tắt tự mở khoá, xoá khoá phụ công cụ đã tạo |

Không hoàn tác được: giải mã (muốn mã hoá lại thì bật BitLocker từ đầu), mở khoá (ổ tự khoá lại khi khởi động
lại nếu không bật tự mở khoá).

## Khi máy hiện màn hình "BitLocker recovery"

1. Ghi lại 8 ký tự đầu của **Recovery key ID** (Mã khoá) trên màn hình.
2. Tìm khoá có Mã khoá bắt đầu bằng 8 ký tự đó:
   - Tài khoản Microsoft (máy cá nhân, Home): https://aka.ms/myrecoverykey, đăng nhập đúng tài khoản đã dùng
     trên máy đó (xem bằng điện thoại cũng được).
   - Tài khoản công ty, trường học: https://aka.ms/aadrecoverykey, hoặc hỏi bộ phận IT.
   - File khoá trên USB, giấy in, file `BitLocker_KhoaKhoiPhuc_...txt` công cụ này đã lưu.
3. Gõ 48 chữ số. Phím số không chạy thì dùng **F1–F9 cho 1–9, F10 cho 0**.
4. Vào được Windows thì chạy **Kiểm tra** để biết vì sao bị hỏi; nếu lặp lại mỗi lần khởi động: Tạm dừng
   (1 lần), khởi động lại, để Windows ghi nhận cấu hình mới.

Hay gặp sau khi: cập nhật hoặc đổi cài đặt BIOS, tắt hay xoá TPM, thay bo mạch, đổi thứ tự khởi động (USB, đĩa
CD trước ổ cứng), cắm/rút dock, chuyển ổ sang máy khác. Không tìm được khoá thì **không có cách nào** đọc lại dữ
liệu trên ổ: chỉ còn cài lại Windows (xoá ổ).

## Trước khi cài lại Windows, thay bo mạch, mang máy đi sửa

1. Chạy **Kiểm tra**: ổ nào đang mã hoá, khoá đã lưu ở đâu.
2. Chạy **Lưu khoá khôi phục** và chép file ra USB (công cụ *Chuyển dữ liệu khi cài lại Windows* cũng xuất khoá
   vào bản sao lưu của nó).
3. Có ổ dữ liệu (D:, E:) mã hoá: cài lại Windows xong ổ đó sẽ bị khoá, mở bằng nút **Mở khoá** (công cụ tự tìm
   khoá trong bản sao lưu và USB), rồi cho tự mở khoá hoặc giải mã.
4. Thay bo mạch, cập nhật BIOS: chạy **Tạm dừng** ngay trước khi tắt máy.

## Mã lỗi hay gặp

| Mã lỗi | Nghĩa | Làm gì |
|---|---|---|
| 0x80041003 | Không có quyền đọc BitLocker | Chạy bằng quyền Admin |
| 0x80310000 | Ổ đang bị khoá | Nút Mở khoá trước |
| 0x80310008 | Ổ không bật BitLocker | Không cần làm gì |
| 0x80310027 | Khoá không đúng với ổ | Đối chiếu Mã khoá; mỗi ổ, mỗi lần bật BitLocker có khoá riêng |
| 0x80310030 | Đang cắm đĩa, USB khởi động | Rút ra rồi chạy lại |
| 0x80310033 | Không thấy khoá đó trên ổ | Chạy Kiểm tra để xem các khoá hiện có |
| 0x80310035 | Khoá sai dạng | 48 chữ số, 8 nhóm 6 số |

## An toàn

- Khoá khôi phục mở được cả ổ: chỉ ghi vào file khoá ở nơi bạn chọn, không vào báo cáo, nhật ký hoàn tác.
- Khoá gõ tay chỉ gõ trong cửa sổ công cụ; Trạm Tool không nhận khoá qua tham số. Khoá hiện trên màn hình khi
  gõ (như hộp mở khoá của Windows) để dễ dò từng nhóm, không được lưu lại.
- Xoá file khoá trong trạm có cảnh báo; xoá xong nhớ dọn Thùng rác. Không đưa `ket_qua\` lên git hay gửi qua tin
  nhắn, email (`.gitignore` đã chặn các mẫu tên file khoá).

## Chạy không cần Trạm Tool

```bat
BITLOCKER.bat
BITLOCKER.bat -Mode kiem-tra
BITLOCKER.bat -Mode luu-khoa -NoiLuu E:\
BITLOCKER.bat -Mode tam-dung -SoLan 1 -ChayThu
```

| Chế độ (`-Mode`) | Tham số |
|---|---|
| `kiem-tra` | `-ThuMucKhoa` (không bắt buộc) |
| `luu-khoa` | `-NoiLuu` (không bắt buộc) |
| `tam-dung` | `-SoLan 0..15` (0 = đến khi bật lại; trống thì hỏi, mặc định 1) |
| `bat-lai` | không |
| `mo-khoa` | `-ODia`, `-ThuMucKhoa` (đều không bắt buộc) |
| `giai-ma` | `-ODia` (không bắt buộc) |
| `hoan-tac` | `-NhatKy HoanTac_...` (không bắt buộc) |

Mọi chế độ nhận `-ChayThu` (chỉ xem) và `-KhongDung` (không chờ Enter khi xong). Mã thoát: 0 xong, 1 lỗi,
2 thiếu điều kiện (chưa cho quyền Admin, không có khoá), 3 làm được một phần.

Mã nguồn: `BitLocker.ps1` (menu, chọn chế độ), `lib\Chung.ps1` (hiển thị, hỏi, mã lỗi), `lib\DocBitLocker.ps1`
(đọc ổ qua WMI `Win32_EncryptableVolume`, TPM, nhật ký, file khoá), `lib\NhatKy.ps1` (hoàn tác),
`lib\ChanDoan.ps1`, `lib\ThaoTac.ps1`.

## Nguồn

- [Find your BitLocker recovery key](https://support.microsoft.com/windows/find-your-bitlocker-recovery-key-6b71ad27-0b89-ea08-f143-056f5ab347d6): aka.ms/myrecoverykey, aka.ms/aadrecoverykey, đối chiếu 8 ký tự đầu của Mã khoá.
- [Device encryption in Windows](https://support.microsoft.com/windows/device-encryption-in-windows-cf7e2b6f-3e70-4882-9532-18633605b7df): Mã hoá thiết bị trên Windows Home, tự bật khi đăng nhập tài khoản Microsoft.
- [BitLocker recovery overview](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/recovery-overview): các nguyên nhân bị hỏi khoá, tạm dừng trước khi nâng cấp phần cứng, firmware; gói khoá (.KPG).
- [BitLocker FAQ](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/faq): khác nhau giữa tạm dừng và giải mã, khi nào phải tạm dừng, phím F1–F10, điều kiện tự mở khoá.
- [Suspend-BitLocker](https://learn.microsoft.com/powershell/module/bitlocker/suspend-bitlocker): số lần khởi động 0–15, mặc định 1.
- [Win32_EncryptableVolume](https://learn.microsoft.com/windows/win32/secprov/win32-encryptablevolume): các phương thức WMI công cụ dùng.
