package telegram

import (
	"context"
	"strings"

	"github.com/mymmrac/telego"

	"github.com/jindong-pan/picoclaw/pkg/config"
)

//

func commandArgs(text string) string {
	parts := strings.SplitN(text, " ", 2)
	if len(parts) < 2 {
		return ""
	}
	return strings.TrimSpace(parts[1])
}


