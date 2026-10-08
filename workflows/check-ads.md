---
description: "Kiểm tra quy chuẩn Ads & chống ANR từ shared-brain trước khi code/review"
---

# Quy Trình Kiểm Tra Quy Chuẩn Ads & Phòng Ngừa ANR

Quy trình này giúp kiểm tra code hoặc kế hoạch triển khai quảng cáo có tuân thủ bộ quy chuẩn trong `agent-shared-brain` hay không.

## Các bước thực hiện:

1. **Xác định phạm vi:**
   - Hỏi hoặc quét màn hình / widget mà người dùng đang làm việc (hoặc xem file đang mở).

2. **Tra cứu quy chuẩn trong Playbook:**
   - Đọc `playbooks/01_ADS_MONETIZATION_PLAYBOOK.md`
   - Đọc `playbooks/02_ANR_ARN_PREVENTION_PLAYBOOK.md`

3. **Audit code đối chiếu 10 Quy Tắc Vàng:**
   - [ ] **Native Ad:** Có dùng Viewport Visibility Trigger ($\le 400\text{px}$) không? Tuyệt đối không eager-load trong ListView/GridView.
   - [ ] **SlotKey:** Có tĩnh theo vị trí (static slot key) không? Không dùng biến động làm đổi key gây spam request.
   - [ ] **Vòng đời Native Ad:** `disposeOnUnmount` mặc định là `false` để giữ trong RAM? Nếu hủy có bọc trong `WidgetsBinding.instance.addPostFrameCallback` không?
   - [ ] **Nút Back / Action:** Có cài đặt Re-entrancy Lock (`_isNavigatingWithAd`) để chống spam click không?
   - [ ] **Timeout:** Có đặt Adaptive Timeout 8–10 giây cho Interstitial/Rewarded không?
   - [ ] **Google UMP:** Khởi tạo ads theo thứ tự chuẩn sau khi consent được phân giải chưa? Có cơ chế Fail-Open 3s không?
   - [ ] **Android Vitals:** Đã bật 2 cờ `OPTIMIZE_INITIALIZATION` và `OPTIMIZE_AD_LOADING` trong `AndroidManifest.xml` chưa? Không chạy disk I/O trên Main Thread.

4. **Báo cáo & Đề xuất code:**
   - Chỉ rõ điểm đạt và chưa đạt.
   - Cung cấp code mẫu đã chuẩn hóa sẵn sàng copy vào dự án.
