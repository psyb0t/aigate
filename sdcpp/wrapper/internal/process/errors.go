package process

import "errors"

var ErrNotReady = errors.New("sd-server not ready within timeout")
