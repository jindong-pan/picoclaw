package feishu

import (
	"github.com/jindong-pan/picoclaw/pkg/bus"
	"github.com/jindong-pan/picoclaw/pkg/channels"
	"github.com/jindong-pan/picoclaw/pkg/config"
)

func init() {
	channels.RegisterFactory("feishu", func(cfg *config.Config, b *bus.MessageBus) (channels.Channel, error) {
		return NewFeishuChannel(cfg.Channels.Feishu, b)
	})
}
