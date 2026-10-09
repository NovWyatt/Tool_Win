# Tối ưu Windows: dịch vụ nền, đồng hồ hệ thống

Bấm đúp `TOI_UU.bat` để mở menu, hoặc chạy từ Trạm Tool. Cửa sổ tự hỏi UAC vì đọc cấu hình khởi động (BCD) và đổi dịch vụ cần quyền Admin.

Gộp từ hai công cụ cũ *Tắt/bật dịch vụ nền* và *Tối ưu đồng hồ hệ thống*. Mỗi phần vẫn là một script chạy được riêng:

| File | Làm gì |
|---|---|
| `ToiUu.ps1` | Cửa vào chung: Kiểm tra tất cả, menu chung (bấm đúp `TOI_UU.bat`) |
| `DichVu.ps1` | Tắt/bật dịch vụ nền: DiagTrack, Windows Insider, SysMain, Tối ưu ổ đĩa |
| `DongHo.ps1` | Đồng hồ hệ thống: Dynamic Tick, ép HPET trong BCD |

## Kiểm tra

Chỉ đọc. Chạy phần Kiểm tra của cả hai trong cùng cửa sổ rồi in tóm tắt, điều nghiêm trọng trước:

- Dịch vụ: kiểu khởi động thật của từng dịch vụ (Tự động, Thủ công, Đã tắt), đang chạy hay dừng, mặc định của Windows, trạng thái gốc đã lưu. "Đang dừng" không có nghĩa là đã tắt: dịch vụ Thủ công bình thường vẫn dừng.
- Đồng hồ: ba thiết lập trong BCD kèm lời khuyên, giá trị registry bản cũ còn sót, trạng thái BitLocker ổ Windows.

Kết quả ghi vào `ket_qua\KetQua_ToiUu_KiemTra_<tên máy>_<giờ>.json` theo chuẩn `tramtool.ketqua/1` (xem `docs\THEM-CONG-CU.md`). Trạm hiện từng phát hiện ở Lịch sử, kèm nút chạy tiếp khi có:

| Mã | Mức | Nghĩa | Nút gợi ý |
|---|---|---|---|
| `TRIM_TAT` | cảnh báo | Máy có SSD mà Tối ưu ổ đĩa đang tắt | Bật lại dịch vụ (đánh dấu Tối ưu ổ đĩa) |
| `INSIDER_TAT` | cảnh báo | Máy nhận bản Insider mà wisvc đang tắt | Bật lại dịch vụ (đánh dấu Windows Insider) |
| `HPET_DANG_EP` | cảnh báo | Đang ép HPET (`useplatformclock`) | Trả đồng hồ về mặc định |
| `PLATFORM_TICK_DANG_EP` | cảnh báo | Đang ép `useplatformtick` | Trả đồng hồ về mặc định |
| `FILE_TRANG_THAI_HONG` | lỗi | File trạng thái gốc của dịch vụ bị hỏng | |
| `KHONG_DOC_DUOC_BCD` | lỗi | Không đọc được BCD | |
| `PHAN_KIEM_TRA_LOI` | lỗi | Một phần dừng giữa chừng, không ghi kết quả | |
| `DICH_VU_DA_TAT` | thông tin | Một dịch vụ đang tắt (kèm trạng thái gốc đã lưu) | |
| `DYNAMIC_TICK_TAT` | thông tin | Đang tắt Dynamic Tick | |
| `GIA_TRI_REGISTRY_CU` | thông tin | Còn giá trị bản 1.0 ghi vào registry | Trả đồng hồ về mặc định |
| `DICH_VU_MAC_DINH`, `DONG_HO_MAC_DINH` | ổn | Không dịch vụ nào tắt; đồng hồ để mặc định | |

Mã thoát của Kiểm tra: 0 xong (kể cả khi có cảnh báo), 1 lỗi, 2 thiếu quyền Admin, 3 chỉ kiểm tra được một phần.

## Dịch vụ nền

| Dịch vụ | Mặc định Windows | Nên tắt? |
|---|---|---|
| DiagTrack (gửi dữ liệu chẩn đoán, telemetry) | Tự động | Tắt được: bớt gửi dữ liệu sử dụng về Microsoft, Windows Update vẫn chạy. |
| Windows Insider (wisvc) | Thủ công | Tắt được, trừ máy đang nhận bản Windows thử nghiệm (công cụ hỏi lại). |
| SysMain | Tự động | Thường không: nó làm mở ứng dụng nhanh hơn. Chỉ tắt khi ổ HDD hay chạy 100% hoặc RAM 4 GB trở xuống. |
| Tối ưu ổ đĩa (defragsvc) | Thủ công | Không: dịch vụ này chạy TRIM định kỳ cho SSD (công cụ hỏi lại, mặc định là không). |

- **Tắt dịch vụ nền**: lưu kiểu khởi động hiện tại vào `ket_qua\TrangThaiGoc_<tên máy>.json`, rồi đặt Đã tắt và dừng dịch vụ. Không lưu được file thì không đổi gì. Đọc lại sau khi đổi để chắc Windows đã nhận.
- **Bật lại dịch vụ như trước khi tắt**: trả đúng kiểu khởi động đã lưu (kể cả Tự động trễ) và chạy lại dịch vụ từng chạy. Dịch vụ tắt từ trước khi dùng công cụ thì trả về mặc định của Windows. Đánh dấu dịch vụ nào thì chỉ bật lại dịch vụ đó; không đánh dấu thì bật lại mọi dịch vụ đang tắt trong bốn dịch vụ.

File trạng thái gốc của bản cũ (`tools\service-optimizer\ket_qua`) được chuyển sang chỗ mới ở lần chạy đầu.

Chạy thẳng: `DichVu.ps1 -Mode kiem-tra|tat|bat-lai [-DiagTrack] [-WiSvc] [-SysMain] [-DefragSvc] [-ChayThu]`. Mã thoát: 0 xong, 1 lỗi, 2 thiếu quyền Admin (bấm "Không" ở UAC), 3 làm được một phần.

## Đồng hồ hệ thống

| Nút | Làm gì |
|---|---|
| Tối ưu đồng hồ cho chơi game | Tắt Dynamic Tick (`disabledynamictick yes`), bỏ ép HPET (xoá `useplatformclock`) nếu đang ép. |
| Trả đồng hồ về mặc định của Windows | Xoá `disabledynamictick`, `useplatformclock`, `useplatformtick`: Windows tự chọn đồng hồ như lúc mới cài. |

Hai nút đổi thiết lập in việc sẽ làm trước, đọc lại BCD sau khi đổi để chắc Windows đã nhận, và cần **khởi động lại máy** mới có hiệu lực.

**Nên dùng khi nào.** Phần lớn máy Windows 10/11 hiện đại không mượt hơn khi đổi các thiết lập này. Chỉ thử khi game giật theo nhịp đều mà đã loại trừ driver, nhiệt độ, nguồn điện. Sau khi khởi động lại mà không thấy khác thì chạy "Trả đồng hồ về mặc định". Laptop có thể hao pin hơn một chút khi tắt Dynamic Tick. Ép HPET (`useplatformclock yes`) thường làm chậm hơn, nên công cụ không bật nó; nút chơi game còn bỏ ép nếu thấy đang bật.

**BitLocker.** Đổi BCD khi ổ Windows đang bật BitLocker có thể làm lần khởi động tới hỏi khoá khôi phục 48 số. Gặp trường hợp này công cụ hỏi trước rồi tạm dừng BitLocker đúng 1 lần khởi động (Windows tự bật lại sau đó). Nên lưu khoá khôi phục trước bằng công cụ BitLocker. Không đọc được trạng thái BitLocker thì công cụ hỏi lại, mặc định là không đổi.

**Bản 1.0.** Bản cũ (`ServiceOptimizer.bat`) ghi `useplatformclock`, `disabledynamictick` vào `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel`. Windows không đọc chỗ đó nên bản cũ không có tác dụng dù báo thành công. Hai nút đổi thiết lập xoá các giá trị đó.

Chạy thẳng: `DongHo.ps1 -Mode kiem-tra|choi-game|mac-dinh [-ChayThu]`. Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (không có quyền Admin, bấm "Không" ở UAC, không đồng ý tạm dừng BitLocker), 3 làm được một phần.

Mọi nút đổi máy đều có ô "Chạy thử" (hoặc thêm `-ChayThu`) để chỉ xem việc sẽ làm.
