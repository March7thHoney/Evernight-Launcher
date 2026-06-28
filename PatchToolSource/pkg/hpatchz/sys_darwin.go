//go:build darwin

package hpatchz

import (
	"os/exec"
)

func hideWindow(cmd *exec.Cmd) {
	// No-op for macOS (Darwin)
}
