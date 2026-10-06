package services

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/NdoleStudio/httpsms/pkg/entities"
	"github.com/NdoleStudio/httpsms/pkg/telemetry"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/otel/metric/noop"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"
)

func TestLocalQueueDeliveryRequiresSuccessAndDoesNotRedirect(t *testing.T) {
	var reached atomic.Bool
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { reached.Store(true); w.WriteHeader(204) }))
	defer target.Close()
	for _, status := range []int{204, 302, 401, 429, 503} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("x-api-key") != "synthetic-key" {
					t.Error("missing API credential")
				}
				if status == 302 {
					w.Header().Set("Location", target.URL)
				}
				w.WriteHeader(status)
			}))
			defer server.Close()
			q := &PostgresPushQueue{client: server.Client(), endpoint: server.URL}
			payload, err := json.Marshal(PushQueueTask{URL: server.URL, Method: "POST", Body: []byte(`{}`), Headers: map[string]string{"x-api-key": "synthetic-key"}})
			require.NoError(t, err)
			err = q.deliver(context.Background(), payload)
			if status == 204 {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
		})
	}
	require.False(t, reached.Load(), "redirect must not leak the event or key")
}

func TestReceiveIDIsStableAndScopedToUser(t *testing.T) {
	id := uuid.NewString()
	require.Equal(t, receivedMessageID("alice", id), receivedMessageID("alice", id))
	require.NotEqual(t, receivedMessageID("alice", id), receivedMessageID("bob", id))
	require.NotEqual(t, receivedMessageID("alice", id), receivedMessageID("alice", uuid.NewString()))
	require.LessOrEqual(t, queueBackoff(10000), 5*time.Minute)
}

func TestEventDispatcherPropagatesListenerFailures(t *testing.T) {
	log := &noopLogger{}
	tracer := telemetry.NewOtelLogger("test", log)
	histogram, err := noop.NewMeterProvider().Meter("test").Float64Histogram("duration")
	require.NoError(t, err)
	d := NewEventDispatcher(log, tracer, histogram, nil, PushQueueConfig{})
	expected := errors.New("synthetic listener failure")
	d.Subscribe("test.received", func(context.Context, cloudevents.Event) error { return expected })
	event := cloudevents.NewEvent()
	event.SetID(uuid.NewString())
	event.SetSource("/test")
	event.SetType("test.received")
	require.ErrorIs(t, d.DispatchSync(context.Background(), event), expected)
}

// Explicit opt-in: uses a unique schema, never truncates existing tables.
func TestLocalQueueDatabase(t *testing.T) {
	dsn := os.Getenv("LOCAL_QUEUE_TEST_DSN")
	if dsn == "" {
		t.Skip("requires a separate PostgreSQL test database via LOCAL_QUEUE_TEST_DSN")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: logger.Discard})
	require.NoError(t, err)
	sqlDB, err := db.DB()
	require.NoError(t, err)
	sqlDB.SetMaxOpenConns(1)
	defer sqlDB.Close()
	schema := "httpsms_test_" + time.Now().Format("20060102150405") + "_" + uuid.NewString()[:8]
	require.NoError(t, db.Exec(`CREATE SCHEMA "`+schema+`"`).Error)
	defer db.Exec(`DROP SCHEMA "` + schema + `" CASCADE`)
	require.NoError(t, db.Exec(`SET search_path TO "`+schema+`"`).Error)
	require.NoError(t, db.AutoMigrate(&entities.Message{}))
	var status atomic.Int32
	status.Store(503)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(int(status.Load())) }))
	defer server.Close()
	q, err := NewPostgresPushQueue(db, server.Client(), server.URL)
	require.NoError(t, err)
	msg := &entities.Message{ID: receivedMessageID("test", uuid.NewString()), UserID: "test", Owner: "+12025550100", Contact: "test", Content: "synthetic OTP", Status: entities.MessageStatusReceived}
	task := &PushQueueTask{URL: server.URL, Method: "POST", Body: []byte(`{}`)}
	_, err = q.StoreReceived(context.Background(), msg, task)
	require.NoError(t, err)
	_, err = q.StoreReceived(context.Background(), msg, task)
	require.NoError(t, err)
	var count int64
	require.NoError(t, db.Model(&entities.Message{}).Count(&count).Error)
	require.EqualValues(t, 1, count)
	require.NoError(t, db.Model(&LocalQueueTask{}).Count(&count).Error)
	require.EqualValues(t, 1, count)
	worked, err := q.runOne(context.Background())
	require.NoError(t, err)
	require.True(t, worked)
	require.NoError(t, db.Model(&LocalQueueTask{}).Count(&count).Error)
	require.EqualValues(t, 1, count, "failure must retain task")
	var retained LocalQueueTask
	require.NoError(t, db.First(&retained).Error)
	require.Equal(t, 1, retained.Attempts)
	q, err = NewPostgresPushQueue(db, server.Client(), server.URL)
	require.NoError(t, err)
	require.NoError(t, db.Model(&retained).Update("available_at", time.Now().Add(-time.Second)).Error)
	status.Store(204)
	worked, err = q.runOne(context.Background())
	require.NoError(t, err)
	require.True(t, worked)
	require.NoError(t, db.Model(&LocalQueueTask{}).Count(&count).Error)
	require.Zero(t, count)
	// An outbox failure must roll back the SMS insert too.
	require.NoError(t, db.Exec(`ALTER TABLE local_queue_tasks ADD CONSTRAINT reject_test CHECK (attempts < 0)`).Error)
	failed := *msg
	failed.ID = uuid.New()
	_, err = q.StoreReceived(context.Background(), &failed, task)
	require.Error(t, err)
	require.NoError(t, db.Model(&entities.Message{}).Where("id = ?", failed.ID).Count(&count).Error)
	require.Zero(t, count)
}
