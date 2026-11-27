<#
.SYNOPSIS
  프레임워크 예제 빌드/테스트/실행 (example.sh 와 동일한 명령)
.EXAMPLE
  .\example\scripts\example.ps1 build all
  .\example\scripts\example.ps1 test express
  .\example\scripts\example.ps1 run fastapi
  .\example\scripts\example.ps1 docker-test all
  .\example\scripts\example.ps1 docker-run django
  .\example\scripts\example.ps1 docker-stop all
  .\example\scripts\example.ps1 smoke all
  .\example\scripts\example.ps1 list
#>
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('build', 'test', 'run', 'docker-build', 'docker-test', 'docker-run', 'docker-stop', 'smoke', 'list')]
    [string]$Command,
    [Parameter(Position = 1)]
    [string]$Target
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'frameworks.ps1')

if ($Command -eq 'list') {
    foreach ($name in $Frameworks.Keys) {
        '{0,-12} port={1} db={2}_customer_db' -f $name, $Frameworks[$name].Port, $Frameworks[$name].Prefix
    }
    exit 0
}
if (-not $Target) { Stop-WithError "대상 프레임워크를 지정하세요: $($Frameworks.Keys -join ', '), all" 64 }
if ($Target -eq 'all') {
    if ($Command -eq 'run') { Stop-WithError 'run 은 하나의 프레임워크만 지정할 수 있습니다 (docker-run all 사용 가능).' 64 }
    $targets = @($Frameworks.Keys)
} elseif ($Frameworks.Contains($Target)) {
    $targets = @($Target)
} else {
    Stop-WithError "알 수 없는 프레임워크: $Target (목록: $($Frameworks.Keys -join ', '))" 64
}

function Set-FwEnv([string]$Fw, [string]$Where, [string]$Purpose) {
    $prefix = $Frameworks[$Fw].Prefix
    $passwordVar = "$($prefix.ToUpper())_DB_PASSWORD"
    $password = [Environment]::GetEnvironmentVariable($passwordVar)
    if (-not $password) { Stop-WithError "$passwordVar 가 $MySqlEnvFile 에 없습니다." 2 }
    if ($Where -eq 'docker') {
        # 컨테이너 내부에서 localhost는 컨테이너 자신이다. 공통 네트워크의 서비스 이름을 사용한다.
        $env:DB_HOST = 'mysql'; $env:DB_PORT = '3306'
    } else {
        $env:DB_HOST = '127.0.0.1'; $env:DB_PORT = $env:MYSQL_PORT
    }
    $env:DB_NAME = if ($Purpose -eq 'test') { "${prefix}_customer_test_db" } else { "${prefix}_customer_db" }
    $env:DB_USERNAME = "${prefix}_app"
    $env:DB_PASSWORD = $password
    $env:DB_READER_USERNAME = "${prefix}_reader"
    $env:DB_READER_PASSWORD = $env:READER_DB_PASSWORD
    $env:APP_PORT = "$($Frameworks[$Fw].Port)"
}

function Add-Result([string]$Fw, [string]$Mode, [int]$Code, [int]$Seconds) {
    $status = if ($Code -eq 0) { 'PASS' } else { 'FAIL' }
    New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
    $summary = Join-Path $ResultsDir 'summary.md'
    if (-not (Test-Path $summary)) {
        "| 시각 | 프레임워크 | 모드 | 결과 | 종료 코드 | 소요(s) | 로그 |`n| --- | --- | --- | --- | --- | --- | --- |" | Out-File -FilePath $summary -Encoding utf8
    }
    "| $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Fw | $Mode | $status | $Code | $Seconds | $Fw-$Mode.log |" | Out-File -FilePath $summary -Append -Encoding utf8
    Write-Log "$Fw [$Mode] $status (exit $Code, ${Seconds}s)"
}

function Get-Image([string]$Fw, [string]$Kind) { "web-security-example/${Fw}:$Kind" }

function Build-Images([string]$Fw) {
    $dir = Join-Path $ExampleDir $Fw
    foreach ($kind in @('test', 'runtime')) {
        $code = Invoke-Native docker @('build', '-q', '--target', $kind, '-t', (Get-Image $Fw $kind), $dir)
        if ($code -ne 0) { return $code }
    }
    Write-Log "$Fw 이미지 빌드 완료"
    return 0
}

# 비밀번호는 명령행 인자에 넣지 않고 환경변수 이름만 전달한다(-e NAME).
$dockerEnvArgs = @('-e', 'DB_HOST', '-e', 'DB_PORT', '-e', 'DB_NAME', '-e', 'DB_USERNAME', '-e', 'DB_PASSWORD',
    '-e', 'DB_READER_USERNAME', '-e', 'DB_READER_PASSWORD', '-e', 'APP_PORT')

function Invoke-One([string]$Fw) {
    $dir = Join-Path $ExampleDir $Fw
    $started = Get-Date
    switch ($Command) {
        'build' {
            Write-Log "$Fw 빌드"
            Push-Location $dir; try { return (Invoke-FwHostBuild $Fw) } finally { Pop-Location }
        }
        'test' {
            Wait-MySql 60
            Set-FwEnv $Fw 'host' 'test'
            New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
            $script:NativeLogFile = Join-Path $ResultsDir "$Fw-host.log"
            Remove-Item $script:NativeLogFile -ErrorAction SilentlyContinue
            Write-Log "$Fw 테스트 (host, DB_NAME=$env:DB_NAME)"
            Push-Location $dir
            try { $code = Invoke-FwHostTest $Fw } finally { Pop-Location; $script:NativeLogFile = $null }
            Add-Result $Fw 'host' $code ([int]((Get-Date) - $started).TotalSeconds)
            return $code
        }
        'run' {
            Wait-MySql 60
            Set-FwEnv $Fw 'host' 'run'
            Write-Log "$Fw 실행: http://127.0.0.1:$env:APP_PORT (DB_NAME=$env:DB_NAME)"
            Push-Location $dir; try { return (Invoke-FwHostRun $Fw) } finally { Pop-Location }
        }
        'docker-build' { Assert-Command docker; return (Build-Images $Fw) }
        'docker-test' {
            Assert-Command docker; Wait-MySql 60
            $code = Build-Images $Fw; if ($code -ne 0) { return $code }
            Set-FwEnv $Fw 'docker' 'test'
            New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
            $script:NativeLogFile = Join-Path $ResultsDir "$Fw-docker.log"
            Remove-Item $script:NativeLogFile -ErrorAction SilentlyContinue
            Write-Log "$Fw 테스트 (docker, network=$DockerNetwork, DB_HOST=$env:DB_HOST)"
            try {
                $code = Invoke-Native docker (@('run', '--rm', '--name', "web-security-example-$Fw-test", '--network', $DockerNetwork) + $dockerEnvArgs + @(Get-Image $Fw 'test'))
            } finally { $script:NativeLogFile = $null }
            Add-Result $Fw 'docker' $code ([int]((Get-Date) - $started).TotalSeconds)
            return $code
        }
        'docker-run' {
            Assert-Command docker; Wait-MySql 60
            $code = Build-Images $Fw; if ($code -ne 0) { return $code }
            Set-FwEnv $Fw 'docker' 'run'
            Invoke-Native docker @('rm', '-f', "web-security-example-$Fw") | Out-Null
            $code = Invoke-Native docker (@('run', '-d', '--name', "web-security-example-$Fw", '--network', $DockerNetwork) + $dockerEnvArgs +
                @('-e', 'DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1', '-p', "127.0.0.1:$($env:APP_PORT):$($env:APP_PORT)", (Get-Image $Fw 'runtime')))
            if ($code -eq 0) { Write-Log "$Fw 컨테이너 실행: http://127.0.0.1:$env:APP_PORT (종료: example.ps1 docker-stop $Fw)" }
            return $code
        }
        'docker-stop' {
            Assert-Command docker
            $code = Invoke-Native docker @('stop', '-t', '15', "web-security-example-$Fw")
            if ($code -eq 0) { Invoke-Native docker @('rm', "web-security-example-$Fw") | Out-Null; Write-Log "$Fw 컨테이너 종료" }
            else { Write-Log "$Fw 컨테이너가 실행 중이 아닙니다." }
            return 0
        }
        'smoke' { return (Invoke-Native (Get-Process -Id $PID).Path @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ScriptsDir 'smoke.ps1'), $Fw)) }
    }
}

if ($Command -in 'test', 'run', 'docker-test', 'docker-run') { Import-MySqlEnv }

$failed = @()
foreach ($fw in $targets) {
    $code = Invoke-One $fw
    if ($code -ne 0) { $failed += $fw }
}
if ($failed.Count -gt 0) { Stop-WithError "실패: $($failed -join ', ')" 1 }
exit 0
