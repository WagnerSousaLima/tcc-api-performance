package br.com.wagnerlima.tcc.infrastructure.rest;

import br.com.wagnerlima.tcc.application.ProdutoService;
import br.com.wagnerlima.tcc.application.dto.ProdutoRequestDTO;
import br.com.wagnerlima.tcc.application.dto.ProdutoResponseDTO;
import jakarta.validation.Valid;
import java.net.URI;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/produtos")
@RequiredArgsConstructor
public class ProdutoController {

    private final ProdutoService produtoService;

    @PostMapping
    public ResponseEntity<ProdutoResponseDTO> criar(@Valid @RequestBody ProdutoRequestDTO dto) {
        ProdutoResponseDTO resposta = produtoService.criarProduto(dto);
        return ResponseEntity.created(URI.create("/produtos/" + resposta.id())).body(resposta);
    }

    @GetMapping("/{id}")
    public ResponseEntity<ProdutoResponseDTO> buscarPorId(@PathVariable UUID id) {
        return ResponseEntity.ok(produtoService.buscarPorId(id));
    }
}

