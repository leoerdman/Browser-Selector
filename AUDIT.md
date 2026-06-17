# Browser Selector Code Audit

Дата аудита: 2026-06-17.

Область: файлы проекта в репозитории, без `.git`, `.build`, `dist`, generated iconset и сторонних зависимостей.

Итог: найдено 28 реальных дефектов из кода. P0 не найдено. Найденные P1 исправлены полностью. P2/P3/UX/SSOT дефекты из списка ниже тоже исправлены.

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

## Verification

Выполнено после фиксов:

```text
bash -n Scripts/*.sh
xcrun swiftc Scripts/set_default_browser.swift -o .build/install-tools/set-default-browser
swift test
./Scripts/validate.sh
./Scripts/package_release.sh
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
