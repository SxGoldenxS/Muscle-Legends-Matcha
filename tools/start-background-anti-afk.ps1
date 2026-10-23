param([string]$StateFile = 'C:\matcha\workspace\muscle-legends-anti-afk.ini')

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    throw 'Load the Muscle Legends hub in Matcha before starting its background helper.'
}

$runtimeDirectory = Join-Path $PSScriptRoot '.runtime\AutoHotkey-2.0.30'
$runtimePath = Join-Path $runtimeDirectory 'AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
    $archivePath = Join-Path $runtimeDirectory 'AutoHotkey_2.0.30.zip'
    Invoke-WebRequest -Uri 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.30/AutoHotkey_2.0.30.zip' -OutFile $archivePath
    $expectedDigest = '1e0ece7ecb2d5646e55758150472677996a57f9db5c83d2996d8b47b9e2f31a4'
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedDigest) {
        throw 'The official AutoHotkey archive did not match its published SHA256 digest.'
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $runtimeDirectory -Force
}

$helperScript = Join-Path $PSScriptRoot 'background-anti-afk.ahk'
$helperProcess = Start-Process -FilePath $runtimePath -WindowStyle Hidden -PassThru -ArgumentList @(
    '/ErrorStdOut', ('"' + $helperScript + '"'), ('"' + $StateFile + '"')
)
Write-Output ('Background anti-AFK running as process ' + $helperProcess.Id + '. No administrator access was requested.')
Write-Output 'Turn Anti AFK off in the hub to pause it, or use its tray menu to exit.'
