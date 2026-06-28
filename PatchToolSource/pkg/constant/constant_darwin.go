//go:build darwin

package constant

const ProxyFile = "firefly-go-proxy"
const LauncherFile = "firefly-launcher"

const (
	Tool7z              ToolFile = "bin/7zz"
	ToolHPatchz         ToolFile = "bin/hpatchz"
	ToolFireflyInjector ToolFile = "bin/firefly-injector.exe"
	ToolFireflyHook     ToolFile = "bin/firefly-hook.dll"
)

var RequiredFiles = map[ToolFile]string{
	Tool7z:              "assets/7zz_macos",
	ToolHPatchz:         "assets/hpatchz_macos",
	ToolFireflyInjector: "assets/firefly-injector.exe",
	ToolFireflyHook:     "assets/firefly-hook.dll",
}
