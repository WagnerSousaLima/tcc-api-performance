import http from 'k6/http';
import { check } from 'k6';

export const options = {
  stages: [
    { duration: '10s', target: 10 },
    { duration: '30s', target: 10 },
    { duration: '10s', target: 0 },
  ],
};

export default function () {
  const baseUrl = __ENV.BASE_URL || 'http://localhost:8085';
  const url = `${baseUrl}/graphql`;
  const payload = JSON.stringify({
    query: `
      mutation {
        criarProduto(input: {
          nome: "Produto GraphQL k6",
          preco: 20.50,
          descricao: "Teste"
        }) {
          id
          nome
          preco
          descricao
        }
      }
    `,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const response = http.post(url, payload, params);

  check(response, {
    'status is 200': (res) => res.status === 200,
  });
}
