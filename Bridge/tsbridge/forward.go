package main

// Lokale TCP-forwarders: elke verbinding op de lokale listener wordt via DialFunc (in de DLL: tsnet.Server.Dial)
// doorgestuurd naar het doel in het tailnet. Los van tsnet, zodat het met een lokale echo-server te testen is.

import (
	"context"
	"errors"
	"io"
	"net"
	"strings"
	"sync"
	"time"
)

// DialFunc maakt een uitgaande verbinding naar het doel (in de DLL via het tailnet).
type DialFunc func(ctx context.Context, network, address string) (net.Conn, error)

// Forwarder luistert op een lokaal adres en stuurt elke verbinding door naar Target.
type Forwarder struct {
	Target      string
	allowedPid  uint32 // 0 = elke verbinding; anders alleen verbindingen uit dit proces
	dial        DialFunc
	listener    net.Listener
	dialTimeout time.Duration
	logf        func(format string, args ...any)

	mu     sync.Mutex
	conns  map[net.Conn]struct{}
	closed bool
	wg     sync.WaitGroup
}

// StartForwarder opent de listener op localAddr ("127.0.0.2:0" = vrije poort) en begint verbindingen te accepteren.
// Alleen loopback; de poort wordt exclusief geclaimd. allowedPid <> 0: alleen verbindingen uit dat proces.
func StartForwarder(localAddr, target string, allowedPid uint32, dial DialFunc, logf func(string, ...any)) (*Forwarder, error) {
	if target == "" {
		return nil, errors.New("geen doel opgegeven")
	}
	if logf == nil {
		logf = func(string, ...any) {}
	}
	if _, _, err := net.SplitHostPort(localAddr); err != nil {
		localAddr = net.JoinHostPort(strings.Trim(localAddr, "[]"), "0") // alleen een adres: vrije poort
	}
	if err := validateLoopbackListen(localAddr); err != nil {
		return nil, err
	}
	ln, err := listenExclusive(localAddr)
	if err != nil {
		return nil, err
	}
	f := &Forwarder{
		Target:      target,
		allowedPid:  allowedPid,
		dial:        dial,
		listener:    ln,
		dialTimeout: 30 * time.Second,
		logf:        logf,
		conns:       make(map[net.Conn]struct{}),
	}
	f.wg.Add(1)
	go f.acceptLoop()
	return f, nil
}

// Port is de lokale poort waarop de forwarder luistert.
func (f *Forwarder) Port() int {
	return f.listener.Addr().(*net.TCPAddr).Port
}

func (f *Forwarder) acceptLoop() {
	defer f.wg.Done()
	for {
		c, err := f.listener.Accept()
		if err != nil {
			if !f.isClosed() {
				f.logf("forward %d: accept: %v", f.Port(), err)
			}
			return
		}
		if !f.track(c) {
			c.Close()
			return
		}
		f.wg.Add(1)
		go f.handle(c)
	}
}

func (f *Forwarder) handle(local net.Conn) {
	defer f.wg.Done()
	defer f.untrack(local)
	defer local.Close()

	if f.allowedPid != 0 {
		ok, err := connFromPid(local, f.allowedPid)
		if err != nil || !ok {
			// Een ander programma op deze pc probeert de tunnel te gebruiken: weigeren.
			f.logf("forward %d: verbinding van %s geweigerd (niet van RDCManagerX; %v)", f.Port(), local.RemoteAddr(), err)
			return
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), f.dialTimeout)
	remote, err := f.dial(ctx, "tcp", f.Target)
	cancel()
	if err != nil {
		f.logf("forward %d: verbinden met %s mislukt: %v", f.Port(), f.Target, err)
		return
	}
	if !f.track(remote) {
		remote.Close()
		return
	}
	defer f.untrack(remote)
	defer remote.Close()

	done := make(chan struct{}, 2)
	pipe := func(dst, src net.Conn) {
		io.Copy(dst, src)
		// Halve sluiting doorgeven waar mogelijk, zodat de andere kant zijn laatste data nog kan sturen.
		if cw, ok := dst.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		} else {
			dst.Close()
		}
		done <- struct{}{}
	}
	go pipe(remote, local)
	go pipe(local, remote)
	<-done
	<-done
}

func (f *Forwarder) track(c net.Conn) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.closed {
		return false
	}
	f.conns[c] = struct{}{}
	return true
}

func (f *Forwarder) untrack(c net.Conn) {
	f.mu.Lock()
	delete(f.conns, c)
	f.mu.Unlock()
}

func (f *Forwarder) isClosed() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.closed
}

// Close stopt de listener en verbreekt alle lopende verbindingen; wacht tot alle goroutines klaar zijn.
func (f *Forwarder) Close() error {
	f.mu.Lock()
	if f.closed {
		f.mu.Unlock()
		return nil
	}
	f.closed = true
	err := f.listener.Close()
	for c := range f.conns {
		c.Close()
	}
	f.mu.Unlock()
	f.wg.Wait()
	return err
}
