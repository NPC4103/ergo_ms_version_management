# Р›РѕРіРёРєР° СЂР°Р±РѕС‚С‹ СЃ СЂРµРїРѕР·РёС‚РѕСЂРёСЏРјРё: СЃРѕР·РґР°РЅРёРµ СЃС‚СЂСѓРєС‚СѓСЂС‹, СЃРѕС…СЂР°РЅРµРЅРёРµ РјРµС‚Р°РґР°РЅРЅС‹С…, РёРјРїРѕСЂС‚, СЂР°Р±РѕС‚Р° СЃ API

# ============================================================================
# Р¤СѓРЅРєС†РёРё РґР»СЏ СЂР°Р±РѕС‚С‹ СЃ API
# ============================================================================

# РџРѕР»СѓС‡РёС‚СЊ Р±Р°Р·РѕРІС‹Р№ URL API
function Get-ApiBaseUrl {
  # РџСЂРёРѕСЂРёС‚РµС‚: РїРµСЂРµРјРµРЅРЅР°СЏ РѕРєСЂСѓР¶РµРЅРёСЏ > РєРѕРЅС„РёРі С„Р°Р№Р» > Р·РЅР°С‡РµРЅРёРµ РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ
  
  # РџСЂРѕРІРµСЂСЏРµРј РїРµСЂРµРјРµРЅРЅСѓСЋ РѕРєСЂСѓР¶РµРЅРёСЏ
  if ($env:API_BASE_URL) {
    return $env:API_BASE_URL
  }
  
  # РџСЂРѕРІРµСЂСЏРµРј РєРѕРЅС„РёРі С„Р°Р№Р» РІ РґРѕРјР°С€РЅРµР№ РґРёСЂРµРєС‚РѕСЂРёРё
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
  
  # РСЃРїРѕР»СЊР·СѓРµРј РїРµСЂРµРјРµРЅРЅС‹Рµ РѕРєСЂСѓР¶РµРЅРёСЏ РґР»СЏ С…РѕСЃС‚Р° Рё РїРѕСЂС‚Р° РёР»Рё Р·РЅР°С‡РµРЅРёСЏ РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ
  $apiHost = if ($env:API_HOST) { $env:API_HOST } else { "localhost" }
  $apiPort = if ($env:API_PORT) { $env:API_PORT } else { "8000" }
  
  return "http://${apiHost}:${apiPort}/api/version_management"
}

# Р’С‹РїРѕР»РЅРёС‚СЊ HTTP Р·Р°РїСЂРѕСЃ Рє API
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
  
  # РџРѕР»СѓС‡Р°РµРј Р±Р°Р·РѕРІС‹Р№ URL
  $baseUrl = Get-ApiBaseUrl
  $url = "$baseUrl$Endpoint"
  
  # РџРѕРґРіРѕС‚РѕРІРєР° Р·Р°РіРѕР»РѕРІРєРѕРІ
  $requestHeaders = @{
    "Content-Type" = "application/json"
    "Accept" = "application/json"
  }
  
  # Р”РѕР±Р°РІР»СЏРµРј РєР°СЃС‚РѕРјРЅС‹Рµ Р·Р°РіРѕР»РѕРІРєРё
  foreach ($key in $Headers.Keys) {
    $requestHeaders[$key] = $Headers[$key]
  }
  
  try {
    # РџРѕРґРіРѕС‚РѕРІРєР° РїР°СЂР°РјРµС‚СЂРѕРІ РґР»СЏ Invoke-RestMethod
    $params = @{
      Uri = $url
      Method = $Method
      Headers = $requestHeaders
      ErrorAction = "Stop"
    }
    
    # Р”РѕР±Р°РІР»СЏРµРј С‚РµР»Рѕ Р·Р°РїСЂРѕСЃР° РґР»СЏ POST/PUT/PATCH
    if ($Body -and ($Method -eq "POST" -or $Method -eq "PUT" -or $Method -eq "PATCH")) {
      $params["Body"] = $Body
    }
    
    # Р’С‹РїРѕР»РЅРµРЅРёРµ Р·Р°РїСЂРѕСЃР°
    $response = Invoke-RestMethod @params
    
    # Р’РѕР·РІСЂР°С‰Р°РµРј РѕС‚РІРµС‚ (РјРѕР¶РµС‚ Р±С‹С‚СЊ РѕР±СЉРµРєС‚ РёР»Рё СЃС‚СЂРѕРєР°)
    if ($response -is [string]) {
      return $response
    } else {
      return ($response | ConvertTo-Json -Depth 10)
    }
  }
  catch {
    # РћР±СЂР°Р±РѕС‚РєР° РѕС€РёР±РѕРє
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMessage = $_.Exception.Message
    
    # РџС‹С‚Р°РµРјСЃСЏ РёР·РІР»РµС‡СЊ РґРµС‚Р°Р»Рё РѕС€РёР±РєРё РёР· РѕС‚РІРµС‚Р°
    if ($_.Exception.Response) {
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        
        # РџС‹С‚Р°РµРјСЃСЏ СЂР°СЃРїР°СЂСЃРёС‚СЊ JSON СЃ РѕС€РёР±РєРѕР№
        $errorObj = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($errorObj -and $errorObj.detail) {
          $errorMessage = $errorObj.detail
        } else {
          $errorMessage = $responseBody
        }
      }
      catch {
        # Р•СЃР»Рё РЅРµ СѓРґР°Р»РѕСЃСЊ СЂР°СЃРїР°СЂСЃРёС‚СЊ, РёСЃРїРѕР»СЊР·СѓРµРј СЃС‚Р°РЅРґР°СЂС‚РЅРѕРµ СЃРѕРѕР±С‰РµРЅРёРµ
      }
    }
    
    Write-Host "[ERROR] API Р·Р°РїСЂРѕСЃ РЅРµ СѓРґР°Р»СЃСЏ: $errorMessage" -ForegroundColor Red
    Write-Host "  URL: $url" -ForegroundColor Yellow
    Write-Host "  РњРµС‚РѕРґ: $Method" -ForegroundColor Yellow
    if ($statusCode) {
      Write-Host "  HTTP РєРѕРґ: $statusCode" -ForegroundColor Yellow
    }
    
    # Р’РѕР·РІСЂР°С‰Р°РµРј РєРѕРґ РѕС€РёР±РєРё
    return $null
  }
}

# РЎРѕР·РґР°С‚СЊ СЂРµРїРѕР·РёС‚РѕСЂРёР№ С‡РµСЂРµР· API
function Invoke-ApiCreateRepository {
  param([string]$Name = $null)
  
  # РџР°СЂР°РјРµС‚СЂС‹:
  #   $Name - РЅР°Р·РІР°РЅРёРµ СЂРµРїРѕР·РёС‚РѕСЂРёСЏ (РѕРїС†РёРѕРЅР°Р»СЊРЅРѕ)
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: JSON СЃ РёРЅС„РѕСЂРјР°С†РёРµР№ Рѕ СЃРѕР·РґР°РЅРЅРѕРј СЂРµРїРѕР·РёС‚РѕСЂРёРё (id, name, path, created_at)
  
  $body = @{}
  if ($Name) {
    $body = @{ name = $Name }
  }
  $bodyJson = $body | ConvertTo-Json -Depth 2
  
  # РЎС‚Р°РЅРґР°СЂС‚РЅС‹Р№ create ViewSet РІ DRF РґРѕСЃС‚СѓРїРµРЅ РїРѕ POST /repositories/
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $bodyJson
}

# РљР»РѕРЅРёСЂРѕРІР°С‚СЊ СЂРµРїРѕР·РёС‚РѕСЂРёР№ С‡РµСЂРµР· API
function Invoke-ApiCloneRepository {
  param([string]$Uuid)
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ РєР»РѕРЅРёСЂРѕРІР°РЅРёРµ С‡РµСЂРµР· API
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: РїСѓС‚СЊ Рє РєР»РѕРЅРёСЂРѕРІР°РЅРЅРѕРјСѓ СЂРµРїРѕР·РёС‚РѕСЂРёСЋ
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/clone/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/clone/"
}

# РЎРѕР·РґР°С‚СЊ РєРѕРјРјРёС‚ С‡РµСЂРµР· API
function Invoke-ApiCreateCommit {
  param(
    [string]$Uuid,
    [string]$Message,
    [string]$Files = $null
  )
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ СЃРѕР·РґР°РЅРёРµ РєРѕРјРјРёС‚Р° С‡РµСЂРµР· API
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: С…РµС€ РєРѕРјРјРёС‚Р°
  
  $body = @{
    message = $Message
  } | ConvertTo-Json -Depth 2
  
  if ($Files) {
    $bodyObj = $body | ConvertFrom-Json
    $bodyObj | Add-Member -NotePropertyName "files" -NotePropertyValue ($Files | ConvertFrom-Json)
    $body = $bodyObj | ConvertTo-Json -Depth 2
  }
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/commits/create/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/commits/create/" -Body $body
}

# РћС‚РїСЂР°РІРёС‚СЊ РёР·РјРµРЅРµРЅРёСЏ С‡РµСЂРµР· API
function Invoke-ApiPushChanges {
  param(
    [string]$Uuid,
    [string]$Branch,
    [string]$Changes = $null
  )
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ РѕС‚РїСЂР°РІРєСѓ РёР·РјРµРЅРµРЅРёР№ С‡РµСЂРµР· API
  
  $body = @{
    branch = $Branch
  } | ConvertTo-Json -Depth 2
  
  if ($Changes) {
    $bodyObj = $body | ConvertFrom-Json
    $bodyObj | Add-Member -NotePropertyName "changes" -NotePropertyValue ($Changes | ConvertFrom-Json)
    $body = $bodyObj | ConvertTo-Json -Depth 2
  }
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/push/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/push/" -Body $body
}

# РћР±РЅРѕРІРёС‚СЊ Р»РѕРєР°Р»СЊРЅС‹Р№ СЂРµРїРѕР·РёС‚РѕСЂРёР№ С‡РµСЂРµР· API
function Invoke-ApiUpdateRepository {
  param(
    [string]$Uuid,
    [string]$Branch
  )
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ РѕР±РЅРѕРІР»РµРЅРёРµ С‡РµСЂРµР· API
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: РїСѓС‚СЊ Рє РѕР±РЅРѕРІР»РµРЅРЅС‹Рј С„Р°Р№Р»Р°Рј РёР»Рё Р°СЂС…РёРІ
  
  $body = @{
    branch = $Branch
  } | ConvertTo-Json -Depth 2
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/update/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/update/" -Body $body
}

# РџРѕР»СѓС‡РёС‚СЊ СЃРїРёСЃРѕРє РєРѕРјРјРёС‚РѕРІ С‡РµСЂРµР· API
function Get-ApiCommitsList {
  param([string]$Uuid)
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ РїРѕР»СѓС‡РµРЅРёРµ СЃРїРёСЃРєР° РєРѕРјРјРёС‚РѕРІ С‡РµСЂРµР· API
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: JSON СЃРѕ СЃРїРёСЃРєРѕРј РєРѕРјРјРёС‚РѕРІ
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/commits/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/"
}

# РџРѕР»СѓС‡РёС‚СЊ РёРЅС„РѕСЂРјР°С†РёСЋ Рѕ РєРѕРјРјРёС‚Рµ С‡РµСЂРµР· API
function Get-ApiCommit {
  param(
    [string]$Uuid,
    [string]$CommitHash
  )
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ РїРѕР»СѓС‡РµРЅРёРµ РёРЅС„РѕСЂРјР°С†РёРё Рѕ РєРѕРјРјРёС‚Рµ С‡РµСЂРµР· API
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: JSON СЃ РјРµС‚Р°РґР°РЅРЅС‹РјРё РєРѕРјРјРёС‚Р°
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/commits/$CommitHash/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/$CommitHash/"
}

# РџРѕР»СѓС‡РёС‚СЊ diff РєРѕРјРјРёС‚Р° С‡РµСЂРµР· API
function Get-ApiCommitDiff {
  param(
    [string]$Uuid,
    [string]$CommitHash
  )
  
  # TODO: Р РµР°Р»РёР·РѕРІР°С‚СЊ РїРѕР»СѓС‡РµРЅРёРµ diff РєРѕРјРјРёС‚Р° С‡РµСЂРµР· API
  # Р’РѕР·РІСЂР°С‰Р°РµС‚: diff РІ С„РѕСЂРјР°С‚Рµ unified diff
  
  Write-Host "[TODO] Р’С‹Р·РІР°С‚СЊ API /api/repositories/$Uuid/commits/$CommitHash/diff/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/$CommitHash/diff/"
}

# ============================================================================
# Р›РѕРєР°Р»СЊРЅС‹Рµ С„СѓРЅРєС†РёРё СЂР°Р±РѕС‚С‹ СЃ СЂРµРїРѕР·РёС‚РѕСЂРёСЏРјРё
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
      Write-Host "[ERROR] Expand-Archive РЅРµРґРѕСЃС‚СѓРїРµРЅ. РСЃРїРѕР»СЊР·СѓР№С‚Рµ PowerShell 5.1 РёР»Рё РІС‹С€Рµ." -ForegroundColor Red
      exit 1
    }
    Expand-Archive -Path $Source -DestinationPath $Target -Force
  }
  else {
    Write-Host "[ERROR] РќРµРёР·РІРµСЃС‚РЅС‹Р№ РёСЃС‚РѕС‡РЅРёРє: $Source" -ForegroundColor Red
    Write-Host "[INFO] РџРѕРґРґРµСЂР¶РёРІР°СЋС‚СЃСЏ: РїР°РїРєР° РёР»Рё zip-Р°СЂС…РёРІ" -ForegroundColor Yellow
    exit 1
  }
}

