package main

import (
	"bytes"
	"crypto/rand"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"tailscale.com/ipn"
)

func newKey(t *testing.T) []byte {
	t.Helper()
	k := make([]byte, 32)
	if _, err := rand.Read(k); err != nil {
		t.Fatal(err)
	}
	return k
}

func TestStoreRoundTrip(t *testing.T) {
	dir := t.TempDir()
	key := newKey(t)
	s, err := newDpapiStore(dir, key)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.ReadState("profiel"); !errors.Is(err, ipn.ErrStateNotExist) {
		t.Fatalf("verwacht ErrStateNotExist, kreeg %v", err)
	}
	secret := []byte("privkey:GEHEIM-node-sleutel-1234567890")
	if err := s.WriteState("profiel", secret); err != nil {
		t.Fatal(err)
	}

	s2, err := newDpapiStore(dir, key)
	if err != nil {
		t.Fatal(err)
	}
	got, err := s2.ReadState("profiel")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, secret) {
		t.Fatal("state na herladen wijkt af")
	}
}

func TestStoreFileIsNotPlaintext(t *testing.T) {
	dir := t.TempDir()
	s, err := newDpapiStore(dir, newKey(t))
	if err != nil {
		t.Fatal(err)
	}
	if err := s.WriteState("profiel", []byte("GEHEIM-node-sleutel")); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, stateFileName))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("GEHEIM")) || bytes.Contains(raw, []byte("profiel")) {
		t.Fatal("state-bestand bevat leesbare gegevens")
	}
}

func TestStoreWrongKeyFails(t *testing.T) {
	dir := t.TempDir()
	s, err := newDpapiStore(dir, newKey(t))
	if err != nil {
		t.Fatal(err)
	}
	if err := s.WriteState("profiel", []byte("x")); err != nil {
		t.Fatal(err)
	}
	if _, err := newDpapiStore(dir, newKey(t)); err == nil {
		t.Fatal("state geopend met een andere sleutel")
	}
}

func TestStoreRejectsShortKey(t *testing.T) {
	if _, err := newDpapiStore(t.TempDir(), make([]byte, 16)); err == nil {
		t.Fatal("korte sleutel geaccepteerd")
	}
}
