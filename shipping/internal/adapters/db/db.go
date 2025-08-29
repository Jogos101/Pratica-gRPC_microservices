package db

import (
	"context"
	"fmt"

	"github.com/Jogos101/microservices/shipping/internal/application/core/domain"
	"github.com/uptrace/opentelemetry-go-extra/otelgorm"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

type Shipping struct {
	gorm.Model
	CustomerID int64
	Status     string
	OrderID    int64
	TotalPrazo float32
}

type Adapter struct {
	db *gorm.DB
}

func (a Adapter) Get(ctx context.Context, id string) (domain.Shipping, error) {
	var shippingEntity Shipping
	res := a.db.WithContext(ctx).First(&shippingEntity, id)
	shipping := domain.Shipping{
		ID:         int64(shippingEntity.ID),
		CustomerID: shippingEntity.CustomerID,
		Status:     shippingEntity.Status,
		OrderId:    shippingEntity.OrderID,
		TotalPrazo: shippingEntity.TotalPrazo,
		CreatedAt:  shippingEntity.CreatedAt.UnixNano(),
	}
	return shipping, res.Error
}

func (a Adapter) Save(ctx context.Context, shipping *domain.Shipping) error {
	orderModel := Shipping{
		CustomerID: shipping.CustomerID,
		Status:     shipping.Status,
		OrderID:    shipping.OrderId,
		TotalPrazo: shipping.TotalPrazo,
	}
	res := a.db.WithContext(ctx).Create(&orderModel)
	if res.Error == nil {
		shipping.ID = int64(orderModel.ID)
	}
	return res.Error
}

func NewAdapter(dataSourceUrl string) (*Adapter, error) {
	db, openErr := gorm.Open(mysql.Open(dataSourceUrl), &gorm.Config{})
	if openErr != nil {
		return nil, fmt.Errorf("db connection error: %v", openErr)
	}

	if err := db.Use(otelgorm.NewPlugin(otelgorm.WithDBName("shipping"))); err != nil {
		return nil, fmt.Errorf("db otel plugin error: %v", err)
	}

	err := db.AutoMigrate(&Shipping{})
	if err != nil {
		return nil, fmt.Errorf("db migration error: %v", err)
	}
	return &Adapter{db: db}, nil
}
