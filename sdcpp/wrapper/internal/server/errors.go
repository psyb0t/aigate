package server

import "errors"

var (
	ErrUnknownModel = errors.New("unknown model")
	ErrLoadFailed   = errors.New("failed to load model")
	ErrGenerating   = errors.New("generation in progress")
	ErrBusy         = errors.New("another load or generation is in progress")
)
