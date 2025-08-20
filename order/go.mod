module github.com/Jogos101/microservices/order

go 1.24.5

require (
	google.golang.org/grpc v1.74.2
	gorm.io/driver/mysql v1.6.0
	gorm.io/gorm v1.30.1
)

require (
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/go-sql-driver/mysql v1.8.1 // indirect
	github.com/jinzhu/inflection v1.0.0 // indirect
	github.com/jinzhu/now v1.1.5 // indirect
	golang.org/x/net v0.40.0 // indirect
	golang.org/x/sys v0.33.0 // indirect
	golang.org/x/text v0.25.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20250528174236-200df99c418a // indirect
	google.golang.org/protobuf v1.36.7 // indirect
)

require (
	github.com/Jogos101/microservices-proto/golang/order v0.0.0-00010101000000-000000000000
	github.com/Jogos101/microservices-proto/golang/payment v0.0.0-00010101000000-000000000000
	github.com/grpc-ecosystem/go-grpc-middleware v1.4.0
)

replace github.com/Jogos101/microservices-proto/golang/order => ../../Pratica-gRPC_microservices-proto/golang/order

replace github.com/Jogos101/microservices-proto/golang/payment => ../../Pratica-gRPC_microservices-proto/golang/payment
