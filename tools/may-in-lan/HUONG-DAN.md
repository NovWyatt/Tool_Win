# Máy in mạng LAN và thư mục chia sẻ

Dùng khi trong văn phòng: không in được, máy in báo Offline, lệnh in kẹt không xoá được, máy in hiện thành
nhiều bản "(Copy 1)", không thấy máy khác trong mục Network, không vào được thư mục chia sẻ hoặc NAS, kết
nối máy in chia sẻ báo lỗi 0x0000011B, 0x00000709, 0x00000BCB...

| Nút trong Trạm Tool | Mục menu | Dùng khi nào |
|---|---|---|
| **Chẩn đoán** | 1 | **Luôn chạy trước.** Chỉ đọc. Ghi báo cáo, cuối báo cáo chỉ nút nên chạy tiếp |
| Sửa hàng đợi in bị kẹt | 2 | Lệnh in kẹt, máy in tạm dừng hoặc "Dùng máy in ngoại tuyến", dịch vụ in dừng |
| Xoá máy in trùng (Copy 1) | 3 | Một máy in hiện thành nhiều bản, in nhầm bản không chạy |
| Bật chia sẻ file và máy in trên máy này | 4 | Trên máy chia sẻ (máy cắm máy in USB, máy chứa thư mục chung); máy không thấy máy khác trong Network |
| Kết nối máy in chia sẻ từ máy khác | 5 | Thêm máy in đang chia sẻ trên một máy khác (`\\PC-KETOAN\HP`) |
| Thêm máy in mạng bằng địa chỉ IP | 6 | Máy in có cổng mạng hoặc Wi-Fi, biết địa chỉ IP |
| Kết nối hoặc ngắt thư mục chia sẻ (ổ mạng) | 7 | Gắn `\\máy\thư-mục` thành ổ Z:, lưu tài khoản của máy chia sẻ; ngắt ổ mạng |
| Nới bảo mật cho thiết bị cũ | 8 | Đã thử cách an toàn mà NAS, máy Windows cũ vẫn lỗi. Hỏi lại 2 lần |
| Hoàn tác lần sửa trước | 9 | Trả máy về như trước một lần sửa |

Ngoài Trạm Tool: bấm đúp `MAY_IN_LAN.bat` để mở menu. Mục cần quyền Admin tự hỏi UAC, chọn **Có**; riêng
mục 7 phải chạy quyền thường để ổ mạng hiện trong File Explorer của bạn.

## 1. Chẩn đoán (chỉ đọc)

Đọc 11 nhóm, mất dưới 1 phút:

1. Máy này: phiên bản Windows, tài khoản đang chạy, người đang dùng máy.
2. Mạng: card mạng, IP, cổng mặc định, mạng đang là Public hay Private.
3. Dịch vụ Windows cần cho in và chia sẻ (Print Spooler, Workstation, Server, phát hiện mạng...).
4. Tường lửa: quy tắc "Chia sẻ file và máy in", "Phát hiện mạng" có bật cho mạng đang dùng không.
5. Chia sẻ SMB: SMB1 (chỉ báo, không bao giờ bật), ký SMB, đăng nhập khách (guest).
6. Máy in: trạng thái, lệnh in đang kẹt, bản trùng, thử kết nối tới máy in mạng.
7. Cài driver qua mạng (Point and Print) và các khoá RPC của dịch vụ in.
8. Ổ mạng đã gắn, tài khoản máy khác đã lưu (chỉ tên, không đọc mật khẩu).
9. Máy này đang chia sẻ gì.
10. Kiểm tra thêm một máy (ô "Kiểm tra thêm một máy"): tên có tìm được không, ping, các cổng 445, 139, 135,
    9100, 631, 515, 80, 443, danh sách chia sẻ hoặc mã lỗi khi xem.
11. Nhật ký lỗi in và SMB 7 ngày gần nhất.

Báo cáo: `ket_qua\BaoCao_MayIn_<tên máy>_<ngày giờ>.txt`. Đọc phần **KẾT LUẬN** cuối báo cáo trước: lỗi xếp
theo thứ tự nên xử lý, kèm nút cần chạy.

Kèm theo là `ket_qua\KetQua_MayIn_ChanDoan_<tên máy>_<ngày giờ>.json` theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`): mỗi lỗi một mã cố định (`SPOOLER_DUNG`, `MANG_PUBLIC`, `MAY_IN_TRUNG`, `LENH_IN_KET`,
`MAY_CHU_TU_CHOI`...), Trạm Tool hiện từng lỗi kèm nút sửa.

Chạy bằng quyền Admin để đọc đủ nhật ký và tường lửa (Trạm Tool tự xin). Khi UAC hỏi mật khẩu của một tài
khoản Admin khác, báo cáo ghi cảnh báo: ổ mạng và mật khẩu đã lưu đọc được là của tài khoản Admin đó.

## 2. Các nút sửa

Mọi nút sửa đều in mục **Sẽ làm** rồi hỏi trước khi làm. Đánh dấu **Chạy thử** (hoặc thêm `-ChayThu` khi chạy
dòng lệnh) để chỉ xem kế hoạch, máy không thay đổi gì.

- **Sửa hàng đợi in bị kẹt**: dừng Print Spooler (chờ 20 giây rồi buộc dừng), xoá file trong
  `spool\PRINTERS`, bật lại dịch vụ và các dịch vụ phụ thuộc, cho máy in đang tạm dừng in tiếp, tắt "Dùng máy
  in ngoại tuyến". Lệnh in đang chờ mất, phải in lại; hoàn tác không lấy lại được.
- **Xoá máy in trùng**: gom các bản "(Copy 1)", "(Bản sao 1)" theo tên gốc, thử kết nối từng bản, gợi ý bản
  nên giữ (tới được máy in, không ngoại tuyến, đang mặc định). Bạn chọn bản giữ; công cụ xoá các bản còn lại,
  đổi tên bản giữ về tên gốc, giữ máy in mặc định.
- **Bật chia sẻ file và máy in**: hỏi riêng từng mạng Public có đổi sang Private không (chỉ đổi khi là mạng
  văn phòng, mạng nhà); bật quy tắc tường lửa chỉ cho Private/Domain, không bao giờ mở trên Public; bật các
  dịch vụ phát hiện mạng; hỏi chia sẻ máy in nào. Cuối cùng in địa chỉ máy khác dùng để vào máy này.
- **Kết nối máy in chia sẻ**: kiểm tra cổng 445, 135 của máy chia sẻ, liệt kê máy in đang chia sẻ để chọn,
  kết nối bằng quyền Admin để Windows cài được driver (tránh 0x00000BCB). Lỗi thì giải thích theo mã lỗi.
  "Thêm cho mọi tài khoản trên máy này" hiện với mọi người sau khi đăng nhập lại.
- **Thêm máy in bằng IP**: thử các cổng 9100, 631, 515, 80, 443. Máy in có IPP (cổng 631) thì thêm bằng
  driver chung của Windows, không cần driver hãng; không thì tạo cổng TCP/IP `IP_<địa chỉ>` (cổng 9100) và
  chọn driver hãng đã cài. Máy chỉ trả lời cổng 80/443 thường là router hoặc camera, không phải máy in.
- **Kết nối thư mục chia sẻ**: chọn chữ ổ còn trống (từ Z: lùi dần), kiểm tra cổng 445, gắn ổ và tự nối lại
  khi đăng nhập. Nhập tài khoản của máy chia sẻ (vd `PC-KETOAN\ketoan`) thì **mật khẩu gõ trong cửa sổ công
  cụ**, không hiện ký tự, Windows lưu lại (`cmdkey`); Trạm Tool không bao giờ nhận mật khẩu. Đánh dấu
  **Ngắt** để bỏ ổ mạng và (nếu muốn) xoá mật khẩu đã lưu.
- **Nới bảo mật cho thiết bị cũ**: chọn đúng một mục, công cụ in rủi ro và hỏi gõ `DONG Y`:

  | Mục | Khi nào | Đổi gì | Rủi ro |
  |---|---|---|---|
  | RPC qua named pipe | Máy này Windows 11 22H2 trở lên, kết nối máy in chia sẻ trên máy Windows cũ báo 0x00000709, 0x00000BC4 | `RpcUseNamedPipeProtocol = 1` (chính sách máy in) | Thấp nhất: cách Windows 10 vẫn dùng |
  | Tắt mã hoá RPC (chạy trên **máy chia sẻ**) | Máy khác báo 0x0000011B dù các máy đã cập nhật Windows | `RpcAuthnLevelPrivacyEnabled = 0` | Mở lại lỗ hổng CVE-2021-1678 của dịch vụ in |
  | Đăng nhập khách | NAS, ổ cắm router, máy chia sẻ không mật khẩu báo 1272 hoặc 0x80070035 | Cho đăng nhập khách, tắt bắt buộc ký SMB | Máy giả mạo trong mạng đọc, sửa được dữ liệu truyền đi |
  | Không bắt buộc ký SMB | NAS báo "The cryptographic signature is invalid" (0xC000A000), 0x80090006 | `RequireSecuritySignature` tắt | Máy giả mạo chen được vào kết nối |

  Cách bền hơn luôn có: cập nhật firmware NAS, đặt mật khẩu cho chia sẻ, thêm máy in thẳng bằng IP.

## 3. Hoàn tác

Mỗi lần sửa ghi nhật ký `ket_qua\hoan-tac\HoanTac_<ngày giờ>_<chế độ>.json`: dịch vụ, registry, quy tắc tường
lửa, mạng Public/Private, cấu hình SMB, máy in đã thêm, xoá, đổi tên, chia sẻ. Nút **Hoàn tác lần sửa trước**
liệt kê các lần sửa, mặc định chọn lần mới nhất chưa hoàn tác, trả từng thay đổi về như cũ theo thứ tự ngược
lại và ghi lại kết quả vào chính file đó.

Không hoàn tác được: lệnh in đã xoá; tuỳ chỉnh khay giấy, in hai mặt của máy in đã xoá (thêm lại chỉ với driver,
cổng cũ); ổ mạng (ngắt bằng nút số 7, đánh dấu Ngắt). Nhật ký của máy khác không chạy được trên máy này. Xoá
file nhật ký thì không hoàn tác được lần sửa đó nữa.

## Mã lỗi hay gặp

| Mã lỗi | Nghĩa | Làm gì |
|---|---|---|
| 0x0000011B | Mã hoá RPC khi in qua máy chia sẻ | Cập nhật Windows trên **máy chia sẻ**; vẫn lỗi thì thêm máy in bằng IP trên từng máy, hoặc Nới bảo mật > Tắt mã hoá RPC trên máy chia sẻ |
| 0x00000709, 0x00000BC4 | Tên máy in không hợp lệ, không tìm thấy máy in | Kiểm tra tên chia sẻ; máy này Windows 11 22H2+ và máy chia sẻ Windows cũ: Nới bảo mật > RPC qua named pipe |
| 0x00000BCB | Cần cài driver nhưng chỉ Admin được cài | Dùng nút Kết nối máy in chia sẻ (đã chạy quyền Admin), hoặc cài sẵn driver hãng |
| 0x0000007C | Lỗi cấp driver máy in | Cài driver hãng trên máy này trước rồi kết nối lại, hoặc thêm bằng IP |
| 0x000006D9 | Máy chia sẻ không nhận kết nối RPC | Trên máy chia sẻ, dịch vụ Windows Defender Firewall đang tắt: bật lại |
| 0x000006BA | Không kết nối được dịch vụ in của máy kia | Máy kia tắt, Print Spooler dừng hoặc tường lửa chặn: chạy nút 4 và nút 2 trên máy đó |
| 0x80070035 (53) | Không tìm thấy đường dẫn mạng | Máy kia tắt, khác mạng, mạng Public hoặc tường lửa chặn; thử bằng IP; chạy nút 4 trên máy chia sẻ |
| 67 | Không tìm thấy tên chia sẻ | Chạy Chẩn đoán với tên máy đó để xem tên chia sẻ đúng |
| 5 | Không có quyền | Cấp quyền cho tài khoản ở tab Sharing và Security trên máy chia sẻ |
| 86, 1326 | Sai tài khoản hoặc mật khẩu | Dùng tài khoản **của máy chia sẻ**; tài khoản không mật khẩu không đăng nhập qua mạng được |
| 1219 | Đã kết nối tới máy đó bằng tài khoản khác | Ngắt các ổ mạng tới máy đó hoặc đăng xuất; hoặc kết nối bằng IP thay cho tên |
| 1272, 3227320323 (0xC05D0003) | Windows chặn đăng nhập khách | Đặt tài khoản có mật khẩu cho chia sẻ (nên làm), hoặc Nới bảo mật > Đăng nhập khách |
| 0xC000A000, 0x80090006 | Chữ ký SMB không hợp lệ | Cập nhật firmware NAS, bật ký SMB trên NAS; tạm thời: Nới bảo mật > Không bắt buộc ký SMB |
| 0x80004005 | Lỗi chung | Thường do tường lửa, mạng Public, thiết bị chỉ có SMB1 hoặc bị chặn khách: Chẩn đoán với tên máy đó |
| 64 | Kết nối bị ngắt giữa chừng | Mạng chập chờn, hoặc thiết bị chỉ có SMB1: cập nhật firmware, in thẳng qua IP. Không bật SMB1 |

Chẩn đoán và các nút sửa tự giải thích những mã này khi gặp.

## Cách bố trí nên dùng cho văn phòng

- **Máy in có cổng mạng hoặc Wi-Fi**: đặt IP cố định (trên máy in, hoặc giữ IP trên router), rồi trên **từng
  máy** dùng nút Thêm máy in bằng IP. Không phụ thuộc máy nào bật, tránh hẳn các lỗi 0x0000011B, 0x00000709.
- **Máy in USB**: cắm vào một máy luôn bật, chạy nút 4 trên máy đó và chia sẻ máy in; các máy khác dùng nút 5.
- **Thư mục chung**: chia sẻ cho tài khoản **có mật khẩu** (tạo tài khoản riêng nếu không muốn đưa tài khoản
  của mình), không dùng đăng nhập khách.
- **NAS**: cập nhật firmware, bật SMB2/SMB3 và ký SMB, tạo tài khoản cho từng người.
- Driver máy in: Microsoft có lộ trình ngừng dần driver máy in bên thứ ba (xem Nguồn); máy in hỗ trợ IPP
  (thường ghi Mopria hoặc AirPrint) chạy được bằng driver chung của Windows, nên chọn loại này khi mua mới.

## An toàn

- Không bao giờ bật SMB1, không mở chia sẻ trên mạng Public, không đổi mạng sang Private khi chưa hỏi.
- Mật khẩu chỉ gõ trong cửa sổ công cụ, Windows lưu bằng `cmdkey`; công cụ không đọc mật khẩu đã lưu.
- Các mục nới bảo mật ở riêng một nút, hỏi lại 2 lần (Trạm Tool và gõ `DONG Y`), hoàn tác được.
- Báo cáo có tên máy, IP, tên chia sẻ, tài khoản của văn phòng: không đưa thư mục `ket_qua\` lên git hay gửi
  ra ngoài khi không cần.

## Chạy không cần Trạm Tool

```bat
MAY_IN_LAN.bat
MAY_IN_LAN.bat -Mode chan-doan -MayChu PC-KETOAN
MAY_IN_LAN.bat -Mode them-may-in-ip -DiaChi 192.168.1.50 -ChayThu
```

| Chế độ (`-Mode`) | Tham số |
|---|---|
| `chan-doan` | `-MayChu` (không bắt buộc) |
| `sua-hang-doi`, `xoa-may-in-trung`, `bat-chia-se` | không |
| `ket-noi-may-in` | `-MayChu`, `-TenChiaSe`, `-ChoMoiNguoi` |
| `them-may-in-ip` | `-DiaChi`, `-TenMayIn`, `-Kieu tu-dong\|ipp\|raw` |
| `ket-noi-thu-muc` | `-DuongDan`, `-ODia`, `-TaiKhoan`, `-Ngat` |
| `noi-bao-mat` | `-Muc rpc-named-pipe\|rpc-privacy-off\|smb-guest\|smb-signing-off` |
| `hoan-tac` | `-NhatKy HoanTac_...` (không bắt buộc) |

Mọi chế độ nhận `-ChayThu` (chỉ xem) và `-KhongDung` (không chờ Enter khi xong). Mã thoát: 0 xong, 1 lỗi,
2 thiếu điều kiện (chưa cho quyền Admin, thiếu driver, máy kia không kết nối được), 3 làm được một phần.

Mã nguồn: `MayInLan.ps1` (menu, chọn chế độ), `lib\Chung.ps1` (hiển thị, mạng, mã lỗi, máy in),
`lib\NhatKy.ps1` (nhật ký, hoàn tác), `lib\ChanDoan.ps1`, `lib\SuaLoi.ps1`.

## Nguồn

- [Windows 11 RPC connection updates for print](https://learn.microsoft.com/en-us/troubleshoot/windows-client/printing/windows-11-rpc-connection-updates-for-print): RPC qua TCP từ 22H2, lỗi 0x00000709, khoá `RpcUseNamedPipeProtocol`.
- [KB5005652](https://support.microsoft.com/kb/5005652): từ 8/2021, cài driver máy in qua mạng (Point and Print) cần quyền Admin.
- [SMB signing](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing): Windows 11 24H2 bản Pro, Enterprise, Education bắt buộc ký SMB, nên không vào được thiết bị chỉ cho khách; lỗi 0xC000A000.
- [End of servicing plan for third-party printer drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/print/end-of-servicing-plan-for-third-party-printer-drivers-on-windows): lộ trình ngừng driver máy in bên thứ ba.
