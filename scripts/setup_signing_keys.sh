#!/usr/bin/env bash
# ==============================================================================
# SCRIPT TỰ ĐỘNG THIẾT LẬP RELEASE SIGNING KEY TỪ APP-KEYBOARD
# Dùng chung cho mọi dự án Flutter trong hệ thống (agent-shared-brain)
# ==============================================================================
set -e

# Màu hiển thị terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}==============================================================${NC}"
echo -e "${CYAN}${BOLD}       FLUTTER RELEASE SIGNING KEY AUTO-SETUP SCRIPT           ${NC}"
echo -e "${CYAN}${BOLD}==============================================================${NC}"

# 1. Xác định Target Project (Dự án cần áp dụng key)
TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)"

if [[ ! -f "$TARGET_DIR/pubspec.yaml" || ! -d "$TARGET_DIR/android" ]]; then
    echo -e "${RED}❌ Lỗi: Thư mục target không phải là Flutter project hợp lệ!${NC}"
    echo -e "   Target path: $TARGET_DIR"
    echo -e "   Vui lòng 'cd' vào thư mục gốc của Flutter project hoặc truyền đường dẫn làm tham số:"
    echo -e "   Ví dụ: $0 /path/to/your-flutter-app"
    exit 1
fi

APP_NAME=$(grep -E '^name:' "$TARGET_DIR/pubspec.yaml" | head -n 1 | awk '{print $2}' | tr -d ' "\r')
echo -e "${BLUE}🎯 Dự án đích (Target):${NC} ${BOLD}$APP_NAME${NC} ($TARGET_DIR)"

# 2. Dò tìm thư mục nguồn app-keyboard
SRC_KEYBOARD=""

# Danh sách ứng viên tìm kiếm
CANDIDATES=(
    "$2"
    "$APP_KEYBOARD_DIR"
    "$TARGET_DIR/../app-keyboard"
    "/Users/inhouse/app-keyboard"
    "$HOME/inhouse/app-keyboard"
    "$HOME/app-keyboard"
    "$HOME/workspace/app-keyboard"
    "$HOME/Projects/app-keyboard"
)

for CANDIDATE in "${CANDIDATES[@]}"; do
    if [[ -n "$CANDIDATE" && -d "$CANDIDATE" ]]; then
        CANDIDATE_PATH="$(cd "$CANDIDATE" 2>/dev/null && pwd)"
        if [[ -f "$CANDIDATE_PATH/android/key.properties" && -f "$CANDIDATE_PATH/android/app/upload-keystore.jks" ]]; then
            SRC_KEYBOARD="$CANDIDATE_PATH"
            break
        fi
    fi
done

# Nếu vẫn chưa tìm thấy, thử quét các thư mục ngang hàng trong cùng thư mục cha
if [[ -z "$SRC_KEYBOARD" ]]; then
    PARENT_DIR="$(cd "$TARGET_DIR/.." 2>/dev/null && pwd)"
    if [[ -d "$PARENT_DIR/app-keyboard" && -f "$PARENT_DIR/app-keyboard/android/key.properties" ]]; then
        SRC_KEYBOARD="$PARENT_DIR/app-keyboard"
    fi
fi

if [[ -z "$SRC_KEYBOARD" ]]; then
    echo -e "${RED}❌ Không tìm thấy thư mục nguồn app-keyboard chứa key.properties & upload-keystore.jks!${NC}"
    echo -e "   Vui lòng chỉ định đường dẫn source app-keyboard:"
    echo -e "   Cú pháp: $0 \"$TARGET_DIR\" \"/duong/dan/toi/app-keyboard\""
    exit 1
fi

echo -e "${GREEN}🔍 Đã tìm thấy nguồn app-keyboard tại:${NC} $SRC_KEYBOARD"

SRC_KEY_PROP="$SRC_KEYBOARD/android/key.properties"
SRC_KEYSTORE="$SRC_KEYBOARD/android/app/upload-keystore.jks"

# 3. Copy key.properties và keystore sang Target Project
mkdir -p "$TARGET_DIR/android/app"

DEST_KEY_PROP="$TARGET_DIR/android/key.properties"
DEST_KEYSTORE="$TARGET_DIR/android/app/upload-keystore.jks"

echo -e "${YELLOW}📦 Đang copy key.properties và upload-keystore.jks...${NC}"

cp "$SRC_KEY_PROP" "$DEST_KEY_PROP"
chmod 600 "$DEST_KEY_PROP"
echo -e "  ✅ Đã copy: ${BOLD}android/key.properties${NC}"

cp "$SRC_KEYSTORE" "$DEST_KEYSTORE"
chmod 600 "$DEST_KEYSTORE"
echo -e "  ✅ Đã copy: ${BOLD}android/app/upload-keystore.jks${NC}"

# 4. Bảo vệ Git (.gitignore) để KHÔNG BAO GIỜ commit keys lên GitHub
echo -e "${YELLOW}🔒 Đang kiểm tra cấu hình .gitignore (Chống lộ keys lên Git)...${NC}"

ensure_gitignore() {
    local GITIGNORE_FILE="$1"
    local PATTERN="$2"
    if [[ -f "$GITIGNORE_FILE" ]]; then
        if ! grep -qF "$PATTERN" "$GITIGNORE_FILE"; then
            echo "$PATTERN" >> "$GITIGNORE_FILE"
            echo -e "  🛡️ Đã thêm '${BOLD}$PATTERN${NC}' vào $GITIGNORE_FILE"
        fi
    fi
}

# Android .gitignore
ANDROID_GITIGNORE="$TARGET_DIR/android/.gitignore"
if [[ -f "$ANDROID_GITIGNORE" ]]; then
    ensure_gitignore "$ANDROID_GITIGNORE" "key.properties"
    ensure_gitignore "$ANDROID_GITIGNORE" "**/*.keystore"
    ensure_gitignore "$ANDROID_GITIGNORE" "**/*.jks"
else
    cat << 'GEOF' > "$ANDROID_GITIGNORE"
gradle-wrapper.jar
/.gradle
/captures/
/gradlew
/gradlew.bat
/local.properties
GeneratedPluginRegistrant.java
.cxx/

# Release signing keys (NEVER commit to git)
key.properties
**/*.keystore
**/*.jks
GEOF
    echo -e "  🛡️ Đã tạo mới $ANDROID_GITIGNORE bảo vệ keys"
fi

# Root .gitignore
ROOT_GITIGNORE="$TARGET_DIR/.gitignore"
if [[ -f "$ROOT_GITIGNORE" ]]; then
    ensure_gitignore "$ROOT_GITIGNORE" "**/key.properties"
    ensure_gitignore "$ROOT_GITIGNORE" "**/*.keystore"
    ensure_gitignore "$ROOT_GITIGNORE" "**/*.jks"
fi

# 5. Cập nhật cấu hình Gradle (build.gradle.kts hoặc build.gradle)
GRADLE_KTS="$TARGET_DIR/android/app/build.gradle.kts"
GRADLE_GROOVY="$TARGET_DIR/android/app/build.gradle"

patch_gradle_kts() {
    local FILE="$1"
    if grep -q "keystoreProperties" "$FILE"; then
        echo -e "${GREEN}  ℹ️ File build.gradle.kts đã có cấu hình keystoreProperties. Bỏ qua patching.${NC}"
        return 0
    fi

    echo -e "${YELLOW}⚙️ Đang cấu hình build.gradle.kts (Kotlin DSL)...${NC}"
    cp "$FILE" "$FILE.bak"

    python3 - "$FILE" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Thêm import vào đầu file nếu chưa có
imports = []
if "import java.io.FileInputStream" not in content:
    imports.append("import java.io.FileInputStream")
if "import java.util.Properties" not in content:
    imports.append("import java.util.Properties")

if imports:
    content = "\n".join(imports) + "\n\n" + content

# 2. Thêm keystoreProperties trước android {
keystore_loader = """val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
"""

if "val keystoreProperties" not in content:
    android_idx = content.find("android {")
    if android_idx != -1:
        content = content[:android_idx] + keystore_loader + "\n" + content[android_idx:]
    else:
        content = content + "\n" + keystore_loader

# 3. Thêm signingConfigs { create("release") { ... } } vào trong khối android { ... }
signing_code = """    signingConfigs {
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
"""

if "signingConfigs {" not in content:
    bt_idx = content.find("buildTypes {")
    if bt_idx != -1:
        content = content[:bt_idx] + signing_code + "\n" + content[bt_idx:]
    else:
        last_brace = content.rfind("}")
        if last_brace != -1:
            content = content[:last_brace] + signing_code + "\n" + content[last_brace:]

# 4. Cập nhật buildTypes.release signingConfig
old_signing_line = 'signingConfig = signingConfigs.getByName("debug")'
new_signing_line = """signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }"""

if old_signing_line in content:
    content = content.replace(old_signing_line, new_signing_line)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("  ✅ Đã tự động cập nhật build.gradle.kts thành công!")
PYEOF
    echo -e "  📄 Đã lưu bản backup tại: ${BOLD}$FILE.bak${NC}"
}

patch_gradle_groovy() {
    local FILE="$1"
    if grep -q "keystoreProperties" "$FILE"; then
        echo -e "${GREEN}  ℹ️ File build.gradle đã có cấu hình keystoreProperties. Bỏ qua patching.${NC}"
        return 0
    fi

    echo -e "${YELLOW}⚙️ Đang cấu hình build.gradle (Groovy DSL)...${NC}"
    cp "$FILE" "$FILE.bak"

    python3 - "$FILE" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

header_code = """def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
"""

if "keystoreProperties" not in content:
    content = header_code + "\n" + content

signing_code = """    signingConfigs {
        release {
            keyAlias = keystoreProperties['keyAlias']
            keyPassword = keystoreProperties['keyPassword']
            storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword = keystoreProperties['storePassword']
        }
    }
"""

if "signingConfigs {" not in content:
    bt_idx = content.find("buildTypes {")
    if bt_idx != -1:
        content = content[:bt_idx] + signing_code + "\n" + content[bt_idx:]

old_debug = 'signingConfig signingConfigs.debug'
new_release = """signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug"""
if old_debug in content:
    content = content.replace(old_debug, new_release)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("  ✅ Đã tự động cập nhật build.gradle (Groovy) thành công!")
PYEOF
    echo -e "  📄 Đã lưu bản backup tại: ${BOLD}$FILE.bak${NC}"
}

if [[ -f "$GRADLE_KTS" ]]; then
    patch_gradle_kts "$GRADLE_KTS"
elif [[ -f "$GRADLE_GROOVY" ]]; then
    patch_gradle_groovy "$GRADLE_GROOVY"
else
    echo -e "${YELLOW}⚠️ Không tìm thấy file build.gradle hoặc build.gradle.kts trong android/app/${NC}"
fi

echo -e ""
echo -e "${GREEN}${BOLD}==============================================================${NC}"
echo -e "${GREEN}${BOLD}         🎉 THIẾT LẬP RELEASE SIGNING KEY HOÀN TẤT!           ${NC}"
echo -e "${GREEN}${BOLD}==============================================================${NC}"
echo -e "Tóm tắt các thay đổi đã thực hiện:"
echo -e "  1. Copy ${BOLD}android/key.properties${NC}"
echo -e "  2. Copy ${BOLD}android/app/upload-keystore.jks${NC}"
echo -e "  3. Cấu hình ${BOLD}.gitignore${NC} ngăn chặn commit key lên GitHub"
echo -e "  4. Cập nhật ${BOLD}build.gradle(.kts)${NC} nhận cấu hình ký tự động"
echo -e ""
echo -e "Kiểm tra lệnh build Release:"
echo -e "  ${CYAN}flutter build appbundle --release${NC}"
echo -e "  hoặc"
echo -e "  ${CYAN}cd android && ./gradlew bundleRelease${NC}"
echo -e "${GREEN}${BOLD}==============================================================${NC}"
