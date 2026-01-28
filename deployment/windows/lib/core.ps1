# core.ps1
# Common utilities: project root search, UUID generation, hashing, ignore checking

$script:ProjectRoot = $null
$script:MediaDir = $null
$script:CliName = 'ergovcs'
$script:CliPath = "$env:SystemRoot\System32\$script:CliName.bat"

function Detect-ProjectRoot {
  if ($script:ProjectRoot) { return }

  $current = Get-Location
  while ($current.Path -ne $current.Drive.Root) {
    $versionManagementPath = Join-Path $current.Path "modules\version_management"
    if (Test-Path $versionManagementPath -PathType Container) {
      $script:ProjectRoot = $current.Path
      $script:MediaDir = Join-Path $script:ProjectRoot "media\version_management"
      New-Item -ItemType Directory -Force -Path $script:MediaDir | Out-Null
      return
    }
    $current = $current.Parent
  }

  Write-Host "[ERROR] Failed to find project root (modules\version_management)!" -ForegroundColor Red
  exit 1
}

function New-Uuid {
  [guid]::NewGuid().ToString()
}

function Get-CliName {
  return $script:CliName
}

function Get-CliPath {
  return $script:CliPath
}

# ============================================================================
# Functions for working with paths and repository search
# ============================================================================

function Find-LocalRepositoryRoot {
  $current = Get-Location
  while ($current.Path -ne $current.Drive.Root) {
    $ergovcsDir = Join-Path $current.Path ".ergovcs"
    $stagingFile = Join-Path $ergovcsDir "staging.json"
    $configFile = Join-Path $ergovcsDir "repos.json"
    
    if ((Test-Path $stagingFile) -or (Test-Path $configFile)) {
      return $current.Path
    }
    $current = $current.Parent
  }
  return $null
}

function Get-CurrentRepositoryUuid {
  param([string]$LocalPath)

  if (-not $LocalPath) {
    Write-Host "[DEBUG] Repository root not found" -ForegroundColor Gray
    return $null
  }
  
  Write-Host "[DEBUG] Repository root: $LocalPath" -ForegroundColor Gray
  
  # Path to local repos.json file in .ergovcs directory
  $localReposFile = Join-Path $LocalPath ".ergovcs" "repos.json"
  Write-Host "[DEBUG] Looking for local file: $localReposFile" -ForegroundColor Gray
  
  # Try to read from local .ergovcs/repos.json first
  if (Test-Path $localReposFile) {
    Write-Host "[DEBUG] Local repos.json file found" -ForegroundColor Gray
    try {
      $reposJson = Get-Content $localReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      
      Write-Host "[DEBUG] Repositories read: $($repos.repositories.PSObject.Properties.Count)" -ForegroundColor Gray
      
      # Look for repository with local_path matching current path
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $uuid = $property.Name
        $repo = $property.Value
        
        Write-Host "[DEBUG] Checking repository: $uuid" -ForegroundColor Gray
        Write-Host "[DEBUG]  local_path: $($repo.local_path)" -ForegroundColor Gray
        Write-Host "[DEBUG]  current: $LocalPath" -ForegroundColor Gray
        
        # Compare paths (account for possible format differences)
        if ($repo.local_path -and (
            $repo.local_path -eq $LocalPath -or 
            (Resolve-Path $repo.local_path -ErrorAction SilentlyContinue) -eq (Resolve-Path $LocalPath -ErrorAction SilentlyContinue))) {
          Write-Host "[DEBUG] Found UUID: $uuid" -ForegroundColor Gray
          return $uuid
        }
      }
    }
    catch {
      Write-Host "[ERROR] Failed to read or parse local repos.json: $_" -ForegroundColor Red
    }
  } else {
    Write-Host "[DEBUG] Local repos.json file not found" -ForegroundColor Gray
  }
  
  # Fallback: check staging.json (if exists)
  $stagingFile = Join-Path $LocalPath ".ergovcs\staging.json"
  if (Test-Path $stagingFile) {
    Write-Host "[DEBUG] Trying to read staging.json" -ForegroundColor Gray
    try {
      $stagingJson = Get-Content $stagingFile -Raw -Encoding UTF8
      $staging = $stagingJson | ConvertFrom-Json -ErrorAction Stop
      if ($staging.repository_uuid) {
        Write-Host "[DEBUG] Found UUID from staging: $($staging.repository_uuid)" -ForegroundColor Gray
        return $staging.repository_uuid
      }
    }
    catch {
      Write-Host "[ERROR] Failed to read staging area: $_" -ForegroundColor Red
    }
  }
  
  # Fallback: check global file (for backward compatibility)
  $globalReposFile = Join-Path $env:USERPROFILE ".ergovcs\repos.json"
  if (Test-Path $globalReposFile) {
    Write-Host "[DEBUG] Trying global file: $globalReposFile" -ForegroundColor Gray
    try {
      $reposJson = Get-Content $globalReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $uuid = $property.Name
        $repo = $property.Value
        
        if ($repo.local_path -and (
            $repo.local_path -eq $LocalPath -or 
            (Resolve-Path $repo.local_path -ErrorAction SilentlyContinue) -eq (Resolve-Path $LocalPath -ErrorAction SilentlyContinue))) {
          Write-Host "[DEBUG] Found UUID in global file: $uuid" -ForegroundColor Gray
          return $uuid
        }
      }
    }
    catch {
      Write-Host "[ERROR] Failed to read global repos.json: $_" -ForegroundColor Red
    }
  }
  
  Write-Host "[DEBUG] Repository UUID not found" -ForegroundColor Gray
  return $null
}

# ============================================================================
# Functions for hashing and file content
# ============================================================================

function Get-FileContentHash {
  param([string]$FilePath)
  
  if (-not (Test-Path $FilePath)) {
    return $null
  }
  
  try {
    $content = Get-Content $FilePath -Raw -Encoding UTF8
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))
    return [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
  }
  catch {
    return $null
  }
}

function Get-FileChangeType {
  param(
    [string]$FilePath,
    [string]$LocalPath,
    [hashtable]$PreviousState,
    [bool]$IsDirectory = $false
  )
  
  $relativePath = [System.IO.Path]::GetRelativePath($LocalPath, $FilePath).Replace('\', '/')
  
  # Check if file/directory exists
  $exists = Test-Path $FilePath
  
  # Look in previous state
  $previousEntry = $null
  if ($PreviousState.structure) {
    # Search by current path
    $previousEntry = $PreviousState.structure | Where-Object { 
      $_.path -eq $relativePath 
    } | Select-Object -First 1
    
    # If not found, search by old path (for renames)
    if (-not $previousEntry) {
      $previousEntry = $PreviousState.structure | Where-Object { 
        $_.old_path -eq $relativePath 
      } | Select-Object -First 1
    }
  }
  
  if ($exists) {
    if (-not $previousEntry) {
      # New file/directory
      return "created"
    }
    else {
      if ($previousEntry.is_directory -eq $IsDirectory) {
        # Check for rename
        if ($previousEntry.path -ne $relativePath) {
          return "renamed"
        }
        
        # For files check content hash
        if (-not $IsDirectory) {
          $currentHash = Get-FileContentHash -FilePath $FilePath
          if ($currentHash -and $previousEntry.hash -and $currentHash -ne $previousEntry.hash) {
            return "updated"
          }
        }
        
        # No changes
        return "unchanged"
      }
      else {
        # Type changed (was file, became directory or vice versa)
        return "updated"
      }
    }
  }
  else {
    if ($previousEntry) {
      # File/directory deleted
      return "deleted"
    }
    # Nothing was and nothing is
    return "unchanged"
  }
}

# ============================================================================
# Functions for file ignoring
# ============================================================================

function Test-Ignored {
  param(
    [string]$FilePath,
    [array]$IgnorePatterns
  )
  
  # Always ignore .ergovcs
  if ($FilePath -like '.ergovcs/*' -or $FilePath -eq '.ergovcs') {
    return $true
  }
  
  # Normalize path (replace backslashes with forward slashes)
  $normalizedPath = $FilePath.Replace('\', '/')
  
  foreach ($pattern in $IgnorePatterns) {
    $normalizedPattern = $pattern.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedPattern)) {
      continue
    }
    
    # Remove leading and trailing spaces
    $normalizedPattern = $normalizedPattern.Trim()
    
    # Skip comments
    if ($normalizedPattern.StartsWith("#")) {
      continue
    }
    
    # If pattern ends with /, it's a directory
    $isDirectoryPattern = $normalizedPattern.EndsWith('/')
    if ($isDirectoryPattern) {
      $normalizedPattern = $normalizedPattern.TrimEnd('/')
    }
    
    # Special handling for ".*" pattern (files/directories starting with dot)
    if ($normalizedPattern -eq '.*') {
      # Pattern ".*" means: file/directory name starts with dot
      # Check if file/directory name starts with dot
      $fileName = Split-Path -Leaf $normalizedPath
      if ($fileName.StartsWith('.')) {
        return $true
      }
      continue
    }
    
    # Special handling for "*/.* " pattern (files/directories starting with dot in any subdirectory)
    if ($normalizedPattern -eq '*/.*') {
      # Check if path has any segment starting with dot
      $pathSegments = $normalizedPath -split '/'
      foreach ($segment in $pathSegments) {
        if ($segment.StartsWith('.')) {
          return $true
        }
      }
      continue
    }
    
    # Convert glob patterns to regex
    $regexPattern = [regex]::Escape($normalizedPattern)
    $regexPattern = $regexPattern.Replace('\*', '.*').Replace('\?', '.')
    
    # If pattern starts with /, it must match from the beginning of path
    if ($normalizedPattern.StartsWith('/')) {
      $regexPattern = '^' + $regexPattern.Substring(1)
    }
    # Otherwise pattern can match any part of path
    else {
      # If pattern contains /, it must match from segment start
      if ($normalizedPattern.Contains('/')) {
        $regexPattern = '(^|/)' + $regexPattern
      }
      # Otherwise pattern can be anywhere in file/directory name
      else {
        $regexPattern = $regexPattern
      }
    }
    
    # Add ending for full match (if not ending with *)
    if (-not $regexPattern.EndsWith('.*')) {
      $regexPattern = $regexPattern + '$'
    }
    
    # If it's a directory pattern, add trailing slash
    if ($isDirectoryPattern) {
      $regexPattern = $regexPattern.TrimEnd('$') + '(/|$)'
    }
    
    # Check match
    if ($normalizedPath -match $regexPattern) {
      return $true
    }
    
    # Additional check for directories: if path starts with pattern
    if ($normalizedPath.StartsWith($normalizedPattern + '/')) {
      return $true
    }
  }
  
  return $false
}
