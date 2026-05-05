package br.com.wagnerlima.tcc.application;

import br.com.wagnerlima.tcc.application.dto.ProdutoRequestDTO;
import br.com.wagnerlima.tcc.application.dto.ProdutoResponseDTO;
import br.com.wagnerlima.tcc.domain.Produto;
import br.com.wagnerlima.tcc.domain.ProdutoRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class ProdutoService {

    private final ProdutoRepository produtoRepository;

    @Transactional
    public ProdutoResponseDTO criarProduto(ProdutoRequestDTO dto) {
        Produto produto = new Produto(null, dto.nome(), dto.preco(), dto.descricao());
        produto.validarPreco();
        Produto salvo = produtoRepository.save(produto);
        return ProdutoResponseDTO.fromEntity(salvo);
    }

    @Transactional(readOnly = true)
    public ProdutoResponseDTO buscarPorId(UUID id) {
        Produto produto = produtoRepository.findById(id)
                .orElseThrow(() -> new RecursoNaoEncontradoException("Produto não encontrado com id " + id));
        return ProdutoResponseDTO.fromEntity(produto);
    }
}

