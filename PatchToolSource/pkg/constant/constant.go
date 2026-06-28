package constant

import (
	"os"
	"path/filepath"
	"runtime"
)

var ServerStorageUrl = ResolvePath("./server")
var ProxyStorageUrl = ResolvePath("./proxy")
var TempUrl = ResolvePath("./temp")

const CurrentLauncherVersion = "3.8.3"

type ToolFile string

func (t ToolFile) GetEmbedPath() string {
	return RequiredFiles[t]
}

func (t ToolFile) String() string {
	return ResolvePath(string(t))
}

// GetDataDir resolves the base dir for bin/ tools and temp/; PATCHTOOL_DATA_DIR overrides it.
func GetDataDir() string {
	if dir := os.Getenv("PATCHTOOL_DATA_DIR"); dir != "" {
		return dir
	}
	if runtime.GOOS != "darwin" {
		return "."
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	return filepath.Join(home, ".firefly-launcher")
}

func ResolvePath(path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(GetDataDir(), filepath.Clean(path))
}
