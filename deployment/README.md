# Утилита version_management

Утилита для управления репозиториями в модуле version_management. Работает на Linux и Windows.

## Основные команды

1. **create** — создать новый локальный репозиторий
   - Генерируется UUID
   - Создаются каталоги в `media/version_management/<UUID>/`
   - Создаются подпапки `api/` и `client/`
   - Сохраняется метаданные в `manifest.json`

2. **download** — скачать сторонний репозиторий
   - Принимает путь к zip-архиву или папке
   - Распаковывает в `media/version_management/<UUID>/`

## Установка и использование

### Linux

```bash
# Сделать скрипт исполняемым
chmod +x linux/version_manager.sh

# Использование
./linux/version_manager.sh create --name "Мой репозиторий" --description "Описание"
./linux/version_manager.sh download --source /path/to/repo.zip --uuid <uuid>
```

### Windows

```powershell
# Использование
pwsh -File windows/version_manager.ps1 create --name "Мой репозиторий" --description "Описание"
pwsh -File windows/version_manager.ps1 download --source "C:\path\to\repo.zip" --uuid <uuid>
```

## Параметры команд

### create
- `--name <имя>` — название репозитория (если не указано, запрашивается интерактивно)
- `--description <текст>` — описание репозитория (если не указано, запрашивается интерактивно)
- `--root <путь>` — указать корень проекта вручную (по умолчанию определяется автоматически)

### download
- `--source <zip|dir>` — путь к zip-архиву или папке с репозиторием (обязательный)
- `--uuid <uuid>` — UUID для репозитория (если не указан, генерируется автоматически)
- `--name <имя>` — название репозитория (опционально, сохраняется в manifest.json)
- `--root <путь>` — указать корень проекта вручную (по умолчанию определяется автоматически)

## Структура репозитория

После создания или скачивания репозитория в `media/version_management/<UUID>/` будет следующая структура:

```
<UUID>/
  ├── api/
  ├── client/
  └── manifest.json
```

Файл `manifest.json` содержит метаданные:
```json
{
  "uuid": "<uuid>",
  "name": "Название репозитория",
  "description": "Описание"
}
```

## Примечания

- Утилита автоматически определяет корень проекта, ища папку `modules/version_management` вверх по дереву каталогов
- Все репозитории хранятся в `media/version_management/<UUID>/`
- Пока утилита работает без бэкенда, создавая только локальную структуру

