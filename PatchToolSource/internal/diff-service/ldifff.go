package diffService

import (
	"firefly-launcher/pkg/firefly"
	"firefly-launcher/pkg/firefly/pb"
	"firefly-launcher/pkg/hpatchz"
	"firefly-launcher/pkg/models"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

func (h *DiffService) LDiffPatchData(gamePath string) (bool, string) {
	entries, err := os.ReadDir(gamePath)
	if err != nil {
		return false, err.Error()
	}
	ldiffPath := filepath.Join(gamePath, "ldiff")

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		if !entry.Type().IsRegular() {
			continue
		}

		name := entry.Name()
		if strings.HasPrefix(name, "manifest") {
			manifestName := entry.Name()
			manifestPath := filepath.Join(gamePath, manifestName)

			manifest, err := firefly.LoadManifestProto(manifestPath)
			if err != nil {
				continue
			}

			ldiffEntries, err := os.ReadDir(ldiffPath)
			if err != nil {
				return false, err.Error()
			}
			emitStage("Processing LDiff")
			for i, ldiffEntry := range ldiffEntries {
				assetName := ldiffEntry.Name()
				var matchingAssets []struct {
					AssetName string
					AssetSize int64
					Asset     *pb.AssetManifest
				}

				emitProgress(i, len(ldiffEntries))

				var wg sync.WaitGroup
				var mu sync.Mutex

				for _, assetGroup := range manifest.Assets {
					assetGroup := assetGroup
					wg.Go(func() {
						if data := assetGroup.AssetData; data != nil {
							for _, asset := range data.Assets {
								if asset.ChunkFileName == assetName {
									mu.Lock()
									matchingAssets = append(matchingAssets, struct {
										AssetName string
										AssetSize int64
										Asset     *pb.AssetManifest
									}{assetGroup.AssetName, assetGroup.AssetSize, asset})
									mu.Unlock()
								}
							}
						}
					})
				}

				wg.Wait()

				for _, ma := range matchingAssets {
					err := firefly.LDiffFile(ma.Asset, ma.AssetName, ma.AssetSize, ldiffPath, gamePath)
					if err != nil {
						continue
					}
				}
			}

			diffMapNames := make([]string, len(ldiffEntries))
			for i, e := range ldiffEntries {
				diffMapNames[i] = e.Name()
			}

			diffMapList, err := MakeDiffMap(manifest, diffMapNames)
			if err != nil {
				return false, err.Error()
			}
			emitStage("Patching HDiff")
			for i, entry := range diffMapList {
				emitProgress(i, len(diffMapList))
				sourceFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.SourceFileName, "\\", "/")))
				patchFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.PatchFileName, "\\", "/")))
				targetFile := filepath.Join(gamePath, filepath.FromSlash(strings.ReplaceAll(entry.TargetFileName, "\\", "/")))

				if _, err := os.Stat(patchFile); os.IsNotExist(err) {
					continue
				}

				if entry.SourceFileName == "" {
					hpatchz.ApplyPatchEmpty(patchFile, targetFile)
					os.Remove(patchFile)
					continue
				}

				if _, err := os.Stat(sourceFile); os.IsNotExist(err) {
					continue
				}

				hpatchz.ApplyPatch(sourceFile, patchFile, targetFile)
				if entry.SourceFileName != entry.TargetFileName {
					os.Remove(sourceFile)
				}
				os.Remove(patchFile)
			}

		}
	}
	os.RemoveAll(ldiffPath)
	return true, "patching completed"
}

func MakeDiffMap(manifest *pb.ManifestProto, chunkNames []string) ([]*models.HDiffData, error) {
	var hdiffFiles []*models.HDiffData

	for _, asset := range manifest.Assets {
		assetName := asset.AssetName
		assetSize := asset.AssetSize

		if asset.AssetData != nil {
			for _, chunk := range asset.AssetData.Assets {
				matched := false
				for _, name := range chunkNames {
					if name == chunk.ChunkFileName {
						matched = true
						break
					}
				}
				if !matched {
					continue
				}

				if chunk.OriginalFileSize != 0 || chunk.HdiffFileSize != assetSize {
					hdiffFiles = append(hdiffFiles, &models.HDiffData{
						SourceFileName: chunk.OriginalFilePath,
						TargetFileName: assetName,
						PatchFileName:  fmt.Sprintf("%s.hdiff", assetName),
					})
				}
			}
		}
	}

	return hdiffFiles, nil
}
