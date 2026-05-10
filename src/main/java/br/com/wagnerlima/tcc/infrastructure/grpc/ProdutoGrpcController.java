package br.com.wagnerlima.tcc.infrastructure.grpc;

import br.com.wagnerlima.tcc.application.ProdutoService;
import br.com.wagnerlima.tcc.application.dto.ProdutoRequestDTO;
import br.com.wagnerlima.tcc.application.dto.ProdutoResponseDTO;
import br.com.wagnerlima.tcc.infrastructure.grpc.stub.ProdutoGrpcServiceGrpc;
import br.com.wagnerlima.tcc.infrastructure.grpc.stub.ProdutoIdRequest;
import br.com.wagnerlima.tcc.infrastructure.grpc.stub.ProdutoRequest;
import br.com.wagnerlima.tcc.infrastructure.grpc.stub.ProdutoResponse;
import io.grpc.stub.StreamObserver;
import java.math.BigDecimal;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import net.devh.boot.grpc.server.service.GrpcService;

@GrpcService
@RequiredArgsConstructor
public class ProdutoGrpcController extends ProdutoGrpcServiceGrpc.ProdutoGrpcServiceImplBase {

    private final ProdutoService produtoService;

    @Override
    public void criarProduto(ProdutoRequest request, StreamObserver<ProdutoResponse> responseObserver) {
        ProdutoRequestDTO dto = new ProdutoRequestDTO(
                request.getNome(),
                BigDecimal.valueOf(request.getPreco()),
                request.getDescricao()
        );

        ProdutoResponseDTO response = produtoService.criarProduto(dto);

        responseObserver.onNext(toGrpcResponse(response));
        responseObserver.onCompleted();
    }

    @Override
    public void buscarProdutoPorId(ProdutoIdRequest request, StreamObserver<ProdutoResponse> responseObserver) {
        ProdutoResponseDTO response = produtoService.buscarPorId(UUID.fromString(request.getId()));

        responseObserver.onNext(toGrpcResponse(response));
        responseObserver.onCompleted();
    }

    private ProdutoResponse toGrpcResponse(ProdutoResponseDTO dto) {
        return ProdutoResponse.newBuilder()
                .setId(dto.id().toString())
                .setNome(dto.nome())
                .setPreco(dto.preco().doubleValue())
                .setDescricao(dto.descricao() == null ? "" : dto.descricao())
                .build();
    }
}
