package br.com.wagnerlima.tcc.infrastructure.graphql;

import br.com.wagnerlima.tcc.application.ProdutoService;
import br.com.wagnerlima.tcc.application.dto.ProdutoRequestDTO;
import br.com.wagnerlima.tcc.application.dto.ProdutoResponseDTO;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
@RequiredArgsConstructor
public class ProdutoGraphQLController {

    private final ProdutoService produtoService;

    @QueryMapping
    public ProdutoResponseDTO buscarProdutoPorId(@Argument String id) {
        return produtoService.buscarPorId(UUID.fromString(id));
    }

    @MutationMapping
    public ProdutoResponseDTO criarProduto(@Argument ProdutoRequestDTO input) {
        return produtoService.criarProduto(input);
    }
}
