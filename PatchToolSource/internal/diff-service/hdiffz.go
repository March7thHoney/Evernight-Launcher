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

	if _, err := os.Stat(constant.TempUrl); os.IsNotExist(err) {
		if err := os.MkdirAll(constant.TempUrl, os.ModePerm); err != nil {
			return false, err.Error()
		}
	}

	okFull, errFull := sevenzip.IsFileIn7z(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes")
	okDiff, errDiff := sevenzip.IsFileIn7z(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes.hdiff")

	if errFull != nil && errDiff != nil {
		return false, errFull.Error()
	}
	if !okFull && !okDiff {
		return true, "validated without BinaryVersion"
	}

	var tempBinFile string

	if okFull {
		if err := sevenzip.ExtractAFileFromZip(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes", constant.TempUrl); err != nil {
			return false, err.Error()
		}
		tempBinFile = filepath.Join(constant.TempUrl, "BinaryVersion.bytes")
	} else {
		if err := sevenzip.ExtractAFileFromZip(patchPath, "StarRail_Data/StreamingAssets/BinaryVersion.bytes.hdiff", constant.TempUrl); err != nil {
			return false, err.Error()
		}

		patchBinFile := filepath.Join(constant.TempUrl, "BinaryVersion.bytes.hdiff")
		sourceBinFile := oldBinPath
		tempBinFile = filepath.Join(constant.TempUrl, "BinaryVersion.bytes")

		if err := hpatchz.ApplyPatch(sourceBinFile, patchBinFile, tempBinFile); err != nil {
			os.Remove(patchBinFile)
			return false, err.Error()
		}
		os.Remove(patchBinFile)
	}

	okFullPkg, err1 := sevenzip.IsFileIn7z(patchPath, "pkg_version")
	okDiffPkg, err2 := sevenzip.IsFileIn7z(patchPath, "pkg_version.hdiff")
	if err1 != nil && err2 != nil {
		return false, err1.Error()
	}
	if okFullPkg {
		if err := sevenzip.ExtractAFileFromZip(patchPath, "pkg_version", constant.TempUrl); err != nil {
			return false, err.Error()
		}
	}
	if okDiffPkg {
		if err := sevenzip.ExtractAFileFromZip(patchPath, "pkg_version.hdiff", constant.TempUrl); err != nil {
			return false, err.Error()
		}
		patchPkgFile := filepath.Join(constant.TempUrl, "pkg_version.hdiff")
		sourcePkgFile := filepath.Join(gamePath, "pkg_version")
		tempPkgFile := filepath.Join(constant.TempUrl, "pkg_version")
		if err := hpatchz.ApplyPatch(sourcePkgFile, patchPkgFile, tempPkgFile); err != nil {
			os.Remove(patchPkgFile)
			os.Remove(tempPkgFile)
			return false, err.Error()
		}
		os.Remove(patchPkgFile)
	}

	tempPkgFile := filepath.Join(constant.TempUrl, "pkg_version")
	pkgDataList, err := models.LoadPkgVersion(tempPkgFile)
	if err != nil {
		os.Remove(tempPkgFile)
		return false, err.Error()
	}
	os.Remove(tempPkgFile)

	// MD5 check BinaryVersion
	flags := false
	for _, pkgData := range pkgDataList {
		if strings.ReplaceAll(pkgData.RemoteFile, "\\", "/") == "StarRail_Data/StreamingAssets/BinaryVersion.bytes" {
			flags = true
			md5, err := verifier.FileMD5(tempBinFile)
			if err != nil {
				os.Remove(tempBinFile)
				return false, err.Error()
			}
			if md5 != pkgData.MD5 {
				os.Remove(tempBinFile)
				return false, fmt.Sprintf("md5 mismatch for %s: expected %s, got %s",
					tempBinFile, pkgData.MD5, md5)
			}
			break
		}
	}
	if !flags {
		os.Remove(tempBinFile)
		return false, "BinaryVersion file not found in patch"
	}
	_, err = models.ParseBinaryVersion(tempBinFile)
	if err != nil {
		os.Remove(tempBinFile)
		return false, err.Error()
	}

	os.Remove(tempBinFile)
	return true, "validated"
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
	var progress int32
	var errorMu sync.Mutex
	var firstError error
	setError := func(err error) {
		errorMu.Lock()
		defer errorMu.Unlock()
		if firstError == nil {
			firstError = err
		}
	}
	hasError := func() bool {
		errorMu.Lock()
		defer errorMu.Unlock()
		return firstError != nil
	}

	workerCount := max(1, runtime.NumCPU()/2)
	for i := 0; i < workerCount; i++ {
		wg.Go(func() {
			for entry := range jobs {
				if hasError() {
					continue
				}
				currentProgress := atomic.AddInt32(&progress, 1)
				emitProgress(int(currentProgress), len(jsonData.DiffMap))

				sourceFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.SourceFileName, "\\", "/")))
				patchFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.PatchFileName, "\\", "/")))
				targetFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.TargetFileName, "\\", "/")))

				if _, err := os.Stat(patchFile); err != nil {
					setError(fmt.Errorf("patch file missing: %s", entry.PatchFileName))
					continue
				}
				if entry.PatchFileSize > 0 {
					info, err := os.Stat(patchFile)
					if err != nil || info.Size() != entry.PatchFileSize {
						setError(fmt.Errorf("patch size mismatch: %s", entry.PatchFileName))
						continue
					}
				}
				if entry.PatchFileMD5 != "" {
					actual, err := verifier.FileMD5(patchFile)
					if err != nil || !strings.EqualFold(actual, entry.PatchFileMD5) {
						setError(fmt.Errorf("patch md5 mismatch: %s", entry.PatchFileName))
						continue
					}
				}
				if err := os.MkdirAll(filepath.Dir(targetFile), os.ModePerm); err != nil {
					setError(err)
					continue
				}

				if entry.SourceFileName == "" {
					if err := hpatchz.ApplyPatchEmpty(patchFile, targetFile); err != nil {
						setError(err)
						continue
					}
				} else {
					info, err := os.Stat(sourceFile)
					if err != nil {
						setError(fmt.Errorf("source file missing: %s", entry.SourceFileName))
						continue
					}
					if entry.SourceFileSize > 0 && info.Size() != entry.SourceFileSize {
						setError(fmt.Errorf("source size mismatch: %s", entry.SourceFileName))
						continue
					}
					if entry.SourceFileMD5 != "" {
						actual, err := verifier.FileMD5(sourceFile)
						if err != nil || !strings.EqualFold(actual, entry.SourceFileMD5) {
							setError(fmt.Errorf("source md5 mismatch: %s", entry.SourceFileName))
							continue
						}
					}
					if err := hpatchz.ApplyPatch(sourceFile, patchFile, targetFile); err != nil {
						setError(err)
						continue
					}
				}

				if entry.TargetFileSize > 0 {
					info, err := os.Stat(targetFile)
					if err != nil || info.Size() != entry.TargetFileSize {
						setError(fmt.Errorf("target size mismatch: %s", entry.TargetFileName))
						continue
					}
				}
				if entry.TargetFileMD5 != "" {
					actual, err := verifier.FileMD5(targetFile)
					if err != nil || !strings.EqualFold(actual, entry.TargetFileMD5) {
						setError(fmt.Errorf("target md5 mismatch: %s", entry.TargetFileName))
						continue
					}
				}
				if entry.SourceFileName != "" && entry.SourceFileName != entry.TargetFileName {
					os.Remove(sourceFile)
				}
				os.Remove(patchFile)
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

	os.Remove(filepath.Join(gamePath, "hdiffmap.json"))
	os.Remove(filepath.Join(gamePath, "hdifffiles.txt"))
	os.Remove(filepath.Join(gamePath, "hdifffiles.json"))
	return true, "patching completed"
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
