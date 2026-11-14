//go:build android || linux || darwin

package fdtun

import (
	"context"
	"crypto/sha256"
	"github.com/TeamGDB/Caelo/core/internal/protocol"
	"time"
)

// Prepare фиксирует адрес и проверяет выход до создания интерфейса. Start
// получает тот же результат, по которому платформа построила интерфейс.
func (s *Session) Prepare(ctx context.Context, text string, node protocol.Config) (protocol.Config, string, error) {
	s.mu.Lock()
	s.cancelPreparationLocked()
	generation := s.preparationGeneration
	ctx, cancel := context.WithCancel(ctx)
	s.preparationCancel = cancel
	s.mu.Unlock()
	defer cancel()
	prepared, address, err := node.Pin(ctx)
	if err == nil {
		if p, ok := prepared.(protocol.Preparer); ok {
			prepared, err = p.Prepare(ctx)
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if generation != s.preparationGeneration {
		return nil, "", context.Canceled
	}
	s.preparationCancel = nil
	if err != nil {
		return nil, "", err
	}
	if err = ctx.Err(); err != nil {
		return nil, "", err
	}
	s.prepared = prepared
	s.preparedHash = sha256.Sum256([]byte(text))
	s.preparedAt = time.Now()
	return prepared, address, nil
}

func (s *Session) cancelPreparationLocked() {
	if s.preparationCancel != nil {
		s.preparationCancel()
		s.preparationCancel = nil
	}
	s.preparationGeneration++
	s.prepared = nil
}

func (s *Session) takePreparedLocked(text string) protocol.Config {
	var node protocol.Config
	if s.prepared != nil && s.preparedHash == sha256.Sum256([]byte(text)) && time.Since(s.preparedAt) < 30*time.Second {
		node = s.prepared
	}
	s.cancelPreparationLocked()
	return node
}
