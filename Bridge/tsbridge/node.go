package main

// Eén tailnet-node (tsnet.Server) per geconfigureerd netwerk, met zijn forwarders.

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"tailscale.com/ipn/store/mem"
	"tailscale.com/tsnet"
)

// nodeConfig is de JSON die TsNetCreate krijgt.
type nodeConfig struct {
	Hostname   string `json:"hostname"`
	AuthKey    string `json:"authKey"`
	Ephemeral  bool   `json:"ephemeral"`
	ControlURL string `json:"controlUrl"`
	Dir        string `json:"dir"`      // werkmap (state bij niet-ephemeral, logconfig); verplicht
	StateKey   string `json:"stateKey"` // base64, 32 bytes uit de kluis van RDCManagerX; verplicht bij niet-ephemeral
	LogFile    string `json:"logFile"` // leeg = geen logging
}

// nodeStatus is de JSON die TsNetGetStatus teruggeeft.
type nodeStatus struct {
	State     string   `json:"state"` // NoState, Starting, NeedsLogin, NeedsMachineAuth, Running, Stopped, Closed
	IPs       []string `json:"ips"`
	DNSName   string   `json:"dnsName"`
	AuthURL   string   `json:"authUrl"`
	LastError string   `json:"lastError"`
}

type node struct {
	srv    *tsnet.Server
	ctx    context.Context
	cancel context.CancelFunc
	logf   func(string, ...any)
	closer func()

	mu       sync.Mutex
	lastErr  string
	started  bool
	closed   bool
	forwards map[int]*Forwarder
}

func newNode(configJSON string) (*node, error) {
	var cfg nodeConfig
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return nil, fmt.Errorf("ongeldige configuratie: %v", err)
	}
	if cfg.Dir == "" {
		return nil, errors.New("geen werkmap (dir) opgegeven")
	}
	if cfg.Hostname == "" {
		return nil, errors.New("geen hostname opgegeven")
	}
	if err := validateControlURL(cfg.ControlURL); err != nil {
		return nil, err
	}
	var stateKey []byte
	if !cfg.Ephemeral {
		var err error
		stateKey, err = base64.StdEncoding.DecodeString(cfg.StateKey)
		if err != nil || len(stateKey) != 32 {
			return nil, errors.New("niet-ephemeral netwerk vereist een state-sleutel van 32 bytes")
		}
	}
	if err := os.MkdirAll(cfg.Dir, 0o700); err != nil {
		return nil, err
	}
	logf, closer := makeLogger(cfg.LogFile, newRedactor(cfg.AuthKey, cfg.StateKey))

	srv := &tsnet.Server{
		Dir:        cfg.Dir,
		Hostname:   cfg.Hostname,
		AuthKey:    cfg.AuthKey,
		Ephemeral:  cfg.Ephemeral,
		ControlURL: cfg.ControlURL,
		Logf:       logf,
		UserLogf:   logf,
	}
	if cfg.Ephemeral {
		srv.Store = new(mem.Store)
	} else {
		st, err := newDpapiStore(filepath.Join(cfg.Dir, "state"), stateKey)
		if err != nil {
			closer()
			return nil, err
		}
		srv.Store = st
		clear(stateKey)
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &node{srv: srv, ctx: ctx, cancel: cancel, logf: logf, closer: closer, forwards: map[int]*Forwarder{}}, nil
}

func (n *node) setErr(err error) {
	n.mu.Lock()
	if err == nil {
		n.lastErr = ""
	} else {
		n.lastErr = err.Error()
	}
	n.mu.Unlock()
}

func (n *node) lastError() string {
	n.mu.Lock()
	defer n.mu.Unlock()
	return n.lastErr
}

// up start de node en wacht tot hij in het tailnet zit (of timeout/annuleren via close).
func (n *node) up(timeout time.Duration) error {
	n.mu.Lock()
	if n.closed {
		n.mu.Unlock()
		return errClosed
	}
	n.started = true
	n.mu.Unlock()

	ctx, cancel := context.WithTimeout(n.ctx, timeout)
	defer cancel()
	_, err := n.srv.Up(ctx)
	if err != nil {
		switch {
		case n.ctx.Err() != nil:
			err = errClosed
		case errors.Is(ctx.Err(), context.DeadlineExceeded):
			err = errTimeout
		}
	}
	n.setErr(err)
	return err
}

func (n *node) status() nodeStatus {
	st := nodeStatus{State: "NoState", LastError: n.lastError()}
	n.mu.Lock()
	started, closed := n.started, n.closed
	n.mu.Unlock()
	if closed {
		st.State = "Closed"
		return st
	}
	if !started {
		return st
	}
	lc, err := n.srv.LocalClient()
	if err != nil {
		st.State = "Starting"
		return st
	}
	ctx, cancel := context.WithTimeout(n.ctx, 2*time.Second)
	defer cancel()
	s, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		st.State = "Starting"
		return st
	}
	st.State = s.BackendState
	st.AuthURL = s.AuthURL
	for _, ip := range s.TailscaleIPs {
		st.IPs = append(st.IPs, ip.String())
	}
	if s.Self != nil {
		st.DNSName = s.Self.DNSName
	}
	return st
}

func (n *node) addForward(localAddr, target string) (int, error) {
	n.mu.Lock()
	closed := n.closed
	n.mu.Unlock()
	if closed {
		return 0, errClosed
	}
	// Alleen RDCManagerX zelf (de RDP-control draait in dit proces) mag de forward gebruiken; het doel wordt
	// alleen binnen het tailnet opgelost.
	f, err := StartForwarder(localAddr, target, uint32(os.Getpid()), n.dialTailnet, n.logf)
	if err != nil {
		return 0, err
	}
	n.mu.Lock()
	n.forwards[f.Port()] = f
	n.mu.Unlock()
	n.logf("forward %s:%d -> %s", localAddr, f.Port(), target)
	return f.Port(), nil
}

// dialTailnet verbindt alleen met doelen binnen het tailnet: de naam wordt opgelost via de apparaten in het
// tailnet (nooit systeem-DNS) en het adres moet een Tailscale-adres of goedgekeurde subnet-route zijn. Zonder deze
// controle zou tsnet een doel buiten het tailnet rechtstreeks (buiten Tailscale om) benaderen.
func (n *node) dialTailnet(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	peers, err := n.peers(ctx)
	if err != nil {
		return nil, err
	}
	ip, err := resolveInTailnet(host, peers)
	if err != nil {
		return nil, err
	}
	return n.srv.Dial(ctx, network, net.JoinHostPort(ip.String(), port))
}

// peers: de apparaten in het tailnet volgens de huidige netmap.
func (n *node) peers(ctx context.Context) ([]tailnetPeer, error) {
	lc, err := n.srv.LocalClient()
	if err != nil {
		return nil, err
	}
	st, err := lc.Status(ctx)
	if err != nil {
		return nil, err
	}
	var peers []tailnetPeer
	for _, ps := range st.Peer {
		p := tailnetPeer{DNSName: ps.DNSName, HostName: ps.HostName, IPs: ps.TailscaleIPs, Online: ps.Online, LastSeen: ps.LastSeen}
		if ps.AllowedIPs != nil {
			p.Routes = ps.AllowedIPs.AsSlice()
		}
		peers = append(peers, p)
	}
	return peers, nil
}

// checkTarget: staat het doel (host:poort) in het tailnet en is het apparaat online? Voor een duidelijke melding
// vóór het verbinden, in plaats van een algemene RDP-fout.
func (n *node) checkTarget(address string) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(n.ctx, 5*time.Second)
	defer cancel()
	peers, err := n.peers(ctx)
	if err != nil {
		return err
	}
	_, peer, err := resolvePeer(host, peers)
	if err != nil {
		return err
	}
	return checkPeerOnline(peer)
}

func (n *node) removeForward(port int) error {
	n.mu.Lock()
	f, ok := n.forwards[port]
	delete(n.forwards, port)
	n.mu.Unlock()
	if !ok {
		return errNotFound
	}
	return f.Close()
}

func (n *node) close() {
	n.mu.Lock()
	if n.closed {
		n.mu.Unlock()
		return
	}
	n.closed = true
	fwds := n.forwards
	n.forwards = map[int]*Forwarder{}
	n.mu.Unlock()

	n.cancel() // breekt een lopende up af
	for _, f := range fwds {
		f.Close()
	}
	n.srv.Close()
	n.closer()
}

var (
	errClosed   = errors.New("netwerk is gesloten of het starten is geannuleerd")
	errTimeout  = errors.New("time-out bij verbinden met het tailnet")
	errNotFound = errors.New("forward niet gevonden")
)

// makeLogger: zonder logbestand wordt alles weggegooid; met logbestand altijd gefilterd op secrets.
func makeLogger(path string, r *redactor) (func(string, ...any), func()) {
	if path == "" {
		return func(string, ...any) {}, func() {}
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return func(string, ...any) {}, func() {}
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return func(string, ...any) {}, func() {}
	}
	var mu sync.Mutex
	closed := false
	logf := func(format string, args ...any) {
		line := r.redact(fmt.Sprintf(format, args...))
		mu.Lock()
		defer mu.Unlock()
		if !closed {
			fmt.Fprintf(f, "%s %s\n", time.Now().Format("2006-01-02 15:04:05.000"), line)
		}
	}
	return logf, func() {
		mu.Lock()
		closed = true
		f.Close()
		mu.Unlock()
	}
}
