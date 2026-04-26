#!/bin/bash
set -e

VERSION="${GOJIPSA_VERSION:-2.0.4}"
DMG="GOJIPSA-${VERSION}.dmg"
URL="https://github.com/CroinDA/gojipsa-cmux/releases/download/v${VERSION}/${DMG}"
VOL="/Volumes/GOJIPSA ${VERSION}"

echo "⬇️  꼬집사 v${VERSION} 다운로드 중..."
curl -L --progress-bar -o "/tmp/${DMG}" "${URL}"

echo "📦 설치 중..."
xattr -dr com.apple.quarantine "/tmp/${DMG}" 2>/dev/null || true
hdiutil attach "/tmp/${DMG}" -nobrowse -quiet
ditto "${VOL}/GOJIPSA.app" "/Applications/GOJIPSA.app"
hdiutil detach "${VOL}" -quiet
xattr -dr com.apple.quarantine "/Applications/GOJIPSA.app" 2>/dev/null || true
rm -f "/tmp/${DMG}"

echo "🔑 API 키 설정..."
mkdir -p ~/.gojipsa
if [ ! -f ~/.gojipsa/api-key.txt ]; then
    read -rp "Gemini API 키를 입력하세요: " APIKEY
    echo "${APIKEY}" > ~/.gojipsa/api-key.txt
    chmod 600 ~/.gojipsa/api-key.txt
fi

echo "🔐 cmux 비밀번호 설정 (없으면 엔터)..."
if [ ! -f ~/.gojipsa/cmux-password.txt ]; then
    read -rp "cmux 비밀번호 (없으면 엔터): " PASS
    if [ -n "${PASS}" ]; then
        echo "${PASS}" > ~/.gojipsa/cmux-password.txt
        chmod 600 ~/.gojipsa/cmux-password.txt
    fi
fi

echo "🤏 꼬집사 실행!"
open -a GOJIPSA
