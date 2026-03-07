package main

import (
	"fmt"
	"os"

	"github.com/jindong-pan/picoclaw/cmd/picoclaw-launcher-tui/internal/ui"
)

func main() {
	if err := ui.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
