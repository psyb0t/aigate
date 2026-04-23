package config

import "errors"

var (
	ErrNoModels       = errors.New("no models defined")
	ErrDefaultMissing = errors.New("default_model not found in models")
	ErrNoArgs         = errors.New("model has no args")
	ErrInvalidSize    = errors.New("model has invalid dimensions")
)
