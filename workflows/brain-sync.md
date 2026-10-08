---
description: "Đồng bộ kiến thức & quy chuẩn mới nhất từ repo agent-shared-brain"
---

# Quy Trình Đồng Bộ Kiến Thức Từ GitHub

Quy trình cập nhật các playbooks và bài học mới nhất được chia sẻ từ repository `agent-shared-brain`.

## Các bước thực hiện:

1. **Thực hiện kéo dữ liệu mới:**
   ```bash
   git -C .agents/skills/agent-shared-brain pull --rebase origin main
   ```

2. **Kiểm tra các thay đổi mới:**
   - Liệt kê các file vừa được cập nhật trong `playbooks/` hoặc `bug_vault/`.

3. **Báo cáo tóm tắt:**
   - Thông báo cho người dùng các bài học hoặc quy chuẩn mới vừa được đồng bộ về máy.
