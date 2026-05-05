# AGENTS.md

## Visão rápida
- Projeto Spring Boot com pacote raiz `br.com.wagnerlima.tcc`.
- Ponto de entrada: `src/main/java/br/com/wagnerlima/tcc/TccApiPerformanceApplication.java`.
- Stack declarada no `pom.xml`: Java 21, Spring Boot 4.0.6, Spring Web MVC, Spring Data JPA, Validation, PostgreSQL e Lombok.

## Como trabalhar neste código-base
- Preserve o pacote raiz `br.com.wagnerlima.tcc` para manter o component scan automático.
- Mantenha o isolamento de camadas usado neste TCC:
  - `domain`: entidades JPA e repositórios.
  - `application`: regras de negócio, DTOs e exceções da aplicação.
  - `infrastructure.rest`: controllers e tratamento HTTP.
- Não exponha entidades JPA nos controllers; aceite e retorne somente DTOs.

## Padrões observáveis/úteis
- Use `record` para DTOs de entrada e saída quando fizer sentido, como `application/dto/ProdutoRequestDTO`.
- Use Lombok apenas onde o projeto já pede simplicidade de construtores/getters, como na entidade `domain/Produto`.
- Para conversão entidade -> DTO, prefira métodos estáticos explícitos, como `ProdutoResponseDTO.fromEntity(...)`.
- Validações de request devem ser acionadas com `@Valid` no controller e tratadas por `@RestControllerAdvice`.
- Erros de negócio/ausência de recurso devem virar exceções da aplicação, por exemplo `RecursoNaoEncontradoException`.

## Workflow recomendado
- Build/teste local com Maven Wrapper:
```bash
./mvnw test
./mvnw spring-boot:run
```
- Em Windows com Git Bash, os mesmos comandos funcionam com `./mvnw`.
- Se algo falhar, valide primeiro `pom.xml` e os pacotes sob `src/main/java/br/com/wagnerlima/tcc`.

## Arquivos de referência neste repositório
- `pom.xml` — dependências, versão do Java e plugins.
- `src/main/resources/application.yaml` — configuração mínima atual da aplicação.
- `src/test/java/br/com/wagnerlima/tcc/TccApiPerformanceApplicationTests.java` — padrão atual de teste de bootstrap.

