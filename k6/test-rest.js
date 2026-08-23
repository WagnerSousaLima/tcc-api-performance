import http from 'k6/http';
import { check } from 'k6';
import { resumoJson, perfilDeCarga } from './resumo.js';

export const options = {
  stages: perfilDeCarga(),
};

export default function () {
  const baseUrl = __ENV.BASE_URL || 'http://localhost:8085';
  const url = `${baseUrl}/produtos`;
  const payload = JSON.stringify({
    nome: 'Produto REST k6',
    preco: 10.50,
    descricao: 'Teste de carga',
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const response = http.post(url, payload, params);

  check(response, {
    'status is 201': (res) => res.status === 201,
  });
}

export function handleSummary(data) {
  return resumoJson(data, 'REST');
}
