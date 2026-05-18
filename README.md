# Desempenho de Arquiteturas de API: REST, GraphQL e gRPC

Este repositório contém o código-fonte e os scripts de automação do experimento prático desenvolvido para o Trabalho de Conclusão de Curso (TCC) do MBA em Engenharia de Software (USP/ESALQ).

**Autor:** Wagner Augusto de Sousa Lima

## 🎯 Objetivo da Pesquisa

Mensurar e comparar objetivamente a latência, o tamanho do *payload* (consumo de rede), o *throughput* (vazão) e a resiliência entre as arquiteturas de comunicação **REST, GraphQL e gRPC**. Todas as três interfaces foram implementadas em um mesmo ecossistema Spring Boot, expondo as mesmas regras de negócio, para serem submetidas a testes de estresse rigorosos e metodológicos usando a ferramenta k6.

## 🛠️ Stack Tecnológica

* **Linguagem:** Java 21
* **Framework:** Spring Boot 3.x
* **Gerenciador de Dependências:** Maven
* **Arquiteturas de API:** REST (HTTP/1.1) | GraphQL (HTTP/1.1) | gRPC (HTTP/2 Binário)
* **Banco de Dados:** PostgreSQL 15 (via Docker)
* **Testes de Carga e Performance:** Grafana k6 (via Docker)
* **Inspeção de Rede:** Postman

## 📂 Arquitetura do Projeto

O projeto foi estruturado seguindo princípios de **Clean Architecture** e isolamento de domínio, garantindo que a regra de negócio central seja estritamente agnóstica ao protocolo de comunicação utilizado na borda da aplicação.

* `domain`: O coração do software. Contém as Entidades e interfaces de Repositório puras.
* `application`: Orquestração de regras de negócio (*Services*) e contratos de dados (DTOs utilizando *Records*).
* `infrastructure`: A borda do sistema. Contém a implementação dos *Controllers* REST, *Controllers* GraphQL, Servidores gRPC, manipuladores globais de exceção e configurações de banco de dados.
* `k6-tests`: Diretório dedicado aos scripts JavaScript para automação de injeção de carga e estresse.
* `evidencias`: Base de dados primários da pesquisa, contendo os *logs* originais e medições de *payload* que embasam a monografia.

---

## 🚀 Como Executar o Ecossistema

### 1. Pré-requisitos
* JDK 21 instalado.
* Docker e Docker Compose rodando na máquina.
* Postman (com suporte a gRPC) para testes manuais.

### 2. Subindo a Infraestrutura
Clone o repositório e suba o contêiner do PostgreSQL a partir da raiz do projeto:
```bash
git clone [https://github.com/WagnerSousaLima/tcc-api-performance.git](https://github.com/WagnerSousaLima/tcc-api-performance.git)
cd tcc-api-performance
docker-compose up -d
```

### 3. Executando a Aplicação
Compile o projeto (etapa obrigatória para gerar os Stubs do Protobuf do gRPC) e inicie o Spring Boot:

```bash
./mvnw clean compile
./mvnw spring-boot:run
```

A aplicação subirá simultaneamente 3 servidores para atender aos diferentes protocolos:

🌐 API REST (Tomcat - HTTP/1.1): http://localhost:8085/produtos (Aceita GET e POST)

🕸️ API GraphQL (Tomcat - HTTP/1.1): * Painel Visual: http://localhost:8085/graphiql

Endpoint de Integração: http://localhost:8085/graphql

⚡ Servidor gRPC (Netty - HTTP/2): grpc://localhost:9090 (Utilize a aba gRPC do Postman para testar os contratos)

🔬 Como Reproduzir os Experimentos (Testes de Carga)
Para garantir a reprodutibilidade científica desta pesquisa, os testes de performance foram conteinerizados utilizando a imagem oficial do Grafana k6.

Com a aplicação Spring Boot e o PostgreSQL rodando, abra um novo terminal na raiz do projeto e execute os scripts de carga conforme a arquitetura desejada:

Para testar a API REST:
```bash 
docker run --rm -i -v "${PWD}:/repo" -w /repo/k6-tests -e BASE_URL=[http://host.docker.internal:8085](http://host.docker.internal:8085) grafana/k6 run test-rest.js
```

Para testar a API GraphQL:
```bash
docker run --rm -i -v "${PWD}:/repo" -w /repo/k6-tests -e BASE_URL=[http://host.docker.internal:8085](http://host.docker.internal:8085) grafana/k6 run test-graphql.js
```
Para testar o Servidor gRPC:
```bash
docker run --rm -i -v "${PWD}:/repo" -w /repo/k6-tests -e GRPC_ADDR=host.docker.internal:9090 grafana/k6 run test-grpc.js
```
Nota Metodológica: Para a coleta de dados de Cold Start (inicialização a frio), é estritamente necessário reiniciar os contêineres do PostgreSQL e a aplicação Spring Boot antes da execução de cada um dos scripts acima.

Status: Etapa prática concluída. Base de código e coleta de dados primários finalizadas.
