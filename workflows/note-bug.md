---
description: "Ghi nhận bài học/lỗi mới vào Agent Node Vault & tự động push lên GitHub"
---

# Quy Trình Ghi Nhận Bài Học / Bug Mới Vào Agent Node

Quy trình tự động hóa việc đúc kết kinh nghiệm sau khi giải quyết một vấn đề kỹ thuật và lưu vào tri thức chung của team.

## Các bước thực hiện:

1. **Tổng hợp thông tin lỗi:**
   - Nếu vừa fix xong bug trong cuộc hội thoại: Tự động trích xuất thông tin.
   - Nếu người dùng cung cấp thông tin mới: Hỏi nhanh các chi tiết còn thiếu.

2. **Soạn thảo Agent Node:**
   - Phân loại thư mục: `bug_vault/ads/`, `bug_vault/flutter/`, `bug_vault/android/`, `bug_vault/ios/`.
   - Tạo file markdown theo chuẩn `bug_vault/TEMPLATE_BUG_NODE.md`:
     - **Triệu chứng (Symptom & Error Logs)**
     - **Nguyên nhân gốc rễ (Root Cause)**
     - **Giải pháp triệt để (Verified Solution)**
     - **Checklist phòng ngừa (Prevention Checklist)**
     - **Dự án phát hiện & Môi trường**

3. **Lưu file & Push lên GitHub:**
   - Ghi file vào thư mục `bug_vault/<category>/<tên_lỗi>.md`.
   - Chạy lệnh git commit & push:
     ```bash
     git -C .agents/skills/agent-shared-brain add .
     git -C .agents/skills/agent-shared-brain commit -m "docs(vault): record <tên_lỗi>"
     git -C .agents/skills/agent-shared-brain push origin main
     ```

4. **Báo cáo hoàn tất:**
   - Gửi thông báo kèm link GitHub trực tiếp tới file bài học vừa tạo.
