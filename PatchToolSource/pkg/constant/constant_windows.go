//go:build windows

package constant

const ProxyFile = "firefly-go-proxy.exe"
const LauncherFile = "firefly-launcher.exe"

const (
	Tool7z      ToolFile = "bin/7za.exe"
	Tool7zaDLL  ToolFile = "bin/7za.dll"
	Tool7zxaDLL ToolFile = "bin/7zxa.dll"
	ToolHPatchz ToolFile = "bin/hpatchz.exe"
)

var RequiredFiles = map[ToolFile]string{
	Tool7z:      "assets/7za.exe",
	Tool7zaDLL:  "assets/7za.dll",
	Tool7zxaDLL: "assets/7zxa.dll",
	ToolHPatchz: "assets/hpatchz.exe",
}
