package middlewares

import (
	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"net/http/httptest"
	"testing"
)

func TestLocalHardenedRejectsUnsafeRoutesAndMissingReceiveID(t *testing.T) {
	app := fiber.New()
	app.Use(LocalHardened())
	app.Use(func(c fiber.Ctx) error { return c.SendStatus(200) })
	for _, tc := range []struct {
		method, path, id string
		status           int
	}{
		{"POST", "/v1/messages/send", "", 403},
		{"POST", "/v1/webhooks", "", 403},
		{"POST", "/v1/messages/receive", "", 400},
		{"POST", "/v1/messages/receive", "bad", 400},
		{"POST", "/v1/messages/receive", uuid.NewString(), 200},
		{"GET", "/v1/messages", "", 200},
	} {
		request := httptest.NewRequest(tc.method, tc.path, nil)
		request.Header.Set("X-Receive-ID", tc.id)
		response, err := app.Test(request)
		require.NoError(t, err)
		require.Equal(t, tc.status, response.StatusCode, tc.path)
		require.Equal(t, "no-store", response.Header.Get("Cache-Control"))
		response.Body.Close()
	}
}
