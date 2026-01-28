# Repository operations: structure creation, metadata saving, import, API work

# ============================================================================
# API Functions
# ============================================================================

# Get base API URL
function Get-ApiBaseUrl {
  # Priority: environment variable > config file > default value
  
  # Check environment variable
  if ($env:API_BASE_URL) {
    return $env:API_BASE_URL
  }
  
  # Check config file in home directory
  $configFile = Join-Path $env:USERPROFILE ".ergovcs\config"
  if (Test-Path $configFile) {
    $configContent = Get-Content $configFile -Raw
    if ($configContent -match 'api_base_url\s*=\s*(.+)') {
      $apiUrl = $matches[1].Trim().Trim('"').Trim("'")
      if ($apiUrl) {
        return $apiUrl
      }
    }
  }
  
  # Use environment variables for host and port or default values
  $apiHost = if ($env:API_HOST) { $env:API_HOST } else { "localhost" }
  $apiPort = if ($env:API_PORT) { $env:API_PORT } else { "8000" }
  
  return "http://${apiHost}:${apiPort}/api/version_management"
}

# Execute HTTP request to API
function Invoke-ApiRequest {
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("GET", "POST", "PUT", "DELETE", "PATCH")]
    [string]$Method,
    
    [Parameter(Mandatory=$true)]
    [string]$Endpoint,
    
    [string]$Body = $null,
    
    [hashtable]$Headers = @{}
  )
  
  # Get base URL
  $baseUrl = Get-ApiBaseUrl
  $url = "$baseUrl$Endpoint"
  
  # Prepare headers
  $requestHeaders = @{
    "Content-Type" = "application/json"
    "Accept" = "application/json"
  }
  
  # Add custom headers
  foreach ($key in $Headers.Keys) {
    $requestHeaders[$key] = $Headers[$key]
  }
  
  try {
    # Prepare parameters for Invoke-RestMethod
    $params = @{
      Uri = $url
      Method = $Method
      Headers = $requestHeaders
      ErrorAction = "Stop"
    }
    
    # Add request body for POST/PUT/PATCH
    if ($Body -and ($Method -eq "POST" -or $Method -eq "PUT" -or $Method -eq "PATCH")) {
      $params["Body"] = $Body
    }
    
    # Execute request
    $response = Invoke-RestMethod @params
    
    # Return response (can be object or string)
    if ($response -is [string]) {
      return $response
    } else {
      return ($response | ConvertTo-Json -Depth 10)
    }
  }
  catch {
    # Error handling
    $statusCode = $null
    $errorMessage = $_.Exception.Message
    
    # Try to extract error details from response
    if ($_.Exception.Response) {
      try {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        
        # Try to parse JSON error
        $errorObj = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($errorObj -and $errorObj.detail) {
          $errorMessage = $errorObj.detail
        } else {
          $errorMessage = $responseBody
        }
      }
      catch {
        # If parsing failed, use standard message
      }
    }
    
    Write-Host "[ERROR] API request failed: $errorMessage" -ForegroundColor Red
    Write-Host "  URL: $url" -ForegroundColor Yellow
    Write-Host "  Method: $Method" -ForegroundColor Yellow
    if ($statusCode) {
      Write-Host "  HTTP code: $statusCode" -ForegroundColor Yellow
    }
    
    # Return error code
    return $null
  }
}

# Create repository via API
function Invoke-ApiCreateRepository {
  param([string]$Name = $null)
  
  # Parameters:
  #   $Name - repository name (optional)
  # Returns: JSON with created repository info (id, name, path, created_at)
  
  $body = @{}
  if ($Name) {
    $body = @{ name = $Name }
  }
  $bodyJson = $body | ConvertTo-Json -Depth 2
  
  # Standard create ViewSet in DRF available at POST /repositories/
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $bodyJson
}

# Get repositories list via API
function Invoke-ApiListRepositories {
  # Returns: JSON with repositories list
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/"
}

# Get repository branches list
function Invoke-ApiListBranches {
  param([string]$RepoUuid)
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$RepoUuid/branches/"
}

# Create branch
function Invoke-ApiCreateBranch {
  param(
    [string]$RepoUuid,
    [string]$BranchName,
    [string]$CliUsername = $null,
    [string]$CliPassword = $null,
    [bool]$CheckPermissions = $true
  )

  $bodyObj = @{
    repository_public_id = $RepoUuid
    name = $BranchName
    check_permissions = $CheckPermissions
  }
  if ($CliUsername) { $bodyObj["cli_username"] = $CliUsername }
  if ($CliPassword) { $bodyObj["cli_password"] = $CliPassword }

  $body = $bodyObj | ConvertTo-Json -Depth 5
  Invoke-ApiRequest -Method "POST" -Endpoint "/branches/" -Body $body
}

# Set default branch (by id)
function Invoke-ApiSetDefaultBranchById {
  param(
    [int]$BranchId,
    [string]$CliUsername = $null,
    [string]$CliPassword = $null,
    [bool]$CheckPermissions = $true
  )

  $bodyObj = @{
    branch_id = $BranchId
    check_permissions = $CheckPermissions
  }
  if ($CliUsername) { $bodyObj["cli_username"] = $CliUsername }
  if ($CliPassword) { $bodyObj["cli_password"] = $CliPassword }

  $body = $bodyObj | ConvertTo-Json -Depth 5
  Invoke-ApiRequest -Method "POST" -Endpoint "/branches/set_default/" -Body $body
}

# Set default branch (by repo+name)
function Invoke-ApiSetDefaultBranchByName {
  param(
    [string]$RepoUuid,
    [string]$BranchName,
    [string]$CliUsername = $null,
    [string]$CliPassword = $null,
    [bool]$CheckPermissions = $true
  )

  $bodyObj = @{
    repository_public_id = $RepoUuid
    branch_name = $BranchName
    check_permissions = $CheckPermissions
  }
  if ($CliUsername) { $bodyObj["cli_username"] = $CliUsername }
  if ($CliPassword) { $bodyObj["cli_password"] = $CliPassword }

  $body = $bodyObj | ConvertTo-Json -Depth 5
  Invoke-ApiRequest -Method "POST" -Endpoint "/branches/set_default/" -Body $body
}

# Delete branch
function Invoke-ApiDeleteBranch {
  param([int]$BranchId)
  Invoke-ApiRequest -Method "DELETE" -Endpoint "/branches/$BranchId/"
}

# Get repository file tree
function Invoke-ApiGetRepoFiles {
  param([string]$RepoUuid)
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$RepoUuid/files/"
}


# Clone repository via API
function Invoke-ApiCloneRepository {
  param([string]$Uuid)
  
  # TODO: Implement cloning via API
  # Returns: path to cloned repository
  
  Write-Host "[TODO] Call API /api/repositories/$Uuid/clone/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/clone/"
}

# Create commit via API
function Invoke-ApiCreateCommit {
  param(
    [string]$Uuid,
    [string]$Message,
    $Files = $null,
    [string]$Branch = $null
  )

  $filesArray = @()
  if ($Files) {
    try {
      if ($Files -is [string]) {
        $filesArray = @($Files | ConvertFrom-Json)
      }
      elseif ($Files -is [array]) {
        $filesArray = $Files
      }
      else {
        $filesArray = @($Files)
      }
    }
    catch {
      Write-Host "[ERROR] Failed to convert files: $_" -ForegroundColor Red
      return $null
    }
  }

  $bodyObj = @{
    message = $Message
    files = $filesArray
  }
  if ($Branch) {
    $bodyObj["branch_name"] = $Branch
  }

  $body = $bodyObj | ConvertTo-Json -Depth 10

  $response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/commits/create/" -Body $body
  return $response
}

# Push changes via API
function Invoke-ApiPushChanges {
  param(
    [string]$Uuid,
    [string]$Branch,
    [string]$CommitData = $null
  )
  
  # Prepare request body
  $body = @{
    branch = $Branch
  }
  
  # If commit data provided, add it
  if ($CommitData) {
    $body["commit"] = $CommitData
  }
  
  $bodyJson = $body | ConvertTo-Json -Depth 10
  
  # Call API endpoint
  return Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/push/" -Body $bodyJson
}

# Update local repository via API
function Invoke-ApiUpdateRepository {
  param(
    [string]$Uuid,
    [string]$Branch
  )
  
  # Prepare request body
  $body = @{
    branch = $Branch
  }
  
  $bodyJson = $body | ConvertTo-Json -Depth 2
  
  # Call API endpoint
  return Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/update/" -Body $bodyJson
}

# Get commit info via API
function Get-ApiCommit {
  param(
    [string]$Uuid,
    [string]$CommitHash
  )
  
  # TODO: Implement getting commit info via API
  # Returns: JSON with commit metadata
  
  Write-Host "[TODO] Call API /api/repositories/$Uuid/commits/$CommitHash/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/$CommitHash/"
}

# Get commit diff via API
function Get-ApiCommitDiff {
  param(
    [string]$Uuid,
    [string]$CommitHash
  )
  
  # TODO: Implement getting commit diff via API
  # Returns: diff in unified diff format
  
  Write-Host "[TODO] Call API /api/repositories/$Uuid/commits/$CommitHash/diff/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/$CommitHash/diff/"
}

# Get repository statistics via API
function Invoke-ApiGetStats {
  param([string]$RepoUuid)
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$RepoUuid/stats/"
}

# Get repository growth forecast via API
function Invoke-ApiGetForecast {
  param(
    [string]$RepoUuid,
    [int]$Days = 30
  )
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$RepoUuid/forecast/?days=$Days"
}

# ============================================================================
# Local repository functions
# ============================================================================

function Ensure-RepoDirs {
  param([string]$Uuid)

  $target = Join-Path $script:MediaDir $Uuid
  New-Item -ItemType Directory -Force -Path (Join-Path $target "api") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $target "client") | Out-Null
  return $target
}

function Save-Metadata {
  param(
    [string]$Target,
    [string]$Name,
    [string]$Description
  )

  $uuid = Split-Path $Target -Leaf
  $content = @{
    uuid = $uuid
    name = $Name
    description = $Description
  } | ConvertTo-Json -Depth 2

  $content | Set-Content -Encoding UTF8 -Path (Join-Path $Target "manifest.json")
}

function Import-FromSource {
  param(
    [string]$Source,
    [string]$Target
  )

  if (Test-Path $Source -PathType Container) {
    Copy-Item "$Source\*" $Target -Recurse -Force
  }
  elseif ($Source.ToLower().EndsWith(".zip")) {
    if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
      Write-Host "[ERROR] Expand-Archive not available. Use PowerShell 5.1 or higher." -ForegroundColor Red
      exit 1
    }
    Expand-Archive -Path $Source -DestinationPath $Target -Force
  }
  else {
    Write-Host "[ERROR] Unknown source: $Source" -ForegroundColor Red
    Write-Host "[INFO] Supported: folder or zip-archive" -ForegroundColor Yellow
    exit 1
  }
}

# ============================================================================
# Functions for working with project content and commits
# ============================================================================

# Get project content (from API or backup.json)
function Get-ProjectContent {
  param(
    [string]$RepoUuid,
    [string]$LocalPath
  )
  
  # 1. Try to get via API
  try {
    $apiResponse = Invoke-ApiGetRepoFiles -RepoUuid $RepoUuid
    if ($apiResponse) {
      $data = $apiResponse | ConvertFrom-Json
      return @{
        source = "api"
        structure = if ($data.structure) { $data.structure } else { $data.items }
      }
    }
  }
  catch {
    Write-Host "[DEBUG] Failed to get project content via API: $_" -ForegroundColor Gray
  }
  
  # 2. Try to get from backup.json
  $backupFile = Join-Path (Join-Path $LocalPath ".ergovcs") "backup.json"
  if (Test-Path $backupFile) {
    try {
      $backupContent = Get-Content $backupFile -Raw -Encoding UTF8
      $backupData = $backupContent | ConvertFrom-Json
      return @{
        source = "backup"
        structure = if ($backupData.structure) { $backupData.structure } else { $backupData.items }
        timestamp = $backupData.timestamp
      }
    }
    catch {
      Write-Host "[DEBUG] Failed to read backup.json: $_" -ForegroundColor Gray
    }
  }
  
  # 3. Create empty structure
  Write-Host "[INFO] Failed to get previous project state. Empty state will be created." -ForegroundColor Yellow
  return @{
    source = "empty"
    structure = @()
  }
}

# Determine commit type based on changes and message
function Get-CommitType {
  param(
    [array]$Files,
    [string]$Message
  )
  
  # Check if type is specified in message (Conventional Commits format)
  $commitTypes = @("feat", "fix", "docs", "style", "refactor", "test", "chore", "perf", "ci", "build", "revert")
  
  # Check if message starts with commit type
  if ($Message -match '^(\w+)(?:\([^)]+\))?:') {
    $type = $Matches[1]
    if ($commitTypes -contains $type) {
      Write-Host "[INFO] Обнаружен тип коммита в сообщении: $type" -ForegroundColor Gray
      return $Message
    }
  }
  
  # Automatic type detection based on changes
  Write-Host "[INFO] Automatic commit type detection..." -ForegroundColor Gray
  
  $hasBuildFiles = $false
  $hasSourceFiles = $false
  $hasDocsFiles = $false
  $hasStyleFiles = $false
  $hasTestFiles = $false
  $hasRefactorFiles = $false
  $hasFixFiles = $false
  $hasFeatureFiles = $false
  
  # Analyze keywords in message
  $messageLower = $Message.ToLower()
  if ($messageLower -match "fix|bug|error|issue") {
    $hasFixFiles = $true
  }
  if ($messageLower -match "feat|feature|add|new") {
    $hasFeatureFiles = $true
  }
  if ($messageLower -match "refactor|restructure|cleanup") {
    $hasRefactorFiles = $true
  }
  if ($messageLower -match "test|spec|unit|integration") {
    $hasTestFiles = $true
  }
  if ($messageLower -match "doc|readme|comment") {
    $hasDocsFiles = $true
  }
  
  # Analyze files
  foreach ($file in $Files) {
    $path = $file.path.ToLower()
    
    # Check build files
    if ($path -match '(package\.json|pom\.xml|build\.gradle|build\.xml|cmakelists\.txt|makefile|dockerfile|\.yml$|\.yaml$|\.json$|\.config$|\.ini$)') {
      $hasBuildFiles = $true
    }
    
    # Check source files
    if ($path -match '(\.py$|\.js$|\.ts$|\.java$|\.cpp$|\.cs$|\.php$|\.rb$|\.go$|\.rs$|\.swift$|\.kt$|\.scala$)') {
      if ($file.action -eq "created") {
        $hasFeatureFiles = $true
      }
      if ($file.action -eq "updated") {
        $hasRefactorFiles = $true
      }
    }
    
    # Check documentation
    if ($path -match '(readme\.md|readme\.txt|\.md$|\.rst$|docs?\/|\.txt$)') {
      $hasDocsFiles = $true
    }
    
    # Check styles
    if ($path -match '(\.css$|\.scss$|\.less$|\.sass$|\.styl$|\.html$|\.vue$|\.jsx$|\.tsx$)') {
      $hasStyleFiles = $true
    }
    
    # Check tests
    if ($path -match '(test|spec|__tests__|__spec__|\.test\.|\.spec\.)') {
      $hasTestFiles = $true
    }
  }
  
  # Determine type by priority
  if ($hasFixFiles) {
    return "fix: $Message"
  }
  elseif ($hasTestFiles) {
    return "test: $Message"
  }
  elseif ($hasFeatureFiles) {
    return "feat: $Message"
  }
  elseif ($hasDocsFiles) {
    return "docs: $Message"
  }
  elseif ($hasStyleFiles) {
    return "style: $Message"
  }
  elseif ($hasBuildFiles) {
    return "build: $Message"
  }
  elseif ($hasRefactorFiles) {
    return "refactor: $Message"
  }
  else {
    return "chore: $Message"
  }
}

# ============================================================================
# Functions for working with backup.json
# ============================================================================

# Save backup.json with current repository state
function Save-BackupJson {
  param(
    [string]$LocalPath,
    [string]$RepoUuid
  )
  
  $backupFile = Join-Path (Join-Path $LocalPath ".ergovcs") "backup.json"
  $backupDir = Split-Path $backupFile -Parent
  if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  }
  
  # Get repository file structure
  $structure = Get-RepositoryStructure -LocalPath $LocalPath
  $currentBranch = Get-CurrentBranch -LocalPath $LocalPath
  
  $backupData = @{
    repository_uuid = $RepoUuid
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    branch = $currentBranch
    structure = $structure
  }
  
  $backupData | ConvertTo-Json -Depth 20 | Set-Content -Path $backupFile -Encoding UTF8
  Write-Host "[INFO] Backup saved: $backupFile" -ForegroundColor Gray
}

# Get repository structure for backup.json
function Get-RepositoryStructure {
  param([string]$LocalPath)
  
  $structure = @()
  
  # Get all files and directories (excluding .ergovcs)
  Get-ChildItem -Path $LocalPath -Recurse -Force | ForEach-Object {
    if ($_.FullName -notlike "*\.ergovcs*") {
      $relativePath = [System.IO.Path]::GetRelativePath($LocalPath, $_.FullName).Replace('\', '/')
      
      $item = @{
        path = $relativePath
        name = $_.Name
        is_directory = $_.PSIsContainer
        last_modified = $_.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
      }
      
      if (-not $_.PSIsContainer) {
        # For files add content hash
        $item.hash = Get-FileContentHash -FilePath $_.FullName
        $item.size = $_.Length
      }
      
      $structure += $item
    }
  }
  
  return $structure
}

# Get current branch from config
function Get-CurrentBranch {
  param([string]$LocalPath)
  
  # Try to get from local config
  $localReposFile = Join-Path (Join-Path $LocalPath ".ergovcs") "repos.json"
  if (Test-Path $localReposFile) {
    try {
      $reposJson = Get-Content $localReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $repo = $property.Value
        if ($repo.local_path -eq $LocalPath) {
          return if ($repo.current_branch) { $repo.current_branch } else { "main" }
        }
      }
    }
    catch {}
  }
  
  # Fallback: global config
  $globalReposFile = Join-Path (Join-Path $env:USERPROFILE ".ergovcs") "repos.json"
  if (Test-Path $globalReposFile) {
    try {
      $reposJson = Get-Content $globalReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $repo = $property.Value
        if ($repo.local_path -eq $LocalPath) {
          return if ($repo.current_branch) { $repo.current_branch } else { "main" }
        }
      }
    }
    catch {}
  }
  
  return "main"
}

# Update repository config
function Update-RepositoryConfig {
  param(
    [string]$Uuid,
    [string]$LastUpdated,
    [string]$CurrentBranch = $null
  )
  
  $configDir = Join-Path $env:USERPROFILE ".ergovcs"
  $configFile = Join-Path $configDir "repos.json"
  
  if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
  }
  
  $configData = @{ repositories = @{} }
  if (Test-Path $configFile) {
    try {
      $existing = Get-Content $configFile -Raw | ConvertFrom-Json
      if ($existing.repositories) {
        foreach ($p in $existing.repositories.PSObject.Properties) {
          $configData.repositories[$p.Name] = $p.Value
        }
      }
    } catch {}
  }
  
  if ($configData.repositories.ContainsKey($Uuid)) {
    $configData.repositories[$Uuid].last_updated = $LastUpdated
    if ($CurrentBranch) {
      $configData.repositories[$Uuid].current_branch = $CurrentBranch
    }
  }
  
  $configData | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
}
