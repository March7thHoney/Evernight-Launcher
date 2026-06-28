package sevenzip

import (
	"bytes"
	"firefly-launcher/pkg/constant"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func IsFileIn7z(archivePath, fileInside string) (bool, error) {
	files, err := ListFilesInZip(archivePath)
	if err != nil {
		return false, err
	}

	targetFile := strings.ReplaceAll(fileInside, "\\", "/")
	for _, f := range files {
		if strings.ReplaceAll(f, "\\", "/") == targetFile {
			return true, nil
		}
	}
	return false, nil
}

func ListFilesInZip(archivePath string) ([]string, error) {
	cmd := exec.Command(constant.Tool7z.String(), "l", archivePath)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("7za list failed: %v\nOutput: %s", err, out.String())
	}

	lines := strings.Split(out.String(), "\n")
	var files []string
	foundTable := false
	nameIndex := 53

	for _, line := range lines {
		line = strings.TrimRight(line, "\r")
		if strings.HasPrefix(line, "----------") {
			if foundTable {
				break
			}
			foundTable = true
			nameIndex = strings.LastIndex(line, " ") + 1
			continue
		}

		if foundTable && len(line) > nameIndex {
			fileName := strings.TrimSpace(line[nameIndex:])
			if fileName != "" {
				files = append(files, fileName)
			}
		}
	}

	return files, nil
}

func ExtractAFileFromZip(archivePath, fileInside, outDir string) error {
	cmd := exec.Command(constant.Tool7z.String(), "e", archivePath, fileInside, "-o"+outDir, "-y")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func ExtractAllFilesFromZip(archivePath, outDir string) error {
	cmd := exec.Command(constant.Tool7z.String(), "x", archivePath, "-o"+outDir, "-y")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
