# Справка по использованию утилиты

function Show-Help {
  @"
version_manager.ps1 <command> [options]

Команды:
  create [--name <имя>] [--description <текст>]
    Создать новый локальный репозиторий
    
  download --source <zip|dir> [--uuid <uuid>] [--name <имя>]
    Скачать/импортировать репозиторий из zip-архива или папки
    
  help
    Показать эту справку

Флаги:
  --root <путь>   указать корень проекта вручную (по умолчанию определяется автоматически)

Примеры:
  .\version_manager.ps1 create --name "Мой репозиторий" --description "Описание"
  .\version_manager.ps1 download --source "C:\path\to\repo.zip"
  .\version_manager.ps1 download --source "C:\path\to\repo" --uuid abc-123-def
"@ | Write-Host
}

