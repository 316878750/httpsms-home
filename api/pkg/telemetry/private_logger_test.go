package telemetry

import (
	"bytes"
	"errors"
	"github.com/stretchr/testify/require"
	"log"
	"testing"
)

func TestPrivateLoggerNeverWritesPayloadOrCredentials(t *testing.T) {
	var buffer bytes.Buffer
	previous := log.Writer()
	log.SetOutput(&buffer)
	defer log.SetOutput(previous)
	secret := "synthetic-otp-and-api-key"
	logger := (&PrivateLogger{}).WithString("body", secret).WithService(secret)
	logger.Info(secret)
	logger.Debug(secret)
	logger.Printf("%s", secret)
	logger.Error(errors.New(secret))
	logger.Warn(errors.New(secret))
	require.NotContains(t, buffer.String(), secret)
	require.Contains(t, buffer.String(), "details redacted")
}
