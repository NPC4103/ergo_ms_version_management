# Help for CLI utility

function Show-Help {
  @"
ergovcs <command> [options]

Main repository commands:
  clone <UUID>
    Clone repository from media/version_management/<UUID>/ to local computer
    Calls API: /api/repositories/{id}/clone/
    
  add <file.extension>
    Add file for commit to staging area
    After commit command changes will be sent to server
    
  commit -m "Message"
    Create commit with changes
    Calls API: /api/repositories/{id}/commits/create/
    After repeated add no new commit is created, changes are added
    to existing one, until commit is pushed to server
    
  push <branch>
    Push changes to server to folder media/version_management/<UUID>/
    Calls API: /api/repositories/{id}/push/
    
  update <branch>
    Update local repository, pulling changes from server
    Calls API: /api/repositories/{id}/update/
    Note: doesn't matter which branch user has downloaded
    
  remove <UUID>
    Remove local copy of repository from user's computer
    Note: removes only local copy, not repository on server

Helper commands:
  create [--name <name>] [--description <text>] [--private] [--read-only] [--branch <branch>] [--username <u>] [--password <p>] [--root <path>]
    Create new repository via API and prepare local files

  branch <list|create|delete|set-default> [options]
    Branch management (via API)
    Examples:
      ergovcs branch list --repo <uuid>
      ergovcs branch create --repo <uuid> --name <branch> --username <u> --password <p>
      ergovcs branch delete --id <branch_id>
      ergovcs branch set-default --repo <uuid> --name <branch>

  files --repo <uuid>
    Show repository file tree
    
  download --source <zip|dir> [--uuid <uuid>] [--name <name>]
    Download/import repository from zip-archive or folder

Analytics and forecasting:
  stats [--repo <uuid>] [--json]
    Get repository statistics (size, file types, cold storage candidates)
    Examples:
      ergovcs stats --repo <uuid>
      ergovcs stats --json

  forecast [--repo <uuid>] [--days <number>] [--json]
    Get repository growth forecast based on time series
    Examples:
      ergovcs forecast --repo <uuid>
      ergovcs forecast --days 90
      ergovcs forecast --json

  install-cli
    Install CLI wrapper to System32 (ergovcs)

  uninstall-cli
    Remove CLI wrapper from System32 (ergovcs)
    
  help
    Show this help

Flags:
  --root <path>   specify project root manually (auto-detected by default)

Examples:
  ergovcs clone abc-123-def-456
  ergovcs add src\main.py
  ergovcs commit -m "Added new feature"
  ergovcs push main
  ergovcs update main
  ergovcs remove abc-123-def-456
  ergovcs create --name "My repository"
  ergovcs download --source "C:\path\to\repo.zip"
  ergovcs files --repo <uuid>
  ergovcs stats --repo <uuid>
  ergovcs forecast --repo <uuid> --days 30
  powershell -ExecutionPolicy Bypass -File .\version_manager.ps1 install-cli
  powershell -ExecutionPolicy Bypass -File .\version_manager.ps1 uninstall-cli
"@ | Write-Host
}
