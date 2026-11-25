package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// echoServer start een lokale TCP-server die alles terugstuurt; vervangt het doel in het tailnet.
func echoServer(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				io.Copy(c, c)
			}()
		}
	}()
	return ln.Addr().String()
}

func plainDial(ctx context.Context, network, address string) (net.Conn, error) {
	var d net.Dialer
	return d.DialContext(ctx, network, address)
}

func TestForwardEchoesData(t *testing.T) {
	target := echoServer(t)
	f, err := StartForwarder("127.0.0.1:0", target, 0, plainDial, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if f.Port() == 0 {
		t.Fatal("poort 0 teruggegeven")
	}

	c, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", itoa(f.Port())))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	payload := make([]byte, 256*1024)
	rand.Read(payload)
	go c.Write(payload)
	got := make([]byte, len(payload))
	c.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(c, got); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("teruggestuurde data wijkt af")
	}
}

func TestForwardHandlesParallelConnections(t *testing.T) {
	target := echoServer(t)
	f, err := StartForwarder("127.0.0.1:0", target, 0, plainDial, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	var wg sync.WaitGroup
	errs := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			c, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", itoa(f.Port())))
			if err != nil {
				errs <- err
				return
			}
			defer c.Close()
			msg := []byte(strings.Repeat(itoa(i), 1000))
			c.Write(msg)
			got := make([]byte, len(msg))
			c.SetReadDeadline(time.Now().Add(10 * time.Second))
			if _, err := io.ReadFull(c, got); err != nil {
				errs <- err
				return
			}
			if !bytes.Equal(got, msg) {
				errs <- errors.New("data wijkt af")
			}
		}(i)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
}

func TestCloseDropsOpenConnections(t *testing.T) {
	target := echoServer(t)
	f, err := StartForwarder("127.0.0.1:0", target, 0, plainDial, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	c, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", itoa(f.Port())))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.Write([]byte("x"))
	buf := make([]byte, 1)
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}

	closed := make(chan struct{})
	go func() { f.Close(); close(closed) }()
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("Close blijft hangen met een open verbinding")
	}
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Read(buf); err == nil {
		t.Fatal("verbinding na Close nog open")
	}
	if _, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", itoa(f.Port())), time.Second); err == nil {
		t.Fatal("listener na Close nog bereikbaar")
	}
}

func TestDialFailureClosesLocalConnection(t *testing.T) {
	failDial := func(ctx context.Context, network, address string) (net.Conn, error) {
		return nil, errors.New("doel onbereikbaar")
	}
	f, err := StartForwarder("127.0.0.1:0", "100.64.0.1:3389", 0, failDial, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", itoa(f.Port())))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Read(make([]byte, 1)); err == nil {
		t.Fatal("verwacht dat de lokale verbinding gesloten wordt")
	}
}

func TestEmptyTargetRejected(t *testing.T) {
	if _, err := StartForwarder("127.0.0.1:0", "", 0, plainDial, nil); err == nil {
		t.Fatal("leeg doel geaccepteerd")
	}
}

func TestRedactSecrets(t *testing.T) {
	// Nep-keys, in stukken opgebouwd zodat secret scanners (GitHub) ze niet voor echte keys aanzien.
	prefix := "tsk" + "ey-"
	fakeAuth := prefix + "auth-kABC123-XYZsecret"
	fakeClient := prefix + "client-other-999"
	r := newRedactor(fakeAuth)
	got := r.redact("login met " + fakeAuth + " en " + fakeClient + " klaar")
	if strings.Contains(got, "XYZsecret") || strings.Contains(got, "other-999") {
		t.Fatalf("secret niet gefilterd: %q", got)
	}
}

func itoa(i int) string {
	return strconv.Itoa(i)
}
