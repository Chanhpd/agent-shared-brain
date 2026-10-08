# Agent Shared Brain 🧠

> **Centralized Engineering Playbooks, Diagnostic Tools, and Agent Bug Nodes for Mobile Development (Flutter & Android/iOS).**

Repository tri thức và quy chuẩn dùng chung cho AI Agent (Antigravity / Claude Code / Codex) và Developer trong toàn bộ các dự án ứng dụng di động. Không phụ thuộc vào bất kỳ codebase cụ thể nào, hỗ trợ tra cứu quy chuẩn 2 chiều và tự động tích lũy kinh nghiệm thực chiến.

---

## 📂 Cấu Trúc Repository

```text
agent-shared-brain/
├── SKILL.md                          # Trái tim điều phối: Agent tự động nhận diện quy tắc & nhiệm vụ
├── README.md                         # Tài liệu hướng dẫn cài đặt & sử dụng
├── playbooks/                        # 1. BỘ QUY CHUẨN KỸ THUẬT (PLAYBOOKS)
│   ├── README.md
│   ├── 01_ADS_MONETIZATION_PLAYBOOK.md   # Show Rate >90%, eCPM, UMP Fail-Open 3s, Native Ad 0s latency
│   ├── 02_ANR_ARN_PREVENTION_PLAYBOOK.md # Triệt tiêu ANR/ARN 0.00%, Android Vitals an toàn (<0.47%)
│   └── 03_PERFORMANCE_OPTIMIZATION_PLAYBOOK.md # Tối ưu 60 FPS, Quản lý Bitmap, Isolate, Memory
│
├── tools/                            # 2. CÔNG CỤ CHẨN ĐOÁN ĐỘC LẬP (STANDALONE TOOLS)
│   ├── README.md
│   ├── admob_diagnostic_runner.dart  # Runner kiểm tra Ad Unit IDs trực tiếp trên thiết bị (0s dependencies)
│   └── GUIDE_DIAGNOSE_ADMOB_UNIT_IDS.md # Hướng dẫn sử dụng & bảng giải mã Error Code AdMob
│
├── bug_vault/                        # 3. KHO TRI THỨC AGENT NODES (LESSONS LEARNED)
│   ├── README.md
│   ├── TEMPLATE_BUG_NODE.md          # Mẫu chuẩn ghi nhận lỗi
│   ├── ads/                          # Các ca xử lý lỗi Ads thực chiến (Format mismatch, DNS delay...)
│   │   └── CASE_STUDY_REWARDED_FORMAT_MISMATCH.md
│   ├── flutter/                      # Lỗi UI, Context, PlatformViews, Memory leak
│   ├── android/                      # Lỗi Native Android, ProGuard, Splash ANR
│   └── ios/                          # Lỗi Native iOS, Pods, Privacy Manifest
│
└── scripts/                          # 4. TIỆN ÍCH TỰ ĐỘNG HÓA
    └── sync.sh                       # Đồng bộ pull/push nhanh chóng
```

---

## 🚀 Cách Cài Đặt Cho AI Agent

### Cách 1: Cài đặt Toàn Cục (Global - Khuyên dùng)
Áp dụng tự động cho **TẤT CẢ** các dự án mở trên máy tính của bạn mà không cần copy hay sửa đổi gì trong từng repo code:

```bash
# Clone thẳng vào thư mục Global Customizations của Antigravity
git clone https://github.com/Chanhpd/agent-shared-brain.git ~/.gemini/config/skills/agent-shared-brain
```

### Cách 2: Cài đặt Theo Từng Dự Án (Workspace Local)
Nếu muốn gắn trực tiếp vào một dự án cụ thể mà không đẩy vào git của dự án đó:

```bash
cd /path/to/your/project
mkdir -p .agents/skills
git clone https://github.com/Chanhpd/agent-shared-brain.git .agents/skills/agent-shared-brain

# Đảm bảo .agents/ đã nằm trong .gitignore của dự án chính
```

---

## 💡 Cách Sử Dụng Trong Thực Tế

### 1. Khi Chuẩn Bị Implement Tính Năng / Ads / Tối Ưu
Chỉ cần chat với Agent:
> *"Tôi muốn thêm Native Ad vào màn hình Home và Interstitial ở nút Back, hãy kiểm tra rule Ads và chống ANR từ shared-brain trước nhé."*
$\rightarrow$ Agent sẽ tự động đọc `playbooks/` và tuân thủ các quy tắc:
- Không eager-load Native Ad, dùng Viewport trigger $\le 400\text{px}$.
- Cố định static slot key, không re-request khi đổi tab.
- Re-entrancy Lock ở nút Back, an toàn unmount.

### 2. Khi Gặp Lỗi Ads Trên Thiết Bị Thật
Chỉ cần chat với Agent:
> *"Ads trên bản Release APK không hiện, hãy dùng tool chuẩn đoán kiểm tra các Ad Unit ID này giúp tôi."*
$\rightarrow$ Agent sẽ hướng dẫn hoặc cấu hình `tools/admob_diagnostic_runner.dart` để chạy đối chứng chéo định dạng và trả về kết luận chính xác 100% trong 10 giây.

### 3. Khi Giải Quyết Xong Một Lỗi Chung (Ghi Agent Node)
Chỉ cần chat với Agent:
> *"Lỗi này do cấu hình ProGuard làm mất class JNI, ghi lại bài học này vào Agent Node nhé."*
$\rightarrow$ Agent sẽ tự tạo file markdown trong `bug_vault/` theo template chuẩn và commit push lên GitHub để các dự án sau tự động được hưởng lợi!

---

## 👨‍💻 Tác giả & Đóng góp
- Repository: [https://github.com/Chanhpd/agent-shared-brain](https://github.com/Chanhpd/agent-shared-brain)
- Maintainer: **Chanhpd** (`phamduychanh1904@gmail.com`)
