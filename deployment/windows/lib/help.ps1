# Help for CLI utility

function Show-Help {
  @"
ergovcs <command> [options]

Main repository commands:
  create [name]
    Create new repository on server via API
    Interactive mode: prompts for name, username, password, description, branch, private flag
    Options:
      --username, -u    Username for authentication
      --password, -pw   Password for authentication
      --description, -d Repository description
      --branch, -b      Initial branch name (default: main)
      --private, -p     Create private repository
    Examples:
      ergovcs create
      ergovcs create "My Project"
      ergovcs create --name "My Project" -u admin -pw secret
    
  clone <uuid|name> [target_path]
    Clone repository from server to local computer
    Copies files from media/version_management/<uuid>/ to target path
    Creates .ergovcs/ folder and .ergovcsignore file
    Examples:
      ergovcs clone abc-123-def-456 ./my-project
      ergovcs clone "My Repository" C:\Projects\MyRepo
      ergovcs clone abc-123
    
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
    
  update <branch>
    Update local repository, pulling changes from server
    Note: doesn't matter which branch user has downloaded
    
  remove <path> [--force]
    Remove cloned repository from local computer by path
    --force (-f): skip confirmation prompt
    Note: removes only local copy, not repository on server
    Examples:
      ergovcs remove C:\Projects\MyRepo
      ergovcs remove ./my-project
      ergovcs remove ./my-project --force

Helper commands:
  branch <list|create|delete|set-default> [options]
    Branch management (via API)
    Examples:
      ergovcs branch list --repo <uuid>
      ergovcs branch create --repo <uuid> --name <branch>
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

Examples:
  ergovcs create "My Project"
  ergovcs clone abc-123-def-456 ./my-project
  ergovcs add src\main.py
  ergovcs commit -m "Added new feature"
  ergovcs push main
  ergovcs update main
  ergovcs remove ./my-project
  ergovcs download --source "C:\path\to\repo.zip"
  ergovcs files --repo <uuid>
  ergovcs stats --repo <uuid>
  ergovcs forecast --repo <uuid> --days 30
"@ | Write-Host
}
