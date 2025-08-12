package ports

import "github.com/Jogos101/microservices/order/internal/application/core/domain"

type PaymentPort interface {
	Charge(*domain.Order) error
}

