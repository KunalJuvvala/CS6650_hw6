// search.go — HW6 product search endpoint, matching product-search.yaml (line 21+).
//
// Registered in main() with: registerSearchRoutes(r)
//
// What it does:
//   - At startup, generates 100,000 products and stores them in a sync.Map.
//   - GET /products/search?q=<text> checks EXACTLY 100 products (not 100 matches),
//     matching q case-insensitively against the product name OR its category name.
//   - Returns at most 20 matching products, total_found, and search_time.
//
// Spec notes (product-search.yaml):
//   - q: required, 1..100 characters                -> otherwise 400 (Error schema)
//   - 200 body: products (array of Product), total_found (int32, 0..20), search_time (string, e.g. "1.2s")
//   - Product requires product_id, sku, manufacturer, category_id (>=1), weight (>=0), some_other_id (>=1).
//     Product has no "name" field, but OpenAPI allows extra properties, so we also return "name"
//     (it's what the search matches on).
//   - total_found has maximum: 20, so it is the number of matches returned (capped at 20).
//     The full number of matches among the 100 checked is sent in the X-Total-Matches header.
package main

import (
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
)

const (
	searchCatalogSize        = 100_000 // products generated at startup
	productsCheckedPerSearch = 100     // every search checks exactly this many
	maxSearchResults         = 20      // at most this many products are returned
	maxQueryLength           = 100     // q maxLength in the spec
)

// Category names, indexed by category_id - 1 (category_id must be >= 1 per the spec).
var categoryNames = []string{
	"Electronics", "Books", "Home", "Garden", "Toys",
	"Sports", "Clothing", "Beauty", "Automotive", "Grocery",
}

var brands = []string{
	"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
}

// SearchProduct follows the Product schema, plus "name" (extra field the search matches on).
type SearchProduct struct {
	ProductID    int32  `json:"product_id"`
	SKU          string `json:"sku"`
	Manufacturer string `json:"manufacturer"`
	CategoryID   int32  `json:"category_id"`
	Weight       int32  `json:"weight"`
	SomeOtherID  int32  `json:"some_other_id"`
	Name         string `json:"name"`
}

// SearchResponse is the 200 body from the spec.
type SearchResponse struct {
	Products   []SearchProduct `json:"products"`
	TotalFound int32           `json:"total_found"`
	SearchTime string          `json:"search_time"`
}

var (
	// sync.Map: safe for many goroutines (one per request) to read at once.
	searchCatalog sync.Map // key: int id (1..100000), value: SearchProduct

	// Each search starts where the previous one stopped, so we cycle through the
	// whole catalog instead of always checking products 1..100.
	searchCursor atomic.Uint64
)

func categoryName(id int32) string {
	return categoryNames[id-1]
}

// init runs automatically before main(), so no change to main() is needed for the data.
func init() {
	start := time.Now()
	for i := 1; i <= searchCatalogSize; i++ {
		brand := brands[(i/7)%len(brands)]
		searchCatalog.Store(i, SearchProduct{
			ProductID:    int32(i),
			SKU:          fmt.Sprintf("SKU-%06d", i),
			Manufacturer: brand,
			CategoryID:   int32(i%len(categoryNames)) + 1, // rotate through 1..10 with modulo
			Weight:       int32((i % 50) * 10),
			SomeOtherID:  int32(i),
			Name:         fmt.Sprintf("Product %s %d", brand, i), // "Product [Brand] [ID]"
		})
	}
	slog.Info("search catalog loaded", "products", searchCatalogSize, "took_ms", time.Since(start).Milliseconds())
}

// registerSearchRoutes wires up GET /products/search on your existing Gin router.
// The observability middleware is global, so this route shows up in Prometheus metrics
// and JSON request logs with route="/products/search".
func registerSearchRoutes(r *gin.Engine) {
	r.GET("/products/search", searchProducts)
}

func searchProducts(c *gin.Context) {
	start := time.Now()

	q := strings.TrimSpace(c.Query("q")) // reads the value after ?q=
	if n := utf8.RuneCountInString(q); n < 1 || n > maxQueryLength {
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "invalid search query",
			Details: fmt.Sprintf("query parameter 'q' is required and must be 1-%d characters", maxQueryLength),
		})
		return
	}
	needle := strings.ToLower(q)

	// Reserve a block of 100 ids for this request (thread-safe).
	offset := int((searchCursor.Add(productsCheckedPerSearch) - productsCheckedPerSearch) % searchCatalogSize)

	results := make([]SearchProduct, 0, maxSearchResults)
	totalMatches := 0
	checkedCount := 0

	// Single-threaded on purpose: fixed amount of work per request.
	for checked := 0; checked < productsCheckedPerSearch; checked++ {
		id := (offset+checked)%searchCatalogSize + 1
		v, ok := searchCatalog.Load(id)
		if !ok {
			continue
		}
		p := v.(SearchProduct)
		checkedCount++

		if strings.Contains(strings.ToLower(p.Name), needle) ||
			strings.Contains(strings.ToLower(categoryName(p.CategoryID)), needle) {
			totalMatches++
			if len(results) < maxSearchResults {
				results = append(results, p)
			}
		}
	}

	// Evidence for the report, visible with curl -i.
	c.Header("X-Products-Checked", fmt.Sprint(checkedCount))
	c.Header("X-Total-Matches", fmt.Sprint(totalMatches))
	c.JSON(http.StatusOK, SearchResponse{
		Products:   results,
		TotalFound: int32(len(results)), // spec: total_found is 0..20
		SearchTime: time.Since(start).String(), // e.g. "41.2µs"
	})
}
