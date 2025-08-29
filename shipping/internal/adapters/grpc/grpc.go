package grpc

import (
	"context"
	"fmt"

	"github.com/Jogos101/microservices-proto/golang/shipping"
	"github.com/Jogos101/microservices/shipping/internal/application/core/domain"
	log "github.com/sirupsen/logrus"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func (a Adapter) Create(ctx context.Context, request *shipping.CreateShippingRequest) (*shipping.CreateShippingResponse, error) {
	log.WithContext(ctx).Info("Creating shipping...")

	newShipping := domain.NewShipping(request.UserId, request.OrderId, request.TotalPrazo)
	result, err := a.api.Charge(ctx, newShipping)
	code := status.Code(err)
	if code == codes.InvalidArgument {
		return nil, err
	} else if err != nil {
		return nil, status.New(codes.Internal, fmt.Sprintf("failed to charge. %v ", err)).Err()
	}
	return &shipping.CreateShippingResponse{ShippingId: result.ID}, nil
}
