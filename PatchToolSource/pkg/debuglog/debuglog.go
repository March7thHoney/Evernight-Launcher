package debuglog

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func Append(format string, args ...any) {
	line := fmt.Sprintf("%s %s\n", time.Now().Format(time.RFC3339), fmt.Sprintf(format, args...))
	path := filepath.Join(os.TempDir(), "firefly-launcher-debug.log")
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line)
}
