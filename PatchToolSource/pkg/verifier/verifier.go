package verifier

import (
	"crypto/md5"
	"encoding/hex"
	"io"
	"os"
	"sync"
)

var bufPool = sync.Pool{
	New: func() interface{} {
		buf := make([]byte, 1024*1024)
		return &buf
	},
}

func FileMD5(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := md5.New()
	bufPtr := bufPool.Get().(*[]byte)
	defer bufPool.Put(bufPtr)
	if _, err := io.CopyBuffer(h, f, *bufPtr); err != nil {
		return "", err
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}
