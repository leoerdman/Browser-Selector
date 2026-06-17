# Browser Selector Code Audit

Дата аудита: 2026-06-17.

Область: файлы проекта в репозитории, без `.git`, `.build`, `dist`, generated iconset и сторонних зависимостей.

Итог: найдено 46 реальных дефектов из кода. P0 не найдено. Найденные P1 исправлены полностью. P2/P3/UX/SSOT дефекты из списка ниже тоже исправлены.

## 1. P1 - release installer убивал процессы только по имени

Файл и строка: `Scripts/install_latest.sh:108`.

Суть: `pkill -x BrowserSelector` мог остановить любой чужой процесс с таким именем.

Последствие: one-command install мог завершить не тот процесс пользователя.

Было:

```bash
if /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1; then
    /usr/bin/pkill -TERM -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || true
```

Стало:

```bash
running_target_pids() {
    /usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" 2>/dev/null | while IFS= read -r pid; do
        command_path="$(/bin/ps -p "${pid}" -o comm= 2>/dev/null || true)"
        [[ "${command_path}" == "${TARGET_EXECUTABLE}" ]] && printf '%s\n' "${pid}"
    done
}
```

Объяснение: installer теперь работает только с executable path установленного bundle.

## 2. P1 - local installer убивал процессы только по имени

Файл и строка: `Scripts/install.sh:34`.

Суть: локальная установка имела тот же blind `pkill`.

Последствие: локальный dev install мог прибить чужой процесс `BrowserSelector`.

Было:

```bash
/usr/bin/pkill -TERM -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 || true
```

Стало:

```bash
terminate_target_app
```

Объяснение: `terminate_target_app` фильтрует PID по `~/Applications/Browser Selector.app/Contents/MacOS/BrowserSelector`.

## 3. P1 - release installer принимал чужой процесс за успешный launch

Файл и строка: `Scripts/install_latest.sh:142`.

Суть: проверка запуска была по `pgrep -x`, а не по path.

Последствие: installer мог сказать `Installed`, хотя новый app не стартовал.

Было:

```bash
/usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 && return 0
```

Стало:

```bash
is_target_app_running && return 0
```

Объяснение: success теперь подтверждает именно установленный bundle.

## 4. P1 - local installer принимал чужой процесс за успешный launch

Файл и строка: `Scripts/install.sh:67`.

Суть: local installer повторял ошибку release installer.

Последствие: локальная проверка могла быть false positive.

Было:

```bash
/usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1 && return 0
```

Стало:

```bash
is_target_app_running && return 0
```

Объяснение: обе ветки install теперь используют один path-aware принцип.

## 5. P1 - release installer удалял старый app до проверки install copy

Файл и строка: `Scripts/install_latest.sh:124`.

Суть: `rm -rf TARGET_APP` выполнялся до staging copy.

Последствие: сбой `ditto` оставлял пользователя без установленного приложения.

Было:

```bash
rm -rf "${TARGET_APP}"
ditto "${SOURCE_APP}" "${TARGET_APP}"
```

Стало:

```bash
ditto "${SOURCE_APP}" "${INSTALL_STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${INSTALL_STAGING_APP}" >/dev/null
rm -rf "${TARGET_APP}"
mv "${INSTALL_STAGING_APP}" "${TARGET_APP}"
```

Объяснение: target заменяется только после успешного staging и verification.

## 6. P1 - local installer удалял старый app до проверки install copy

Файл и строка: `Scripts/install.sh:51`.

Суть: локальная установка делала прямой replace.

Последствие: при сбое копирования установленный app пропадал.

Было:

```bash
rm -rf "${TARGET_APP}"
ditto "${STAGING_APP}" "${TARGET_APP}"
```

Стало:

```bash
ditto "${STAGING_APP}" "${INSTALL_STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${INSTALL_STAGING_APP}" >/dev/null
rm -rf "${TARGET_APP}"
mv "${INSTALL_STAGING_APP}" "${TARGET_APP}"
```

Объяснение: local и release installers теперь одинаково используют staged replacement.

## 7. P1 - release installer не проверял подпись app/helper

Файл и строка: `Scripts/install_latest.sh:91`.

Суть: plist проверялся, но code signature archive payload не проверялась.

Последствие: поврежденный bundle мог попасть в `~/Applications`.

Было:

```bash
plutil -lint "${SOURCE_INFO_PLIST}" >/dev/null
```

Стало:

```bash
codesign --verify --deep --strict --verbose=2 "${SOURCE_APP}" >/dev/null
codesign --verify --strict --verbose=2 "${HELPER}" >/dev/null
```

Объяснение: install теперь валидирует app и helper до копирования.

## 8. P1 - local installer не проверял staged/installed bundle

Файл и строка: `Scripts/install.sh:32`.

Суть: локальный install копировал app без post-copy verification.

Последствие: broken local build мог считаться установленным.

Было:

```bash
ditto "${SOURCE_APP}" "${STAGING_APP}"
```

Стало:

```bash
ditto "${SOURCE_APP}" "${STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGING_APP}" >/dev/null
```

Объяснение: install fails fast на битом signed bundle.

## 9. P1 - helper падал сразу после LaunchServices `-54`

Файл и строка: `Scripts/set_default_browser.swift:163`.

Суть: helper принимал `-54`, но сразу проверял handlers без ожидания user confirmation.

Последствие: one-command install мог провалиться во время системного default-browser prompt.

Было:

```swift
guard status == noErr || status == -54 else {
    fail("LaunchServices returned \(status) while setting \(scheme) handler.")
}
```

Стало:

```swift
if status == -54 {
    requestedSystemConfirmation = true
    continue
}
```

Объяснение: helper теперь poll-ит handlers до 120 секунд, если macOS требует подтверждение.

## 10. P1 - helper считал `-54` fatal для content type

Файл и строка: `Scripts/set_default_browser.swift:174`.

Суть: URL schemes и `public.html` обрабатывали LaunchServices status по-разному.

Последствие: default handler мог применяться частично или падать на `public.html`.

Было:

```swift
guard status == noErr else {
    fail("LaunchServices returned \(status) while setting \(contentType) viewer.")
}
```

Стало:

```swift
if status == -54 {
    requestedSystemConfirmation = true
    continue
}
```

Объяснение: URL schemes и content types теперь используют одну модель pending confirmation.

## 11. P1 - app registration останавливалась на первом `-54`

Файл и строка: `Sources/BrowserSelector/DefaultBrowserRegistrationService.swift:64`.

Суть: service возвращал `.requestedSystemConfirmation` сразу внутри первого loop.

Последствие: остальные declared handlers могли не получить попытку регистрации в этом проходе.

Было:

```swift
if status == promptPendingStatus {
    return .requestedSystemConfirmation
}
```

Стало:

```swift
if status == promptPendingStatus {
    continue
}
```

Объяснение: сервис проходит все declared web schemes/content types и только потом возвращает state.

## 12. P1 - release package не падал при missing architecture

Файл и строка: `Scripts/package_release.sh:79`.

Суть: `lipo -info` только печатал архитектуры.

Последствие: GitHub Release мог случайно выйти только для Intel или только для Apple Silicon.

Было:

```bash
lipo -info "${APP_DIR}/Contents/MacOS/${BINARY_NAME}"
lipo -info "${HELPER_UNIVERSAL}"
```

Стало:

```bash
assert_architectures "${APP_DIR}/Contents/MacOS/${BINARY_NAME}" "Release app"
assert_architectures "${HELPER_UNIVERSAL}" "Release helper"
```

Объяснение: release build теперь hard-fails, если нет `arm64` или `x86_64`.

## 13. P1 - BrowserLauncher мог никогда не вызвать completion

Файл и строка: `Sources/BrowserSelector/BrowserLauncher.swift:19`.

Суть: `[weak self]` использовался через optional chaining.

Последствие: URL мог зависнуть в coordinator без success/error.

Было:

```swift
self?.openLocation(url, browser: browser) { [weak self] openLocationResult in
```

Стало:

```swift
guard let self else {
    completion(.failure(BrowserLaunchError(message: "Browser launcher was released before opening the link.")))
    return
}
```

Объяснение: completion теперь вызывается даже при unexpected lifetime edge-case.

## 14. P1 - activeProcesses менялся с разных queues

Файл и строка: `Sources/BrowserSelector/BrowserLauncher.swift:204`.

Суть: dictionary писался напрямую и из `terminationHandler` через main queue.

Последствие: data race в fallback process tracking.

Было:

```swift
activeProcesses[processID] = process
```

Стало:

```swift
private func trackProcess(_ process: Process, identifier: UUID) {
    processStateQueue.sync {
        activeProcesses[identifier] = process
    }
}
```

Объяснение: mutable state теперь изолирован serial queue.

## 15. P1 - process timeout только отправлял SIGTERM

Файл и строка: `Sources/BrowserSelector/BrowserLauncher.swift:171`.

Суть: зависший `/usr/bin/open` мог игнорировать terminate.

Последствие: fallback open мог висеть без завершения.

Было:

```swift
process.terminate()
```

Стало:

```swift
process.terminate()
DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Timeout.processTerminationGrace) {
    Darwin.kill(process.processIdentifier, SIGKILL)
}
```

Объяснение: timeout теперь имеет deterministic hard stop после grace period.

## 16. P1 - зависший NSAppleScript мог плодить worker threads

Файл и строка: `Sources/BrowserSelector/BrowserLauncher.swift:115`.

Суть: после timeout старый `NSAppleScript` продолжал висеть, а новые вызовы создавали новые global jobs.

Последствие: серия зависаний могла съесть threads/resources.

Было:

```swift
DispatchQueue.global(qos: .userInitiated).async {
    appleScript.executeAndReturnError(&errorInfo)
}
```

Стало:

```swift
guard appleScriptExecutionLimiter.wait(timeout: .now()) == .success else {
    return .failure(BrowserLaunchError(message: "Предыдущий AppleScript еще не завершился; ссылка будет открыта через LaunchServices."))
}
```

Объяснение: одновременно может быть только один реально исполняющийся AppleScript; следующий вызов уходит в fallback.

## 17. P1 - non-web passthrough мог открыть URL через самого себя

Файл и строка: `Sources/BrowserSelector/AppDelegate.swift:96`.

Суть: non-web URL blindly отправлялся в `NSWorkspace.open`.

Последствие: если LaunchServices выбирал Browser Selector для такого URL, получался self-loop.

Было:

```swift
NSWorkspace.shared.open(url)
```

Стало:

```swift
guard targetBundleIdentifier != AppMetadata.bundleIdentifier else {
    BrowserSelectorDiagnostics.record("non-web-url blocked-self-loop \(BrowserSelectorDiagnostics.describe(url: url))")
    return
}
```

Объяснение: app больше не переоткрывает URL через собственный bundle.

## 18. P1 - auth-session external URL мог self-loop через Browser Selector

Файл и строка: `Sources/BrowserSelector/WebAuthenticationSessionCoordinator.swift:363`.

Суть: любой non-http/about URL из WKWebView открывался через LaunchServices.

Последствие: unexpected callback/custom scheme мог вернуться в Browser Selector.

Было:

```swift
NSWorkspace.shared.open(url)
```

Стало:

```swift
if targetBundleIdentifier == AppMetadata.bundleIdentifier {
    BrowserSelectorDiagnostics.record("auth-session external-url blocked-self-loop ...")
} else {
    NSWorkspace.shared.open(url)
}
```

Объяснение: auth flow сохраняет external handoff, но блокирует self-loop.

## 19. P1 - BrowserUsageStore мог deadlock при reentrant sync

Файл и строка: `Sources/BrowserSelector/BrowserUsageStore.swift:61`.

Суть: public methods всегда делали `queue.sync`.

Последствие: reentrant вызов из той же queue приводил к deadlock.

Было:

```swift
try queue.sync {
    ...
}
```

Стало:

```swift
private func syncOnQueue<T>(_ work: () throws -> T) throws -> T {
    if DispatchQueue.getSpecific(key: Self.queueIdentityKey) == queueIdentity {
        return try work()
    }
    return try queue.sync(execute: work)
}
```

Объяснение: store теперь безопасно работает при вложенном вызове на собственной queue.

## 20. P2 - auth WKWebView мог бесконечно reload-иться

Файл и строка: `Sources/BrowserSelector/WebAuthenticationSessionCoordinator.swift:402`.

Суть: `webViewWebContentProcessDidTerminate` всегда вызывал `reload()`.

Последствие: crash-loop web content process зацикливал auth window.

Было:

```swift
webView.reload()
```

Стало:

```swift
guard webContentProcessReloadCount < Layout.maximumWebContentProcessReloads else {
    cancelSession()
    return
}
webContentProcessReloadCount += 1
webView.reload()
```

Объяснение: один восстановительный reload разрешен, повторный crash завершает session.

## 21. P2 - usage store молча терял статистику при read error

Файл и строка: `Sources/BrowserSelector/BrowserUsageStore.swift:31`.

Суть: `try? loadUsageCounts()` скрывал все ошибки.

Последствие: порядок браузеров сбрасывался без диагностируемой причины.

Было:

```swift
(try? loadUsageCounts()) ?? [:]
```

Стало:

```swift
} catch {
    BrowserSelectorDiagnostics.record("usage-store-read-failed path=\(fileURL.path) error=\(error.localizedDescription)")
    return [:]
}
```

Объяснение: fallback остался безопасным, но причина теперь попадает в diagnostics log.

## 22. P2 - diagnostics мог crash-нуться на `[0]`

Файл и строка: `Sources/BrowserSelector/BrowserSelectorDiagnostics.swift:70`.

Суть: Application Support URL брался индексом `[0]`.

Последствие: редкий пустой результат FileManager приводил к crash.

Было:

```swift
FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
```

Стало:

```swift
let applicationSupportDirectory = FileManager.default.urls(...).first
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
```

Объяснение: есть deterministic fallback.

## 23. P2 - diagnostics читал весь append-only log ради последних строк

Файл и строка: `Sources/BrowserSelector/BrowserSelectorDiagnostics.swift:57`.

Суть: `Data(contentsOf:)` грузил весь файл.

Последствие: menu diagnostics со временем мог стать медленным и прожорливым.

Было:

```swift
guard let data = try? Data(contentsOf: logFileURL)
```

Стало:

```swift
let readSize = min(fileSize, recentLogReadByteLimit)
try fileHandle.seek(toOffset: fileSize - readSize)
data = try fileHandle.readToEnd() ?? Data()
```

Объяснение: recent log теперь читается tail-окном 64 KB.

## 24. P3 - diagnostics создавал ISO formatter на каждую запись

Файл и строка: `Sources/BrowserSelector/BrowserSelectorDiagnostics.swift:77`.

Суть: `ISO8601DateFormatter()` создавался для каждой строки.

Последствие: лишние allocations и потенциальная thread-safety неоднозначность.

Было:

```swift
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
return formatter.string(from: Date())
```

Стало:

```swift
private static let timestampFormatter: ISO8601DateFormatter = { ... }()
timestampFormatterLock.lock()
return timestampFormatter.string(from: Date())
```

Объяснение: formatter стал singleton с lock вокруг использования.

## 25. P2 - Preferences не чистил raw custom names storage

Файл и строка: `Sources/BrowserSelector/Preferences.swift:228`.

Суть: setter сравнивал normalized dictionary с уже sanitized getter.

Последствие: invalid raw keys/values могли оставаться в UserDefaults навсегда.

Было:

```swift
guard normalizedDisplayNames != customBrowserDisplayNames else {
    return
}
```

Стало:

```swift
guard normalizedDisplayNames != rawCustomBrowserDisplayNames else {
    return
}
```

Объяснение: raw storage теперь canonicalized; добавлен XCTest на cleanup.

## 26. P2 - кнопка `Позже` в default-browser prompt значила `никогда`

Файл и строка: `Sources/BrowserSelector/AppDelegate.swift:116`.

Суть: `didShowDefaultBrowserPrompt` ставился до ответа пользователя.

Последствие: выбор `Позже` отключал startup prompt навсегда.

Было:

```swift
preferences.didShowDefaultBrowserPrompt = true
let response = alert.runModal()
```

Стало:

```swift
let response = alert.runModal()
guard response == .alertFirstButtonReturn else { ... }
preferences.didShowDefaultBrowserPrompt = true
```

Объяснение: флаг теперь означает реальную попытку назначения, а не факт показа окна.

## 27. UX - chooser показывал английские команды в русской UI

Файл и строка: `Sources/BrowserSelector/BrowserChoiceWindowController.swift:260`.

Суть: visible context menu и rename sheet были на английском.

Последствие: интерфейс выглядел несобранным и непоследовательным.

Было:

```swift
title: "Rename"
title: "Hide"
alert.addButton(withTitle: "Save")
```

Стало:

```swift
title: "Переименовать"
title: "Скрыть"
alert.addButton(withTitle: "Сохранить")
```

Объяснение: UI, tests и README приведены к одному языку.

## 28. UX/accessibility - tile accessibility strings были на английском

Файл и строка: `Sources/BrowserSelector/BrowserTileButton.swift:139`.

Суть: accessibility label/help не соответствовали языку интерфейса.

Последствие: VoiceOver получал mixed-language UI.

Было:

```swift
setAccessibilityLabel("Open in \(displayName)")
setAccessibilityHelp("Opens the current link in \(displayName).")
```

Стало:

```swift
setAccessibilityLabel("Открыть в \(displayName)")
setAccessibilityHelp("Открывает текущую ссылку в \(displayName).")
```

Объяснение: visible UI и accessibility теперь согласованы.

## 29. P1 - release installer пропускал traversal install path

Файл и строка: `Scripts/install_latest.sh:30`.

Суть: raw pattern guard принимал путь вида `~/Applications/../...`.

Последствие: destructive replace мог уйти за пределы ожидаемого `~/Applications/Browser Selector.app`.

Было:

```bash
case "${TARGET_APP}" in
    "${HOME}/Applications/"*.app) ;;
```

Стало:

```bash
DEFAULT_INSTALL_DIR="$(trim_trailing_slashes "${DEFAULT_INSTALL_DIR}")"
INSTALL_DIR="$(trim_trailing_slashes "${INSTALL_DIR}")"
if [[ "${INSTALL_DIR}" != "${DEFAULT_INSTALL_DIR}" ]]; then
    echo "Refusing to install outside ~/Applications: ${TARGET_APP}" >&2
    exit 64
fi
```

Объяснение: one-command installer теперь устанавливает только в canonical product location и отказывается от traversal/custom path.

## 30. P1 - release installer позволял отключить checksum

Файл и строка: `Scripts/install_latest.sh:66`.

Суть: `BROWSER_SELECTOR_SKIP_CHECKSUM=1` отключал integrity check.

Последствие: сетевой installer мог установить неподтвержденный zip.

Было:

```bash
if [[ "${BROWSER_SELECTOR_SKIP_CHECKSUM:-0}" == "1" ]]; then
    echo "Skipping checksum verification because BROWSER_SELECTOR_SKIP_CHECKSUM=1."
else
    curl ... "${ASSET_NAME}.sha256"
fi
```

Стало:

```bash
"${CURL}" -fL --retry 3 --retry-delay 1 \
    "${RELEASE_BASE_URL}/${ASSET_NAME}.sha256" \
    -o "${CHECKSUM_PATH}"
"${SHASUM}" -a 256 -c "$(basename "${CHECKSUM_PATH}")"
```

Объяснение: checksum для public release install теперь обязательный.

## 31. P1 - public installer доверял `PATH` для критичных команд

Файл и строка: `Scripts/install_latest.sh:20`.

Суть: `curl`, `ditto`, `shasum`, `codesign`, `open` вызывались по имени.

Последствие: при подмененном `PATH` installer мог выполнить не системный бинарь.

Было:

```bash
need_command curl
curl -fL --retry 3 --retry-delay 1 ...
codesign --verify --deep --strict ...
open -n "${TARGET_APP}"
```

Стало:

```bash
CURL="/usr/bin/curl"
CODESIGN="/usr/bin/codesign"
OPEN="/usr/bin/open"
need_command "${CURL}"
"${CURL}" -fL --retry 3 --retry-delay 1 ...
"${CODESIGN}" --verify --deep --strict ...
"${OPEN}" -n "${TARGET_APP}"
```

Объяснение: release install path теперь использует абсолютные macOS system tools.

## 32. P2 - local installer дублировал небезопасные PATH-вызовы

Файл и строка: `Scripts/install.sh:27`.

Суть: локальная установка вызывала `xcrun`, `ditto`, `codesign`, `open` по имени.

Последствие: dev install был менее детерминированным и хуже соответствовал release installer.

Было:

```bash
xcrun swiftc ...
ditto "${SOURCE_APP}" "${STAGING_APP}"
codesign --verify --deep --strict ...
open -n "${TARGET_APP}"
```

Стало:

```bash
XCRUN="/usr/bin/xcrun"
DITTO="/usr/bin/ditto"
CODESIGN="/usr/bin/codesign"
OPEN="/usr/bin/open"
"${XCRUN}" swiftc ...
"${DITTO}" "${SOURCE_APP}" "${STAGING_APP}"
"${CODESIGN}" --verify --deep --strict ...
"${OPEN}" -n "${TARGET_APP}"
```

Объяснение: local installer теперь повторяет release-grade deterministic command resolution.

## 33. P1/SSOT - release metadata отставала от исправленного installer

Файл и строка: `Resources/Info.plist:49`, `README.md:35`.

Суть: после installer hardening bundle version и documented release tag оставались `1.0.1`.

Последствие: публичная one-command установка продолжала бы ставить предыдущий GitHub Release без последних security/installer fixes.

Было:

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.1</string>
<key>CFBundleVersion</key>
<string>2</string>
```

```bash
BROWSER_SELECTOR_VERSION=v1.0.1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/UltraDeepAutomation/browser-selector/main/Scripts/install_latest.sh)"
git tag v1.0.1
git push origin v1.0.1
```

Стало:

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.2</string>
<key>CFBundleVersion</key>
<string>3</string>
```

```bash
BROWSER_SELECTOR_VERSION=v1.0.2 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/UltraDeepAutomation/Browser-Selector/main/Scripts/install_latest.sh)"
git tag v1.0.2
git push origin v1.0.2
```

Объяснение: repository state, app metadata, README и release tag снова имеют один источник правды.

## 34. P1 - installer падал, когда приложение не было запущено

Файл и строка: `Scripts/install_latest.sh:142`, `Scripts/install.sh:50`.

Суть: `pgrep` возвращал exit code `1` при отсутствии процесса, а `set -euo pipefail` превращал нормальное состояние в аварийный выход.

Последствие: fresh install мог завершиться после проверки подписи, не дойдя до копирования app, LaunchServices registration и запуска.

Было:

```bash
/usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" 2>/dev/null | while IFS= read -r pid; do
    command_path="$(/bin/ps -p "${pid}" -o comm= 2>/dev/null || true)"
    [[ "${command_path}" == "${TARGET_EXECUTABLE}" ]] && printf '%s\n' "${pid}"
done
```

Стало:

```bash
while IFS= read -r pid; do
    command_path="$(/bin/ps -p "${pid}" -o comm= 2>/dev/null || true)"
    [[ "${command_path}" == "${TARGET_EXECUTABLE}" ]] && printf '%s\n' "${pid}"
done < <(/usr/bin/pgrep -x "${BUNDLE_EXECUTABLE}" 2>/dev/null || true)
```

Объяснение: отсутствие running instance теперь трактуется как пустой список PID, а не как ошибка installer.

## 35. P1 - `.app` получал SIGKILL из-за склеенных document content types

Файл и строка: `Resources/Info.plist:40`.

Суть: `public.html` и `public.xhtml` были объявлены в одном `CFBundleDocumentTypes` entry.

Последствие: подписанный bundle проходил `codesign --verify`, но executable внутри `.app` сразу завершался `SIGKILL`, installer не мог запустить приложение.

Было:

```xml
<key>LSItemContentTypes</key>
<array>
    <string>public.html</string>
    <string>public.xhtml</string>
</array>
```

Стало:

```xml
<dict>
    <key>CFBundleTypeName</key>
    <string>HTML document</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>public.html</string>
    </array>
</dict>
<dict>
    <key>CFBundleTypeName</key>
    <string>XHTML document</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>public.xhtml</string>
    </array>
</dict>
```

Объяснение: web content type claims теперь разделены на отдельные LaunchServices document declarations.

## 36. P1 - validation не ловил опасную структуру `CFBundleDocumentTypes`

Файл и строка: `Scripts/validate.sh:52`.

Суть: validation требовал наличие `public.xhtml`, но не проверял, что каждый document type содержит ровно один public content type.

Последствие: release blocker из пункта 35 проходил CI/local validate.

Было:

```bash
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:0:LSItemContentTypes" "${plist_path}" | grep -qx "    public.xhtml"; then
    echo "Missing browser claim content type in ${plist_path}: public.xhtml" >&2
    exit 1
fi
```

Стало:

```bash
for document_index in 0 1; do
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes:${document_index}:LSItemContentTypes" "${plist_path}" | grep -c '^[[:space:]]*public\.')" != "1" ]]; then
        echo "CFBundleDocumentTypes:${document_index} must declare exactly one public content type in ${plist_path}" >&2
        exit 1
    fi
done
```

Объяснение: validation теперь закрепляет рабочую структуру LaunchServices declarations, а не только наличие строк.

## 37. P1 - installer не узнавал запущенный app из-за `ps -o comm` и пробела в path

Файл и строка: `Scripts/install_latest.sh:143`, `Scripts/install.sh:51`.

Суть: `ps -o comm` возвращал усеченный command для `Browser Selector.app` path с пробелом.

Последствие: installer мог убить/переустановить app некорректно или сказать, что app не стартовал, хотя процесс уже был жив.

Было:

```bash
command_path="$(/bin/ps -p "${pid}" -o comm= 2>/dev/null || true)"
if [[ "${command_path}" == "${TARGET_EXECUTABLE}" ]]; then
    printf '%s\n' "${pid}"
fi
```

Стало:

```bash
command_path="$(/bin/ps -p "${pid}" -o command= 2>/dev/null || true)"
if [[ "${command_path}" == "${TARGET_EXECUTABLE}" || "${command_path}" == "${TARGET_EXECUTABLE} "* ]]; then
    printf '%s\n' "${pid}"
fi
```

Объяснение: process detection теперь сравнивает полный executable command и корректно работает с app paths, содержащими пробел.

## 38. P3 - public install path использовал redirect repo URL

Файл и строка: `Scripts/install_latest.sh:4`, `README.md:27`.

Суть: default repo и README raw URL указывали на `UltraDeepAutomation/browser-selector`, хотя GitHub canonical repo - `UltraDeepAutomation/Browser-Selector`.

Последствие: install flow работал через redirect и давал лишний источник путаницы при диагностике release/install проблем.

Было:

```bash
REPO="${BROWSER_SELECTOR_REPO:-UltraDeepAutomation/browser-selector}"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/UltraDeepAutomation/browser-selector/main/Scripts/install_latest.sh)"
```

Стало:

```bash
REPO="${BROWSER_SELECTOR_REPO:-UltraDeepAutomation/Browser-Selector}"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/UltraDeepAutomation/Browser-Selector/main/Scripts/install_latest.sh)"
```

Объяснение: public install docs и installer default теперь используют canonical GitHub location без redirect.

## 39. P1 - Zen Browser ошибочно считался Chromium-браузером

Файл и строка: `Sources/BrowserSelector/BrowserClassifier.swift:70`.

Суть: `isChromiumLike` выводил Chromium model из общего exact browser list и относил Firefox-based Zen к Chromium.

Последствие: для Zen генерировался Chrome-style AppleScript с `tabs`, что могло ломать открытие ссылок.

Было:

```swift
let exactChromiumBrowser = exactBrowserBundleIdentifiers.contains(bundleIdentifier)
    && !bundleIdentifier.hasPrefix("com.apple.Safari")
    && !bundleIdentifier.hasPrefix("org.mozilla.")
    && bundleIdentifier != "com.duckduckgo.macos.browser"
```

Стало:

```swift
private static let chromiumBundleIdentifiers: Set<String> = [
    "com.google.Chrome",
    "com.brave.Browser",
    "company.thebrowser.Browser"
]

static func isChromiumLike(bundleIdentifier: String) -> Bool {
    chromiumBundleIdentifiers.contains(bundleIdentifier)
        || chromiumBundlePrefixes.contains { bundleIdentifier.hasPrefix($0) }
}
```

Объяснение: Chromium automation теперь включается только для явно Chromium-family браузеров.

## 40. P2 - Chrome-style script создавал лишнюю пустую вкладку при нуле окон

Файл и строка: `Sources/BrowserSelector/BrowserLaunchScriptFactory.swift:11`.

Суть: script делал `make new window`, а затем всегда создавал новую вкладку во front window.

Последствие: когда Chrome/Brave/Arc были закрыты, пользователь получал окно с лишней blank tab.

Было:

```swift
if (count of windows) = 0 then make new window
tell front window
    set newTab to make new tab at end of tabs with properties {URL:\(targetURL)}
end tell
```

Стало:

```swift
if (count of windows) = 0 then
    set newWindow to make new window
    set URL of active tab of newWindow to \(targetURL)
else
    tell front window
        set newTab to make new tab at end of tabs with properties {URL:\(targetURL)}
    end tell
end if
```

Объяснение: новое окно теперь использует свою стартовую вкладку, а новая вкладка создается только в уже существующем окне.

## 41. P1 - shell scripts всё ещё частично доверяли пользовательскому `PATH`

Файл и строка: `Scripts/install_latest.sh:2`, `Scripts/build.sh:2`, `Scripts/package_release.sh:2`.

Суть: после hardening критичных команд scripts всё ещё вызывали `rm`, `mv`, `mkdir`, `mktemp`, `sleep`, `security`, `awk`, `swift`, `codesign` через пользовательский `PATH`.

Последствие: подмененный PATH мог сделать install/build/release недетерминированным.

Было:

```bash
set -euo pipefail
TMP_DIR="$(mktemp -d)"
rm -rf "${TMP_DIR}"
```

Стало:

```bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
TMP_DIR="$(mktemp -d)"
rm -rf "${TMP_DIR}"
```

Объяснение: все shell scripts теперь стартуют с системным PATH, а explicit command variables продолжают указывать на конкретные macOS tools.

## 42. P1 - installer принимал краткий process flash за успешный launch

Файл и строка: `Scripts/install_latest.sh:211`, `Scripts/install.sh:117`.

Суть: launch check возвращал success при первом обнаружении процесса.

Последствие: app мог стартовать и сразу умереть, но installer уже сообщал `Installed`.

Было:

```bash
for _ in {1..30}; do
    is_target_app_running && return 0
    sleep 0.1
done
```

Стало:

```bash
wait_for_target_app_to_stay_running() {
    for _ in $(seq 1 "${initial_attempts}"); do
        if is_target_app_running; then
            for _ in $(seq 1 "${stable_attempts}"); do
                sleep 0.1
                is_target_app_running || return 1
            done
            return 0
        fi
        sleep 0.1
    done
    return 1
}
```

Объяснение: installer теперь требует устойчивого running state, а не одного моментального PID.

## 43. P2/SSOT - browser classifier держал Chromium ids в двух источниках

Файл и строка: `Sources/BrowserSelector/BrowserClassifier.swift:7`.

Суть: один и тот же Chromium bundle id нужно было добавлять и в общий exact list, и в Chromium classifier.

Последствие: новые браузеры легко попадали в список обнаружения, но получали неправильную automation strategy.

Было:

```swift
private static let exactBrowserBundleIdentifiers: Set<String> = [
    "com.google.Chrome",
    "app.zen-browser.zen"
]
```

Стало:

```swift
private static let exactNonChromiumBrowserBundleIdentifiers: Set<String> = [
    "app.zen-browser.zen"
]

private static let exactBrowserBundleIdentifiers =
    exactNonChromiumBrowserBundleIdentifiers.union(chromiumBundleIdentifiers)
```

Объяснение: Chromium list теперь единственный источник правды для Chromium automation и часть общего exact browser detection.

## 44. UX - menu называл запомненный выбор “браузером по умолчанию”

Файл и строка: `Sources/BrowserSelector/MenuBarController.swift:252`, `README.md:113`.

Суть: remembered choice отображался как `Браузер по умолчанию`, что конфликтовало с macOS default browser meaning.

Последствие: пользователь мог решить, что этот пункт меняет системный default browser.

Было:

```swift
return "Браузер по умолчанию: \(browserName ?? bundleIdentifier)"
```

Стало:

```swift
return "Запомненный браузер: \(browserName ?? bundleIdentifier)"
```

Объяснение: UI теперь разделяет системное назначение default handler и локальную память последнего выбора.

## 45. UX - LaunchServices error называл content type схемой

Файл и строка: `Sources/BrowserSelector/DefaultBrowserRegistrationService.swift:13`.

Суть: одна ошибка использовалась и для URL schemes, и для `public.html`, но текст всегда говорил `для схемы`.

Последствие: диагностика регистрации `public.html` была неточной.

Было:

```swift
case launchServicesFailure(scheme: String, status: OSStatus)
return "LaunchServices вернул ошибку \(status) для схемы \(scheme)."
```

Стало:

```swift
case launchServicesFailure(handler: String, status: OSStatus)
return "LaunchServices вернул ошибку \(status) для обработчика \(handler)."
```

Объяснение: один текст теперь корректно покрывает и URL schemes, и content type handlers.

## 46. P1/SSOT - публичный latest release отстал бы от новых фиксов

Файл и строка: `Resources/Info.plist:60`, `README.md:35`.

Суть: после runtime/install fixes bundle metadata и documented tag нужно поднять с `1.0.2` до `1.0.3`.

Последствие: one-command install через latest GitHub Release продолжил бы ставить сборку без последних исправлений.

Было:

```xml
<string>1.0.2</string>
<string>3</string>
```

Стало:

```xml
<string>1.0.3</string>
<string>4</string>
```

Объяснение: app metadata, README, tag и release artifact снова будут указывать на один проверенный build.

## Verification

Выполнено после фиксов:

```text
bash -n Scripts/*.sh
xcrun swiftc Scripts/set_default_browser.swift -o .build/install-tools/set-default-browser
swift test
./Scripts/validate.sh
./Scripts/package_release.sh
open -n dist/Browser\ Selector.app
BROWSER_SELECTOR_RELEASE_BASE_URL=file://... /bin/bash Scripts/install_latest.sh
env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin BROWSER_SELECTOR_RELEASE_BASE_URL=file://... /bin/bash Scripts/install_latest.sh
./Scripts/install.sh
```

Проверено installed state:

```text
LSUIElement=true
quarantine xattr отсутствует
http=https=public.html handler: com.leoerdman.BrowserSelector
process path: ~/Applications/Browser Selector.app/Contents/MacOS/BrowserSelector
System Events background only: true
```
