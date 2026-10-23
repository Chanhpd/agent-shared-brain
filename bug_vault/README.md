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
│   ├── pagination_load_more_vs_bulk_fetching.md
│   ├── network_image_disk_cache_and_retry_resilience.md
│   ├── category_navigation_in_memory_cache_and_race_condition.md
│   └── http_client_keep_alive_and_double_download_elimination.md
├── android/                             # Lỗi Android Native, ProGuard, ANR, Gradle, Splash
└── ios/                                 # Lỗi iOS, Pods, Privacy Manifest, ATT
```

## Danh Mục Các Node Đã Lưu Trữ

### Flutter
1. **[GoRouter Desynced Modal Pop & Double-Pop Completer Crash](flutter/gorouter_ghost_pop_and_double_pop_crash.md)**: Triệt tiêu lỗi Ghost Pop làm sập màn hình cha (`type bool is not a subtype...`) và lỗi Future already completed khi Back.
2. **[Clean Architecture Pagination & Load More Thay Thế Bulk Fetching](flutter/pagination_load_more_vs_bulk_fetching.md)**: Triệt tiêu lỗi fetch hàng loạt (`limit=100`) gây drop FPS và tràn RAM; chuẩn hóa phân trang 4 tầng, re-entrancy guard, khử trùng ID và nạp trước với ngưỡng `extentAfter < 400px`.
3. **[Image Network Fallback & Resilient Disk Caching](flutter/network_image_disk_cache_and_retry_resilience.md)**: Triệt tiêu lỗi ảnh nạp đồng loạt gây timeout/rớt về icon fallback vĩnh viễn, thiếu disk cache và không tự retry; chuẩn hóa `AppCachedNetworkImage`, queue 8 luồng và background retry có backoff.
4. **[Category Switch Latency, In-Memory Caching & Race Condition](flutter/category_navigation_in_memory_cache_and_race_condition.md)**: Triệt tiêu độ trễ mạng và race condition khi chuyển đổi category liên tục; chuẩn hóa In-Memory Session Cache 0ms, cờ `isCategoryLoading` kèm shimmer phản hồi UI tức thì và Request ID chống đè state.
5. **[Persistent HttpClient Keep-Alive, Double-Download & Stream Reset Elimination](flutter/http_client_keep_alive_and_double_download_elimination.md)**: Triệt tiêu độ trễ 2.5s – 3s tải ảnh Cloudflare R2 do hủy socket TLS liên tục, tải đúp 2 lần (NetworkImage + File I/O) và Stream Reset giữa chừng; chuẩn hóa Singleton HttpClient Keep-Alive, Pre-warm Disk Cache và rút ngắn reveal animation.

### Ads
1. **[Rewarded Format Mismatch & Fallback Strategy](ads/CASE_STUDY_REWARDED_FORMAT_MISMATCH.md)**: Xử lý lỗi Code 3 và lệch định dạng giữa RewardedAd và RewardedInterstitialAd.

### Android
1. **[Android Adaptive Launcher Icon Full Bleed](android/adaptive_launcher_icon_full_bleed.md)**: Xóa sổ viền trắng xấu xí, fix lỗi icon lọt thỏm/cắt cụt mép trên Android 8.0+ bằng cơ chế Adaptive Inset 16% tràn viền tuyệt đối.
2. **[R8 Full Mode & Android 13+ Parcelable Crash in RevenueCat Paywall](android/r8_android13_parcelable_revenuecat_paywall_npe.md)**: Triệt tiêu lỗi sập app Fatal Exception `NullPointerException: Class.isInterface()` khi mở Paywall/VIP trên bản Release Android 13+ do R8 strip mất EnclosingClass của Parcelable Creator; chuẩn hóa bộ đôi ProGuard keep rules và cờ `android.enableR8.fullMode=false`.
3. **[ARM Mali GPU Shader Compilation Stall & CPU Double-Buffering ANR Prevention](android/mali_gpu_shader_compile_anr_prevention.md)**: Triệt tiêu cụm lỗi ANR `cmpbe_v2_compile_multiple_shaders` và `nativePollOnce` trên GPU ARM Mali và thiết bị Android cấu hình thấp; chuẩn hóa chuyển đổi hardware `canvas.saveLayer` GPU FBO, loại bỏ CPU double-buffering 720 MB/s, gỡ bỏ `MaskFilter.blur` trên dynamic shader và đẩy IPC Clipboard sang Background Executor.

## Nguyên Tắc Hoạt Động
1. **Lập tài liệu ngay khi giải quyết xong:** Khi agent vừa fix xong một bug lạ hoặc người dùng yêu cầu "ghi lại bug này", một markdown note mới sẽ được tạo trong thư mục tương ứng.
2. **Kế thừa tri thức:** Khi bước vào một dự án mới, Agent có thể tra cứu nhanh thư mục này để phòng ngừa rủi ro ngay từ khâu thiết kế.
