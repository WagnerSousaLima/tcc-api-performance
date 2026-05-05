# 🚀 Desempenho de Arquiteturas de API: REST, GraphQL e gRPC

Este repositório contém o código-fonte do experimento prático desenvolvido para o Trabalho de Conclusão de Curso (TCC) do MBA em Engenharia de Software.

## 🎯 Objetivo da Pesquisa

Mensurar e comparar objetivamente a latência, o tamanho do *payload*, o *throughput* e o consumo de recursos computacionais (CPU e memória) entre as arquiteturas de comunicação **REST, GraphQL e gRPC**. Todas as três interfaces foram implementadas em um mesmo ecossistema Spring Boot, expondo as mesmas regras de negócio, para serem submetidas a testes de estresse rigorosos e idênticos.

## 🛠️ Stack Tecnológica

- **Linguagem:** Java 21
- **Framework:** Spring Boot 4.0.6
- **Gerenciador de Dependências:** Maven
- **Arquiteturas de API:** REST (**implementado**) | GraphQL (**planejado**) | gRPC (**planejado**)
- **Banco de Dados:** H2 Database (memória / desenvolvimento) | PostgreSQL (dependência presente para uso futuro)
- **Testes e Métricas:** JUnit 5, Mockito, Spring Boot Actuator (planejado), k6 (planejado)

## 📂 Arquitetura do Projeto

O projeto foi estruturado seguindo princípios de **Clean Architecture** e isolamento de domínio, garantindo que a regra de negócio seja agnóstica ao protocolo de comunicação (HTTP/JSON ou binário).

- `domain`: o coração do software. Contém as entidades JPA e os repositórios.
- `application`: orquestração de regras de negócio (services), DTOs e exceções da aplicação.
- `infrastructure.rest`: borda HTTP da aplicação. Contém os controllers REST e o tratamento global de exceções.

Exemplos reais no código:
- `src/main/java/br/com/wagnerlima/tcc/domain/Produto.java`
- `src/main/java/br/com/wagnerlima/tcc/application/ProdutoService.java`
- `src/main/java/br/com/wagnerlima/tcc/infrastructure/rest/ProdutoController.java`

## 🚀 Como Executar (Ambiente de Desenvolvimento)

1. Clone este repositório:

```bash
git clone https://github.com/SEU_USUARIO/tcc-api-performance.git
```

2. Acesse a pasta do projeto e garanta que o JDK 21 está configurado na sua máquina.

3. Suba a aplicação utilizando o Maven Wrapper:

```bash
./mvnw spring-boot:run
```

No Windows com Git Bash, o mesmo comando funciona com `./mvnw`.

4. A API REST estará disponível para testes locais na porta:

```text
http://localhost:8085/produtos
```

## 🧪 Testes

Execute a suíte de testes com:

```bash
./mvnw test
```

A base atual inclui:
- `src/test/java/br/com/wagnerlima/tcc/TccApiPerformanceApplicationTests.java`
- `src/test/java/br/com/wagnerlima/tcc/application/ProdutoServiceTest.java`

## 📌 Endpoints REST Disponíveis

- `POST /produtos` — cria um produto a partir de `ProdutoRequestDTO`
- `GET /produtos/{id}` — busca um produto por ID e retorna `ProdutoResponseDTO`

## Observações

- O banco padrão configurado em `src/main/resources/application.yaml` é o **H2 em memória**.
- A arquitetura foi preparada para suportar evolução futura para GraphQL e gRPC sem expor a entidade de domínio nos controllers.
- *Pesquisa em desenvolvimento.*

