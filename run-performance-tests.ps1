<#
    run-performance-tests.ps1
    ---------------------------------------------------------------------------
    Execucao automatizada e repetida dos ensaios de carga (Grafana k6) para as
    abordagens de comunicacao REST, GraphQL e gRPC, com captura do pico de CPU
    (%) e do pico de memoria (MB) do processo da aplicacao em CADA execucao.

    O QUE MUDOU EM RELACAO A VERSAO ANTERIOR
      1. Repeticoes: cada abordagem e executada N vezes por cenario (padrao 5),
         permitindo calcular media, desvio padrao e coeficiente de variacao.
      2. Isolamento: a aplicacao e reiniciada ANTES DE CADA execucao. Assim, o
         consumo de memoria medido nao carrega o crescimento acumulado das
         execucoes anteriores, problema que existia quando as tres abordagens
         eram exercitadas em sequencia na mesma JVM.
      3. Cenarios: "frio" reinicia tambem o container do Postgres antes de cada
         execucao; "quente" aplica um aquecimento descartado de 20 s antes da
         janela medida.
      4. Coleta estruturada: os roteiros k6 gravam um resumo em JSON via
         handleSummary, eliminando a leitura por expressao regular do log.
      5. Saidas consolidadas: resultados_brutos.csv (uma linha por execucao) e
         resultados_consolidados.csv/.txt (media +/- desvio padrao por celula).

    COMO EXECUTAR (PowerShell, com o Docker Desktop aberto)
        .\run-performance-tests.ps1                       # 5 repeticoes, os 2 cenarios
        .\run-performance-tests.ps1 -Repeticoes 3         # versao mais rapida
        .\run-performance-tests.ps1 -Cenario quente       # apenas um cenario
        .\run-performance-tests.ps1 -PularBuild           # reaproveita o jar ja compilado

    Tempo aproximado: 5 repeticoes x 2 cenarios x 3 abordagens = 30 execucoes,
    entre 50 e 70 minutos. Nao use a maquina para outras tarefas durante os
    ensaios, para nao contaminar as medidas de CPU e memoria.
#>

[CmdletBinding()]
param(
    [ValidateSet('frio', 'quente', 'ambos')]
    [string]$Cenario = 'ambos',

    [ValidateRange(1, 30)]
    [int]$Repeticoes = 5,

    [switch]$PularBuild
)

$ErrorActionPreference = 'Continue'
# NOTA: usamos 'Continue' (nao 'Stop') porque no Windows PowerShell 5.1 qualquer
# saida no stream de erro de um comando nativo (docker, mvnw), mesmo com exit
# code 0, e promovida a excecao terminante quando EAP='Stop'. Falhas reais sao
# tratadas explicitamente via checagem de $LASTEXITCODE e "throw".

# ---------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------
$ProjectRoot      = $PSScriptRoot
$EvidenciasDir    = Join-Path $ProjectRoot 'evidencias'
$TmpDir           = Join-Path $EvidenciasDir '_tmp'
$LogsDir          = Join-Path $EvidenciasDir '_app-logs'
$RodadasDir       = Join-Path $EvidenciasDir 'rodadas'
$SampleIntervalMs = 400

$Arquiteturas = @(
    [PSCustomObject]@{
        Nome    = 'rest'
        Rotulo  = 'REST'
        Script  = 'test-rest.js'
        EnvArgs = @('-e', 'BASE_URL=http://host.docker.internal:8085')
    },
    [PSCustomObject]@{
        Nome    = 'graphql'
        Rotulo  = 'GraphQL'
        Script  = 'test-graphql.js'
        EnvArgs = @('-e', 'BASE_URL=http://host.docker.internal:8085')
    },
    [PSCustomObject]@{
        Nome    = 'grpc'
        Rotulo  = 'gRPC'
        Script  = 'test-grpc.js'
        EnvArgs = @('-e', 'GRPC_ADDR=host.docker.internal:9090')
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
        if ($useV2) { docker compose up -d } else { docker-compose up -d }
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao executar docker compose up -d (exit code $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }
}

function Wait-ForPort {
    param([int]$Port, [int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $ok = Test-NetConnection -ComputerName 'localhost' -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($ok) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Wait-ForPortFree {
    param([int]$Port, [int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($null -eq $conn) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-ListeningProcessId {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $conn) { return $null }
    return $conn.OwningProcess
}

function Resolve-JavaExe {
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    if ($env:JAVA_HOME) {
        $candidato = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path $candidato) { return $candidato }
    }
    throw "Executavel 'java' nao encontrado no PATH nem em JAVA_HOME."
}

function Invoke-Build {
    Write-Step "Compilando a aplicacao ('mvnw clean package -DskipTests')..."
    Push-Location $ProjectRoot
    try {
        & "$ProjectRoot\mvnw.cmd" clean package -DskipTests
        if ($LASTEXITCODE -ne 0) {
            throw "Falha na compilacao (mvnw retornou $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }
}

function Get-AppJar {
    $jar = Get-ChildItem -Path (Join-Path $ProjectRoot 'target') -Filter '*.jar' -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike '*sources*' -and $_.Name -notlike '*javadoc*' } |
           Sort-Object Length -Descending | Select-Object -First 1
    return $jar
}

function Stop-App {
    param($Proc)
    if ($null -ne $Proc) {
        try {
            if (-not $Proc.HasExited) {
                Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
                Wait-Process -Id $Proc.Id -Timeout 25 -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    # Garante que nenhum processo remanescente esta ocupando as portas.
    foreach ($porta in @(8085, 9090)) {
        $residual = Get-ListeningProcessId -Port $porta
        if ($null -ne $residual) {
            Stop-Process -Id $residual -Force -ErrorAction SilentlyContinue
        }
    }
    Wait-ForPortFree -Port 8085 -TimeoutSeconds 60 | Out-Null
}

function Start-App {
    param([string]$JavaExe, [string]$JarPath, [string]$Rotulo)
    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    $stdOut = Join-Path $LogsDir "app-stdout-$Rotulo.log"
    $stdErr = Join-Path $LogsDir "app-stderr-$Rotulo.log"

    $proc = Start-Process -FilePath $JavaExe `
        -ArgumentList @('-jar', $JarPath) `
        -WorkingDirectory $ProjectRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdOut `
        -RedirectStandardError $stdErr `
        -PassThru

    if (-not (Wait-ForPort -Port 8085 -TimeoutSeconds 180)) {
        throw "Timeout aguardando a porta 8085. Verifique $stdErr"
    }
    if (-not (Wait-ForPort -Port 9090 -TimeoutSeconds 60)) {
        throw "Timeout aguardando a porta 9090. Verifique $stdErr"
    }
    Start-Sleep -Seconds 2
    return $proc
}

function Restart-Postgres {
    docker restart tcc-postgres *> $null
    if (-not (Wait-ForPort -Port 5433 -TimeoutSeconds 90)) {
        throw "Timeout aguardando o Postgres (tcc-postgres) na porta 5433."
    }
    Start-Sleep -Seconds 3
}

function Start-CpuMemMonitor {
    param([int]$TargetPid, [string]$CsvPath, [int]$IntervalMs)
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
    param([System.Management.Automation.Job]$Job, [string]$CsvPath)
    Stop-Job $Job -ErrorAction SilentlyContinue | Out-Null
    Wait-Job $Job -Timeout 5 | Out-Null
    Remove-Job $Job -Force -ErrorAction SilentlyContinue | Out-Null

    if (-not (Test-Path $CsvPath)) {
        return [PSCustomObject]@{ PicoCpu = $null; PicoMemMB = $null }
    }
    $rows = Import-Csv -Path $CsvPath -Header 'Cpu', 'Mem' | Where-Object { $_.Cpu -match '^-?[\d\.]+$' }
    if (-not $rows -or $rows.Count -eq 0) {
        return [PSCustomObject]@{ PicoCpu = $null; PicoMemMB = $null }
    }
    $picoCpu = ($rows | Measure-Object -Property Cpu -Maximum).Maximum
    $picoMem = ($rows | Measure-Object -Property Mem -Maximum).Maximum
    return [PSCustomObject]@{
        PicoCpu   = [math]::Round([double]$picoCpu, 2)
        PicoMemMB = [math]::Round([double]$picoMem, 2)
    }
}

function Invoke-K6 {
    param($Arch, [string]$CenarioNome, [int]$Rep, [string]$OutFileName, [switch]$Aquecimento)

    $envArgs = @()
    $envArgs += $Arch.EnvArgs
    $envArgs += @('-e', "CENARIO=$CenarioNome", '-e', "REP=$Rep")

    if ($Aquecimento) {
        $envArgs += @('-e', 'RAMPA=5s', '-e', 'SUSTENTACAO=15s', '-e', 'DESCIDA=1s')
    } else {
        $envArgs += @('-e', "OUT_FILE=/repo/evidencias/_tmp/$OutFileName")
    }

    $dockerArgs = @('run', '--rm', '-i', '-v', "${ProjectRoot}:/repo", '-w', '/repo/k6') +
                  $envArgs + @('grafana/k6', 'run', $Arch.Script)

    return (& docker @dockerArgs 2>&1 | Out-String)
}

function Get-Estatisticas {
    param([double[]]$Valores)
    $validos = @($Valores | Where-Object { $null -ne $_ })
    if ($validos.Count -eq 0) {
        return [PSCustomObject]@{ Media = $null; Desvio = $null; CV = $null; N = 0 }
    }
    $n = $validos.Count
    $media = ($validos | Measure-Object -Average).Average
    if ($n -gt 1) {
        $soma = 0.0
        foreach ($v in $validos) { $soma += [math]::Pow(($v - $media), 2) }
        $desvio = [math]::Sqrt($soma / ($n - 1))
    } else {
        $desvio = 0.0
    }
    $cv = 0.0
    if ($media -ne 0) { $cv = 100.0 * $desvio / $media }
    return [PSCustomObject]@{
        Media  = [math]::Round($media, 2)
        Desvio = [math]::Round($desvio, 2)
        CV     = [math]::Round($cv, 1)
        N      = $n
    }
}

# ---------------------------------------------------------------------------
# Execucao principal
# ---------------------------------------------------------------------------

foreach ($dir in @($EvidenciasDir, $TmpDir, $LogsDir, $RodadasDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Write-Step "Verificando Docker Desktop..."
if (-not (Test-DockerRunning)) {
    throw "Docker nao esta acessivel (docker info falhou). Inicie o Docker Desktop e execute novamente."
}
Write-Host "Docker OK." -ForegroundColor Green

Invoke-DockerComposeUp

Write-Step "Aguardando o Postgres (porta 5433)..."
if (-not (Wait-ForPort -Port 5433 -TimeoutSeconds 90)) {
    throw "Timeout aguardando o Postgres (tcc-postgres) na porta 5433."
}
Write-Host "Postgres OK." -ForegroundColor Green

if (-not $PularBuild) { Invoke-Build }

$jar = Get-AppJar
if ($null -eq $jar) {
    throw "Jar executavel nao encontrado em target\. Execute o script sem -PularBuild."
}
Write-Host "Artefato: $($jar.Name)" -ForegroundColor DarkGray

$javaExe = Resolve-JavaExe
Write-Host "Java: $javaExe" -ForegroundColor DarkGray

if ($Cenario -eq 'ambos') { $cenarios = @('frio', 'quente') } else { $cenarios = @($Cenario) }

$totalExecucoes = $cenarios.Count * $Repeticoes * $Arquiteturas.Count
Write-Step "Plano: $($cenarios.Count) cenario(s) x $Repeticoes repeticao(oes) x $($Arquiteturas.Count) abordagens = $totalExecucoes execucoes"

$resultados = @()
$appProc = $null
$contador = 0
$inicio = Get-Date

foreach ($cen in $cenarios) {
    for ($rep = 1; $rep -le $Repeticoes; $rep++) {
        foreach ($arch in $Arquiteturas) {
            $contador++
            Write-Step "[$contador/$totalExecucoes] Cenario '$cen' | $($arch.Rotulo) | repeticao $rep"

            Stop-App -Proc $appProc
            $appProc = $null

            if ($cen -eq 'frio') {
                Write-Host "Reiniciando o container do Postgres (cenario a frio)..." -ForegroundColor DarkGray
                Restart-Postgres
            }

            $appProc = Start-App -JavaExe $javaExe -JarPath $jar.FullName -Rotulo $arch.Nome
            Write-Host "Aplicacao iniciada (PID $($appProc.Id))." -ForegroundColor DarkGray

            if ($cen -eq 'quente') {
                Write-Host "Aquecimento de 20 s (resultados descartados)..." -ForegroundColor DarkGray
                Invoke-K6 -Arch $arch -CenarioNome $cen -Rep $rep -Aquecimento | Out-Null
                Start-Sleep -Seconds 2
            }

            $sufixo   = "${cen}_$($arch.Nome)_rep$rep"
            $csvPath  = Join-Path $TmpDir "monitor_$sufixo.csv"
            $jsonName = "summary_$sufixo.json"
            $jsonPath = Join-Path $TmpDir $jsonName

            if (Test-Path $jsonPath) { Remove-Item $jsonPath -Force }

            $monitorJob = Start-CpuMemMonitor -TargetPid $appProc.Id -CsvPath $csvPath -IntervalMs $SampleIntervalMs
            $log = Invoke-K6 -Arch $arch -CenarioNome $cen -Rep $rep -OutFileName $jsonName
            $peaks = Stop-CpuMemMonitorAndGetPeaks -Job $monitorJob -CsvPath $csvPath

            Set-Content -Path (Join-Path $RodadasDir "$sufixo.txt") -Value $log -Encoding UTF8

            if (-not (Test-Path $jsonPath)) {
                Write-Host "AVISO: resumo JSON nao gerado para $sufixo. Execucao ignorada." -ForegroundColor Yellow
                continue
            }

            $s = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json

            $resultados += [PSCustomObject]@{
                Cenario           = $cen
                Abordagem         = $arch.Rotulo
                Repeticao         = $rep
                VazaoReqS         = [double]$s.vazao_req_s
                TotalRequisicoes  = [double]$s.total_requisicoes
                LatenciaMedianaMs = [double]$s.latencia_mediana_ms
                LatenciaP95Ms     = [double]$s.latencia_p95_ms
                TaxaSucessoPct    = [double]$s.taxa_sucesso_pct
                EnviadosMB        = [double]$s.dados_enviados_mb
                RecebidosMB       = [double]$s.dados_recebidos_mb
                PicoCpuPct        = $peaks.PicoCpu
                PicoMemoriaMB     = $peaks.PicoMemMB
            }

            Write-Host ("OK -> {0,8:N2} req/s | p95 {1,7:N2} ms | CPU {2,7:N2}% | Mem {3,7:N2} MB" -f `
                $s.vazao_req_s, $s.latencia_p95_ms, $peaks.PicoCpu, $peaks.PicoMemMB) -ForegroundColor Green

            Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Stop-App -Proc $appProc

# ---------------------------------------------------------------------------
# Consolidacao
# ---------------------------------------------------------------------------
Write-Step "Consolidando resultados..."

$brutosPath = Join-Path $EvidenciasDir 'resultados_brutos.csv'
$resultados | Export-Csv -Path $brutosPath -NoTypeInformation -Encoding UTF8
Write-Host "Resultados brutos: $brutosPath" -ForegroundColor DarkGray

$metricas = @(
    @{ Nome = 'Vazao media (req/s)';      Campo = 'VazaoReqS' },
    @{ Nome = 'Total de requisicoes';     Campo = 'TotalRequisicoes' },
    @{ Nome = 'Latencia mediana (ms)';    Campo = 'LatenciaMedianaMs' },
    @{ Nome = 'Latencia p95 (ms)';        Campo = 'LatenciaP95Ms' },
    @{ Nome = 'Taxa de sucesso (%)';      Campo = 'TaxaSucessoPct' },
    @{ Nome = 'Trafego enviado (MB)';     Campo = 'EnviadosMB' },
    @{ Nome = 'Trafego recebido (MB)';    Campo = 'RecebidosMB' },
    @{ Nome = 'Pico de processador (%)';  Campo = 'PicoCpuPct' },
    @{ Nome = 'Pico de memoria (MB)';     Campo = 'PicoMemoriaMB' }
)

$consolidado = @()
foreach ($cen in $cenarios) {
    foreach ($arch in $Arquiteturas) {
        $subset = @($resultados | Where-Object { $_.Cenario -eq $cen -and $_.Abordagem -eq $arch.Rotulo })
        if ($subset.Count -eq 0) { continue }
        foreach ($met in $metricas) {
            $valores = @($subset | ForEach-Object { $_.($met.Campo) })
            $est = Get-Estatisticas -Valores $valores
            $consolidado += [PSCustomObject]@{
                Cenario     = $cen
                Abordagem   = $arch.Rotulo
                Metrica     = $met.Nome
                N           = $est.N
                Media       = $est.Media
                DesvioPadrao= $est.Desvio
                CVPercent   = $est.CV
            }
        }
    }
}

$consolidadoCsv = Join-Path $EvidenciasDir 'resultados_consolidados.csv'
$consolidado | Export-Csv -Path $consolidadoCsv -NoTypeInformation -Encoding UTF8

$linhas = @()
$linhas += "===================================================================="
$linhas += "Resultados consolidados - media +/- desvio padrao (n = $Repeticoes)"
$linhas += "Data/Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$linhas += "Duracao total: $([math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)) min"
$linhas += "Execucoes validas: $($resultados.Count) de $totalExecucoes"
$linhas += "===================================================================="

foreach ($cen in $cenarios) {
    $linhas += ""
    $linhas += "CENARIO: $cen"
    $linhas += ("{0,-28} {1,-24} {2,-24} {3,-24}" -f 'Metrica', 'REST', 'GraphQL', 'gRPC')
    $linhas += ("-" * 102)
    foreach ($met in $metricas) {
        $celulas = @()
        foreach ($arch in $Arquiteturas) {
            $reg = $consolidado | Where-Object {
                $_.Cenario -eq $cen -and $_.Abordagem -eq $arch.Rotulo -and $_.Metrica -eq $met.Nome
            } | Select-Object -First 1
            if ($null -eq $reg) {
                $celulas += 'n/d'
            } else {
                $celulas += ("{0} +/- {1} (CV {2}%)" -f $reg.Media, $reg.DesvioPadrao, $reg.CVPercent)
            }
        }
        $linhas += ("{0,-28} {1,-24} {2,-24} {3,-24}" -f $met.Nome, $celulas[0], $celulas[1], $celulas[2])
    }
}

$linhas += ""
$linhas += "Notas:"
$linhas += "- CPU em percentual do processo: 100% = um processador logico ocupado integralmente."
$linhas += "- A aplicacao foi reiniciada antes de cada execucao, isolando o consumo de memoria."
$linhas += "- Cenario 'frio': container do Postgres reiniciado antes de cada execucao."
$linhas += "- Cenario 'quente': aquecimento descartado de 20 s antes da janela medida."
$linhas += "===================================================================="

$consolidadoTxt = Join-Path $EvidenciasDir 'resultados_consolidados.txt'
Set-Content -Path $consolidadoTxt -Value $linhas -Encoding UTF8

Write-Host ""
$linhas | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Arquivos gerados:" -ForegroundColor Cyan
Write-Host "  $brutosPath" -ForegroundColor Cyan
Write-Host "  $consolidadoCsv" -ForegroundColor Cyan
Write-Host "  $consolidadoTxt" -ForegroundColor Cyan
Write-Host "  $RodadasDir (log completo de cada execucao)" -ForegroundColor Cyan
