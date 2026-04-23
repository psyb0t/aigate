package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeJSON(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadRegistry(t *testing.T) {
	dir := t.TempDir()

	path := writeJSON(t, dir, "models.json", `{
		"models": {
			"flux-schnell": {
				"args": ["--diffusion-model", "/models/flux.gguf"],
				"width": 1024, "height": 1024
			},
			"sd-turbo": {
				"args": ["--model", "/models/sd.gguf"],
				"width": 512, "height": 512
			}
		},
		"default_model": "flux-schnell"
	}`)

	reg, err := LoadRegistry(path)
	if err != nil {
		t.Fatal(err)
	}

	if reg.DefaultModel != "flux-schnell" {
		t.Fatalf("default=%q, want flux-schnell", reg.DefaultModel)
	}
	if len(reg.Models) != 2 {
		t.Fatalf("got %d models, want 2", len(reg.Models))
	}
}

func TestLoadRegistryModelNames(t *testing.T) {
	dir := t.TempDir()

	path := writeJSON(t, dir, "models.json", `{
		"models": {
			"c-model": {"args": ["--m"], "width": 1, "height": 1},
			"a-model": {"args": ["--m"], "width": 1, "height": 1},
			"b-model": {"args": ["--m"], "width": 1, "height": 1}
		},
		"default_model": "a-model"
	}`)

	reg, err := LoadRegistry(path)
	if err != nil {
		t.Fatal(err)
	}

	names := reg.ModelNames()
	want := []string{"a-model", "b-model", "c-model"}
	if len(names) != len(want) {
		t.Fatalf("got %v, want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("names[%d]=%q, want %q", i, names[i], want[i])
		}
	}
}

func TestLoadRegistryHasGet(t *testing.T) {
	dir := t.TempDir()

	path := writeJSON(t, dir, "models.json", `{
		"models": {
			"flux": {"args": ["--m", "/f.gguf"], "width": 1024, "height": 1024}
		},
		"default_model": "flux"
	}`)

	reg, err := LoadRegistry(path)
	if err != nil {
		t.Fatal(err)
	}

	if !reg.Has("flux") {
		t.Fatal("Has(flux) = false")
	}
	if reg.Has("nope") {
		t.Fatal("Has(nope) = true")
	}

	m, err := reg.Get("flux")
	if err != nil {
		t.Fatal(err)
	}
	if m.Width != 1024 || m.Height != 1024 {
		t.Fatalf("dims=%dx%d, want 1024x1024", m.Width, m.Height)
	}
	if len(m.Args) != 2 {
		t.Fatalf("args=%v, want 2 elements", m.Args)
	}

	_, err = reg.Get("nope")
	if err == nil {
		t.Fatal("Get(nope) should fail")
	}
}

func TestLoadRegistryValidationErrors(t *testing.T) {
	tests := []struct {
		name string
		json string
	}{
		{
			name: "no models",
			json: `{"models": {}, "default_model": "x"}`,
		},
		{
			name: "default missing",
			json: `{"models": {"a": {"args": ["--m"], "width": 1, "height": 1}}, "default_model": "b"}`,
		},
		{
			name: "no args",
			json: `{"models": {"a": {"args": [], "width": 1, "height": 1}}, "default_model": "a"}`,
		},
		{
			name: "zero width",
			json: `{"models": {"a": {"args": ["--m"], "width": 0, "height": 1}}, "default_model": "a"}`,
		},
		{
			name: "negative height",
			json: `{"models": {"a": {"args": ["--m"], "width": 1, "height": -1}}, "default_model": "a"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			path := writeJSON(t, dir, "models.json", tt.json)

			_, err := LoadRegistry(path)
			if err == nil {
				t.Fatal("expected error")
			}
		})
	}
}

func TestLoadRegistryFileNotFound(t *testing.T) {
	_, err := LoadRegistry("/nonexistent/models.json")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestLoadRegistryInvalidJSON(t *testing.T) {
	dir := t.TempDir()
	path := writeJSON(t, dir, "models.json", `{not valid json`)

	_, err := LoadRegistry(path)
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}
