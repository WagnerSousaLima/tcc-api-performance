// resumo.js
// Helper compartilhado pelos tres roteiros de carga. Ao final de cada ensaio,
// gera um resumo compacto em JSON com as metricas usadas na analise do TCC.
// O arquivo de saida e definido pela variavel de ambiente OUT_FILE.

function round2(v) {
  if (v === null || v === undefined || isNaN(v)) { return null; }
  return Math.round(v * 100) / 100;
}

function taxaSucesso(m) {
  if (m.checks && m.checks.values && m.checks.values.rate !== undefined) {
    return round2(m.checks.values.rate * 100);
  }
  if (m.http_req_failed && m.http_req_failed.values && m.http_req_failed.values.rate !== undefined) {
    return round2((1 - m.http_req_failed.values.rate) * 100);
  }
  return null;
}

export function resumoJson(data, tecnologia) {
  var m = data.metrics;
  var dur = m.http_req_duration || m.grpc_req_duration || null;
  var iter = m.iterations ? m.iterations.values : { rate: 0, count: 0 };
  var enviados = m.data_sent ? m.data_sent.values.count : 0;
  var recebidos = m.data_received ? m.data_received.values.count : 0;

  var res = {
    tecnologia: tecnologia,
    cenario: __ENV.CENARIO || 'nao-informado',
    repeticao: Number(__ENV.REP || 1),
    vazao_req_s: round2(iter.rate),
    total_requisicoes: iter.count,
    latencia_mediana_ms: dur ? round2(dur.values.med) : null,
    latencia_p95_ms: dur ? round2(dur.values['p(95)']) : null,
    taxa_sucesso_pct: taxaSucesso(m),
    dados_enviados_mb: round2(enviados / 1048576),
    dados_recebidos_mb: round2(recebidos / 1048576)
  };

  var saida = {};
  if (__ENV.OUT_FILE) {
    saida[__ENV.OUT_FILE] = JSON.stringify(res, null, 2);
  }
  saida['stdout'] = '\nRESUMO ' + JSON.stringify(res) + '\n';
  return saida;
}

// Perfil de carga parametrizavel, identico para as tres abordagens.
export function perfilDeCarga() {
  var vus = Number(__ENV.VUS || 10);
  return [
    { duration: __ENV.RAMPA || '10s', target: vus },
    { duration: __ENV.SUSTENTACAO || '30s', target: vus },
    { duration: __ENV.DESCIDA || '10s', target: 0 }
  ];
}
