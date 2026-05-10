import grpc from 'k6/net/grpc';
import { check } from 'k6';

const client = new grpc.Client();
client.load(['../src/main/proto'], 'produto.proto');

export const options = {
  stages: [
    { duration: '10s', target: 10 },
    { duration: '30s', target: 10 },
    { duration: '10s', target: 0 },
  ],
};

export default function () {
  const grpcAddress = __ENV.GRPC_ADDR || 'localhost:9090';

  client.connect(grpcAddress, {
    plaintext: true,
  });

  const response = client.invoke('produto.ProdutoGrpcService/CriarProduto', {
    nome: 'Produto gRPC k6',
    preco: 30.50,
    descricao: 'Teste',
  });

  check(response, {
    'status is OK': (res) => res && res.status === grpc.StatusOK,
  });

  client.close();
}

export function teardown() {
  client.close();
}
