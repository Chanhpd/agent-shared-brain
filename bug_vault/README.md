# Bug Vault (Agent Knowledge Nodes)

Nơi lưu trữ các **Agent Nodes** - bài học thực chiến, giải mã lỗi hiểm hóc (post-mortems) và kinh nghiệm xử lý lỗi dùng chung cho toàn bộ các dự án trong hệ thống.

---

## Cấu Trúc Thư Mục

```text
bug_vault/
├── TEMPLATE_BUG_NODE.md                 # Mẫu chuẩn khi tạo node mới
├── ads/                                 # Lỗi liên quan đến AdMob, UMP, Mediation, format mismatch
│   └── CASE_STUDY_REWARDED_FORMAT_MISMATCH.md
├── flutter/                             # Lỗi Flutter UI, Context, Navigation, Lifecycle
│   ├── gorouter_ghost_pop_and_double_pop_crash.md
│   └── pagination_load_more_vs_bulk_fetching.md
├── android/                             # Lỗi Android Native, ProGuard, ANR, Gradle, Splash
└── ios/                                 # Lỗi iOS, Pods, Privacy Manifest, ATT
```

## Danh Mục Các Node Đã Lưu Trữ

### Flutter
1. **[GoRouter Desynced Modal Pop & Double-Pop Completer Crash](flutter/gorouter_ghost_pop_and_double_pop_crash.md)**: Triệt tiêu lỗi Ghost Pop làm sập màn hình cha (`type bool is not a subtype...`) và lỗi Future already completed khi Back.
2. **[Clean Architecture Pagination & Load More Thay Thế Bulk Fetching](flutter/pagination_load_more_vs_bulk_fetching.md)**: Triệt tiêu lỗi fetch hàng loạt (`limit=100`) gây drop FPS và tràn RAM; chuẩn hóa phân trang 4 tầng, re-entrancy guard, khử trùng ID và nạp trước với ngưỡng `extentAfter < 400px`.

### Ads
1. **[Rewarded Format Mismatch & Fallback Strategy](ads/CASE_STUDY_REWARDED_FORMAT_MISMATCH.md)**: Xử lý lỗi Code 3 và lệch định dạng giữa RewardedAd và RewardedInterstitialAd.

### Android
1. **[Android Adaptive Launcher Icon Full Bleed](android/adaptive_launcher_icon_full_bleed.md)**: Xóa sổ viền trắng xấu xí, fix lỗi icon lọt thỏm/cắt cụt mép trên Android 8.0+ bằng cơ chế Adaptive Inset 16% tràn viền tuyệt đối.

## Nguyên Tắc Hoạt Động
1. **Lập tài liệu ngay khi giải quyết xong:** Khi agent vừa fix xong một bug lạ hoặc người dùng yêu cầu "ghi lại bug này", một markdown note mới sẽ được tạo trong thư mục tương ứng.
2. **Kế thừa tri thức:** Khi bước vào một dự án mới, Agent có thể tra cứu nhanh thư mục này để phòng ngừa rủi ro ngay từ khâu thiết kế.
