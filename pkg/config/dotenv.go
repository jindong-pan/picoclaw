package config

import (
	"os"
	"path/filepath"

	"github.com/joho/godotenv"
)

// loadDotEnv loads a .env file before config parsing so that both
// env.Parse() (for PICOCLAW_* struct tags) and os.ExpandEnv() (for
// ${VAR} placeholders in JSON values) can see the variables.
//
// Search order — first file found wins:
//  1. <config_dir>/.env      e.g. ~/.picoclaw/.env  (next to config.json)
//  2. ~/picoclaw/.env        git repo root, handy for developers
//  3. ./.env                 current working directory
//
// godotenv.Load never overrides a variable that is already set in the
// real environment, so explicit shell exports always take priority.
func loadDotEnv(configPath string) {
	candidates := dotEnvCandidates(configPath)
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			// Silently ignore load errors — .env is always optional.
			_ = godotenv.Load(p)
			return
		}
	}
}

func dotEnvCandidates(configPath string) []string {
	home, _ := os.UserHomeDir()

	return []string{
		// 1. Alongside the config file (canonical location)
		filepath.Join(filepath.Dir(configPath), ".env"),
		// 2. Git repo root (convenient for local development)
		filepath.Join(home, "picoclaw", ".env"),
		// 3. Current working directory
		".env",
	}
}
