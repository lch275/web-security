<#
.SYNOPSIS
  실행 중인 예제 앱에 대한 HTTP 스모크 테스트 (데모 DB의 시드 데이터 기준)
.EXAMPLE
  .\example\scripts\smoke.ps1 express
  .\example\scripts\smoke.ps1 fastapi http://127.0.0.1:8084
#>
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Framework,
    [Parameter(Position = 1)][string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'frameworks.ps1')

if (-not $Frameworks.Contains($Framework)) { Stop-WithError "알 수 없는 프레임워크: $Framework" 64 }
# PowerShell 5.1의 curl 별칭(Invoke-WebRequest)이 아닌 curl.exe를 사용한다(Windows 10 이상 기본 포함).
Assert-Command curl.exe
$meta = $Frameworks[$Framework]
if (-not $BaseUrl) { $BaseUrl = "http://127.0.0.1:$($meta.Port)" }
$param = $meta.Param
$invalidStatus = if ($Framework -eq 'fastapi') { '422' } else { '400' }
$script:failures = 0

function Test-Endpoint([string]$Name, [string]$ExpectedStatus, [string]$ExpectedBody, [string[]]$CurlArgs) {
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = (& curl.exe -s -m 10 -w "`n%{http_code}" @CurlArgs) -join "`n"
    $ErrorActionPreference = $previous
    $lines = $out -split "`n"
    $status = $lines[-1]
    $body = ($lines[0..($lines.Length - 2)] -join "`n")
    if ($status -eq $ExpectedStatus -and $body -match $ExpectedBody) {
        Write-Output "PASS $Name -> $status $body"
    } else {
        Write-Output "FAIL $Name -> $status $body (expected $ExpectedStatus /$ExpectedBody/)"
        $script:failures++
    }
}

Write-Output "== $Framework smoke test: $BaseUrl"
Test-Endpoint 'health' '200' '"status": ?"UP"' @("$BaseUrl/health")
Test-Endpoint "search O'Connor" '200' '^\["?[0-9]+"?\]$' @('-G', "$BaseUrl/customers/search", '--data-urlencode', "$param=O'Connor")
Test-Endpoint 'search injection' '200' '^\[\]$' @('-G', "$BaseUrl/customers/search", '--data-urlencode', "$param=' OR '1'='1")
Test-Endpoint 'search drop payload' '200' '^\[\]$' @('-G', "$BaseUrl/customers/search", '--data-urlencode', "$param=x'; DROP TABLE customers; --")
Test-Endpoint 'contains %' '200' '^\["?[0-9]+"?\]$' @('-G', "$BaseUrl/customers/contains", '--data-urlencode', 'keyword=%')
Test-Endpoint 'sorted invalid' $invalidStatus '.' @("$BaseUrl/customers/sorted?sort=id")
Test-Endpoint 'search missing' $invalidStatus '.' @("$BaseUrl/customers/search")
Test-Endpoint 'table intact' '200' '^\[.+\]$' @("$BaseUrl/customers/sorted?sort=name")

if ($script:failures -gt 0) { Stop-WithError "$Framework smoke test 실패 $($script:failures)건" 1 }
Write-Output "== $Framework smoke test PASS"
exit 0
