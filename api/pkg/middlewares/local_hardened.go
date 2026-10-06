package middlewares

import (
	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"
	"strings"
)

// LocalHardened is defense in depth behind the loopback/LAN reverse proxies.
// This profile is for receiving SMS; remote sends and outbound integrations are disabled.
func LocalHardened() fiber.Handler {
	return func(c fiber.Ctx) error {
		c.Set("Cache-Control", "no-store")
		path := c.Path()
		for _, prefix := range []string{"/v1/webhooks", "/v1/discord", "/v1/integration", "/v1/send-schedules", "/v1/lemonsqueezy"} {
			if strings.HasPrefix(path, prefix) {
				return c.SendStatus(403)
			}
		}
		if path == "/v1/messages/receive" && c.Method() == fiber.MethodPost {
			if _, err := uuid.Parse(c.Get("X-Receive-ID")); err != nil {
				return c.Status(400).JSON(fiber.Map{"status": "error", "message": "A valid X-Receive-ID is required"})
			}
		}
		switch {
		case path == "/v1/events":
			// Never allow a phone/user key to inject events; the handler also checks the system user.
		case c.Method() == fiber.MethodGet && (path == "/v1/messages/outstanding"):
			return c.SendStatus(403)
		case path == "/v1/messages/send" || path == "/v1/messages/bulk-send":
			return c.SendStatus(403)
		}
		return c.Next()
	}
}
