package main

// Beveiliging van de lokale forwards en de doelen:
//   - de listener mag alleen op een loopback-adres (nooit 0.0.0.0 of een LAN-adres);
//   - de poort wordt exclusief geclaimd (SO_EXCLUSIVEADDRUSE): een ander proces kan hem niet kapen;
//   - alleen verbindingen uit dit proces (de RDP-control draait in-process) worden doorgestuurd;
//   - doelen worden alleen binnen het tailnet opgelost (geen systeem-DNS, nooit buiten Tailscale om verbinden);
//   - een eigen control server moet https gebruiken (behalve naar localhost).

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// soExclusiveAddrUse = ~SO_REUSEADDR (winsock2.h).
const soExclusiveAddrUse = ^int(windows.SO_REUSEADDR)

// validateLoopbackListen: only an IPv4 loopback address (127.0.0.0/8) as listen address. IPv6 (::1) is refused:
// the owner check (ownerPidOfClient) only reads the IPv4 TCP table, so it could never accept a connection there.
func validateLoopbackListen(localAddr string) error {
	host, _, err := net.SplitHostPort(localAddr)
	if err != nil {
		return fmt.Errorf("ongeldig lokaal adres %q: %v", localAddr, err)
	}
	ip, err := netip.ParseAddr(host)
	if err != nil || !ip.Is4() || !ip.IsLoopback() {
		return fmt.Errorf("lokaal adres %q is geen IPv4-loopback-adres; alleen 127.x.x.x is toegestaan", host)
	}
	return nil
}

// listenExclusive opent een TCP-listener met SO_EXCLUSIVEADDRUSE.
func listenExclusive(localAddr string) (net.Listener, error) {
	lc := net.ListenConfig{
		Control: func(network, address string, c syscall.RawConn) error {
			var sockErr error
			err := c.Control(func(fd uintptr) {
				sockErr = windows.SetsockoptInt(windows.Handle(fd), windows.SOL_SOCKET, soExclusiveAddrUse, 1)
			})
			if err != nil {
				return err
			}
			return sockErr
		},
	}
	return lc.Listen(context.Background(), "tcp", localAddr)
}

var (
	modIphlpapi             = windows.NewLazySystemDLL("iphlpapi.dll")
	procGetExtendedTcpTable = modIphlpapi.NewProc("GetExtendedTcpTable")
)

const (
	afInet                      = 2
	tcpTableOwnerPidConnections = 4
)

// mibTcpRowOwnerPid = MIB_TCPROW_OWNER_PID (alle velden DWORD; adressen en poorten in netwerkvolgorde).
type mibTcpRowOwnerPid struct {
	State      uint32
	LocalAddr  uint32
	LocalPort  uint32
	RemoteAddr uint32
	RemotePort uint32
	OwningPid  uint32
}

// ownerPidOfClient zoekt het proces dat de clientkant van een geaccepteerde loopback-verbinding bezit.
// client = c.RemoteAddr() (de kant van de verbinder), server = c.LocalAddr() (onze listener).
func ownerPidOfClient(client, server *net.TCPAddr) (uint32, error) {
	c4, s4 := client.IP.To4(), server.IP.To4()
	if c4 == nil || s4 == nil {
		return 0, errors.New("alleen IPv4-loopback wordt ondersteund")
	}
	var size uint32
	for attempt := 0; attempt < 5; attempt++ {
		var buf []byte
		var ptr uintptr
		if size > 0 {
			buf = make([]byte, size)
			ptr = uintptr(unsafe.Pointer(&buf[0]))
		}
		r, _, _ := procGetExtendedTcpTable.Call(ptr, uintptr(unsafe.Pointer(&size)), 0, afInet, tcpTableOwnerPidConnections, 0)
		if r == uintptr(windows.ERROR_INSUFFICIENT_BUFFER) || buf == nil {
			continue
		}
		if r != 0 {
			return 0, fmt.Errorf("GetExtendedTcpTable: %v", syscall.Errno(r))
		}
		count := binary.LittleEndian.Uint32(buf[:4])
		rowSize := uint32(unsafe.Sizeof(mibTcpRowOwnerPid{}))
		for i := uint32(0); i < count; i++ {
			off := 4 + i*rowSize
			if off+rowSize > uint32(len(buf)) {
				break
			}
			row := (*mibTcpRowOwnerPid)(unsafe.Pointer(&buf[off]))
			if addrEqual(row.LocalAddr, c4) && portEqual(row.LocalPort, client.Port) &&
				addrEqual(row.RemoteAddr, s4) && portEqual(row.RemotePort, server.Port) {
				return row.OwningPid, nil
			}
		}
		return 0, errors.New("verbinding niet gevonden in de TCP-tabel")
	}
	return 0, errors.New("TCP-tabel kon niet worden gelezen")
}

func addrEqual(raw uint32, ip net.IP) bool {
	var b [4]byte
	binary.LittleEndian.PutUint32(b[:], raw) // in het geheugen staat het adres in netwerkvolgorde
	return b[0] == ip[0] && b[1] == ip[1] && b[2] == ip[2] && b[3] == ip[3]
}

func portEqual(raw uint32, port int) bool {
	var b [4]byte
	binary.LittleEndian.PutUint32(b[:], raw)
	return int(b[0])<<8|int(b[1]) == port
}

// connFromPid: komt de verbinding uit proces pid?
func connFromPid(c net.Conn, pid uint32) (bool, error) {
	client, ok1 := c.RemoteAddr().(*net.TCPAddr)
	server, ok2 := c.LocalAddr().(*net.TCPAddr)
	if !ok1 || !ok2 {
		return false, errors.New("geen TCP-verbinding")
	}
	owner, err := ownerPidOfClient(client, server)
	if err != nil {
		return false, err
	}
	return owner == pid, nil
}

// tailnetPeer: wat nodig is om een doel binnen het tailnet op te lossen.
type tailnetPeer struct {
	DNSName  string         // FQDN, met of zonder punt aan het eind
	HostName string         // hostnaam van het apparaat (chosen by the device itself)
	IPs      []netip.Addr   // Tailscale-adressen
	Routes   []netip.Prefix // AllowedIPs (eigen adressen + goedgekeurde subnet-routes)
	Online   bool           // verbonden met de control server
	LastSeen time.Time      // alleen bekend als het apparaat offline is
	Shared   bool           // shared into this tailnet from another one (not ours)
}

// resolveOptions: the explicit opt-ins of a tailnet (stored by RDCManagerX in its own settings, not in the file).
type resolveOptions struct {
	MatchHostName bool // also match the host name the device chose itself
	AllowShared   bool // also devices shared into this tailnet
}

// isSharedPeer: a device from another tailnet. Shared-in devices keep the MagicDNS domain of their own tailnet, and
// the control server reports who shared them (AltSharerUserID) or that they are only there because they were shared
// to us (ShareeNode). Those two flags count even when the MagicDNS suffix is unknown.
func isSharedPeer(dnsName, magicDNSSuffix string, altSharer, shareeNode bool) bool {
	if altSharer || shareeNode {
		return true
	}
	suffix := strings.ToLower(strings.Trim(magicDNSSuffix, "."))
	if suffix == "" {
		return false
	}
	return !strings.HasSuffix(strings.ToLower(strings.TrimSuffix(dnsName, ".")), "."+suffix)
}

// displayName: korte naam voor meldingen.
func (p tailnetPeer) displayName() string {
	if first, _, _ := strings.Cut(strings.TrimSuffix(p.DNSName, "."), "."); first != "" {
		return first
	}
	return p.HostName
}

// errOffline: het doel staat in het tailnet, maar is niet verbonden.
type errOffline struct{ msg string }

func (e errOffline) Error() string { return e.msg }

// checkPeerOnline geeft een duidelijke fout als het apparaat offline is.
func checkPeerOnline(p tailnetPeer) error {
	if p.Online {
		return nil
	}
	seen := "onbekend"
	if !p.LastSeen.IsZero() {
		seen = p.LastSeen.Local().Format("02-01-2006 15:04")
	}
	return errOffline{fmt.Sprintf("%s is offline in het tailnet (laatst gezien: %s). Staat Tailscale aan op dat apparaat?", p.displayName(), seen)}
}

// resolveInTailnet zet host om in een adres dat via het tailnet bereikbaar is. Een naam moet bij precies één
// apparaat horen: the full MagicDNS name or its first label (assigned by the control server, unique in the tailnet).
// The host name a device chose itself only counts with opts.MatchHostName: otherwise any device calling itself
// "srv" would win once the real server is gone or renamed. Devices shared in from another tailnet are skipped
// unless opts.AllowShared. Een IP moet een Tailscale-adres of in een goedgekeurde subnet-route liggen. Nooit
// systeem-DNS; nooit iets buiten het tailnet.
func resolveInTailnet(host string, peers []tailnetPeer, opts resolveOptions) (netip.Addr, error) {
	ip, _, err := resolvePeer(host, peers, opts)
	return ip, err
}

// resolvePeer: zoals resolveInTailnet, plus het apparaat dat het doel bedient (zelf, of de subnet-router).
func resolvePeer(host string, peers []tailnetPeer, opts resolveOptions) (netip.Addr, tailnetPeer, error) {
	if !opts.AllowShared {
		own := make([]tailnetPeer, 0, len(peers))
		for _, p := range peers {
			if !p.Shared {
				own = append(own, p)
			}
		}
		peers = own
	}
	return resolvePeerInner(host, peers, opts)
}

func resolvePeerInner(host string, peers []tailnetPeer, opts resolveOptions) (netip.Addr, tailnetPeer, error) {
	host = strings.TrimSuffix(strings.TrimSpace(host), ".")
	host = strings.TrimSuffix(strings.TrimPrefix(host, "["), "]")
	if host == "" {
		return netip.Addr{}, tailnetPeer{}, errors.New("geen doel opgegeven")
	}
	if ip, err := netip.ParseAddr(host); err == nil {
		ip = ip.Unmap()
		for _, p := range peers {
			for _, own := range p.IPs {
				if own == ip {
					return ip, p, nil
				}
			}
		}
		for _, p := range peers {
			for _, r := range p.Routes {
				// Een exit-node-route (0.0.0.0/0, ::/0) telt niet: dan zou alles "in het tailnet" liggen.
				if r.Bits() > 0 && r.Contains(ip) {
					return ip, p, nil
				}
			}
		}
		return netip.Addr{}, tailnetPeer{}, fmt.Errorf("%s is niet bereikbaar via dit tailnet (geen Tailscale-adres of goedgekeurde subnet-route)", host)
	}
	var matches []tailnetPeer
	for _, p := range peers {
		fqdn := strings.TrimSuffix(p.DNSName, ".")
		first, _, _ := strings.Cut(fqdn, ".")
		if (fqdn != "" && (strings.EqualFold(fqdn, host) || strings.EqualFold(first, host))) || (opts.MatchHostName && strings.EqualFold(p.HostName, host)) {
			matches = append(matches, p)
		}
	}
	switch len(matches) {
	case 0:
		if !opts.MatchHostName {
			for _, p := range peers {
				if strings.EqualFold(p.HostName, host) {
					return netip.Addr{}, tailnetPeer{}, fmt.Errorf("%q is geen MagicDNS-naam in dit tailnet; het apparaat %s noemt zichzelf zo. Gebruik de MagicDNS-naam (%s) of het 100.x-adres, of zet bij het Tailscale-netwerk \"ook op apparaatnaam zoeken\" aan", host, p.displayName(), strings.TrimSuffix(p.DNSName, "."))
				}
			}
		}
		return netip.Addr{}, tailnetPeer{}, fmt.Errorf("%q is geen apparaat in dit tailnet (controleer de naam of gebruik het 100.x-adres)", host)
	case 1:
	default:
		return netip.Addr{}, tailnetPeer{}, fmt.Errorf("%q komt bij meerdere apparaten in dit tailnet voor; gebruik de volledige MagicDNS-naam of het 100.x-adres", host)
	}
	for _, ip := range matches[0].IPs {
		if ip.Is4() {
			return ip, matches[0], nil
		}
	}
	if len(matches[0].IPs) > 0 {
		return matches[0].IPs[0], matches[0], nil
	}
	return netip.Addr{}, tailnetPeer{}, fmt.Errorf("%q heeft geen Tailscale-adres", host)
}

// validateControlURL: leeg (Tailscale), https://..., of http:// alleen naar localhost.
func validateControlURL(raw string) error {
	if raw == "" {
		return nil
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return fmt.Errorf("ongeldige control URL %q", raw)
	}
	switch strings.ToLower(u.Scheme) {
	case "https":
		return nil
	case "http":
		host := u.Hostname()
		if ip, err := netip.ParseAddr(host); (err == nil && ip.IsLoopback()) || strings.EqualFold(host, "localhost") { // DevSkim: ignore DS162092 (deliberate: plain http only to localhost)
			return nil
		}
		return errors.New("een control URL moet https gebruiken (http alleen naar localhost): anders kan de auth key onderweg worden onderschept") // DevSkim: ignore DS162092 (error text)
	default:
		return fmt.Errorf("control URL moet met https:// beginnen")
	}
}
