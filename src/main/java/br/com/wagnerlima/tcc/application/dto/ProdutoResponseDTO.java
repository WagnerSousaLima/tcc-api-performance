package br.com.wagnerlima.tcc.application.dto;

import br.com.wagnerlima.tcc.domain.Produto;
import java.math.BigDecimal;
import java.util.UUID;

public record ProdutoResponseDTO(
        UUID id,
        String nome,
        BigDecimal preco,
        String descricao
) {
    public static ProdutoResponseDTO fromEntity(Produto produto) {
        return new ProdutoResponseDTO(
                produto.getId(),
                produto.getNome(),
                produto.getPreco(),
                produto.getDescricao()
        );
    }
}

