package api

import (
	"context"

	"github.com/Jogos101/microservices/payment/internal/application/core/domain"
	"github.com/Jogos101/microservices/payment/internal/ports"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Application struct {
	db ports.DBPort
}

func NewApplication(db ports.DBPort) *Application {
	return &Application{
		db: db,
	}
}

func (a Application) Charge(ctx context.Context, payment domain.Payment) (domain.Payment, error) {
	if payment.TotalPrice > 1000 {
		return domain.Payment{}, status.Errorf(codes.InvalidArgument, "Não é permitido pagamento maior que R$1.000,00.")
	}
	err := a.db.Save(ctx, &payment)
	if err != nil {
		return domain.Payment{}, err
	}
	return payment, nil
}
