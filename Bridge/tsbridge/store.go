package main

// State-opslag voor niet-ephemeral netwerken: één bestand met de node-sleutels, dubbel versleuteld:
//   1. AES-256-GCM met de state-sleutel (32 bytes) die RDCManagerX in zijn wachtwoordkluis bewaart: zonder
//      ontgrendelde kluis is de state onbruikbaar;
//   2. daaroverheen DPAPI (CryptProtectData, per Windows-gebruiker, met eigen entropy).
// De standaard FileStore van tsnet schrijft de node-sleutels onversleuteld weg; deze store niet.

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"unsafe"

	"golang.org/x/sys/windows"
	"tailscale.com/ipn"
)

const stateFileName = "state.dpapi"

// dpapiEntropy bindt de versleuteling aan deze toepassing (extra naast de gebruikerssleutel van DPAPI).
var dpapiEntropy = []byte("RDCManagerX tsbridge state v1")

type dpapiStore struct {
	path  string
	aead  cipher.AEAD // DevSkim: ignore DS187371 (AES-256-GCM, see newDpapiStore)
	mu    sync.Mutex
	cache map[ipn.StateKey][]byte
}

func newDpapiStore(dir string, stateKey []byte) (*dpapiStore, error) {
	if len(stateKey) != 32 {
		return nil, errors.New("state-sleutel moet 32 bytes zijn")
	}
	block, err := aes.NewCipher(stateKey)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	s := &dpapiStore{path: filepath.Join(dir, stateFileName), aead: aead, cache: map[ipn.StateKey][]byte{}}
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	sealed, err := dpapiDecrypt(data)
	if err != nil {
		return nil, errors.New("state kan niet worden ontsleuteld (andere Windows-gebruiker of beschadigd bestand)")
	}
	plain, err := s.open(sealed)
	if err != nil {
		return nil, errors.New("state kan niet worden ontsleuteld (andere state-sleutel of beschadigd bestand)")
	}
	if err := json.Unmarshal(plain, &s.cache); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *dpapiStore) String() string { return "dpapiStore" }

func (s *dpapiStore) ReadState(id ipn.StateKey) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	v, ok := s.cache[id]
	if !ok {
		return nil, ipn.ErrStateNotExist
	}
	return append([]byte(nil), v...), nil
}

func (s *dpapiStore) WriteState(id ipn.StateKey, bs []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cache[id] = append([]byte(nil), bs...)
	plain, err := json.Marshal(s.cache)
	if err != nil {
		return err
	}
	sealed, err := s.seal(plain)
	if err != nil {
		return err
	}
	enc, err := dpapiEncrypt(sealed)
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, enc, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

// seal: nonce (12 bytes) || AES-GCM(plain), met het bestandsformaat als AAD.
func (s *dpapiStore) seal(plain []byte) ([]byte, error) {
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return s.aead.Seal(nonce, nonce, plain, dpapiEntropy), nil
}

func (s *dpapiStore) open(sealed []byte) ([]byte, error) {
	ns := s.aead.NonceSize()
	if len(sealed) < ns {
		return nil, errors.New("te kort")
	}
	return s.aead.Open(nil, sealed[:ns], sealed[ns:], dpapiEntropy)
}

func blob(b []byte) *windows.DataBlob {
	if len(b) == 0 {
		return &windows.DataBlob{}
	}
	return &windows.DataBlob{Size: uint32(len(b)), Data: &b[0]}
}

func takeBlob(out *windows.DataBlob) []byte {
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	return append([]byte(nil), unsafe.Slice(out.Data, out.Size)...)
}

func dpapiEncrypt(plain []byte) ([]byte, error) {
	var out windows.DataBlob
	if err := windows.CryptProtectData(blob(plain), nil, blob(dpapiEntropy), 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out); err != nil {
		return nil, err
	}
	return takeBlob(&out), nil
}

func dpapiDecrypt(enc []byte) ([]byte, error) {
	var out windows.DataBlob
	if err := windows.CryptUnprotectData(blob(enc), nil, blob(dpapiEntropy), 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out); err != nil {
		return nil, err
	}
	return takeBlob(&out), nil
}
