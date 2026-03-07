package dingtalk

import (
	"github.com/jindong-pan/picoclaw/pkg/bus"
	"github.com/jindong-pan/picoclaw/pkg/channels"
	"github.com/jindong-pan/picoclaw/pkg/config"
)

func init() {
	channels.RegisterFactory("dingtalk", func(cfg *config.Config, b *bus.MessageBus) (channels.Channel, error) {
		return NewDingTalkChannel(cfg.Channels.DingTalk, b)
	})
}
