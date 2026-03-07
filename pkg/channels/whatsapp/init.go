package whatsapp

import (
	"github.com/jindong-pan/picoclaw/pkg/bus"
	"github.com/jindong-pan/picoclaw/pkg/channels"
	"github.com/jindong-pan/picoclaw/pkg/config"
)

func init() {
	channels.RegisterFactory("whatsapp", func(cfg *config.Config, b *bus.MessageBus) (channels.Channel, error) {
		return NewWhatsAppChannel(cfg.Channels.WhatsApp, b)
	})
}
