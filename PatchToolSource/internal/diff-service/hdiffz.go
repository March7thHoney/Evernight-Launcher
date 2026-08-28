package diffService

import (
	"bufio"
	"encoding/json"
	"firefly-launcher/pkg/constant"
	"firefly-launcher/pkg/debuglog"
	"firefly-launcher/pkg/hpatchz"
	"firefly-launcher/pkg/models"
	"firefly-launcher/pkg/sevenzip"
	"firefly-launcher/pkg/verifier"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
)

type DiffService struct{}

func (h *DiffService) CheckTypeHDiff(patchPath string) (bool, string, string) {
	if ok, err := sevenzip.IsFileIn7z(patchPath, "hdifffiles.txt"); err == nil && ok {
		return true, "hdifffiles.txt", ""
	} else if err != nil {
		debuglog.Append("CheckTypeHDiff hdifffiles.txt: %v", err)
	}
	if ok, err := sevenzip.IsFileIn7z(patchPath, "hdifffiles.json"); err == nil && ok {
		return true, "hdifffiles.json", ""
	} else if err != nil {
		debuglog.Append("CheckTypeHDiff hdifffiles.json: %v", err)
	}
	if ok, err := sevenzip.IsFileIn7z(patchPath, "hdiffmap.json"); err == nil && ok {
		return true, "hdiffmap.json", ""
	} else if err != nil {
		debuglog.Append("CheckTypeHDiff hdiffmap.json: %v", err)
	}
	if ok, err := sevenzip.IsFileIn7z(patchPath, "manifest"); err == nil && ok {
		return true, "manifest", ""
	} else if err != nil {
		debuglog.Append("CheckTypeHDiff manifest: %v", err)
	}

	return false, "", "not found hdifffiles.txt or hdiffmap.json"
}

func (h *DiffService) VersionValidate(gamePath, patchPath string) (bool, string) {
	oldBinPath := filepath.Join(gamePath, "StarRail_Data", "StreamingAssets", "BinaryVersion.bytes")
	if _, err := os.Stat(oldBinPath); err != nil {
		return false, err.Error()
	}
	if _, err := os.Stat(patchPath); err != nil {
		return false, err.Error()
	}

	if err := os.MkdirAll(constant.TempUrl, os.ModePerm); err != nil {
		return false, err.Error()
	}

	okFull, errFull := sevenzip.IsFileIn7z(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes")
	okDiff, errDiff := sevenzip.IsFileIn7z(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes.hdiff")

	if errFull != nil && errDiff != nil {
		return false, errFull.Error()
	}
	if !okFull && !okDiff {
		return true, "validated without BinaryVersion"
	}

	expected, msg := expectedBinaryVersionMD5(gamePath, patchPath)
	if expected == "" {
		return false, msg
	}

	// Re-running a partly applied patch: the installed file already is the target.
	if actual, err := verifier.FileMD5(oldBinPath); err == nil && strings.EqualFold(actual, expected) {
		return true, "already at target version"
	}

	tempBinFile := filepath.Join(constant.TempUrl, "BinaryVersion.bytes")
	defer os.Remove(tempBinFile)

	if okFull {
		if err := sevenzip.ExtractAFileFromZip(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes", constant.TempUrl); err != nil {
			return false, err.Error()
		}
	} else {
		if err := sevenzip.ExtractAFileFromZip(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes.hdiff", constant.TempUrl); err != nil {
			return false, err.Error()
		}
		patchBinFile := filepath.Join(constant.TempUrl, "BinaryVersion.bytes.hdiff")
		err := hpatchz.ApplyPatch(oldBinPath, patchBinFile, tempBinFile)
		os.Remove(patchBinFile)
		if err != nil {
			return false, err.Error()
		}
	}

	md5, err := verifier.FileMD5(tempBinFile)
	if err != nil {
		return false, err.Error()
	}
	if !strings.EqualFold(md5, expected) {
		return false, fmt.Sprintf("md5 mismatch for %s: expected %s, got %s", tempBinFile, expected, md5)
	}
	if _, err := models.ParseBinaryVersion(tempBinFile); err != nil {
		return false, err.Error()
	}

	return true, "validated"
}

// Target md5 of BinaryVersion.bytes, read from the patch's pkg_version.
func expectedBinaryVersionMD5(gamePath, patchPath string) (string, string) {
	tempPkgFile := filepath.Join(constant.TempUrl, "pkg_version")
	defer os.Remove(tempPkgFile)

	okFullPkg, err1 := sevenzip.IsFileIn7z(patchPath, "pkg_version")
	okDiffPkg, err2 := sevenzip.IsFileIn7z(patchPath, "pkg_version.hdiff")
	if err1 != nil && err2 != nil {
		return "", err1.Error()
	}

	pkgFile := tempPkgFile
	switch {
	case okFullPkg:
		if err := sevenzip.ExtractAFileFromZip(patchPath, "pkg_version", constant.TempUrl); err != nil {
			return "", err.Error()
		}
	case okDiffPkg:
		if err := sevenzip.ExtractAFileFromZip(patchPath, "pkg_version.hdiff", constant.TempUrl); err != nil {
			return "", err.Error()
		}
		patchPkgFile := filepath.Join(constant.TempUrl, "pkg_version.hdiff")
		err := hpatchz.ApplyPatch(filepath.Join(gamePath, "pkg_version"), patchPkgFile, tempPkgFile)
		os.Remove(patchPkgFile)
		// An earlier run already patched it, so the installed copy is the target.
		if err != nil {
			pkgFile = filepath.Join(gamePath, "pkg_version")
		}
	default:
		return "", "pkg_version not found in patch"
	}

	pkgDataList, err := models.LoadPkgVersion(pkgFile)
	if err != nil {
		return "", err.Error()
	}
	for _, pkgData := range pkgDataList {
		if strings.ReplaceAll(pkgData.RemoteFile, "\\", "/") == "StarRail_Data/StreamingAssets/BinaryVersion.bytes" {
			return pkgData.MD5, ""
		}
	}
	return "", "BinaryVersion file not found in patch"
}

// Empty when the file matches the expected size/md5, otherwise the reason it does not.
func verifyFile(path string, size int64, md5 string) string {
	info, err := os.Stat(path)
	if err != nil {
		return "missing"
	}
	if size > 0 && info.Size() != size {
		return fmt.Sprintf("size mismatch: expected %d, got %d", size, info.Size())
	}
	if md5 == "" {
		return ""
	}
	actual, err := verifier.FileMD5(path)
	if err != nil {
		return "unreadable: " + err.Error()
	}
	if !strings.EqualFold(actual, md5) {
		return fmt.Sprintf("md5 mismatch: expected %s, got %s", md5, actual)
	}
	return ""
}

func (h *DiffService) HDiffPatchData(gamePath string) (bool, string) {
	hdiffMapPath := filepath.Join(gamePath, "hdiffmap.json")
	hdiffFilesPath := filepath.Join(gamePath, "hdifffiles.txt")
	hdifffilesJsonPath := filepath.Join(gamePath, "hdifffiles.json")

	var jsonData struct {
		DiffMap []*models.HDiffData `json:"diff_map"`
	}

	if _, err := os.Stat(hdiffMapPath); err == nil {
		data, err := os.ReadFile(hdiffMapPath)
		if err != nil {
			return false, err.Error()
		}

		var jsonDataDiffMap struct {
			DiffMap []*models.DiffMapType `json:"diff_map"`
		}
		if err := json.Unmarshal(data, &jsonDataDiffMap); err != nil {
			return false, err.Error()
		}
		for _, entry := range jsonDataDiffMap.DiffMap {
			jsonData.DiffMap = append(jsonData.DiffMap, entry.ToHDiffData())
		}
	} else if _, err := os.Stat(hdifffilesJsonPath); err == nil {
		data, err := os.ReadFile(hdifffilesJsonPath)
		if err != nil {
			return false, err.Error()
		}
		var hdiffJson []*models.HDiffData
		if err := json.Unmarshal(data, &hdiffJson); err != nil {
			return false, err.Error()
		}
		jsonData.DiffMap = append(jsonData.DiffMap, hdiffJson...)
	} else if _, err := os.Stat(hdiffFilesPath); err == nil {
		files, err := models.LoadHDiffFiles(hdiffFilesPath)
		if err != nil {
			return false, err.Error()
		}
		for _, entry := range files {
			jsonData.DiffMap = append(jsonData.DiffMap, entry.ToHDiffData())
		}
	} else {
		return false, "no hdiff entries map exist"
	}

	emitStage("Patching HDiff")

	var wg sync.WaitGroup
	jobs := make(chan *models.HDiffData, len(jsonData.DiffMap))
	var progress, patched, reused int32
	var mu sync.Mutex
	var firstError error
	var skippedEntries []*models.HDiffData
	setError := func(err error) {
		mu.Lock()
		defer mu.Unlock()
		if firstError == nil {
			firstError = err
		}
	}
	hasError := func() bool {
		mu.Lock()
		defer mu.Unlock()
		return firstError != nil
	}
	// A local file the patch no longer recognises is left untouched instead of aborting the whole run.
	skip := func(entry *models.HDiffData, reason string) {
		mu.Lock()
		skippedEntries = append(skippedEntries, entry)
		mu.Unlock()
		emitWarn(fmt.Sprintf("%s (%s)", entry.TargetFileName, reason))
	}

	processEntry := func(entry *models.HDiffData) {
		sourceFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.SourceFileName, "\\", "/")))
		patchFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.PatchFileName, "\\", "/")))
		targetFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.TargetFileName, "\\", "/")))

		// Resuming a run that stopped halfway: this entry is already the target.
		if entry.TargetFileMD5 != "" && verifyFile(targetFile, entry.TargetFileSize, entry.TargetFileMD5) == "" {
			if entry.SourceFileName != "" && entry.SourceFileName != entry.TargetFileName {
				os.Remove(sourceFile)
			}
			os.Remove(patchFile)
			atomic.AddInt32(&reused, 1)
			return
		}

		if reason := verifyFile(patchFile, entry.PatchFileSize, entry.PatchFileMD5); reason != "" {
			setError(fmt.Errorf("patch file %s %s", entry.PatchFileName, reason))
			return
		}
		if err := os.MkdirAll(filepath.Dir(targetFile), os.ModePerm); err != nil {
			setError(err)
			return
		}
		if entry.SourceFileName != "" {
			if reason := verifyFile(sourceFile, entry.SourceFileSize, entry.SourceFileMD5); reason != "" {
				skip(entry, "source "+reason)
				return
			}
		}

		// Patch into a sibling temp file so a failure never damages the installed one.
		tempFile := targetFile + ".hpatch_tmp"
		os.Remove(tempFile)
		var err error
		if entry.SourceFileName == "" {
			err = hpatchz.ApplyPatchEmpty(patchFile, tempFile)
		} else {
			err = hpatchz.ApplyPatch(sourceFile, patchFile, tempFile)
		}
		if err != nil {
			os.Remove(tempFile)
			setError(err)
			return
		}
		if reason := verifyFile(tempFile, entry.TargetFileSize, entry.TargetFileMD5); reason != "" {
			os.Remove(tempFile)
			skip(entry, "patched output "+reason)
			return
		}
		if err := os.Rename(tempFile, targetFile); err != nil {
			os.Remove(tempFile)
			setError(err)
			return
		}

		if entry.SourceFileName != "" && entry.SourceFileName != entry.TargetFileName {
			os.Remove(sourceFile)
		}
		os.Remove(patchFile)
		atomic.AddInt32(&patched, 1)
	}

	workerCount := max(1, runtime.NumCPU()/2)
	for i := 0; i < workerCount; i++ {
		wg.Go(func() {
			for entry := range jobs {
				if !hasError() {
					processEntry(entry)
				}
				emitProgress(int(atomic.AddInt32(&progress, 1)), len(jsonData.DiffMap))
			}
		})
	}

	for _, entry := range jsonData.DiffMap {
		jobs <- entry
	}
	close(jobs)
	wg.Wait()
	if firstError != nil {
		return false, firstError.Error()
	}

	for _, entry := range skippedEntries {
		os.Remove(filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.PatchFileName, "\\", "/"))))
	}
	os.Remove(filepath.Join(gamePath, "hdiffmap.json"))
	os.Remove(filepath.Join(gamePath, "hdifffiles.txt"))
	os.Remove(filepath.Join(gamePath, "hdifffiles.json"))
	return true, fmt.Sprintf("patching completed (%d patched, %d already up to date, %d skipped)", patched, reused, len(skippedEntries))
}

func (h *DiffService) DeleteFiles(gamePath string) (bool, string) {
	var deleteFiles []string

	file, err := os.Open(filepath.Join(gamePath, "deletefiles.txt"))
	if err != nil {
		return false, ""
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			deleteFiles = append(deleteFiles, line)
		}
	}

	if err := scanner.Err(); err != nil {
		file.Close()
		return false, "no delete files exist"
	}

	file.Close()

	var wg sync.WaitGroup
	jobs := make(chan string, len(deleteFiles))
	var progress int32

	workerCount := max(1, runtime.NumCPU())
	for i := 0; i < workerCount; i++ {
		wg.Go(func() {
			for file := range jobs {
				cleanFile := filepath.FromSlash(strings.ReplaceAll(file, "\\", "/"))
				os.Remove(filepath.Join(gamePath, cleanFile))

				currentProgress := atomic.AddInt32(&progress, 1)
				emitProgress(int(currentProgress), len(deleteFiles))
			}
		})
	}

	for _, file := range deleteFiles {
		jobs <- file
	}
	close(jobs)
	wg.Wait()
	os.Remove(filepath.Join(gamePath, "deletefiles.txt"))
	return true, ""
}
