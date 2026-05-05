package br.com.wagnerlima.tcc.infrastructure.rest;

import br.com.wagnerlima.tcc.application.RecursoNaoEncontradoException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(RecursoNaoEncontradoException.class)
    public ResponseEntity<Map<String, Object>> handleRecursoNaoEncontrado(RecursoNaoEncontradoException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of(
                "mensagem", ex.getMessage()
        ));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleMethodArgumentNotValid(MethodArgumentNotValidException ex) {
        Map<String, String> erros = ex.getBindingResult().getFieldErrors().stream()
                .collect(Collectors.toMap(
                        FieldError::getField,
                        fieldError -> Objects.requireNonNullElse(fieldError.getDefaultMessage(), "Valor inválido"),
                        (primeiro, segundo) -> primeiro,
                        LinkedHashMap::new
                ));

        Map<String, Object> resposta = new LinkedHashMap<>();
        resposta.put("mensagem", "Falha de validação");
        resposta.put("erros", erros);
        return ResponseEntity.badRequest().body(resposta);
    }
}

