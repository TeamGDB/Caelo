//go:build android || linux || darwin

package main

import (
	"context"
	"github.com/TeamGDB/Caelo/core/internal/protocol"
)

func prepareRegistered(ctx context.Context, text string, node protocol.Config) (protocol.Config, string, error) {
	return hosted.Prepare(ctx, text, node)
}
