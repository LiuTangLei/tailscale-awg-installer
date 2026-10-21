// Isolated Linux routing probe using the release's real netns socket hooks.
package main

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"strings"
	"syscall"
	"time"

	quic "github.com/quic-go/quic-go"
	"golang.org/x/sys/unix"
	"tailscale.com/net/netmon"
	"tailscale.com/net/netns"
)

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func cert() tls.Certificate {
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	must(err)
	t := &x509.Certificate{SerialNumber: big.NewInt(1), NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, t, t, &k.PublicKey, k)
	must(err)
	key, err := x509.MarshalECPrivateKey(k)
	must(err)
	c, err := tls.X509KeyPair(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: key}))
	must(err)
	return c
}
func serve(label string) {
	for _, family := range []string{"4", "6"} {
		addr := "0.0.0.0"
		if family == "6" {
			addr = "::"
		}
		u, err := net.ListenPacket("udp"+family, net.JoinHostPort(addr, "9000"))
		must(err)
		go func() {
			b := make([]byte, 4096)
			for {
				_, a, e := u.ReadFrom(b)
				if e != nil {
					return
				}
				u.WriteTo([]byte(label), a)
			}
		}()
		t, err := net.Listen("tcp"+family, net.JoinHostPort(addr, "9001"))
		must(err)
		go func() {
			for {
				c, e := t.Accept()
				if e != nil {
					return
				}
				go func() { defer c.Close(); c.Write([]byte(label)) }()
			}
		}()
		p, err := net.ListenPacket("udp"+family, net.JoinHostPort(addr, "9443"))
		must(err)
		tr := &quic.Transport{Conn: p}
		ln, err := tr.Listen(&tls.Config{Certificates: []tls.Certificate{cert()}, NextProtos: []string{"issue19"}}, nil)
		must(err)
		go func() {
			for {
				c, e := ln.Accept(context.Background())
				if e != nil {
					return
				}
				go func() {
					defer c.CloseWithError(0, "")
					s, e := c.AcceptStream(context.Background())
					if e != nil {
						return
					}
					io.ReadAll(s)
					s.Write([]byte(label))
					s.Close()
					time.Sleep(50 * time.Millisecond)
				}()
			}
		}()
	}
	fmt.Println("ready")
	select {}
}
func checkMark(c syscall.Conn) {
	r, err := c.SyscallConn()
	must(err)
	must(r.Control(func(fd uintptr) {
		m, e := unix.GetsockoptInt(int(fd), unix.SOL_SOCKET, unix.SO_MARK)
		must(e)
		if m != 0x80000 {
			panic(fmt.Sprintf("SO_MARK=%x", m))
		}
	}))
}

type result struct {
	Kind  string `json:"kind"`
	Label string `json:"label,omitempty"`
	Error string `json:"error,omitempty"`
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "serve" {
		serve(os.Args[2])
		return
	}
	m := netmon.NewStatic()
	defer m.Close()
	logf := func(string, ...any) {}
	lc := netns.Listener(logf, m)
	udp := map[string]net.PacketConn{}
	qt := map[string]*quic.Transport{}
	for _, f := range []string{"4", "6"} {
		a := "0.0.0.0:0"
		if f == "6" {
			a = "[::]:0"
		}
		p, e := lc.ListenPacket(context.Background(), "udp"+f, a)
		must(e)
		checkMark(p.(syscall.Conn))
		udp[f] = p
		q, e := lc.ListenPacket(context.Background(), "udp"+f, a)
		must(e)
		checkMark(q.(syscall.Conn))
		qt[f] = &quic.Transport{Conn: q}
	}
	d := netns.NewDialer(logf, m)
	sc := bufio.NewScanner(os.Stdin)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 2 {
			panic("expected kind address")
		}
		kind, host := fields[0], fields[1]
		f := kind[len(kind)-1:]
		r := result{Kind: kind}
		ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
		var err error
		switch {
		case strings.HasPrefix(kind, "plain"):
			var p net.PacketConn
			p, err = net.ListenPacket("udp"+f, ":0")
			if err == nil {
				p.SetDeadline(time.Now().Add(1500 * time.Millisecond))
				var a *net.UDPAddr
				a, err = net.ResolveUDPAddr("udp"+f, net.JoinHostPort(host, "9000"))
				if err == nil {
					_, err = p.WriteTo([]byte("plain"), a)
				}
				if err == nil {
					b := make([]byte, 32)
					var n int
					n, _, err = p.ReadFrom(b)
					r.Label = string(b[:n])
				}
				p.Close()
			}
		case strings.HasPrefix(kind, "udp"):
			p := udp[f]
			p.SetDeadline(time.Now().Add(1500 * time.Millisecond))
			var a *net.UDPAddr
			a, err = net.ResolveUDPAddr("udp"+f, net.JoinHostPort(host, "9000"))
			if err == nil {
				_, err = p.WriteTo([]byte("probe"), a)
			}
			if err == nil {
				b := make([]byte, 32)
				var n int
				n, _, err = p.ReadFrom(b)
				r.Label = string(b[:n])
			}
		case strings.HasPrefix(kind, "tcp"):
			var c net.Conn
			c, err = d.DialContext(ctx, "tcp"+f, net.JoinHostPort(host, "9001"))
			if err == nil {
				checkMark(c.(syscall.Conn))
				c.SetDeadline(time.Now().Add(1500 * time.Millisecond))
				var b []byte
				b, err = io.ReadAll(c)
				r.Label = string(b)
				c.Close()
			}
		case strings.HasPrefix(kind, "quic"):
			var a *net.UDPAddr
			a, err = net.ResolveUDPAddr("udp"+f, net.JoinHostPort(host, "9443"))
			if err == nil {
				var c *quic.Conn
				// This certificate bypass is confined to the network-less test fixture.
				c, err = qt[f].Dial(ctx, a, &tls.Config{InsecureSkipVerify: true, NextProtos: []string{"issue19"}}, nil)
				if err == nil {
					var s *quic.Stream
					s, err = c.OpenStreamSync(ctx)
					if err == nil {
						s.SetDeadline(time.Now().Add(1500 * time.Millisecond))
						_, err = s.Write([]byte("probe"))
						s.Close()
						if err == nil {
							var b []byte
							b, err = io.ReadAll(s)
							r.Label = string(b)
						}
					}
					c.CloseWithError(0, "")
				}
			}
		}
		cancel()
		if err != nil {
			r.Error = err.Error()
		}
		must(json.NewEncoder(os.Stdout).Encode(r))
	}
}
