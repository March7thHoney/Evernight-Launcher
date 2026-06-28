//go:build linux

package hpatchz

import (
	"os/exec"
)

func hideWindow(cmd *exec.Cmd) {
	// No-op for Linux
}
