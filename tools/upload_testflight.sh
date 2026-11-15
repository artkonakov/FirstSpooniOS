#!/usr/bin/env bash
# Release-сборка → App Store Connect (TestFlight). Подпись автоматическая, аккаунт из Xcode (см. ниже).
#   tools/upload_testflight.sh [номер сборки]
# Номер сборки (CFBundleVersion) должен расти с каждой загрузкой; по умолчанию — CURRENT_PROJECT_VERSION из проекта.
# После загрузки Apple обрабатывает сборку 5–30 мин: node tools/asc_api.mjs builds.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=A2VCF6W9QB
ISSUER_ID=d7cee3e8-50f7-4cfb-bf4f-d3127e6a691a
KEY_PATH="$HOME/.littlebite-keys/AuthKey_${KEY_ID}.p8"
TEAM_ID=93DY8Q8W67
[[ -f "$KEY_PATH" ]] || { echo "Нет ключа $KEY_PATH" >&2; exit 1; }

BUILD_NUMBER="${1:-}"
OUT=build/release
ARCHIVE="$OUT/FirstSpoon.xcarchive"
rm -rf "$OUT" && mkdir -p "$OUT"

# Подпись для App Store (облачный сертификат Apple) выпускает только Admin. Ключ API — App Manager, поэтому по умолчанию
# подпись и загрузку делает Apple Account, в который вошли в Xcode → Settings → Accounts. SIGN_WITH=key — через ключ
# (нужен ключ с ролью Admin).
AUTH=(-allowProvisioningUpdates)
if [[ "${SIGN_WITH:-xcode}" == key ]]; then
  AUTH+=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")
fi

xcodebuild -project FirstSpoon.xcodeproj -scheme FirstSpoon -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  ${BUILD_NUMBER:+CURRENT_PROJECT_VERSION=$BUILD_NUMBER} \
  "${AUTH[@]}" archive

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" "${AUTH[@]}"

echo "Загружено. Статус обработки: node tools/asc_api.mjs builds"
