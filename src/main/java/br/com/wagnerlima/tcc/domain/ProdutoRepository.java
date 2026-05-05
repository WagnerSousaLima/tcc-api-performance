package br.com.wagnerlima.tcc.domain;

import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProdutoRepository extends JpaRepository<Produto, UUID> {
}

