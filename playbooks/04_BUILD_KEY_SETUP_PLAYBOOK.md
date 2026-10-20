# CẨM NANG THIẾT LẬP RELEASE SIGNING KEY CHUẨN HÓA (BUILD KEY SETUP PLAYBOOK)
> **Dự án áp dụng:** Mọi ứng dụng Flutter & Android Native trong hệ sinh thái (`app-theme-pack`, `clock-watch-app`, `wallpaper_app`,...)  
> **Mục tiêu:** Thiết lập quy trình ký số Release (AAB / APK) tự động, an toàn và đồng nhất; tự động dò tìm và đồng bộ bộ khóa từ dự án mẫu `app-keyboard` sang dự án mới; cấu hình Gradle (Kotlin DSL & Groovy DSL) chuẩn xác; bảo vệ tuyệt đối không bao giờ để lộ key lên GitHub.

---

## 📌 MỤC LỤC
1. [Nguyên Tắc Bất Di Bất Dịch Về Bảo Mật Key](#1-nguyên-tắc-bất-di-bất-dịch-về-bảo-mật-key)
2. [Cấu Trúc Bộ Khóa Ký Release Chuẩn](#2-cấu-trúc-bộ-khóa-ký-release-chuẩn)
3. [Quy Trình Tự Động Hóa 1-Lệnh (One-Command Automation)](#3-quy-trình-tự-động-hóa-1-lệnh-one-command-automation)
4. [Cơ Chế Tự Động Dò Tìm Source Key (Auto-Discovery Engine)](#4-cơ-chế-tự-động-dò-tìm-source-key-auto-discovery-engine)
5. [Cấu Hình Gradle Chuẩn Hóa: Kotlin DSL (`build.gradle.kts`)](#5-cấu-hình-gradle-chuẩn-hóa-kotlin-dsl-buildgradlekts)
6. [Cấu Hình Gradle Chuẩn Hóa: Groovy DSL (`build.gradle`)](#6-cấu-hình-gradle-chuẩn-hóa-groovy-dsl-buildgradle)
7. [Bảo Vệ Git Chống Lộ Key (.gitignore Standard)](#7-bảo-vệ-git-chống-lộ-key-gitignore-standard)
8. [Quy Trình Kiểm Tra & Build Release](#8-quy-trình-kiểm-tra--build-release)
9. [Xử Lý Sự Cố Thường Gặp (Troubleshooting)](#9-xử-lý-sự-cố-thường-gặp-troubleshooting)

---

## 1. Nguyên Tắc Bất Di Bất Dịch Về Bảo Mật Key

> [!CAUTION]
> **TUYỆT ĐỐI KHÔNG COMMIT KEY LÊN GITHUB HOẶC BẤT KỲ REMOTE REPOSITORY NÀO!**  
> Việc để lộ file Keystore (`.jks`, `.keystore`) hoặc `key.properties` (chứa mật khẩu dạng plain text) có thể dẫn đến việc ứng dụng bị hijack mã độc, mất quyền cập nhật trên Google Play Store và vi phạm nghiêm trọng chính sách bảo mật.

1. **Chỉ chia sẻ qua kênh cục bộ nội bộ (Local-Only):**
   - Bộ tài liệu này và công cụ `setup_signing_keys.sh` chỉ lưu trữ **logic điều hướng và tự động hóa**.
   - Khóa thực tế được máy tính nhà phát triển tự động copy từ dự án mẫu (`app-keyboard`) sang dự án mới.
2. **Double-Layer Git Ignore (Bảo vệ 2 tầng):**
   - Luôn khai báo ignore file key ở cả `android/.gitignore` VÀ root `.gitignore`.
3. **Graceful Fallback khi thiếu Key:**
   - Trong `build.gradle(.kts)`, nếu không tìm thấy file `key.properties` (ví dụ trên môi trường CI/CD mới hoặc máy lập trình viên chưa setup key), Gradle **tự động fallback sang signing debug** thay vì làm vỡ build:
     ```kotlin
     signingConfig = if (keystorePropertiesFile.exists()) {
         signingConfigs.getByName("release")
     } else {
         signingConfigs.getByName("debug")
     }
     ```

---

## 2. Cấu Trúc Bộ Khóa Ký Release Chuẩn

Mô hình chuẩn hóa được trích xuất từ dự án gốc `app-keyboard` gồm 2 file trọng yếu:

```
<project-root>/
├── android/
│   ├── key.properties               <-- Chứa alias và mật khẩu truy cập keystore
│   ├── .gitignore                   <-- Khai báo bỏ qua key.properties & *.jks
│   └── app/
│       ├── build.gradle.kts         <-- Cấu hình signingConfigs.release
│       └── upload-keystore.jks      <-- Keystore nhị phân dùng để ký AAB/APK
└── .gitignore                       <-- Khai báo bảo vệ tầng root
```

### 2.1. Định dạng file `android/key.properties`
```properties
storePassword=Thuan31188@
keyPassword=Thuan31188@
keyAlias=upload
storeFile=upload-keystore.jks
```

* **`storePassword`**: Mật khẩu bảo vệ kho khóa Keystore.
* **`keyPassword`**: Mật khẩu bảo vệ khóa ký (Key Entry).
* **`keyAlias`**: Tên định danh của khóa ký bên trong Keystore (chuẩn: `upload`).
* **`storeFile`**: Tên file keystore tương đối (nằm tại thư mục `android/app/upload-keystore.jks`).

---

## 3. Quy Trình Tự Động Hóa 1-Lệnh (One-Command Automation)

Để áp dụng bộ key build và cấu hình Gradle cho một dự án mới chỉ trong 2 giây:

### Cách 1: Chạy từ thư mục gốc của dự án cần setup (Khuyên dùng)
```bash
# Di chuyển vào thư mục dự án mới (ví dụ: app-theme-pack)
cd /Users/inhouse/app-theme-pack

# Chạy script tự động hóa từ agent-shared-brain
bash ~/.gemini/config/skills/agent-shared-brain/scripts/setup_signing_keys.sh
```

### Cách 2: Truyền đường dẫn dự án đích tường minh
```bash
bash ~/.gemini/config/skills/agent-shared-brain/scripts/setup_signing_keys.sh /Users/inhouse/app-theme-pack
```

### Những gì script sẽ tự động thực hiện:
1. 🔍 **Tự động quét và định vị** thư mục nguồn `app-keyboard` trên máy của bạn.
2. 📦 **Copy 2 file thiết yếu**:
   - `app-keyboard/android/key.properties` $\rightarrow$ `<target>/android/key.properties`
   - `app-keyboard/android/app/upload-keystore.jks` $\rightarrow$ `<target>/android/app/upload-keystore.jks`
3. 🔒 **Thiết lập quyền file an toàn** (`chmod 600`) cho các file khóa.
4. 🛡️ **Kiểm tra và cập nhật file `.gitignore`** ở cả thư mục `android/` và root project.
5. ⚙️ **Tự động cập nhật `build.gradle.kts` (hoặc `build.gradle`)**:
   - Thêm import `FileInputStream` và `Properties`.
   - Nạp `key.properties`.
   - Tạo `signingConfigs.release`.
   - Gán `signingConfig` cho `buildTypes.release` có fallback an toàn.
   - Tạo file backup `build.gradle(.kts).bak` đề phòng cần hoàn tác.

---

## 4. Cơ Chế Tự Động Dò Tìm Source Key (Auto-Discovery Engine)

Khi chạy script hoặc thiết lập thủ công, engine tìm kiếm `app-keyboard` theo thứ tự ưu tiên sau:

```
[Target Project]
       │
       ▼ (1) Tham số dòng lệnh chỉ định ($2)
       │
       ▼ (2) Biến môi trường $APP_KEYBOARD_DIR
       │
       ▼ (3) Thư mục ngang hàng: ../app-keyboard
       │
       ▼ (4) Đường dẫn chuẩn máy dev: /Users/inhouse/app-keyboard
       │
       ▼ (5) Thư mục Workspace người dùng: $HOME/inhouse/app-keyboard hoặc $HOME/app-keyboard
       │
       ▼ (6) Quét tự động các thư mục con trong cùng thư mục cha
```

Nếu tìm thấy thư mục có đầy đủ cả `android/key.properties` và `android/app/upload-keystore.jks`, hệ thống lập tức khóa nguồn và tiến hành đồng bộ.

---

## 5. Cấu Hình Gradle Chuẩn Hóa: Kotlin DSL (`build.gradle.kts`)

Đối với các dự án Flutter phiên bản mới (Flutter 3.20+), file cấu hình là `android/app/build.gradle.kts`.

### 5.1. Khối Import & Nạp Thuộc Tính (Đặt ở đầu file)
```kotlin
// android/app/build.gradle.kts
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Nạp file cấu hình signing key nếu tồn tại
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

### 5.2. Khối `signingConfigs` & `buildTypes` (Bên trong `android { ... }`)
```kotlin
android {
    ...
    defaultConfig {
        ...
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String
            keyPassword = keystoreProperties["keyPassword"] as? String
            storeFile = (keystoreProperties["storeFile"] as? String)?.let {
                val f = file(it)
                if (f.exists()) f else rootProject.file(it)
            }
            storePassword = keystoreProperties["storePassword"] as? String
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // Tự động dùng release key nếu có, nếu chưa setup thì fallback sang debug key
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

> [!TIP]
> Điểm tinh tế ở logic `storeFile`:
> `val f = file(it); if (f.exists()) f else rootProject.file(it)`
> Giúp Gradle giải quyết đường dẫn chính xác bất kể `storeFile` được khai báo dạng tương đối từ thư mục `android/app` hay từ root project `android/`.

---

## 6. Cấu Hình Gradle Chuẩn Hóa: Groovy DSL (`build.gradle`)

Đối với các dự án Flutter cũ hơn dùng `android/app/build.gradle` (Groovy):

```groovy
// android/app/build.gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        release {
            keyAlias = keystoreProperties['keyAlias']
            keyPassword = keystoreProperties['keyPassword']
            storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword = keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

---

## 7. Bảo Vệ Git Chống Lộ Key (.gitignore Standard)

Kiểm tra 2 file `.gitignore` để đảm bảo key không bao giờ bị đưa vào Staging:

### 7.1. File `android/.gitignore`
Thêm các dòng sau vào cuối file `android/.gitignore`:
```gitignore
# Release signing keys & keystores (NEVER commit to git)
key.properties
**/*.keystore
**/*.jks
```

### 7.2. File `.gitignore` tại thư mục gốc dự án
```gitignore
# Keystore & Android signing
**/key.properties
**/*.keystore
**/*.jks
```

### 7.3. Lệnh kiểm tra an toàn trước khi commit
Sau khi setup, chạy lệnh sau trong terminal của dự án để kiểm chứng:
```bash
git status --ignored
```
Nếu thấy `android/key.properties` và `android/app/upload-keystore.jks` nằm trong mục **Ignored files** (màu xám / bị bỏ qua) $\rightarrow$ **Cực kỳ an toàn**.

---

## 8. Quy Trình Kiểm Tra & Build Release

### 8.1. Kiểm Tra Tính Toàn Vẹn Của Keystore Bằng `keytool`
Chạy lệnh kiểm tra mật khẩu và alias trong Keystore:
```bash
keytool -list -v \
  -keystore android/app/upload-keystore.jks \
  -alias upload \
  -storepass Thuan31188@
```
Nếu terminal hiển thị thông tin chứng chỉ:
`Alias name: upload`  
`Owner: CN=...`  
`Certificate fingerprints: SHA-1, SHA-256`  
$\rightarrow$ Keystore hợp lệ 100%.

### 8.2. Build App Bundle (`.aab`) Cho Google Play Store
```bash
flutter build appbundle --release
```
Hoặc dùng script build thống nhất của dự án:
```bash
./scripts/build_release.sh --target appbundle
```

### 8.3. Build APK Cài Đặt Thử Nghiệm (`.apk`)
```bash
flutter build apk --release
```

### 8.4. Kiểm Tra Chữ Ký Số Của File Build Đầu Ra
Xác thực gói phát hành thực sự được ký bởi `upload` key:
```bash
# Kiểm tra AAB:
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab

# Hoặc kiểm tra APK:
$ANDROID_HOME/build-tools/<version>/apksigner verify --verbose build/app/outputs/flutter-apk/app-release.apk
```

---

## 9. Xử Lý Sự Cố Thường Gặp (Troubleshooting)

| Sự Cố (Error) | Nguyên Nhân Gốc Rễ | Cách Khắc Phục |
|:---|:---|:---|
| `Keystore file ... not found for signing config 'release'` | Đường dẫn `storeFile` sai hoặc chưa copy `upload-keystore.jks` vào `android/app/`. | Đảm bảo file `upload-keystore.jks` nằm tại `android/app/` và cấu hình `storeFile` có fallback `file(it)` hoặc `rootProject.file(it)`. |
| `Keystore was tampered with, or password was incorrect` | Sai mật khẩu `storePassword` trong `android/key.properties`. | Kiểm tra lại mật khẩu chuẩn: `Thuan31188@`. |
| `Cannot recover key` | `keyPassword` khác với `storePassword` hoặc gõ sai mật khẩu key entry. | Kiểm tra cả `storePassword` và `keyPassword` trong `key.properties`. |
| `AAB signed with debug key instead of release` | Chưa copy file `key.properties` hoặc file đặt sai thư mục (phải ở `android/key.properties`, không phải `android/app/`). | Đảm bảo `key.properties` nằm ngay dưới thư mục `android/`. |
| `Import statements must appear before any top-level expressions` | Trong `build.gradle.kts`, đặt `import java.io.FileInputStream` phía sau `plugins { ... }`. | Chuyển toàn bộ các dòng `import` lên dòng 1 và 2 ở đầu file `build.gradle.kts`. |

---

## 10. Tóm Tắt Quy Trình Chuẩn Cho Mọi Dự Án Mới
1. Tạo dự án mới hoặc mở dự án chưa có key.
2. Chạy: `bash ~/.gemini/config/skills/agent-shared-brain/scripts/setup_signing_keys.sh`
3. Kiểm tra: `git status` đảm bảo key không bị track.
4. Chạy: `flutter build appbundle --release` $\rightarrow$ Hoàn thành xuất xưởng!
