---
name: agent-shared-brain
description: >-
  Bộ quy chuẩn kỹ thuật dùng chung cho mọi dự án: Playbooks (Ads Show Rate >90%, Triệt tiêu ANR/ARN 0.00%, Tối ưu 60 FPS), 
  công cụ chẩn đoán AdMob Ad Unit ID độc lập, và kho tri thức Agent Nodes (Bug Vault / Post-mortems) để không bao giờ lặp lại lỗi cũ.
  Kích hoạt khi: implement hoặc debug Ads/ANR/Vitals, chạy chẩn đoán Ad Unit ID, review code theo quy chuẩn, 
  hoặc khi người dùng yêu cầu "lưu lỗi này vào playbook / ghi agent node".
---

# Agent Shared Brain & Playbooks Engine

Repository tri thức tập trung: [agent-shared-brain](https://github.com/Chanhpd/agent-shared-brain)

---

## 1. Mục Đích & Năng Lực Cốt Lõi

1. **Tuân thủ Playbook Kỹ Thuật (Engineering Playbooks):**
   - Đảm bảo tỷ lệ hiển thị quảng cáo (Show Rate) > 90%, Match Rate cao, eCPM tối ưu.
   - Triệt tiêu lỗi ANR/ARN (Application Not Responding) đạt ngưỡng an toàn Android Vitals (< 0.47%).
   - Tối ưu hiệu năng 60 FPS, quản lý bộ nhớ Bitmap, vòng đời ứng dụng.

2. **Chẩn Đoán Trực Tiếp Ad Unit ID (Standalone Diagnostic Runner):**
   - Kiểm tra tính hợp lệ của Ad Unit ID AdMob độc lập 100% không qua logic phức tạp của app.
   - Đối chứng chéo định dạng (RewardedAd vs RewardedInterstitialAd) để bắt lỗi sai format (Code 3).

3. **Lưu Trữ & Tái Sử Dụng Bài Học Thực Chiến (Bug Vault / Agent Nodes):**
   - Khi dự án A gặp và xử lý xong một lỗi chung (generic bug) -> Tự động ghi vào `bug_vault/`.
   - Khi sang dự án B -> Tra cứu trước để phòng tránh, không lặp lại sai lầm.

---

## 2. Quy Trình Kích Hoạt Khi Implement Chức Năng

Khi người dùng yêu cầu implement liên quan đến Ads, Lifecycle, ANR, hoặc Performance:

### Bước 1: Tra cứu Playbook tương ứng trong `playbooks/`
- **Ads & Monetization:** Đọc `playbooks/01_ADS_MONETIZATION_PLAYBOOK.md`
  - Tuân thủ 10 quy tắc sống còn (không eager-load Native Ad, static slot key, adaptive timeout 8-10s, UMP fail-open 3s, không cross-format fallback).
- **ANR & Vitals:** Đọc `playbooks/02_ANR_ARN_PREVENTION_PLAYBOOK.md`
  - Bật cờ tối ưu `OPTIMIZE_INITIALIZATION` & `OPTIMIZE_AD_LOADING` trong `AndroidManifest.xml`.
  - Không I/O hay font loading trên Main Thread, dùng SingleThreadExecutor cho Disk I/O.
  - Bọc `PlatformViewsController resize race` filter trong `main.dart`.
- **Performance & FPS:** Đọc `playbooks/03_PERFORMANCE_OPTIMIZATION_PLAYBOOK.md`
  - Tái sử dụng Matrix, không khởi tạo object trong `onDraw`/`paint()`, offload tác vụ nặng sang `compute()` / `Isolate`.

### Bước 2: Tra cứu các lỗi đã lưu trong `bug_vault/`
- Tra cứu nhanh các case study trong thư mục `bug_vault/<category>/` để tránh các bẫy đã từng gặp.

---

## 3. Quy Trình Chẩn Đoán Ad Unit ID AdMob

Khi người dùng phản ánh:
- *"Ads không load được trên máy thật / release APK"*
- *"Lỗi No-Fill, Code 3, videoAdUnavailable"*
- *"Cần kiểm tra xem Ad Unit ID đã active chưa"*

### Hành động:
1. Đọc hướng dẫn chi tiết tại `tools/GUIDE_DIAGNOSE_ADMOB_UNIT_IDS.md`.
2. Hướng dẫn hoặc cấu hình `tools/admob_diagnostic_runner.dart` với danh sách Ad Unit IDs cần test.
3. Chạy lệnh:
   ```bash
   flutter run -t tools/admob_diagnostic_runner.dart
   ```
4. Đọc kết quả trên màn hình chẩn đoán hoặc Logcat:
   - Nếu `RewardedAd` thất bại với *"Ad unit doesn't match format"* nhưng `RewardedInterstitialAd` thành công $\rightarrow$ **Format Mismatch trên AdMob Console**.
   - Nếu trả về `Code 3 ERROR_CODE_NO_FILL` $\rightarrow$ Chưa lan truyền DNS hoặc eCPM Floor quá cao.
   - Nếu trả về `Code 1 INVALID_REQUEST` $\rightarrow$ Sai App ID hoặc format chuỗi.

---

## 4. Quy Trình Ghi Nhận Lỗi Mới Vào "Agent Node" (Bug Vault)

Khi người dùng yêu cầu:
- *"Lưu lỗi này vào playbook / ghi agent node"*
- *"Ghi lại bug này để sau này sang dự án khác nhớ"*
- Hoặc Agent vừa giải quyết một vấn đề kỹ thuật có tính tái sử dụng cao.

### Các bước thực hiện:
1. Xác định phân loại thư mục:
   - `bug_vault/ads/`: Lỗi liên quan đến AdMob, UMP, Mediation, format mismatch, timeout.
   - `bug_vault/flutter/`: Lỗi vòng đời widget, context, navigation, PlatformView, animation leak.
   - `bug_vault/android/`: Lỗi native Android, Gradle, ProGuard/R8, ANR main thread, permissions.
   - `bug_vault/ios/`: Lỗi Pod, Apple privacy manifest, ATT, App Tracking.

2. Tạo file markdown theo format từ `bug_vault/TEMPLATE_BUG_NODE.md`:
   - **Tên file:** `<tên_ngắn_mô_tả_vấn_đề>.md` (ví dụ `bug_vault/ads/admob_v23_init_main_thread_anr.md`).
   - Ghi đầy đủ 5 mục cốt lõi:
     - **Triệu chứng (Symptom & Log)**
     - **Nguyên nhân gốc rễ (Root Cause)**
     - **Giải pháp triệt để (Solution & Code Diff)**
     - **Checklist phòng ngừa (Prevention Checklist)**
     - **Bối cảnh & Dự án đã gặp (Context & Project)**

3. Commit & Push lên GitHub repository:
   ```bash
   git -C path/to/agent-shared-brain add .
   git -C path/to/agent-shared-brain commit -m "docs(vault): record <tên_lỗi>"
   git -C path/to/agent-shared-brain push origin main
   ```
