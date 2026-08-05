# Browser Selector

Нативная macOS-утилита: когда macOS открывает `http` или `https` ссылку, приложение показывает компактное окно по центру экрана и дает выбрать установленный браузер.

## Что внутри

- URL handler для `http` и `https` через `CFBundleURLTypes`.
- Browser bundle claim для `file` URL; default handler для `file` не назначается.
- Поддержка `ASWebAuthenticationSession`: Browser Selector объявляет capabilities браузера (`ASWebAuthenticationSessionWebBrowserSupportCapabilities`), но намеренно **не** регистрируется как `sessionHandler`. `ASWebAuthenticationSession` флоу (OAuth/SSO из Claude.app, ChatGPT.app и др.) macOS передаёт Safari secure web view (`SFAuthenticationViewController`), а не через LaunchServices, поэтому chooser для них недостижим (ограничение macOS для menu-bar агентов). Обычные `http(s)` ссылки, включая ссылки-переходы на OAuth-страницы, открытые как обычные ссылки, идут через chooser.
- Получение ссылок через стандартный Apple Event `kAEGetURL`.
- Поиск браузеров через LaunchServices, без ручных списков и костылей.
- Минималистичный горизонтальный chooser: только браузеры и подписи, без скролла и лишнего текста.
- `Esc` закрывает chooser и отменяет переход по ссылке.
- Клик вне chooser закрывает его и отменяет переход по ссылке.
- Для Chrome/Chromium-браузеров ссылка открывается новой вкладкой в последнем активном окне.
- Выбранные браузеры ранжируются по успешным открытиям: чаще используемые уходят левее и становятся первыми для `Enter`.
- Menu bar приложение без иконки в Dock: `LSUIElement=true` в `Info.plist` и accessory mode на старте приложения.
- Один источник правды для настроек: `Preferences`.
- Локальная статистика хранится простым текстовым файлом: `~/Library/Application Support/Browser Selector/browser-usage.txt`.
- Диагностика default handlers и auth-session flow пишется в `~/Library/Application Support/Browser Selector/diagnostics.log`; URL query/fragment значения в логе редактируются.
- Локально сгенерированная уникальная иконка `.icns`.
- Сборка и подпись `.app` одной командой.

## Установка одной командой

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/UltraDeepAutomation/Browser-Selector/main/Scripts/install_latest.sh)"
```

Скрипт скачивает последний GitHub Release `BrowserSelector.zip`, проверяет `BrowserSelector.zip.sha256`, устанавливает приложение в `~/Applications/Browser Selector.app`, регистрирует bundle в LaunchServices, назначает Browser Selector обработчиком `http`, `https` и `public.html`, при необходимости ждет системное подтверждение macOS, затем запускает menu bar приложение.

Для установки конкретной версии:

```bash
BROWSER_SELECTOR_VERSION=v1.0.5 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/UltraDeepAutomation/Browser-Selector/main/Scripts/install_latest.sh)"
```

## Установка из локального клона

```bash
./Scripts/install.sh
```

Скрипт соберет приложение, установит его в `~/Applications/Browser Selector.app`, зарегистрирует bundle в LaunchServices и запустит приложение.
После установки скрипт компилирует локальный helper, назначает Browser Selector обработчиком web-схем из `CFBundleURLSchemes` и web content type `public.html`, затем проверяет, что LaunchServices применил это назначение.

При первом запуске нажмите `Назначить`, затем подтвердите системный запрос macOS, если он появится. После этого все web-ссылки будут попадать в Browser Selector.

При первом открытии ссылки через конкретный браузер macOS может один раз запросить Automation-доступ, чтобы Browser Selector мог открыть новую вкладку в уже открытом окне этого браузера. Разрешение нужно подтвердить один раз для выбранного браузера.

## Сборка без установки

```bash
./Scripts/build.sh
```

Готовое приложение появится здесь:

```text
dist/Browser Selector.app
```

Скрипт автоматически выбирает лучшую доступную signing identity: `Developer ID Application`, затем `Apple Development`, затем локальную identity, и только если сертификатов нет - ad-hoc подпись. Для явной Developer ID подписи:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build.sh
```

## Release package

```bash
./Scripts/package_release.sh
```

Скрипт собирает universal `arm64 + x86_64` приложение, universal helper `set-default-browser`, подписывает оба артефакта, создает `dist/release/BrowserSelector.zip` и `dist/release/BrowserSelector.zip.sha256`.

GitHub Actions автоматически:

- валидирует приложение на `push`, `pull_request` и `workflow_dispatch`;
- собирает release zip как CI artifact;
- публикует GitHub Release с `BrowserSelector.zip` и checksum при пуше тега `v*`.

Релиз:

```bash
git tag v1.0.5
git push origin v1.0.5
```

## macOS installer для Gumroad

Для продажи как обычного macOS-приложения собирайте installer-артефакт:

```bash
xcrun notarytool store-credentials browser-selector-notary \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "5M3L3LU4XV" \
  --password "APP_SPECIFIC_PASSWORD"
```

```bash
BROWSER_SELECTOR_REQUIRE_DEVELOPER_ID=1 \
BROWSER_SELECTOR_NOTARY_PROFILE=browser-selector-notary \
./Scripts/package_macos_installer.sh
```

Готовые файлы:

```text
dist/installer/BrowserSelector-1.0.5.pkg
dist/installer/BrowserSelector-1.0.5.dmg
dist/installer/BrowserSelector-1.0.5.dmg.sha256
```

`BrowserSelector-1.0.5.pkg` устанавливает приложение в `/Applications`, регистрирует bundle в LaunchServices и запускает Browser Selector после установки. При первом запуске macOS может показать системное подтверждение назначения браузера по умолчанию - это обязательный user-consent flow macOS.

Для публичной продажи вне Mac App Store нужны именно:

- `Developer ID Application` для подписи `.app` и `.dmg`;
- `Developer ID Installer` для подписи `.pkg`;
- notarization через `xcrun notarytool` и stapled ticket для `.pkg` и `.dmg`.

Локальный preview без installer-сертификата можно собрать только для внутренней проверки:

```bash
CODE_SIGN_IDENTITY="Apple Distribution: IRYNA SHAUKO (5M3L3LU4XV)" \
BROWSER_SELECTOR_ALLOW_UNSIGNED_INSTALLER=1 \
./Scripts/package_macos_installer.sh
```

## Проверка

```bash
./Scripts/validate.sh
```

Скрипт проверяет `Info.plist`, URL schemes, Apple Events usage description, install-helper, XCTest, сборку `.app` и подпись.

Текущие LaunchServices handlers можно проверить без изменения настроек:

```bash
mkdir -p .build/install-tools
xcrun swiftc Scripts/set_default_browser.swift -o .build/install-tools/set-default-browser
.build/install-tools/set-default-browser --print-default-handlers Resources/Info.plist
```

## Использование

- Иконка приложения находится в строке меню.
- Пункт `Назначить браузером по умолчанию` делает приложение обработчиком `http` и `https`.
- Пункт `Проверить окно выбора` открывает тестовый chooser без необходимости искать ссылку в другом приложении.
- Пункт `Проверить системную ссылку` открывает `https` через macOS LaunchServices, чтобы проверить реальный default-handler path.
- Пункт `Показать диагностику` показывает текущий bundle, handlers, путь к diagnostics log и последние строки лога.
- В menu bar есть `Запоминать выбранный браузер`. Если включить его, следующий выбранный браузер станет строкой `Запомненный браузер: X`.
- В menu bar есть список найденных браузеров с галочками: отмеченные показываются в chooser, снятые скрываются.
- В chooser можно нажать правой кнопкой по браузеру и выбрать `Скрыть`, чтобы скрыть его из текущего и будущих окон выбора.
- В том же контекстном меню есть `Переименовать`: пользовательское имя сохраняется локально и показывается в chooser и menu bar.
- Статистика успешных открытий остается главным источником порядка: чаще используемые браузеры идут левее; запомненный браузер используется как tie-breaker при равной статистике.
- Menu bar показывает текущий запомненный браузер и позволяет сбросить его через `Сбросить запомненный браузер`.

Важно: Browser Selector перехватывает все обычные `http`/`https` открытия через LaunchServices и показывает общий browser chooser. Системный `ASWebAuthenticationSession` (например prompt `Claude.app wants to use claude.com to Sign In`) обрабатывает macOS сама через Safari secure web view — chooser в этом случае не появляется, это ограничение macOS для agent-приложений; после завершения auth flow callback URL возвращается в исходное приложение через его URL scheme. Browser Selector намеренно не регистрируется как `ASWebAuthenticationSessionWebBrowserSessionManager.sessionHandler` (регистрация бесполезна для menu-bar агента и вызывает отмену сессии у исходного приложения).

## Требования

- macOS 13 или новее.
- Для установки одной командой: `curl`, `ditto`, `shasum` из стандартной macOS.
- Для локальной сборки из исходников: Xcode Command Line Tools или Xcode.
