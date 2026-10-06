package services

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/NdoleStudio/httpsms/pkg/entities"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// LocalQueueTask is a durable outbox. Leases recover automatically after a crash.
// Payloads contain SMS data and credentials: never log them or expose this table.
type LocalQueueTask struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey"`
	Payload     []byte    `gorm:"not null"`
	AvailableAt time.Time `gorm:"index;not null"`
	Attempts    int       `gorm:"not null"`
	CreatedAt   time.Time
}

type PostgresPushQueue struct {
	db       *gorm.DB
	client   *http.Client
	endpoint string
}

func NewPostgresPushQueue(db *gorm.DB, client *http.Client, endpoint string) (*PostgresPushQueue, error) {
	if err := db.AutoMigrate(&LocalQueueTask{}); err != nil {
		return nil, err
	}
	return &PostgresPushQueue{db: db, client: client, endpoint: endpoint}, nil
}

func queueRecord(task *PushQueueTask, delay time.Duration) (*LocalQueueTask, error) {
	payload, err := json.Marshal(task)
	if err != nil {
		return nil, err
	}
	return &LocalQueueTask{ID: uuid.New(), Payload: payload, AvailableAt: time.Now().UTC().Add(delay)}, nil
}

func (q *PostgresPushQueue) Enqueue(ctx context.Context, task *PushQueueTask, delay time.Duration) (string, error) {
	if task.URL != q.endpoint {
		return "", errors.New("local queue only accepts its configured event endpoint")
	}
	record, err := queueRecord(task, delay)
	if err != nil {
		return "", err
	}
	err = q.db.WithContext(ctx).Create(record).Error
	return record.ID.String(), err
}

// StoreReceived commits the SMS and event together. An acknowledgement can only
// be returned after both are durable. The same upload ID never inserts twice.
func (q *PostgresPushQueue) StoreReceived(ctx context.Context, message *entities.Message, task *PushQueueTask) (*entities.Message, error) {
	if task.URL != q.endpoint {
		return nil, errors.New("unexpected event endpoint")
	}
	record, err := queueRecord(task, 0)
	if err != nil {
		return nil, err
	}
	result := message
	err = q.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		inserted := tx.Clauses(clause.OnConflict{Columns: []clause.Column{{Name: "id"}}, DoNothing: true}).Create(message)
		if inserted.Error != nil {
			return inserted.Error
		}
		if inserted.RowsAffected == 0 {
			existing := new(entities.Message)
			if err := tx.Where("id = ? AND user_id = ?", message.ID, message.UserID).First(existing).Error; err != nil {
				return err
			}
			if existing.Owner != message.Owner || existing.Contact != message.Contact || existing.Content != message.Content || existing.Encrypted != message.Encrypted || existing.SIM != message.SIM {
				return errors.New("receive ID was reused with different message data")
			}
			result = existing
			return nil
		}
		return tx.Create(record).Error
	})
	return result, err
}

func queueBackoff(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	if attempt > 6 {
		return 5 * time.Minute
	}
	return time.Duration(1<<(attempt-1)) * 5 * time.Second
}

// Run must have a single shared queue instance per process. Database leases also
// prevent concurrently running processes from claiming the same task.
func (q *PostgresPushQueue) Run(ctx context.Context) {
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			// A bound avoids starving shutdown when the backlog is large.
			for i := 0; i < 20 && ctx.Err() == nil; i++ {
				if worked, _ := q.runOne(ctx); !worked {
					break
				}
			}
		}
	}
}

func (q *PostgresPushQueue) runOne(ctx context.Context) (bool, error) {
	var record LocalQueueTask
	err := q.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		err := tx.Clauses(clause.Locking{Strength: "UPDATE", Options: "SKIP LOCKED"}).
			Where("available_at <= ?", time.Now().UTC()).Order("available_at, created_at").First(&record).Error
		if err != nil {
			return err
		}
		record.Attempts++
		record.AvailableAt = time.Now().UTC().Add(2 * time.Minute)
		return tx.Model(&record).Select("attempts", "available_at").Updates(&record).Error
	})
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	deliveryErr := q.deliver(ctx, record.Payload)
	if deliveryErr == nil {
		return true, q.db.WithContext(ctx).Delete(&record).Error
	}
	// Retain even 4xx failures so configuration mistakes do not discard events.
	return true, q.db.WithContext(ctx).Model(&record).Update("available_at", time.Now().UTC().Add(queueBackoff(record.Attempts))).Error
}

func (q *PostgresPushQueue) deliver(ctx context.Context, payload []byte) error {
	var task PushQueueTask
	if err := json.Unmarshal(payload, &task); err != nil {
		return errors.New("invalid queued task")
	}
	if task.URL != q.endpoint {
		return errors.New("unexpected queued endpoint")
	}
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, task.Method, task.URL, bytes.NewReader(task.Body))
	if err != nil {
		return errors.New("invalid queue request")
	}
	for key, value := range task.Headers {
		request.Header.Set(key, value)
	}
	request.Header.Set("Content-Type", "application/json")
	// Do not follow redirects with event bodies or API credentials.
	client := *q.client
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	response, err := client.Do(request)
	if err != nil {
		return errors.New("event endpoint unavailable")
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("event endpoint status %d", response.StatusCode)
	}
	return nil
}
