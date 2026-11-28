<#
.SYNOPSIS
  공통 MySQL 컨테이너 관리
.EXAMPLE
  .\example\scripts\mysql.ps1 up           # 시작 후 healthy 대기
  .\example\scripts\mysql.ps1 wait         # healthy 대기
  .\example\scripts\mysql.ps1 status       # 상태 출력
  .\example\scripts\mysql.ps1 provision    # 기존 Volume에 init/ 스크립트 재적용 (데이터 유지)
  .\example\scripts\mysql.ps1 down         # 종료 (Volume 유지)
  .\example\scripts\mysql.ps1 reset -Yes   # Volume 삭제 후 재초기화 (데이터 삭제)
#>
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('up', 'wait', 'status', 'provision', 'down', 'reset')]
    [string]$Command,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

Assert-Command docker
Import-MySqlEnv
$waitSeconds = if ($env:MYSQL_WAIT_SECONDS) { [int]$env:MYSQL_WAIT_SECONDS } else { 180 }

switch ($Command) {
    'up' {
        Write-Log "MySQL 시작 (127.0.0.1:$($env:MYSQL_PORT))"
        Invoke-Compose @('up', '-d', '--build')
        Wait-MySql $waitSeconds
    }
    'wait' { Wait-MySql $waitSeconds }
    'status' {
        Invoke-Compose @('ps')
        Write-Output "health: $(Get-MySqlHealth)"
    }
    'provision' {
        Wait-MySql 60
        Write-Log 'init/ 스크립트를 기존 Volume에 다시 적용합니다.'
        $code = Invoke-Native docker @('exec', $MySqlContainer, 'bash', '/opt/example/provision.sh')
        if ($code -ne 0) { Stop-WithError 'provision 실패' $code }
    }
    'down' {
        Write-Log 'MySQL 종료 (Volume 유지)'
        Invoke-Compose @('down')
    }
    'reset' {
        if (-not $Yes) { Stop-WithError "데이터가 모두 삭제됩니다. 계속하려면 'mysql.ps1 reset -Yes'로 실행하세요." 64 }
        Write-Log 'MySQL 컨테이너와 Volume(web-security-example-mysql-data)을 삭제하고 다시 초기화합니다.'
        Invoke-Compose @('down', '--volumes')
        Invoke-Compose @('up', '-d', '--build')
        Wait-MySql $waitSeconds
    }
}
exit 0
