# 공통 함수. 다른 스크립트에서 dot-source 한다. (Windows PowerShell 5.1 / PowerShell 7 호환)
# 모든 경로는 이 파일의 위치를 기준으로 계산하므로 현재 작업 디렉터리와 무관하게 동작한다.

$ScriptsDir = $PSScriptRoot
$ExampleDir = Split-Path -Parent $ScriptsDir
$MySqlDir = Join-Path $ExampleDir 'dbms\mysql'
$ResultsDir = Join-Path $ExampleDir 'reports\test-results'
$MySqlEnvFile = Join-Path $MySqlDir '.env'
$MySqlContainer = 'web-security-example-mysql'
$DockerNetwork = 'web-security-example'

function Write-Log([string]$Message) {
    # 메서드 인자 안에서 -f 를 쓰면 쉼표가 인자 구분자로 해석되므로 문자열을 먼저 만든다.
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    [Console]::Error.WriteLine($line)
}

function Stop-WithError([string]$Message, [int]$Code = 1) {
    [Console]::Error.WriteLine("[ERROR] $Message (exit $Code)")
    exit $Code
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Stop-WithError "'$Name' 명령을 찾을 수 없습니다. 설치 후 다시 실행하세요." 127
    }
}

# dbms/mysql/.env 를 KEY=VALUE 형식으로만 읽는다. 이미 설정된 환경변수가 우선한다.
function Import-MySqlEnv {
    if (-not (Test-Path $MySqlEnvFile)) {
        Stop-WithError "$MySqlEnvFile 이 없습니다. '.env.example'을 복사해 '.env'를 만드세요." 2
    }
    foreach ($line in Get-Content -Path $MySqlEnvFile -Encoding UTF8) {
        if ($line -match '^\s*#' -or $line -notmatch '^([A-Z_][A-Z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]; $value = $Matches[2]
        if (-not (Test-Path "Env:$key")) { Set-Item -Path "Env:$key" -Value $value }
    }
    if (-not $env:MYSQL_PORT) { $env:MYSQL_PORT = '3306' }
}

# 설정되어 있으면 Invoke-Native 출력을 이 파일에도 기록한다(테스트 결과 수집).
$script:NativeLogFile = $null

function Invoke-Native {
    # 네이티브 명령을 실행하고 종료 코드만 반환한다.
    # 출력은 콘솔(및 로그 파일)로 보내며, PowerShell 5.1에서 stderr가 오류로 처리되지 않도록 한다.
    param([string]$Exe, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Node/Python/Maven 출력(UTF-8)을 콘솔 코드페이지(CP949 등)로 잘못 해석하지 않도록 호출 동안만 UTF-8로 지정한다.
    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    try {
        if ($script:NativeLogFile) {
            # Tee-Object는 PowerShell 5.1에서 UTF-16으로 기록하므로 UTF-8로 직접 추가한다.
            & $Exe @Arguments 2>&1 | ForEach-Object {
                $text = "$_"
                Add-Content -Path $script:NativeLogFile -Value $text -Encoding UTF8
                $text
            } | Out-Host
        } else {
            & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
        }
        return $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $previousEncoding
        $ErrorActionPreference = $previous
    }
}

function Invoke-Compose([string[]]$Arguments) {
    $all = @('compose', '--project-directory', $MySqlDir, '-f', (Join-Path $MySqlDir 'compose.yaml'), '--env-file', $MySqlEnvFile) + $Arguments
    $code = Invoke-Native docker $all
    if ($code -ne 0) { Stop-WithError "docker compose $($Arguments -join ' ') 실패" $code }
}

function Get-MySqlHealth {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $status = & docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $MySqlContainer 2>$null
    $ErrorActionPreference = $previous
    if ($LASTEXITCODE -ne 0 -or -not $status) { return 'missing' }
    return "$status".Trim()
}

function Wait-MySql([int]$TimeoutSeconds = 180) {
    $waited = 0
    while ($true) {
        $status = Get-MySqlHealth
        switch ($status) {
            'healthy' { Write-Log "MySQL ready (${waited}s)"; return }
            'missing' { Stop-WithError "MySQL 컨테이너($MySqlContainer)가 없습니다. 'mysql.ps1 up'을 먼저 실행하세요." 3 }
            'unhealthy' { Stop-WithError "MySQL health check 실패. 'docker logs $MySqlContainer'로 원인을 확인하세요." 4 }
        }
        if ($waited -ge $TimeoutSeconds) { Stop-WithError "MySQL이 ${TimeoutSeconds}초 안에 준비되지 않았습니다 (status=$status)." 5 }
        Start-Sleep -Seconds 2
        $waited += 2
    }
}
