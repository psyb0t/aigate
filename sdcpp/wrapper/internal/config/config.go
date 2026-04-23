package config

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"time"

	"github.com/psyb0t/ctxerrors"
	"github.com/psyb0t/gonfiguration"
)

type Config struct {
	SDServerPath    string        `env:"SD_SERVER_PATH" default:"/sd-server"`
	SDServerAddress string        `env:"SD_SERVER_ADDRESS" default:"127.0.0.1:1234"`
	ModelPrefix     string        `env:"MODEL_PREFIX,required"`
	ExtraArgs       []string      `env:"EXTRA_ARGS"`
	IdleTimeout     time.Duration `env:"IDLE_TIMEOUT" default:"5m"`
	LoadTimeout     time.Duration `env:"LOAD_TIMEOUT" default:"10m"`
	ModelsFile      string        `env:"MODELS_FILE" default:"/etc/sdcpp/models.json"`
	Verbose         bool          `env:"VERBOSE"`
}

func Parse() (Config, error) {
	var cfg Config
	if err := gonfiguration.Parse(&cfg); err != nil {
		return Config{}, ctxerrors.Wrap(err, "parse config")
	}

	return cfg, nil
}

type ModelConfig struct {
	Args   []string `json:"args"`
	Width  int      `json:"width"`
	Height int      `json:"height"`
}

type Registry struct {
	Models       map[string]ModelConfig `json:"models"`
	DefaultModel string                 `json:"default_model"`
}

func LoadRegistry(path string) (*Registry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, ctxerrors.Wrap(err, "read registry file")
	}

	var reg Registry
	if err := json.Unmarshal(data, &reg); err != nil {
		return nil, ctxerrors.Wrap(err, "parse registry json")
	}

	if err := reg.validate(); err != nil {
		return nil, ctxerrors.Wrap(err, "validate registry")
	}

	return &reg, nil
}

func (r *Registry) validate() error {
	if len(r.Models) == 0 {
		return ErrNoModels
	}

	if _, ok := r.Models[r.DefaultModel]; !ok {
		return ctxerrors.Wrapf(ErrDefaultMissing, "%q", r.DefaultModel)
	}

	for name, m := range r.Models {
		if len(m.Args) == 0 {
			return ctxerrors.Wrapf(ErrNoArgs, "%q", name)
		}
		if m.Width <= 0 || m.Height <= 0 {
			return ctxerrors.Wrapf(ErrInvalidSize, "%q: %dx%d", name, m.Width, m.Height)
		}
	}

	return nil
}

// ModelNames returns sorted model keys.
func (r *Registry) ModelNames() []string {
	names := make([]string, 0, len(r.Models))
	for name := range r.Models {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func (r *Registry) Has(key string) bool {
	_, ok := r.Models[key]
	return ok
}

func (r *Registry) Get(key string) (ModelConfig, error) {
	m, ok := r.Models[key]
	if !ok {
		return ModelConfig{}, fmt.Errorf("model %q not found", key)
	}
	return m, nil
}
