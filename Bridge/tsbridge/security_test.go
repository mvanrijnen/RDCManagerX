package main

import (
	"io"
	"net"
	"net/netip"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestListenOnlyLoopback(t *testing.T) {
	for _, bad := range []string{"0.0.0.0:0", ":0", "192.168.1.10:0", "[::]:0", "[::1]:0", "[::ffff:127.0.0.1]:0", "localhost:0", "x"} {
		if err := validateLoopbackListen(bad); err == nil {
			t.Errorf("%q geaccepteerd", bad)
		}
		if f, err := StartForwarder(bad, "x:1", 0, plainDial, nil); err == nil {
			f.Close()
			t.Errorf("forwarder op %q gestart", bad)
		}
	}
	for _, good := range []string{"127.0.0.1:0", "127.0.0.2:0", "127.255.0.1:0"} {
		if err := validateLoopbackListen(good); err != nil {
			t.Errorf("%q geweigerd: %v", good, err)
		}
	}
}

func TestListenAddressWithoutPort(t *testing.T) {
	// De app gaf eerst "127.0.0.2" zonder poort door; dat moet ook werken (vrije poort).
	f, err := StartForwarder("127.0.0.2", "x:1", 0, plainDial, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if f.Port() == 0 {
		t.Fatal("geen poort")
	}
	if _, err := StartForwarder("0.0.0.0", "x:1", 0, plainDial, nil); err == nil {
		t.Fatal("0.0.0.0 zonder poort geaccepteerd")
	}
}

func TestPortIsExclusive(t *testing.T) {
	f, err := StartForwarder("127.0.0.2:0", "x:1", 0, plainDial, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	// Ook met SO_REUSEADDR mag een tweede socket de poort niet krijgen.
	if ln, err := net.Listen("tcp", "127.0.0.2:"+strconv.Itoa(f.Port())); err == nil {
		ln.Close()
		t.Fatal("poort kon nogmaals worden gebonden")
	}
}

func TestForwardAcceptsOwnProcess(t *testing.T) {
	target := echoServer(t)
	f, err := StartForwarder("127.0.0.2:0", target, uint32(osGetpid()), plainDial, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := net.Dial("tcp", net.JoinHostPort("127.0.0.2", strconv.Itoa(f.Port())))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.Write([]byte("hallo"))
	buf := make([]byte, 5)
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadFull(c, buf); err != nil || string(buf) != "hallo" {
		t.Fatalf("eigen proces niet doorgelaten: %v %q", err, buf)
	}
}

func TestForwardRejectsOtherProcess(t *testing.T) {
	target := echoServer(t)
	f, err := StartForwarder("127.0.0.2:0", target, uint32(osGetpid()), plainDial, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	// Een ander proces (PowerShell) verbindt en stuurt een byte; die mag niet terugkomen.
	script := `$c = New-Object Net.Sockets.TcpClient('127.0.0.2', ` + strconv.Itoa(f.Port()) + `); $s = $c.GetStream(); ` +
		`$s.ReadTimeout = 5000; $s.Write([byte[]](65), 0, 1); $b = New-Object byte[] 1; ` +
		`try { $n = $s.Read($b, 0, 1); if ($n -eq 1) { 'ECHO' } else { 'GESLOTEN' } } catch { 'GESLOTEN' }`
	out, err := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", script).CombinedOutput()
	if err != nil {
		t.Skipf("powershell niet beschikbaar: %v %s", err, out)
	}
	if strings.Contains(string(out), "ECHO") {
		t.Fatalf("ander proces kreeg toegang tot de tunnel: %s", out)
	}
	if !strings.Contains(string(out), "GESLOTEN") {
		t.Fatalf("onverwachte uitvoer: %s", out)
	}
}

func peersForTest() []tailnetPeer {
	return []tailnetPeer{
		{
			DNSName: "thuis-pc.tail1234.ts.net.", HostName: "THUIS-PC",
			IPs:    []netip.Addr{netip.MustParseAddr("100.101.102.103"), netip.MustParseAddr("fd7a:115c:a1e0::1")},
			Routes: []netip.Prefix{netip.MustParsePrefix("100.101.102.103/32"), netip.MustParsePrefix("192.168.50.0/24")},
		},
		{
			DNSName: "exit.tail1234.ts.net.", HostName: "exit",
			IPs:    []netip.Addr{netip.MustParseAddr("100.64.0.9")},
			Routes: []netip.Prefix{netip.MustParsePrefix("100.64.0.9/32"), netip.MustParsePrefix("0.0.0.0/0")},
		},
		{DNSName: "dubbel.tail1234.ts.net.", HostName: "server", IPs: []netip.Addr{netip.MustParseAddr("100.64.0.10")}},
		{DNSName: "server.tail1234.ts.net.", HostName: "anders", IPs: []netip.Addr{netip.MustParseAddr("100.64.0.11")}},
	}
}

func TestResolveInTailnet(t *testing.T) {
	peers := peersForTest()
	ok := map[string]string{
		"thuis-pc":                  "100.101.102.103",
		"THUIS-PC":                  "100.101.102.103",
		"thuis-pc.tail1234.ts.net":  "100.101.102.103",
		"thuis-pc.tail1234.ts.net.": "100.101.102.103",
		"100.101.102.103":           "100.101.102.103",
		"192.168.50.20":             "192.168.50.20", // goedgekeurde subnet-route
		"[fd7a:115c:a1e0::1]":       "fd7a:115c:a1e0::1",
	}
	for host, want := range ok {
		got, err := resolveInTailnet(host, peers)
		if err != nil || got.String() != want {
			t.Errorf("%q: %v %v, verwacht %s", host, got, err, want)
		}
	}
	bad := []string{
		"8.8.8.8",          // alleen via de exit-node-route 0.0.0.0/0: niet toegestaan
		"192.168.1.10",     // geen route
		"www.example.com",  // geen apparaat in het tailnet (en geen systeem-DNS)
		"onbekend",         // idem
		"server",           // twee apparaten: hostnaam van de een, eerste label van de ander
		"",                 // leeg
		"100.64.0.99",      // Tailscale-bereik, maar geen apparaat
	}
	for _, host := range bad {
		if got, err := resolveInTailnet(host, peers); err == nil {
			t.Errorf("%q opgelost naar %v, verwacht een fout", host, got)
		}
	}
}

func TestOfflinePeerGivesClearError(t *testing.T) {
	peers := peersForTest()
	peers[0].Online = false
	peers[0].LastSeen = time.Date(2026, 11, 25, 14, 3, 0, 0, time.Local)
	_, peer, err := resolvePeer("thuis-pc", peers)
	if err != nil {
		t.Fatal(err)
	}
	err = checkPeerOnline(peer)
	if err == nil || !strings.Contains(err.Error(), "thuis-pc is offline") || !strings.Contains(err.Error(), "25-11-2026 14:03") {
		t.Fatalf("onverwachte melding: %v", err)
	}
	if codeFor(err) != codeOffline {
		t.Fatalf("code %d", codeFor(err))
	}
	peers[0].Online = true
	_, peer, _ = resolvePeer("192.168.50.20", peers) // via de subnet-router
	if err := checkPeerOnline(peer); err != nil {
		t.Fatalf("online router gaf fout: %v", err)
	}
}

func TestControlURLMustBeHTTPS(t *testing.T) {
	for _, good := range []string{"", "https://hs.example.com", "https://hs.example.com:8443/", "http://localhost:8080", "http://127.0.0.1:8080"} {
		if err := validateControlURL(good); err != nil {
			t.Errorf("%q geweigerd: %v", good, err)
		}
	}
	for _, bad := range []string{"http://hs.example.com", "ftp://x", "hs.example.com", "file:///c:/x", "https://"} {
		if err := validateControlURL(bad); err == nil {
			t.Errorf("%q geaccepteerd", bad)
		}
	}
}
