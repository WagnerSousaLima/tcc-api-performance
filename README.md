# 🚀 Desempenho de Arquiteturas de API: REST, GraphQL e gRPC

Este repositório contém o código-fonte do experimento prático desenvolvido para o Trabalho de Conclusão de Curso (TCC) do MBA em Engenharia de Software (USP/ESALQ).

**Autor:** Wagner Augusto de Sousa Lima

## 🎯 Objetivo da Pesquisa
Mensurar e comparar objetivamente a latência, o tamanho do *payload*, o *throughput* e o consumo de recursos computacionais (CPU e memória) entre as arquiteturas de comunicação **REST, GraphQL e gRPC**. Todas as três interfaces foram implementadas em um mesmo ecossistema Spring Boot, expondo as mesmas regras de negócio, para serem submetidas a testes de estresse rigorosos usando K6.

## 🛠️ Stack Tecnológica
* **Linguagem:** Java 21
* **Framework:** Spring Boot 
* **Gerenciador de Dependências:** Maven
* **Arquiteturas de API:** REST (Implementado) | GraphQL (Implementado) | gRPC (Implementado)
* **Banco de Dados:** PostgreSQL 15 (via Docker)
* **Testes e Métricas:** JUnit 5, k6 (Planejado), Spring Boot Actuator

## 📂 Arquitetura do Projeto
O projeto foi estruturado seguindo princípios de **Clean Architecture** e isolamento de domínio, garantindo que a regra de negócio seja agnóstica ao protocolo de comunicação (HTTP/JSON ou HTTP/2 Binário).

* `domain`: O coração do software. Contém as Entidades e interfaces de Repositório puras.
* `application`: Orquestração de regras de negócio (Services) e contratos de dados (DTOs utilizando `Records`).
* `infrastructure`: A borda do sistema. Contém a implementação dos *Controllers* REST, *Controllers* GraphQL, Servidores gRPC e os manipuladores globais de exceção.

## 🚀 Como Executar (Ambiente de Desenvolvimento)

### 1. Pré-requisitos
* [JDK 21](https://adoptium.net/) instalado.
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) rodando na máquina.
* [Postman](https://www.postman.com/) (com suporte a gRPC) para testes manuais.

### 2. Subindo a Infraestrutura (Banco de Dados)
Clone o repositório e suba o contêiner do PostgreSQL na raiz do projeto:
```bash
git clone [https://github.com/WagnerSousaLima/tcc-api-performance.git](https://github.com/WagnerSousaLima/tcc-api-performance.git)
cd tcc-api-performance
docker-compose up -d
```

### 3. Executando a Aplicação
Compile o projeto (necessário para gerar os Stubs do gRPC) e inicie o Spring Boot:
```
Bash
./mvnw clean compile
./mvnw spring-boot:run
```
### 4. Acessando as Interfaces
A aplicação subirá simultaneamente 3 servidores para atender aos diferentes protocolos:

🌐 API REST (Tomcat - HTTP/1.1): * http://localhost:8085/produtos (Aceita GET e POST)

🕸️ API GraphQL (Tomcat - HTTP/1.1): * Painel Visual: http://localhost:8085/graphiql

Endpoint de Integração: http://localhost:8085/graphql

⚡ Servidor gRPC (Netty - HTTP/2): * grpc://localhost:9090 (Utilize a aba gRPC do Postman para testar os contratos)

Pesquisa científica em desenvolvimento. Etapa de coleta de métricas em andamento.