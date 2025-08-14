# Pratica-gRPC_microservices

Microsserviços **Order** e **Payment** em Go com gRPC, integrados via protobufs compartilhados.  
Inclui scripts para inicialização, teste e limpeza do ambiente no WSL + Docker.

## Requisitos

- **WSL2** com Ubuntu
- **Go** ≥ 1.21
- **Docker Desktop** com integração WSL
- **Protocol Buffers (protoc)**
- Plugins Go:
  ```bash
  go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
  ```
- **grpcurl** para testes:
  ```bash
  go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
  echo 'export PATH="$(go env GOPATH)/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
  ```

## Estrutura

```
Pratica-gRPC_microservices/
├── order/       # serviço Order
├── payment/     # serviço Payment
├── run.sh       # inicialização e utilitários
├── stop.sh
../init/init.sql # script de criação de bancos
../Pratica-gRPC_microservices-proto/
```

## Variáveis de Ambiente

| Variável                | Descrição                                                        |
|------------------------|------------------------------------------------------------------|
| `DB_DRIVER`            | Driver do banco (`mysql`)                                        |
| `DATA_SOURCE_URL`      | DSN do banco (`root:minhasenha@tcp(127.0.0.1:3306)/order`)       |
| `APPLICATION_PORT`     | Porta gRPC do serviço                                            |
| `ENV`                  | Ambiente (`development` ativa o Server Reflection)               |
| `PAYMENT_SERVICE_URL`  | URL do serviço Payment (usado no Order, ex.: `localhost:3001`)   |

## Uso

```bash
# Subir MySQL + Payment + Order
bash run.sh up

# Testar chamada Order/Create
bash run.sh test

# Ver dados rapidamente (orders e payments)
bash run.sh db-view

# Abrir MySQL no terminal
bash run.sh db

# Limpar tabelas para novo teste (redefine AUTO_INCREMENT)
bash run.sh reset-db

# Ver logs dos serviços
bash run.sh logs

# Derrubar tudo (e remover o MySQL)
bash run.sh down
```

## Teste manual com grpcurl

```bash
# Listar serviços (reflection precisa de ENV=development)
grpcurl -plaintext localhost:3000 list

# Criar pedido
grpcurl -plaintext -d '{
  "customer_id": 123,
  "order_items": [
    {"product_code":"P1","quantity":2,"unit_price":10.5},
    {"product_code":"P2","quantity":1,"unit_price":50.0}
  ],
  "total_price": 71.0
}' localhost:3000 Order/Create
```

## Observações

- Se a porta 3306 já estiver ocupada no host, use outra:
  ```bash
  export MYSQL_PORT=3307
  bash run.sh up
  ```
- No `go.mod` dos serviços, aponte os `replace` para `../Pratica-gRPC_microservices-proto/golang/...`.
- Para testes da Parte 3, você pode chamar `bash run.sh test` com payloads diferentes pelo `grpcurl`.
