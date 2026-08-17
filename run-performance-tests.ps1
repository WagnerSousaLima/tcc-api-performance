<#
    run-performance-tests.ps1
    ---------------------------------------------------------------------------
    Automacao "zero touch" dos testes de carga (k6) para as arquiteturas
    REST, GraphQL e gRPC deste projeto, com captura do PICO de CPU (%) e
    PICO de Memoria (MB) durante cada execucao.

    NOTA IMPORTANTE SOBRE O ALVO DO MONITORAMENTO
    O docker-compose.yml deste projeto so define UM servico (tcc-postgres).
    As tres APIs (REST :8085/produtos, GraphQL :8085/graphql e gRPC :9090)
    sao expostas pelo MESMO processo Java (Spring Boot, "./mvnw spring-boot:run"),
    rodando no host, fora do Docker. Portanto nao existem 3 containers Docker
    distintos para descobrir. Em vez disso, este script descobre dinamicamente
    o PID do processo Java (via a porta TCP em escuta) e mede CPU%/Memoria
    desse processo durante cada rodada de k6 - o equivalente ao "docker stats"
    aplicado ao processo real que atende cada arquitetura.

    O que o script faz, sem intervencao manual:
      1. Garante que o Docker esta rodando e sobe o container tcc-postgres.
      2. Garante que a aplicacao Spring Boot esta no ar (compila e inicia se
         necessario) e aguarda as portas 8085 e 9090 ficarem disponiveis.
      3. Descobre o PID do processo Java que atende essas portas.
      4. Para cada arquitetura (REST, GraphQL, gRPC):
           - inicia um monitor de CPU%/Memoria em background para o PID;
           - executa o script k6 correspondente via container grafana/k6;
           - encerra o monitor e calcula o pico de CPU% e o pico de Mem (MB);
           - grava log do k6 + metricas de pico em evidencias/metricas_finais_<tech>.txt
      5. Imprime um resumo final no console.
#>

$ErrorActionPreference = 'Continue'
# NOTA: usamos 'Continue' (nao 'Stop') porque no Windows PowerShell 5.1 qualquer
# saida no stream de erro de um comando nativo (docker, mvnw), mesmo com exit
# code 0, e promovida a excecao terminante quando EAP='Stop'. Falhas reais sao
# tratadas explicitamente abaixo via checagem de $LASTEXITCODE e "throw".

# ---------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------
$ProjectRoot   = $PSScriptRoot
$EvidenciasDir = Join-Path $ProjectRoot 'evidencias'
$K6Dir         = Join-Path $ProjectRoot 'k6'
$SampleIntervalMs = 400

$Arquiteturas = @(
    [PSCustomObject]@{
        Nome      = 'rest'
        Rotulo    = 'REST'
        Script    = 'test-rest.js'
        EnvArgs   = @('-e', 'BASE_URL=http://host.docker.internal:8085')
    },
    [PSCustomObject]@{
        Nome      = 'graphql'
        Rotulo    = 'GraphQL'
        Script    = 'test-graphql.js'
        EnvArgs   = @('-e', 'BASE_URL=http://host.docker.internal:8085')
    },
    [PSCustomObject]@{
        Nome      = 'grpc'
        Rotulo    = 'gRPC'
        Script    = 'test-grpc.js'
        EnvArgs   = @('-e', 'GRPC_ADDR=host.docker.internal:9090')
    }
)

# ---------------------------------------------------------------------------
# Funcoes auxiliares
# ---------------------------------------------------------------------------

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Test-DockerRunning {
    try {
        docker info *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Invoke-DockerComposeUp {
    Write-Step "Subindo infraestrutura Docker (tcc-postgres)..."
    $useV2 = $true
    try { docker compose version *> $null; $useV2 = ($LASTEXITCODE -eq 0) } catch { $useV2 = $false }

    Push-Location $ProjectRoot
    try {
        if ($useV2) {
            docker compose up -d
        } else {
            docker-compose up -d
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao executar docker compose up -d (exit code $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }
}

function Wait-ForPort {
    param(
        [int]$Port,
        [int]$TimeoutSeconds = 180
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $ok = Test-NetConnection -ComputerName 'localhost' -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($ok) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Get-ListeningProcessId {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $conn) { return $null }
    return $conn.OwningProcess
}

function Start-SpringBootIfNeeded {
    Write-Step "Verificando se a aplicacao Spring Boot (REST/GraphQL/gRPC) ja esta no ar..."
    $pid8085 = Get-ListeningProcessId -Port 8085

    if ($null -ne $pid8085) {
        Write-Host "Aplicacao ja em execucao (PID $pid8085 na porta 8085). Reaproveitando processo existente." -ForegroundColor Green
        return
    }

    Write-Host "Aplicacao nao encontrada. Compilando e iniciando automaticamente..." -ForegroundColor Yellow

    Push-Location $ProjectRoot
    try {
        Write-Step "Executando './mvnw clean compile' (necessario para gerar os stubs do Protobuf/gRPC)..."
        & "$ProjectRoot\mvnw.cmd" clean compile
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao compilar o projeto (mvnw clean compile retornou $LASTEXITCODE)."
        }

        Write-Step "Iniciando './mvnw spring-boot:run' em segundo plano..."
        $logsDir = Join-Path $EvidenciasDir '_app-logs'
        New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
        $stdOut = Join-Path $logsDir 'spring-boot-stdout.log'
        $stdErr = Join-Path $logsDir 'spring-boot-stderr.log'

        Start-Process -FilePath "$ProjectRoot\mvnw.cmd" `
            -ArgumentList 'spring-boot:run' `
            -WorkingDirectory $ProjectRoot `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdOut `
            -RedirectStandardError $stdErr | Out-Null
    } finally {
        Pop-Location
    }

    Write-Step "Aguardando portas 8085 (REST/GraphQL) e 9090 (gRPC) ficarem disponiveis..."
    if (-not (Wait-ForPort -Port 8085 -TimeoutSeconds 180)) {
        throw "Timeout aguardando a porta 8085. Verifique evidencias/_app-logs/spring-boot-stderr.log"
    }
    if (-not (Wait-ForPort -Port 9090 -TimeoutSeconds 60)) {
        throw "Timeout aguardando a porta 9090. Verifique evidencias/_app-logs/spring-boot-stderr.log"
    }
    Write-Host "Aplicacao Spring Boot no ar." -ForegroundColor Green
}

function Start-CpuMemMonitor {
    param(
        [int]$TargetPid,
        [string]$CsvPath,
        [int]$IntervalMs
    )
    if (Test-Path $CsvPath) { Remove-Item $CsvPath -Force }

    return Start-Job -ScriptBlock {
        param($TargetPid, $CsvPath, $IntervalMs)

        $prevProc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
        if ($null -eq $prevProc) { return }
        $prevCpuSeconds = $prevProc.CPU
        $prevTimestamp  = Get-Date

        while ($true) {
            Start-Sleep -Milliseconds $IntervalMs

            $proc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
            if ($null -eq $proc) { break }

            $now         = Get-Date
            $elapsedWall = ($now - $prevTimestamp).TotalSeconds
            $elapsedCpu  = $proc.CPU - $prevCpuSeconds

            if ($elapsedWall -gt 0) {
                $cpuPercent = [math]::Round((($elapsedCpu / $elapsedWall) * 100), 2)
            } else {
                $cpuPercent = 0
            }
            $memMB = [math]::Round(($proc.WorkingSet64 / 1MB), 2)

            Add-Content -Path $CsvPath -Value "$cpuPercent,$memMB"

            $prevCpuSeconds = $proc.CPU
            $prevTimestamp  = $now
        }
    } -ArgumentList $TargetPid, $CsvPath, $IntervalMs
}

function Stop-CpuMemMonitorAndGetPeaks {
    param(
        [System.Management.Automation.Job]$Job,
        [string]$CsvPath
    )
    Stop-Job $Job -ErrorAction SilentlyContinue | Out-Null
    Wait-Job $Job -Timeout 5 | Out-Null
    Remove-Job $Job -Force -ErrorAction SilentlyContinue | Out-Null

    if (-not (Test-Path $CsvPath)) {
        return [PSCustomObject]@{ PicoCpu = 'N/A'; PicoMemMB = 'N/A' }
    }

    $rows = Import-Csv -Path $CsvPath -Header 'Cpu', 'Mem' | Where-Object { $_.Cpu -match '^-?[\d\.]+$' }
    if (-not $rows -or $rows.Count -eq 0) {
        return [PSCustomObject]@{ PicoCpu = 'N/A'; PicoMemMB = 'N/A' }
    }

    $picoCpu = ($rows | Measure-Object -Property Cpu -Maximum).Maximum
    $picoMem = ($rows | Measure-Object -Property Mem -Maximum).Maximum

    return [PSCustomObject]@{
        PicoCpu   = [math]::Round([double]$picoCpu, 2)
        PicoMemMB = [math]::Round([double]$picoMem, 2)
    }
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $EvidenciasDir | Out-Null

Write-Step "Verificando Docker Desktop..."
if (-not (Test-DockerRunning)) {
    throw "Docker nao esta acessivel (docker info falhou). Inicie o Docker Desktop e execute o script novamente."
}
Write-Host "Docker OK." -ForegroundColor Green

Invoke-DockerComposeUp

Write-Step "Aguardando o Postgres (porta 5433)..."
if (-not (Wait-ForPort -Port 5433 -TimeoutSeconds 60)) {
    throw "Timeout aguardando o Postgres (tcc-postgres) na porta 5433."
}
Write-Host "Postgres OK." -ForegroundColor Green

Start-SpringBootIfNeeded

$appPid = Get-ListeningProcessId -Port 8085
if ($null -eq $appPid) {
    throw "Nao foi possivel identificar o PID do processo Java na porta 8085."
}
Write-Host "Processo da aplicacao identificado: PID $appPid" -ForegroundColor Green

$resumo = @()
$tempDir = Join-Path $EvidenciasDir '_tmp'
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

foreach ($arch in $Arquiteturas) {
    Write-Step "Testando arquitetura $($arch.Rotulo) (PID monitorado: $appPid)..."

    $csvPath    = Join-Path $tempDir "monitor_$($arch.Nome).csv"
    $k6LogPath  = Join-Path $tempDir "k6_$($arch.Nome).log"
    $finalPath  = Join-Path $EvidenciasDir "metricas_finais_$($arch.Nome).txt"

    $monitorJob = Start-CpuMemMonitor -TargetPid $appPid -CsvPath $csvPath -IntervalMs $SampleIntervalMs

    $dockerArgs = @(
        'run', '--rm', '-i',
        '-v', "${ProjectRoot}:/repo",
        '-w', '/repo/k6'
    ) + $arch.EnvArgs + @('grafana/k6', 'run', $arch.Script)

    if (Test-Path $k6LogPath) { Remove-Item $k6LogPath -Force }
    & docker @dockerArgs 2>&1 | Tee-Object -FilePath $k6LogPath
    $k6ExitCode = $LASTEXITCODE

    $peaks = Stop-CpuMemMonitorAndGetPeaks -Job $monitorJob -CsvPath $csvPath

    $k6Log = Get-Content -Path $k6LogPath -Raw -ErrorAction SilentlyContinue

    $reportLines = @()
    $reportLines += "===================================================================="
    $reportLines += "Metricas Finais - Arquitetura $($arch.Rotulo)"
    $reportLines += "Data/Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $reportLines += "Script k6: k6/$($arch.Script)"
    $reportLines += "PID monitorado (processo Spring Boot): $appPid"
    $reportLines += "k6 exit code: $k6ExitCode"
    $reportLines += "===================================================================="
    $reportLines += ""
    $reportLines += "----- LOG COMPLETO DO K6 -----"
    $reportLines += $k6Log
    $reportLines += ""
    $reportLines += "----- METRICAS DE PICO (processo da aplicacao durante o teste) -----"
    $reportLines += "Pico Maximo de CPU (%): $($peaks.PicoCpu)"
    $reportLines += "Pico Maximo de Memoria (MB): $($peaks.PicoMemMB)"
    $reportLines += "===================================================================="

    Set-Content -Path $finalPath -Value $reportLines -Encoding UTF8

    Write-Host "Concluido $($arch.Rotulo) -> Pico CPU: $($peaks.PicoCpu)% | Pico Mem: $($peaks.PicoMemMB) MB" -ForegroundColor Green
    Write-Host "Evidencia salva em: $finalPath" -ForegroundColor DarkGray

    $resumo += [PSCustomObject]@{
        Arquitetura = $arch.Rotulo
        'Pico CPU (%)' = $peaks.PicoCpu
        'Pico Memoria (MB)' = $peaks.PicoMemMB
        Arquivo = $finalPath
    }

    Remove-Item $csvPath, $k6LogPath -Force -ErrorAction SilentlyContinue
}

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Step "Resumo final"
$resumo | Format-Table -AutoSize | Out-String | Write-Host

Write-Host ""
Write-Host "Todos os testes concluidos. A aplicacao Spring Boot (PID $appPid) permanece em execucao." -ForegroundColor Cyan
Write-Host "Se ela foi iniciada por este script, os logs estao em evidencias\_app-logs\." -ForegroundColor Cyan
