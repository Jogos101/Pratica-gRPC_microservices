package ports

import (
	"context"

	"github.com/Jogos101/microservices/shipping/internal/application/core/domain"
)

type APIPort interface {
	Charge(ctx context.Context, shipping domain.Shipping) (domain.Shipping, error)
}
