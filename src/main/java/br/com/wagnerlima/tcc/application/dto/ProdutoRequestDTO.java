package br.com.wagnerlima.tcc.application.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.math.BigDecimal;

public record ProdutoRequestDTO(
        @NotBlank String nome,
        @NotNull @Positive BigDecimal preco,
        String descricao
) {
}

