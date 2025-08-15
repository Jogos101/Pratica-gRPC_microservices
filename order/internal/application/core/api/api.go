package api

import (
	"github.com/Jogos101/microservices/order/internal/application/core/domain"
	"github.com/Jogos101/microservices/order/internal/ports"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Application struct {
	db      ports.DBPort
	payment ports.PaymentPort
}

func NewApplication(db ports.DBPort, payment ports.PaymentPort) *Application {
	return &Application{
		db:      db,
		payment: payment,
	}
}

func (a Application) PlaceOrder(order domain.Order) (domain.Order, error) {
	for _, orderItem := range order.OrderItems {
		if orderItem.Quantity > 50 {
			return domain.Order{}, status.Errorf(codes.InvalidArgument, "Não é uma ordem com mais de 50 itens.")
		}
	}
	err := a.db.Save(&order)
	if err != nil {
		return domain.Order{}, err
	}
	paymentErr := a.payment.Charge(&order)
	if paymentErr != nil {
		return domain.Order{}, paymentErr
	}
	return order, nil
}
