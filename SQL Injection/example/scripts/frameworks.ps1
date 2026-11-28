# 프레임워크 등록 정보 (frameworks.sh 와 동일한 내용을 유지한다)
# 신규 프레임워크는 $Frameworks 와 Invoke-FwHost* 의 switch 에 추가한다.

$Frameworks = [ordered]@{
    'spring-boot' = @{ Port = 8081; Prefix = 'spring_boot'; Param = 'lastName' }
    'nestjs'      = @{ Port = 8082; Prefix = 'nestjs';      Param = 'lastName' }
    'express'     = @{ Port = 8083; Prefix = 'express';     Param = 'lastName' }
    'fastapi'     = @{ Port = 8084; Prefix = 'fastapi';     Param = 'last_name' }
    'django'      = @{ Port = 8085; Prefix = 'django';      Param = 'last_name' }
}

# JDK 21 이상을 찾는다: JAVA_HOME → ~/.jdks → 일반 설치 경로. release 파일의 JAVA_VERSION으로 판별한다.
function Find-JavaHome {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    foreach ($root in @((Join-Path $HOME '.jdks'), 'C:\Program Files\Java', 'C:\Program Files\Eclipse Adoptium',
            'C:\Program Files\Amazon Corretto', 'C:\Program Files\Microsoft')) {
        if (Test-Path $root) { $candidates += (Get-ChildItem -Path $root -Directory | ForEach-Object FullName) }
    }
    foreach ($candidate in $candidates) {
        $release = Join-Path $candidate 'release'
        if (-not (Test-Path (Join-Path $candidate 'bin\java.exe')) -or -not (Test-Path $release)) { continue }
        $line = Select-String -Path $release -Pattern '^JAVA_VERSION="(\d+)' | Select-Object -First 1
        if ($line -and [int]$line.Matches[0].Groups[1].Value -ge 21) { return $candidate }
    }
    return $null
}

function Use-Java {
    $javaHome = Find-JavaHome
    if (-not $javaHome) { Stop-WithError "JDK 21 이상이 필요합니다. JAVA_HOME을 설정하거나 'example.ps1 docker-test spring-boot'를 사용하세요." 127 }
    $env:JAVA_HOME = $javaHome
    $env:Path = "$javaHome\bin;$env:Path"
}

function Find-Python {
    foreach ($candidate in @($env:PYTHON, 'python', 'python3')) {
        if ($candidate -and (Get-Command $candidate -ErrorAction SilentlyContinue)) {
            $code = Invoke-Native $candidate @('-c', 'import sys; sys.exit(sys.version_info < (3, 12))')
            if ($code -eq 0) { return $candidate }
        }
    }
    return $null
}

function Initialize-Venv([string]$Requirements) {
    if (-not (Test-Path '.venv')) {
        $python = Find-Python
        if (-not $python) { Stop-WithError 'Python 3.12 이상을 찾을 수 없습니다 (PYTHON 환경변수로 지정 가능).' 127 }
        Write-Log "가상환경 생성: .venv ($python)"
        $code = Invoke-Native $python @('-m', 'venv', '.venv'); if ($code -ne 0) { return $code }
    }
    return (Invoke-Native '.\.venv\Scripts\python.exe' @('-m', 'pip', 'install', '--disable-pip-version-check', '-q', '-r', $Requirements, '-c', 'constraints.txt'))
}

function Initialize-NodeModules {
    Assert-Command npm
    if (-not (Test-Path 'node_modules')) { return (Invoke-Native npm @('ci', '--no-audit', '--no-fund')) }
    return 0
}

# 각 함수는 프레임워크 디렉터리에서 실행되며 종료 코드를 반환한다.
function Invoke-FwHostBuild([string]$Fw) {
    switch ($Fw) {
        'spring-boot' { Use-Java; return (Invoke-Native '.\mvnw.cmd' @('-B', '-q', '-DskipTests', 'package')) }
        { $_ -in 'nestjs', 'express' } {
            Assert-Command npm
            $code = Invoke-Native npm @('ci', '--no-audit', '--no-fund'); if ($code -ne 0) { return $code }
            return (Invoke-Native npm @('run', 'build'))
        }
        'fastapi' {
            $code = Initialize-Venv 'requirements-dev.txt'; if ($code -ne 0) { return $code }
            return (Invoke-Native '.\.venv\Scripts\python.exe' @('-m', 'compileall', '-q', 'app', 'tests'))
        }
        'django' {
            $code = Initialize-Venv 'requirements-dev.txt'; if ($code -ne 0) { return $code }
            return (Invoke-Native '.\.venv\Scripts\python.exe' @('manage.py', 'check'))
        }
    }
}

function Invoke-FwHostTest([string]$Fw) {
    switch ($Fw) {
        'spring-boot' { Use-Java; return (Invoke-Native '.\mvnw.cmd' @('-B', 'test', "-Dtest.db.name=$env:DB_NAME")) }
        { $_ -in 'nestjs', 'express' } {
            $code = Initialize-NodeModules; if ($code -ne 0) { return $code }
            return (Invoke-Native npm @('test'))
        }
        'fastapi' {
            $code = Initialize-Venv 'requirements-dev.txt'; if ($code -ne 0) { return $code }
            return (Invoke-Native '.\.venv\Scripts\python.exe' @('-m', 'pytest', '-p', 'no:cacheprovider'))
        }
        'django' {
            $code = Initialize-Venv 'requirements-dev.txt'; if ($code -ne 0) { return $code }
            return (Invoke-Native '.\.venv\Scripts\python.exe' @('manage.py', 'test', '-v', '2'))
        }
    }
}

function Invoke-FwHostRun([string]$Fw) {
    switch ($Fw) {
        'spring-boot' {
            Use-Java
            if (-not (Test-Path 'target\spring-boot-sql-injection-example-1.0.0.jar')) {
                $code = Invoke-FwHostBuild $Fw; if ($code -ne 0) { return $code }
            }
            return (Invoke-Native java @('-jar', 'target\spring-boot-sql-injection-example-1.0.0.jar'))
        }
        'nestjs' {
            if (-not (Test-Path 'dist\main.js')) { $code = Invoke-FwHostBuild $Fw; if ($code -ne 0) { return $code } }
            return (Invoke-Native node @('dist\main.js'))
        }
        'express' {
            $code = Initialize-NodeModules; if ($code -ne 0) { return $code }
            return (Invoke-Native node @('src\server.js'))
        }
        'fastapi' {
            $code = Initialize-Venv 'requirements.txt'; if ($code -ne 0) { return $code }
            return (Invoke-Native '.\.venv\Scripts\python.exe' @('-m', 'app'))
        }
        'django' {
            $code = Initialize-Venv 'requirements.txt'; if ($code -ne 0) { return $code }
            return (Invoke-Native '.\.venv\Scripts\python.exe' @('manage.py', 'runserver', "127.0.0.1:$env:APP_PORT", '--noreload'))
        }
    }
}
