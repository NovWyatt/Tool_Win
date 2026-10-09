# Dọn ổ C an toàn

Công cụ xem ổ C đang đầy vì đâu, rồi dọn những thứ Windows và ứng dụng tự tạo lại được: file tạm, bộ nhớ đệm trình duyệt, file tải về của Windows Update đã cài, báo cáo lỗi. Nút dọn nào cũng in danh sách sẽ xoá kèm dung lượng, hỏi lại rồi mới xoá.

| Nút | Quyền Admin | Làm gì |
|---|---|---|
| Xem ổ C đang đầy vì đâu | Không | Chỉ đọc. Đo từng loại rác và những thứ chiếm nhiều chỗ, ghi báo cáo. |
| Dọn rác của bạn | Không | File tạm cũ, báo cáo lỗi ứng dụng, bộ nhớ đệm trình duyệt của tài khoản đang dùng máy. |
| Dọn rác của Windows | Có | Windows\Temp cũ, file tải về của Windows Update, Delivery Optimization, báo cáo lỗi, nhật ký CBS cũ. |
| Dọn kho thành phần Windows (WinSxS) | Có | Phân tích rồi dọn bằng DISM, chỉ khi Windows khuyên dọn. |
| Mở Storage Sense | Không | Mở Settings > System > Storage để bật Windows tự dọn định kỳ. |

Nên chạy **Xem ổ C đang đầy vì đâu** trước. Cuối báo cáo có dòng chỉ nút nên chạy.

## Không bao giờ xoá

- Thùng rác, Windows.old, Downloads, Desktop, Documents, ảnh, video, mọi dữ liệu cá nhân.
- Mật khẩu, lịch sử, cookie, đăng nhập, tiện ích, dữ liệu trang web lưu ngoại tuyến (Service Worker) của trình duyệt.
- Windows\Minidump (bản ghi lỗi màn hình xanh dạng nhỏ, công cụ chẩn đoán cần).
- Junction, symlink: không đi theo, không xoá.
- File đang được dùng: để lại, chỉ đếm.

Mọi thư mục được dọn tính từ đường dẫn chuẩn của Windows (AppData\Local, Windows, ProgramData), không nhận đường dẫn gõ vào. Công cụ có danh sách thư mục được phép dọn và kiểm tra lại trước mỗi lần xoá. Biến TEMP trỏ ra chỗ khác thư mục tạm mặc định (vd `C:\Temp`) thì không dọn file tạm.

## Dọn những gì

| Mục | Ở đâu | Điều kiện |
|---|---|---|
| File tạm của bạn | `%TEMP%` (AppData\Local\Temp) | Ngày sửa và ngày tạo đều cũ hơn số ngày đã chọn (mặc định 7) |
| Báo cáo lỗi, bản ghi ứng dụng bị treo | AppData\Local\CrashDumps, ...\WER\ReportArchive, ReportQueue | Cũ hơn số ngày đã chọn |
| Bộ nhớ đệm trình duyệt | Chrome, Edge, Brave, Cốc Cốc: thư mục Cache, Code Cache, GPUCache, Dawn*Cache của từng hồ sơ, ShaderCache, GrShaderCache, GraphiteDawnCache. Firefox: cache2 | Trình duyệt đã tắt. Xoá hết, trình duyệt tự tải lại |
| File tạm của Windows | Windows\Temp | Cũ hơn số ngày đã chọn |
| File tải về của Windows Update | Windows\SoftwareDistribution\Download | Cũ hơn số ngày đã chọn; bỏ qua khi Windows đang cài cập nhật hoặc chờ khởi động lại |
| Delivery Optimization | Bộ nhớ đệm chia sẻ bản cập nhật giữa các máy | Xoá bằng lệnh của Windows `Delete-DeliveryOptimizationCache -Force` |
| Báo cáo lỗi của Windows | ProgramData\Microsoft\Windows\WER\ReportArchive, ReportQueue, Temp | Cũ hơn số ngày đã chọn |
| Nhật ký cài cập nhật cũ | Windows\Logs\CBS\CbsPersist_* (không đụng CBS.log) | Cũ hơn số ngày đã chọn |
| Bản ghi lỗi màn hình xanh (khi chọn) | Windows\MEMORY.DMP, *.dmp trong Windows\LiveKernelReports | Chỉ khi bật tuỳ chọn |

Thư mục con rỗng được xoá sau khi dọn, trừ thư mục mới tạo trong khoảng số ngày đã chọn (ứng dụng có thể đang dùng).

## 1. Xem ổ C đang đầy vì đâu

Chỉ đọc, dưới 1 phút. Báo cáo `ket_qua\BaoCao_DonOC_<tên máy>_<thời gian>.txt` gồm:

- Dung lượng trống, Storage Sense đang bật hay tắt.
- Rác của bạn, rác của Windows: từng mục, dung lượng dọn được, tổng của mục. Không có quyền Admin thì Windows\Temp hiện dấu `?` (cần quyền Admin để đo).
- **Chiếm nhiều chỗ, bạn tự quyết**: thùng rác, Windows.old, file ngủ đông, bộ nhớ ảo, điểm khôi phục (khi có quyền Admin), Zalo, Teams, bộ cài driver đã giải nén (`C:\AMD`, `C:\NVIDIA`, `C:\Intel`), Downloads, Desktop, Documents, Pictures, Videos, Music. Chỉ hiện mục từ 50 MB. Mỗi mục có cách xử lý; công cụ không xoá các mục này. Dấu `+` sau dung lượng: thư mục lớn, chưa đếm hết trong 10 giây.
- **Kết luận**: lỗi, cảnh báo (ổ gần đầy) rồi việc nên làm, mục lợi nhiều lên trước.

## 2. Dọn rác của bạn

1. Công cụ đo và in từng mục kèm dung lượng.
2. Gõ **C** để dọn, **K** để thôi (không có lựa chọn mặc định, Enter không làm gì).
3. Trình duyệt đang mở thì công cụ hỏi:
   - **T**: bạn tự đóng rồi, kiểm tra lại.
   - **D**: đóng giúp như bấm nút X; tiến trình chạy nền không có cửa sổ (Edge Startup boost) thì dừng. Trình duyệt mở lại các thẻ nếu đã bật "tiếp tục từ chỗ cũ".
   - **B**: bỏ qua, không dọn phần của trình duyệt đó.
4. In dung lượng đã dọn từng mục, số file đang dùng để lại, dung lượng trống trước và sau.

Phải chạy bằng chính tài khoản đang dùng máy. Cửa sổ chạy bằng một tài khoản Admin khác (UAC hỏi mật khẩu người khác) thì công cụ dừng, mã 2, vì sẽ dọn nhầm rác của tài khoản kia.

## 3. Dọn rác của Windows

Cần quyền Admin (Trạm Tool tự hỏi UAC). Cách chạy như mục 2. Công cụ không tạo điểm khôi phục cho nút này: chỉ xoá file tạm, điểm khôi phục không giúp lấy lại chúng.

- File tải về của Windows Update bị bỏ qua khi Windows đang cài cập nhật (tiến trình TiWorker đang chạy) hoặc đang chờ khởi động lại. Khởi động lại máy rồi chạy lại.
- Tuỳ chọn **Xoá cả bản ghi lỗi màn hình xanh**: MEMORY.DMP có thể vài GB. Giữ lại nếu còn cần gửi đi phân tích lỗi.

## 4. Dọn kho thành phần Windows (WinSxS)

1. Chạy `DISM /Online /Cleanup-Image /AnalyzeComponentStore`, in kích thước thật của kho, phần dùng chung với Windows, phần bản cũ, bộ nhớ đệm, số gói dọn được.
2. Windows không khuyên dọn thì dừng ở đây.
3. Windows khuyên dọn: gõ **C** để chạy `DISM /Online /Cleanup-Image /StartComponentCleanup`, 5-30 phút, đừng tắt máy.

Không dùng `/ResetBase`. Theo Microsoft, `/StartComponentCleanup` xoá ngay bản cũ của thành phần đã được cập nhật thay thế (Windows tự dọn thì chờ 30 ngày). `/ResetBase` mới làm các bản cập nhật đang cài không gỡ được nữa. Không bao giờ xoá tay thư mục WinSxS.

Không chạy khi Windows đang cài cập nhật hoặc chờ khởi động lại. DISM trả 3010 nghĩa là xong nhưng cần khởi động lại.

## 5. Storage Sense

Windows tự xoá file tạm và thùng rác cũ khi ổ sắp đầy (hoặc theo lịch). Bật ở Settings > System > Storage > Storage Sense. Trang công cụ trong Trạm hiện trạng thái Storage Sense.

## Mục bạn tự quyết

| Mục | Cách xử lý |
|---|---|
| Thùng rác | Mở Thùng rác, xem lại rồi bấm Empty Recycle Bin. |
| Windows.old | Dùng để quay về bản Windows trước, Windows tự xoá sau 10 ngày. Chắc không quay lại: Settings > System > Storage > Temporary files > Previous Windows installation(s). |
| hiberfil.sys | File ngủ đông. Không dùng Hibernate: trong cửa sổ Admin chạy `powercfg /h /type reduced` (nhỏ lại, vẫn khởi động nhanh) hoặc `powercfg /h off` (tắt hẳn, mất cả khởi động nhanh). |
| pagefile.sys | Bộ nhớ ảo, Windows tự quản lý. Không nên tắt. |
| Điểm khôi phục | Giữ lại để quay về khi Windows lỗi. Giảm giới hạn ở System Properties > System Protection > Configure. |
| Zalo | Xoá ảnh, video, file cũ trong cài đặt dữ liệu của Zalo. Không xoá tay thư mục ZaloData: mất tin nhắn lưu trên máy. |
| Microsoft Teams | Thoát hẳn Teams rồi xoá nội dung `%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams` theo hướng dẫn của Microsoft. Việc này xoá cả nhật ký chẩn đoán của Teams. |
| C:\AMD, C:\NVIDIA, C:\Intel | Bộ cài driver đã giải nén, cài xong thì xoá được. |
| Downloads, Desktop, Documents... | Dữ liệu cá nhân: xem lại, chuyển bớt sang ổ khác hoặc ổ ngoài. |

## Kết quả, nhật ký, mã thoát

- Báo cáo: `ket_qua\BaoCao_DonOC_<tên máy>_<thời gian>.txt`.
- Mỗi lần dọn thật ghi `ket_qua\NhatKy_DonOC_<tên máy>_<thời gian>.txt`: mục đã dọn, dung lượng, file để lại, dung lượng trống trước và sau. Chạy thử hoặc gõ K thì không ghi.
- Mỗi lần chạy (trừ khi gõ K) ghi `ket_qua\KetQua_DonOC_<chế độ>_<tên máy>_<thời gian>.json` theo chuẩn `tramtool.ketqua/1` (xem `docs\THEM-CONG-CU.md`) để Trạm Tool hiện kết quả: Xem ổ C có mã cho từng điều (`O_GAN_DAY`, `RAC_CUA_BAN` kèm nút dọn, mục từ 1 GB như `WINDOWS_OLD`, `FILE_NGU_DONG`, `DU_LIEU_ZALO`); các nút dọn ghi đã dọn bao nhiêu (`DA_DON`), mục lỗi (`DON_LOI`), file đang dùng để lại.
- Mã thoát: 0 xong; 1 lỗi; 2 thiếu điều kiện (thiếu quyền Admin, sai tài khoản, Windows đang cài cập nhật); 3 làm được một phần (có mục lỗi); 1223 bạn chọn không dọn hoặc từ chối UAC.

## Chạy không cần Trạm Tool

Bấm đúp `DON_O_C.bat` để mở menu. Mục cần quyền Admin tự hỏi UAC trong cửa sổ mới. Chạy thẳng một chế độ:

```bat
DON_O_C.bat -Mode kiem-tra
DON_O_C.bat -Mode don-cua-toi -SoNgay 14 -ChayThu
DON_O_C.bat -Mode don-he-thong -DumpLoi
DON_O_C.bat -Mode don-winsxs -ChayThu
```

| Tham số | Ý nghĩa |
|---|---|
| `-Mode` | `kiem-tra`, `don-cua-toi`, `don-he-thong`, `don-winsxs` |
| `-SoNgay` | Chỉ xoá file cũ hơn số ngày này (1-365, mặc định 7). Không áp dụng cho bộ nhớ đệm trình duyệt, Delivery Optimization, bản ghi lỗi màn hình xanh |
| `-DumpLoi` | `don-he-thong`: xoá cả MEMORY.DMP, LiveKernelReports |
| `-ChayThu` | Chỉ đo và in, không xoá. Không có quyền Admin thì chỉ đo phần đọc được |
| `-KhongDung` | Không chờ Enter khi xong |

Mã nguồn: `DonOC.ps1` (menu, chế độ, xin quyền Admin), `lib\Chung.ps1` (in, hỏi, đóng ứng dụng), `lib\Muc.ps1` (danh sách mục, thư mục được phép, đếm và xoá), `lib\Don.ps1` (các chế độ dọn, WinSxS), `lib\KiemTra.ps1` (báo cáo).

## Nguồn

- Microsoft, Clean up the WinSxS folder: https://learn.microsoft.com/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder
- Microsoft, Determine the actual size of the WinSxS folder: https://learn.microsoft.com/windows-hardware/manufacture/desktop/determine-the-actual-size-of-the-winsxs-folder
- Microsoft, Delete-DeliveryOptimizationCache: https://learn.microsoft.com/powershell/module/deliveryoptimization/delete-deliveryoptimizationcache
- Microsoft, Clear the Teams client cache: https://learn.microsoft.com/troubleshoot/microsoftteams/teams-administration/clear-teams-cache
