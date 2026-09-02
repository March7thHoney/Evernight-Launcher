package main

import (
	"flag"
	"fmt"
	"os"

	diffService "firefly-launcher/internal/diff-service"
	"firefly-launcher/pkg/models"
)

func fail(msg string) {
	fmt.Printf("RESULT ERR %s\n", msg)
	os.Exit(1)
}

func stage(name string) {
	fmt.Printf("STAGE %s\n", name)
}

// Applies an ldiff/hdiff patch: -game <dir> {-patch <archive> | -patch-dir <dir>}, tools from PATCHTOOL_DATA_DIR.
func main() {
	game := flag.String("game", "", "game install directory")
	patch := flag.String("patch", "", "patch archive path (.7z/.zip/.rar)")
	patchDir := flag.String("patch-dir", "", "pre-extracted patch payload directory (manifest + ldiff/)")
	flag.Parse()

	if *game == "" {
		fail("missing -game argument")
	}
	if *patch == "" && *patchDir == "" {
		fail("missing -patch or -patch-dir argument")
	}
	if *patch != "" && *patchDir != "" {
		fail("-patch and -patch-dir are mutually exclusive")
	}
	if _, err := os.Stat(*game); err != nil {
		fail("game directory not found: " + *game)
	}

	ds := &diffService.DiffService{}

	if *patchDir != "" {
		if _, err := os.Stat(*patchDir); err != nil {
			fail("patch directory not found: " + *patchDir)
		}
		stage("Adopt Data")
		if aok, msg := ds.AdoptDirectory(*game, *patchDir); !aok {
			fail(msg)
		}
		stage("Patch")
		pok, msg, applied := ds.LDiffPatchData(*game)
		if !pok {
			fail(msg)
		}
		if sok, smsg := ds.SyncPersistent(*game, applied); !sok {
			fail(smsg)
		}
		fmt.Println("RESULT OK")
		return
	}

	if _, err := os.Stat(*patch); err != nil {
		fail("patch archive not found: " + *patch)
	}

	stage("Check Type")
	ok, validType, errType := ds.CheckTypeHDiff(*patch)
	if !ok {
		fail(errType)
	}

	isHdiff := validType == "hdiffmap.json" || validType == "hdifffiles.txt" || validType == "hdifffiles.json"

	if isHdiff {
		stage("Version Validate")
		if vok, msg := ds.VersionValidate(*game, *patch); !vok {
			fail(msg)
		}
	}

	stage("Extract")
	if eok, msg := ds.DataExtract(*game, *patch); !eok {
		fail(msg)
	}

	stage("Cut Data")
	if cok, msg := ds.CutData(*game); !cok {
		fail(msg)
	}

	stage("Patch")
	var applied []*models.HDiffData
	if isHdiff {
		pok, msg, entries := ds.HDiffPatchData(*game)
		if !pok {
			fail(msg)
		}
		applied = entries
		stage("Delete Old Files")
		if dok, msg := ds.DeleteFiles(*game); !dok && msg != "" {
			fail(msg)
		}
	} else {
		pok, msg, entries := ds.LDiffPatchData(*game)
		if !pok {
			fail(msg)
		}
		applied = entries
	}

	if sok, msg := ds.SyncPersistent(*game, applied); !sok {
		fail(msg)
	}

	fmt.Println("RESULT OK")
}
