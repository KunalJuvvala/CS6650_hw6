// product-service.go
//
// Product API implementing the Product section of api.yaml:
//   GET  /products/{productId}          -> 200 Product | 404 Error | 500 Error
//   POST /products/{productId}/details  -> 204 (no body) | 400 Error | 404 Error | 500 Error
//
// Extras for Part V (observability):
//   GET /metrics  -> Prometheus metrics (RED: rate, errors, duration)
//   GET /health   -> simple liveness check
//   One structured JSON log line per request on stdout (ends up in CloudWatch on ECS).
//
// Environment variables:
//   PORT                    port to listen on (default 8080, must match container_port in terraform/variables.tf)
//   SEED_PRODUCTS           number of products pre-loaded with IDs 1..N (default 100)
//   ENABLE_FAULT_INJECTION  "true" lets the header `X-Fault-Inject: 500` force a 500 (for demoing that code)
package main

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ---------------------------------------------------------------------------
// Models (mirror components/schemas in api.yaml)
// ---------------------------------------------------------------------------

// Product is what we store and what GET returns.
type Product struct {
	ProductID    int32  `json:"product_id"`
	SKU          string `json:"sku"`
	Manufacturer string `json:"manufacturer"`
	CategoryID   int32  `json:"category_id"`
	Weight       int32  `json:"weight"`
	SomeOtherID  int32  `json:"some_other_id"`
}

// ProductInput uses pointers so we can tell "field missing" apart from "field = 0 / empty".
// int32 matches `format: int32` in api.yaml: values above 2147483647, decimals (1.5) or strings
// fail JSON decoding and become a 400.
type ProductInput struct {
	ProductID    *int32  `json:"product_id"`
	SKU          *string `json:"sku"`
	Manufacturer *string `json:"manufacturer"`
	CategoryID   *int32  `json:"category_id"`
	Weight       *int32  `json:"weight"`
	SomeOtherID  *int32  `json:"some_other_id"`
}

// ErrorResponse mirrors the Error schema in api.yaml.
type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
	Details string `json:"details,omitempty"`
}

// validate applies the constraints from the Product schema. Returns "" when valid.
func (in ProductInput) validate(pathID int32) string {
	switch {
	case in.ProductID == nil || *in.ProductID < 1:
		return "product_id is required and must be an integer >= 1"
	case *in.ProductID != pathID:
		return "product_id in body must match productId in the path"
	case in.SKU == nil || utf8.RuneCountInString(*in.SKU) < 1 || utf8.RuneCountInString(*in.SKU) > 100:
		return "sku is required and must be 1-100 characters"
	case in.Manufacturer == nil || utf8.RuneCountInString(*in.Manufacturer) < 1 || utf8.RuneCountInString(*in.Manufacturer) > 200:
		return "manufacturer is required and must be 1-200 characters"
	case in.CategoryID == nil || *in.CategoryID < 1:
		return "category_id is required and must be an integer >= 1"
	case in.Weight == nil || *in.Weight < 0:
		return "weight is required and must be an integer >= 0"
	case in.SomeOtherID == nil || *in.SomeOtherID < 1:
		return "some_other_id is required and must be an integer >= 1"
	}
	return ""
}

func (in ProductInput) toProduct() Product {
	return Product{
		ProductID:    *in.ProductID,
		SKU:          *in.SKU,
		Manufacturer: *in.Manufacturer,
		CategoryID:   *in.CategoryID,
		Weight:       *in.Weight,
		SomeOtherID:  *in.SomeOtherID,
	}
}

// ---------------------------------------------------------------------------
// Storage: map + RWMutex
//   - map gives O(1) lookup by product_id (the only access pattern the API needs)
//   - Go maps are NOT safe for concurrent read+write (the runtime crashes the whole
//     process with "concurrent map read and map write"), so we guard it.
//   - RWMutex lets many GETs read in parallel; only POSTs take the exclusive lock.
//     Reads dominate in a real store, so this fits the workload.
// ---------------------------------------------------------------------------

type ProductStore struct {
	mu       sync.RWMutex
	products map[int32]Product
}

func NewProductStore() *ProductStore {
	return &ProductStore{products: make(map[int32]Product)}
}

func (s *ProductStore) Get(id int32) (Product, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.products[id]
	return p, ok
}

// Update replaces an existing product's details. Returns false if the product does not exist (-> 404).
func (s *ProductStore) Update(p Product) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.products[p.ProductID]; !ok {
		return false
	}
	s.products[p.ProductID] = p
	return true
}

// Seed pre-loads products 1..n so GET has data and POST /details has something to update.
func (s *ProductStore) Seed(n int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := int32(1); i <= int32(n); i++ {
		s.products[i] = Product{
			ProductID:    i,
			SKU:          fmt.Sprintf("SKU-%05d", i),
			Manufacturer: "Acme Corporation",
			CategoryID:   (i % 10) + 1,
			Weight:       (i % 50) * 10,
			SomeOtherID:  i,
		}
	}
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

// parseProductID enforces the path parameter schema: integer, int32, minimum 1.
func parseProductID(raw string) (int32, bool) {
	v, err := strconv.ParseInt(raw, 10, 32)
	if err != nil || v < 1 {
		return 0, false
	}
	return int32(v), true
}

type handlers struct {
	store *ProductStore
}

// GET /products/{productId}
func (h *handlers) getProduct(c *gin.Context) {
	id, ok := parseProductID(c.Param("productId"))
	if !ok {
		// api.yaml lists only 200/404/500 for this GET (no 400), so an unusable ID is "not found".
		c.JSON(http.StatusNotFound, ErrorResponse{
			Error:   "NOT_FOUND",
			Message: "product not found",
			Details: "productId must be an integer between 1 and 2147483647",
		})
		return
	}

	p, ok := h.store.Get(id)
	if !ok {
		c.JSON(http.StatusNotFound, ErrorResponse{
			Error:   "NOT_FOUND",
			Message: "product not found",
			Details: fmt.Sprintf("no product with id %d", id),
		})
		return
	}
	c.JSON(http.StatusOK, p)
}

// POST /products/{productId}/details
func (h *handlers) addProductDetails(c *gin.Context) {
	id, ok := parseProductID(c.Param("productId"))
	if !ok {
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "invalid productId",
			Details: "productId must be an integer between 1 and 2147483647",
		})
		return
	}

	var in ProductInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "request body is not valid JSON for a Product",
			Details: err.Error(),
		})
		return
	}

	if msg := in.validate(id); msg != "" {
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "product validation failed",
			Details: msg,
		})
		return
	}

	if !h.store.Update(in.toProduct()) {
		c.JSON(http.StatusNotFound, ErrorResponse{
			Error:   "NOT_FOUND",
			Message: "product not found",
			Details: fmt.Sprintf("no product with id %d", id),
		})
		return
	}

	c.Status(http.StatusNoContent) // 204, no body
}

// ---------------------------------------------------------------------------
// Observability: Prometheus RED metrics + one JSON log line per request
// ---------------------------------------------------------------------------

var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total HTTP requests (Rate).",
	}, []string{"method", "route", "status"})

	httpErrorsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_request_errors_total",
		Help: "Total non-2xx HTTP responses (Errors).",
	}, []string{"method", "route", "status"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name: "http_request_duration_seconds",
		Help: "HTTP request latency in seconds (Duration).",
		// In-memory handlers are sub-millisecond, so start buckets small.
		Buckets: []float64{0.0001, 0.00025, 0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5},
	}, []string{"method", "route"})
)

// observability must be registered FIRST so it wraps recovery and still records 500s.
func observability(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.URL.Path == "/metrics" {
			c.Next() // don't measure Prometheus scraping itself
			return
		}

		start := time.Now()
		c.Next()
		elapsed := time.Since(start)

		route := c.FullPath() // route template, e.g. /products/:productId (keeps label cardinality low)
		if route == "" {
			route = "unmatched"
		}
		status := c.Writer.Status()
		statusStr := strconv.Itoa(status)
		method := c.Request.Method

		httpRequestsTotal.WithLabelValues(method, route, statusStr).Inc()
		if status < 200 || status > 299 {
			httpErrorsTotal.WithLabelValues(method, route, statusStr).Inc()
		}
		httpRequestDuration.WithLabelValues(method, route).Observe(elapsed.Seconds())

		logger.Info("request",
			"method", method,
			"endpoint", route,
			"path", c.Request.URL.Path,
			"status", status,
			"duration_ms", float64(elapsed.Microseconds())/1000.0,
		)
	}
}

// faultInjection forces a panic (-> recovery -> 500) when the client sends `X-Fault-Inject: 500`.
// Only active when ENABLE_FAULT_INJECTION=true, so it is off in normal deployments.
func faultInjection() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("X-Fault-Inject") == "500" {
			panic("simulated internal failure (fault injection)")
		}
		c.Next()
	}
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil && v >= 0 {
		return v
	}
	return def
}

func main() {
	gin.SetMode(gin.ReleaseMode)
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	store := NewProductStore()
	seed := envInt("SEED_PRODUCTS", 100)
	store.Seed(seed)

	r := gin.New()
	r.Use(observability(logger)) // 1st: measures everything, including recovered panics
	r.Use(gin.CustomRecovery(func(c *gin.Context, recovered any) { // 2nd: turns panics into 500 JSON
		c.AbortWithStatusJSON(http.StatusInternalServerError, ErrorResponse{
			Error:   "INTERNAL_ERROR",
			Message: "an unexpected error occurred",
			Details: fmt.Sprint(recovered),
		})
	}))
	if os.Getenv("ENABLE_FAULT_INJECTION") == "true" {
		r.Use(faultInjection())
		logger.Warn("fault injection enabled: send header 'X-Fault-Inject: 500' to force a 500")
	}

	h := &handlers{store: store}
	r.GET("/health", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))
	r.GET("/products/:productId", h.getProduct)
	r.POST("/products/:productId/details", h.addProductDetails)
	registerSearchRoutes(r) // HW6: GET /products/search?q=... (defined in search.go)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	logger.Info("starting product service", "port", port, "seeded_products", seed)
	if err := r.Run(":" + port); err != nil {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
