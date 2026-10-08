# Template: Agent Bug Node / Post-Mortem

Dùng template này để ghi nhận các lỗi chung (generic bugs) nhằm lưu giữ vào tri thức tập thể.

---

# [TÊN_VẤN_ĐỀ_HOẶC_LỖI]

- **Ngày ghi nhận:** YYYY-MM-DD
- **Phân loại:** Ads / Flutter / Android / iOS / Performance / Network
- **Mức độ nghiêm trọng:** Blocker / Critical / Major / Minor
- **Dự án phát hiện lần đầu:** [Tên App, ví dụ: Clock Watch, App Keyboard]
- **Môi trường:** Máy thật / Máy ảo / Release APK / Debug / iOS Device

---

## 1. Triệu Chứng (Symptom & Error Logs)
Mô tả hiện tượng người dùng hoặc developer quan sát thấy.
Dán error stack trace / logcat nếu có:
```
[Dán error log tại đây]
```

## 2. Nguyên Nhân Gốc Rễ (Root Cause)
Phân tích tại sao lỗi xảy ra (bản chất tầng hệ điều hành, SDK, hoặc kiến trúc Flutter):
- Điểm mấu chốt gây ra sự cố.
- Tại sao trên debug/máy ảo không thấy nhưng trên production/máy thật lại bị?

## 3. Giải Pháp Đã Xác Thực (Verified Solution)
Cách giải quyết triệt để vấn đề:

### Code Snippet / Configuration Fix:
```dart
// Code mẫu sửa lỗi
```

### Các bước can thiệp (nếu có cấu hình Console / ProGuard / Gradle):
1. Bước 1...
2. Bước 2...

## 4. Checklist Phòng Ngừa (Prevention Checklist)
Danh sách câu hỏi cần tự kiểm tra để không bao giờ bị lại ở các dự án tiếp theo:
- [ ] Checklist item 1
- [ ] Checklist item 2
- [ ] Checklist item 3

## 5. Tài Liệu Tham Khảo (References)
- Link Google Developers / Flutter Issue / AdMob Help Center
