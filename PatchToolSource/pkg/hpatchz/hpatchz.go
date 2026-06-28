package hpatchz

import (
	"firefly-launcher/pkg/constant"
	"fmt"
	"os/exec"
)

func ApplyPatch(oldFile, diffFile, newFile string) error {
	cmd := exec.Command(constant.ToolHPatchz.String(), "-f", oldFile, diffFile, newFile)
	hideWindow(cmd)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to execute hpatchz: %w", err)
	}
	if cmd.ProcessState.ExitCode() != 0 {
		return fmt.Errorf("hpatchz failed: %s", string(output))
	}
	return nil
}

func ApplyPatchEmpty(diffFile, newFile string) error {
	cmd := exec.Command(constant.ToolHPatchz.String(), "-f", "", diffFile, newFile)
	hideWindow(cmd)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to execute hpatchz: %w", err)
	}
	if cmd.ProcessState.ExitCode() != 0 {
		return fmt.Errorf("hpatchz failed: %s", string(output))
	}
	return nil
}
