package main

// tsbridge.dll: C-API rond tailscale.com/tsnet voor RDCManagerX.
//
// Afspraken:
//   - Invoer is UTF-8 char*; returncodes zijn int32. Tekst gaat naar een buffer van de aanroeper; de functies geven
//     het aantal benodigde bytes (zonder afsluitende 0) terug. Is dat >= buflen, dan is de tekst afgekapt: opnieuw
//     aanroepen met een grotere buffer.
//   - Negatieve waarden zijn foutcodes (zie hieronder); de tekst via TsLastError (handle 0 = laatste Create-fout).
//   - Alle functies zijn thread-safe. TsNetClose vanuit een andere thread breekt een lopende TsNetUp af.
//   - De DLL mag niet ontladen worden (Go-runtime).

/*
#include <stdint.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"os"
	"sync"
	"time"
	"unsafe"
)

const (
	codeOK            = 0
	codeInvalidHandle = -1
	codeInvalidArgs   = -2
	codeTimeout       = -3
	codeClosed        = -4
	codeFailed        = -5
	codeNotFound      = -6
	codeOffline       = -7
)

const bridgeVersion = "1"

var (
	nodesMu    sync.Mutex
	nodes      = map[int32]*node{}
	nextHandle int32
	createErr  string
)

func init() {
	// Geen logs naar de log-servers van Tailscale sturen (privacy); lokaal loggen gaat via Logf.
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true")
}

func lookup(h C.int) *node {
	nodesMu.Lock()
	defer nodesMu.Unlock()
	return nodes[int32(h)]
}

func codeFor(err error) C.int {
	switch {
	case err == nil:
		return codeOK
	case errors.Is(err, errTimeout):
		return codeTimeout
	case errors.Is(err, errClosed):
		return codeClosed
	case errors.Is(err, errNotFound):
		return codeNotFound
	case errors.As(err, new(errOffline)):
		return codeOffline
	default:
		return codeFailed
	}
}

func writeBuf(buf *C.char, buflen C.int, s string) C.int {
	b := []byte(s)
	if buf != nil && buflen > 0 {
		dst := unsafe.Slice((*byte)(unsafe.Pointer(buf)), int(buflen))
		n := copy(dst[:int(buflen)-1], b)
		dst[n] = 0
	}
	return C.int(len(b))
}

//export TsBridgeVersion
func TsBridgeVersion(buf *C.char, buflen C.int) C.int {
	return writeBuf(buf, buflen, bridgeVersion)
}

//export TsNetCreate
func TsNetCreate(configJSON *C.char) C.int {
	if configJSON == nil {
		return codeInvalidArgs
	}
	n, err := newNode(C.GoString(configJSON))
	nodesMu.Lock()
	defer nodesMu.Unlock()
	if err != nil {
		createErr = err.Error()
		return codeInvalidArgs
	}
	createErr = ""
	nextHandle++
	nodes[nextHandle] = n
	return C.int(nextHandle)
}

//export TsNetUp
func TsNetUp(h C.int, timeoutMs C.int) C.int {
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	if timeoutMs <= 0 {
		timeoutMs = 60000
	}
	return codeFor(n.up(time.Duration(timeoutMs) * time.Millisecond))
}

//export TsNetGetStatus
func TsNetGetStatus(h C.int, buf *C.char, buflen C.int) C.int {
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	data, _ := json.Marshal(n.status())
	return writeBuf(buf, buflen, string(data))
}

//export TsNetAddForward
func TsNetAddForward(h C.int, localAddr *C.char, target *C.char) C.int {
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	if localAddr == nil || target == nil {
		return codeInvalidArgs
	}
	port, err := n.addForward(C.GoString(localAddr), C.GoString(target))
	n.setErr(err)
	if err != nil {
		return codeFor(err)
	}
	return C.int(port)
}

//export TsNetCheckTarget
func TsNetCheckTarget(h C.int, target *C.char) C.int {
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	if target == nil {
		return codeInvalidArgs
	}
	err := n.checkTarget(C.GoString(target))
	n.setErr(err)
	return codeFor(err)
}

//export TsNetResolvedTarget
func TsNetResolvedTarget(h C.int, target *C.char, buf *C.char, buflen C.int) C.int {
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	if target == nil {
		return codeInvalidArgs
	}
	data, _ := json.Marshal(n.lastResolved(C.GoString(target)))
	return writeBuf(buf, buflen, string(data))
}

//export TsNetRemoveForward
func TsNetRemoveForward(h C.int, localPort C.int) C.int {
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	return codeFor(n.removeForward(int(localPort)))
}

//export TsNetClose
func TsNetClose(h C.int) C.int {
	nodesMu.Lock()
	n := nodes[int32(h)]
	delete(nodes, int32(h))
	nodesMu.Unlock()
	if n == nil {
		return codeInvalidHandle
	}
	n.close()
	return codeOK
}

//export TsLastError
func TsLastError(h C.int, buf *C.char, buflen C.int) C.int {
	if h == 0 {
		nodesMu.Lock()
		s := createErr
		nodesMu.Unlock()
		return writeBuf(buf, buflen, s)
	}
	n := lookup(h)
	if n == nil {
		return codeInvalidHandle
	}
	return writeBuf(buf, buflen, n.lastError())
}

func main() {}
