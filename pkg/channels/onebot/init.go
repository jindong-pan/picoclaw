package onebot

import (
	"github.com/jindong-pan/picoclaw/pkg/bus"
	"github.com/jindong-pan/picoclaw/pkg/channels"
	"github.com/jindong-pan/picoclaw/pkg/config"
)

func init() {
	channels.RegisterFactory("onebot", func(cfg *config.Config, b *bus.MessageBus) (channels.Channel, error) {
		return NewOneBotChannel(cfg.Channels.OneBot, b)
	})
}
