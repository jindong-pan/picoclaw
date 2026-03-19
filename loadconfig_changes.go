// =============================================================================
// CHANGES TO pkg/config/config.go
// =============================================================================
//
// 1. Add "github.com/joho/godotenv" to the import block
// 2. Replace the LoadConfig function with the one below
// 3. Add the expandEnvInModelList helper below LoadConfig
//
// That's it — everything else in config.go stays unchanged.
// =============================================================================

// UPDATED LoadConfig — replace the existing one in config.go
func LoadConfig(path string) (*Config, error) {
	cfg := DefaultConfig()

	// ── Step 1: Load .env ──────────────────────────────────────────────────
	// Must happen first so env.Parse() and os.ExpandEnv() both see the vars.
	loadDotEnv(path)

	// ── Step 2: Read config file ───────────────────────────────────────────
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, err
	}

	// ── Step 3: Expand ${VAR} placeholders in the raw JSON ─────────────────
	// This handles model_list[].api_key and any other plain string fields
	// that have no env: struct tag but use ${VAR} syntax in the JSON value.
	expanded := os.ExpandEnv(string(data))
	data = []byte(expanded)

	// Pre-scan the JSON to check how many model_list entries the user provided.
	// Go's JSON decoder reuses existing slice backing-array elements rather than
	// zero-initializing them, so fields absent from the user's JSON (e.g. api_base)
	// would silently inherit values from the DefaultConfig template at the same
	// index position. We only reset cfg.ModelList when the user actually provides
	// entries; when count is 0 we keep DefaultConfig's built-in list as fallback.
	var tmp Config
	if err := json.Unmarshal(data, &tmp); err != nil {
		return nil, err
	}
	if len(tmp.ModelList) > 0 {
		cfg.ModelList = nil
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	// ── Step 4: Apply PICOCLAW_* environment variables ─────────────────────
	// This handles all fields with env:"PICOCLAW_..." struct tags.
	// Runs after JSON so env vars override config file values.
	if err := env.Parse(cfg); err != nil {
		return nil, err
	}

	// Migrate legacy channel config fields to new unified structures
	cfg.migrateChannelConfigs()

	// Auto-migrate: if only legacy providers config exists, convert to model_list
	if len(cfg.ModelList) == 0 && cfg.HasProvidersConfig() {
		cfg.ModelList = ConvertProvidersToModelList(cfg)
	}

	// Validate model_list for uniqueness and required fields
	if err := cfg.ValidateModelList(); err != nil {
		return nil, err
	}

	return cfg, nil
}
