import grpc from 'k6/net/grpc';
import { check } from 'k6';
import { resumoJson, perfilDeCarga } from './resumo.js';

const client = new grpc.Client();
client.load(['../src/main/proto'], 'produto.proto');

export const options = {
  stages: perfilDeCarga(),
};

// O canal e aberto uma unica vez por usuario virtual e reaproveitado em todas
// as iteracoes, preservando a conexao persistente do HTTP/2. Abrir e fechar o
// canal a cada iteracao adicionaria o custo de handshake a cada requisicao e
// invalidaria a comparacao com REST e GraphQL, que reaproveitam a conexao HTTP.
let conectado = false;

export default function () {
  if (!conectado) {
    client.connect(__ENV.GRPC_ADDR || 'localhost:9090', { plaintext: true });
    conectado = true;
  }

  const response = client.invoke('produto.ProdutoGrpcService/CriarProduto', {
    nome: 'Produto gRPC k6',
    preco: 30.50,
    descricao: 'Teste',
  });

  check(response, {
    'status is OK': (res) => res && res.status === grpc.StatusOK,
  });
}

export function handleSummary(data) {
  return resumoJson(data, 'gRPC');
}
