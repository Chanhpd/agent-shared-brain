#!/usr/bin/env bash
# Script đồng bộ kiến thức agent-shared-brain
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

ACTION=${1:-"pull"}

if [ "$ACTION" = "pull" ]; then
    echo "🔄 Đang cập nhật kiến thức mới nhất từ GitHub..."
    git pull --rebase origin main
    echo "✅ Đồng bộ thành công!"
elif [ "$ACTION" = "push" ]; then
    MSG=${2:-"docs: update agent knowledge base"}
    echo "🚀 Đang gửi kiến thức mới lên GitHub..."
    git add .
    git commit -m "$MSG"
    git push origin main
    echo "✅ Đã tải lên GitHub thành công!"
else
    echo "Cách dùng:"
    echo "  ./scripts/sync.sh pull           # Kéo kiến thức mới nhất về"
    echo "  ./scripts/sync.sh push \"message\" # Đẩy kiến thức mới lên GitHub"
fi
