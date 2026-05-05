package br.com.wagnerlima.tcc.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import br.com.wagnerlima.tcc.domain.ProdutoRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ProdutoServiceTest {

    @Mock
    private ProdutoRepository produtoRepository;

    @InjectMocks
    private ProdutoService produtoService;

    @Test
    void buscarPorIdQuandoNaoExisteDeveLancarExcecao() {
        UUID id = UUID.randomUUID();
        when(produtoRepository.findById(id)).thenReturn(Optional.empty());

        RecursoNaoEncontradoException exception = assertThrows(
                RecursoNaoEncontradoException.class,
                () -> produtoService.buscarPorId(id)
        );

        assertEquals("Produto não encontrado com id " + id, exception.getMessage());
        verify(produtoRepository).findById(id);
    }
}

