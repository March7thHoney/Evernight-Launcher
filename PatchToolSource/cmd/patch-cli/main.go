package main

import (
	"flag"
	"fmt"
	"os"

	diffService "firefly-launcher/internal/diff-service"
)

func fail(msg string) {
	fmt.Printf("RESULT ERR %s\n", msg)
	os.Exit(1)
}

func stage(name string) {
	fmt.Printf("STAGE %s\n", name)
}

// patch-cli applies an ldiff/hdiff patch archive to a Star Rail game directory.
// Usage: patch-cli -game <dir> -patch <archive>  (PATCHTOOL_DATA_DIR points to bin/ tools + temp)
func main() {
	game := flag.String("game", "", "game install directory")
	patch := flag.String("patch", "", "patch archive path (.7z/.zip/.rar)")
	flag.Parse()

	if *game == "" || *patch == "" {
		fail("missing -game or -patch argument")
	}
	if _, err := os.Stat(*game); err != nil {
		fail("game directory not found: " + *game)
	}
	if _, err := os.Stat(*patch); err != nil {
		fail("patch archive not found: " + *patch)
	}

	ds := &diffService.DiffService{}

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
	if isHdiff {
		if pok, msg := ds.HDiffPatchData(*game); !pok {
			fail(msg)
		}
		stage("Delete Old Files")
		if dok, msg := ds.DeleteFiles(*game); !dok && msg != "" {
			fail(msg)
		}
	} else {
		if pok, msg := ds.LDiffPatchData(*game); !pok {
			fail(msg)
		}
	}

	fmt.Println("RESULT OK")
}
