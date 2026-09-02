package diffService

import (
	"firefly-launcher/pkg/models"
	"firefly-launcher/pkg/verifier"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
)

const (
	streamingPrefix  = "StarRail_Data/StreamingAssets/"
	persistentPrefix = "StarRail_Data/Persistent/"
	verifyFailName   = "StarRail_Data/Persistent/verify.fail"
)

// Marker the client drops next to a downloaded asset, named after that asset's md5.
var hashMarkerPattern = regexp.MustCompile(`^(.+)_([0-9a-fA-F]{32})\.hash$`)

var copyBufPool = sync.Pool{
	New: func() interface{} {
		buf := make([]byte, 4*1024*1024)
		return &buf
	},
}

type persistentCounters struct {
	replaced int32
	current  int32
	cleaned  int32
}

// Persistent shadows StreamingAssets, so refresh the twins the client staged and drop partial downloads.
func (h *DiffService) SyncPersistent(gamePath string, entries []*models.HDiffData) (bool, string) {
	targets := collectPersistentTargets(entries)
	if len(targets) == 0 {
		return true, ""
	}

	emitStage("Syncing Persistent")

	var counters persistentCounters
	var progress int32
	var wg sync.WaitGroup
	jobs := make(chan *models.HDiffData, len(targets))

	workerCount := max(1, runtime.NumCPU()/2)
	for i := 0; i < workerCount; i++ {
		wg.Go(func() {
			for entry := range jobs {
				syncPersistentEntry(gamePath, entry, &counters)
				emitProgress(int(atomic.AddInt32(&progress, 1)), len(targets))
			}
		})
	}

	for _, entry := range targets {
		jobs <- entry
	}
	close(jobs)
	wg.Wait()

	if counters.replaced > 0 {
		os.Remove(filepath.Join(gamePath, filepath.FromSlash(verifyFailName)))
	}
	return true, fmt.Sprintf("persistent synced (%d replaced, %d already up to date, %d leftovers removed)",
		counters.replaced, counters.current, counters.cleaned)
}

// Keeps only entries whose patched target could have a counterpart in the download layer.
func collectPersistentTargets(entries []*models.HDiffData) []*models.HDiffData {
	var targets []*models.HDiffData
	seen := make(map[string]bool, len(entries))
	for _, entry := range entries {
		name := toSlashPath(entry.TargetFileName)
		if !strings.HasPrefix(name, streamingPrefix) || seen[name] {
			continue
		}
		seen[name] = true
		targets = append(targets, entry)
	}
	return targets
}

func syncPersistentEntry(gamePath string, entry *models.HDiffData, counters *persistentCounters) {
	relative := toSlashPath(entry.TargetFileName)
	sourceFile := filepath.Join(gamePath, filepath.FromSlash(relative))
	twinFile := filepath.Join(gamePath, filepath.FromSlash(persistentPrefix+strings.TrimPrefix(relative, streamingPrefix)))

	twinDir := filepath.Dir(twinFile)
	stem, extension := splitStem(filepath.Base(twinFile))
	partialFile := filepath.Join(twinDir, stem+"_tmp"+extension)
	markers := findHashMarkers(twinDir, stem)

	twinExists := fileExists(twinFile)
	partialExists := fileExists(partialFile)
	if !twinExists && !partialExists && len(markers) == 0 {
		return
	}

	targetMD5 := entry.TargetFileMD5
	sourceVerified := false
	if targetMD5 == "" {
		actual, err := verifier.FileMD5(sourceFile)
		if err != nil {
			emitWarn(fmt.Sprintf("%s (persistent sync: %v)", relative, err))
			return
		}
		targetMD5 = actual
		sourceVerified = true
	}

	if twinExists && verifyFile(twinFile, entry.TargetFileSize, targetMD5) == "" {
		atomic.AddInt32(&counters.current, 1)
	} else {
		if !sourceVerified {
			if reason := verifyFile(sourceFile, entry.TargetFileSize, targetMD5); reason != "" {
				emitWarn(fmt.Sprintf("%s (persistent sync source %s)", relative, reason))
				return
			}
		}
		if err := copyOverwrite(sourceFile, twinFile); err != nil {
			emitWarn(fmt.Sprintf("%s (persistent sync: %v)", relative, err))
			return
		}
		atomic.AddInt32(&counters.replaced, 1)
	}

	refreshHashMarkers(markers, twinDir, stem, targetMD5)
	for _, leftover := range []string{partialFile, twinFile + patchTempSuffix} {
		if fileExists(leftover) && os.Remove(leftover) == nil {
			atomic.AddInt32(&counters.cleaned, 1)
		}
	}
}

// Writes through a sibling temp file so an interrupted copy never leaves a truncated asset behind.
func copyOverwrite(sourceFile, destFile string) error {
	if err := os.MkdirAll(filepath.Dir(destFile), os.ModePerm); err != nil {
		return err
	}
	source, err := os.Open(sourceFile)
	if err != nil {
		return err
	}
	defer source.Close()

	tempFile := destFile + patchTempSuffix
	os.Remove(tempFile)
	dest, err := os.Create(tempFile)
	if err != nil {
		return err
	}

	bufPtr := copyBufPool.Get().(*[]byte)
	_, copyErr := io.CopyBuffer(dest, source, *bufPtr)
	copyBufPool.Put(bufPtr)
	closeErr := dest.Close()
	if copyErr == nil {
		copyErr = closeErr
	}
	if copyErr != nil {
		os.Remove(tempFile)
		return copyErr
	}
	if err := os.Rename(tempFile, destFile); err != nil {
		os.Remove(tempFile)
		return err
	}
	return nil
}

// Only rewrites the marker when the client already kept one for this asset.
func refreshHashMarkers(markers []string, dir, stem, md5 string) {
	if len(markers) == 0 {
		return
	}
	wanted := stem + "_" + strings.ToLower(md5) + ".hash"
	found := false
	for _, marker := range markers {
		if strings.EqualFold(marker, wanted) {
			found = true
			continue
		}
		os.Remove(filepath.Join(dir, marker))
	}
	if found {
		return
	}
	if file, err := os.Create(filepath.Join(dir, wanted)); err == nil {
		file.Close()
	}
}

func findHashMarkers(dir, stem string) []string {
	handle, err := os.Open(dir)
	if err != nil {
		return nil
	}
	defer handle.Close()

	names, err := handle.Readdirnames(-1)
	if err != nil {
		return nil
	}
	var markers []string
	for _, name := range names {
		if groups := hashMarkerPattern.FindStringSubmatch(name); groups != nil && groups[1] == stem {
			markers = append(markers, name)
		}
	}
	return markers
}

func splitStem(name string) (string, string) {
	extension := filepath.Ext(name)
	return strings.TrimSuffix(name, extension), extension
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func toSlashPath(name string) string {
	return strings.ReplaceAll(name, "\\", "/")
}
