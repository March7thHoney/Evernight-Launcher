package diffService

import (
	"fmt"
	"os"
	"sync"
)

// emit* write the line-based progress protocol to stdout for the Swift caller to parse.
var emitMu sync.Mutex

func emitStage(stage string) {
	emitMu.Lock()
	defer emitMu.Unlock()
	fmt.Fprintf(os.Stdout, "STAGE %s\n", stage)
}

func emitProgress(progress, maxProgress int) {
	emitMu.Lock()
	defer emitMu.Unlock()
	fmt.Fprintf(os.Stdout, "PROGRESS %d %d\n", progress, maxProgress)
}

func emitMessage(msg string) {
	emitMu.Lock()
	defer emitMu.Unlock()
	fmt.Fprintf(os.Stdout, "MSG %s\n", msg)
}
