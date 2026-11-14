//go:build !android && !linux && !darwin

package main

import (
	"context"
	"github.com/TeamGDB/Caelo/core/internal/protocol"
)

// На Windows интерфейс настраивает отдельный сервис, а не приложение.
func prepareRegistered(ctx context.Context, _ string, node protocol.Config) (protocol.Config, string, error) {
	return node.Pin(ctx)
}
