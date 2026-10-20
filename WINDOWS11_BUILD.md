# ReFind One → IPA с Windows 11 (без Mac)

**Рабочая схема:** Windows 11 → GitHub → облачный Mac с Xcode 27 → неподписанная IPA → Files на iPhone → LiveContainer.

Компилировать настоящий iOS ARM64 `.app` из SwiftUI/Apple Vision прямо Windows SDK не умеет. Облачный macOS-раннер GitHub Actions решает это без покупки Mac, без платного Apple Developer Program и без публикации в App Store. Уже установленный LiveContainer должен сам обеспечить поддерживаемый способ подписи гостевой IPA (обычно JIT-less); этот этап НЕ гарантирован без проверки на iPhone.

## 1. Установить инструменты на Windows

Открой **PowerShell** и выполни:

```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e
```

Перезапусти PowerShell, чтобы обновился `PATH`. Создай аккаунт на https://github.com, если его нет. Выполни:

```powershell
gh auth login
```

Выбери `GitHub.com`, `HTTPS`, вход через браузер. Настрой имя автора (можно GitHub no-reply email, если не хочешь показывать реальный адрес):

```powershell
git config --global user.name "Your GitHub name"
git config --global user.email "YOUR_ID+YOUR_USERNAME@users.noreply.github.com"
```

Вместо примера введи настоящий email из своих GitHub Settings → Emails либо настроенный GitHub no-reply адрес. Не указывай выдуманный GitHub ID.

## 2. Опубликовать исходники

Распакуй архив `ReFindOne_v0.2_Windows11_source.zip` **как папку проекта**, в которой находятся `ReFindOne.xcodeproj`, `Package.swift`, `tools`, `.github`.

В PowerShell перейди в эту папку, например:

```powershell
cd "$HOME\Downloads\ReFindOne"
```

Затем:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish_windows.ps1
```

Скрипт создаёт **private** репозиторий (по умолчанию), делает коммит, загружает проект и выводит ссылку на сборку. Публичный репозиторий, для которого стандартные GitHub-hosted сборки бесплатны, можно создать только по явному выбору:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish_windows.ps1 -Visibility public
```

**Внимание:** `public` откроет исходники всему интернету. Никогда не публикуй пароли, ключи, сертификаты, личные данные, свою базу и резервные копии. Скрипт не загружает `.build`, `*.ipa`, секретные ключи, файлы сборки благодаря `.gitignore`, однако перед публикацией всё равно проверь содержимое.

Если Windows заблокирует скрипт, можно выполнить Git-команды вручную в корне проекта:

```powershell
git init -b main
git add -A
git commit -m "Initial ReFind One"
gh repo create ReFindOne --private --source . --remote origin --push
```

## 3. Собрать IPA в браузере

1. Открой в браузере свой репозиторий GitHub.
2. Перейди **Actions → Build iOS IPA (LiveContainer)**.
3. Нажми **Run workflow → Run workflow** (ветка `main`).
4. После **зелёной** сборки открой её страницу.
5. Внизу страницы, в блоке **Artifacts**, скачай `ReFindOne-unsigned-iOS27`.
6. GitHub скачает внешний ZIP с двумя файлами. **Распакуй этот ZIP**, внутри будет настоящий `ReFindOne-unsigned.ipa` и `SHA256.txt`. Нельзя переименовывать внешний ZIP в IPA.

Workflow живёт в `.github/workflows/build-ios-ipa.yml`, запускается **вручную**, использует runner `xcode-27`, упаковывает iPhoneOS `.app` в `Payload/...`, проверяет наличие ARM64 Mach-O и публикует артефакт. Если Xcode компиляция завершится с ошибкой, workflow будет **красным** и IPA не выдаст: открой красный шаг и скопируй полный текст ошибки для исправления исходников.

## 4. Импортировать на iPhone

1. Передай `ReFindOne-unsigned.ipa` в «Файлы» на iPhone (iCloud Drive, собственное облако или другой доверенный способ).
2. Открой **официальный LiveContainer**, нажми `+` и выбери файл IPA.
3. Убедись, что в LiveContainer настроен поддерживаемый JIT-less signing, как описано в его официальном FAQ. В зависимости от версии может понадобиться повторная подпись приложения в его настройках.
4. Запусти ReFind One из LiveContainer. Если вылетает на iOS 27, проверь обновление LiveContainer и настройку `Spoof SDK Version` (для несовместимых сборок выключить).
5. Протестируй сохранение ссылки, выход из приложения, повторный запуск, импорт скриншота и OCR.

Официальный LiveContainer: https://github.com/LiveContainer/LiveContainer ; FAQ: https://livecontainer.github.io/docs/faq/installing-livecontainer

## 5. Обновлять приложение с Windows

Измени `.swift` файлы в **Visual Studio Code** (или другом редакторе) → снова выполни `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish_windows.ps1` → вручную повтори **Actions → Run workflow** → получи новую IPA.

Важное: не меняй `PRODUCT_BUNDLE_IDENTIFIER` без необходимости. Перед пробным обновлением сохрани резервную копию из ReFind One. LiveContainer имеет собственную модель контейнеров, и перезапись гостевой IPA может повлиять на доступность данных.

## Стоимость и безопасность

- В **публичном** репозитории стандартные GitHub-hosted runners бесплатны (в том числе macOS). Исходники видны всем.
- В **приватном** репозитории macOS Actions расходует включённый лимит минут; превышение квоты может блокировать сборку или создавать расходы согласно настройкам биллинга GitHub. Поэтому workflow запускается только вручную.
- Apple developer subscription не нужна **для получения неподписанной IPA** из облачного Xcode. Для обычной прямой установки на iPhone потребуется отдельная подпись; установленный LiveContainer при корректной настройке способен переподписывать гостевые приложения.
- GitHub workflow не получает никаких сертификатов, паролей и Apple ID, а исходный код ReFind One не отправляет ваши заметки в облако. Локальные записи/скриншоты с телефона в Actions не загружаются.

## Как понять, что уже проверено

- Проверяются: Linux-unit-тесты ядра в отдельном workflow; структура IPA, bundle metadata, наличие ARM64 бинарника после успешного Xcode build.
- **Не проверяется без iPhone:** запуск гостевой IPA, нативные разрешения, PhotosPicker/OCR, совместимость с конкретной сборкой LiveContainer, жизненный цикл и сохранность данных после обновления.
