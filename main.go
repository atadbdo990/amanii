package main

// Amani — config generator + xray supervisor
// @amona_mora

import (
	"log"
	"os"
	"os/exec"
	"os/signal"
	"regexp"
	"strings"
	"syscall"
	"time"
)

var safeRe = regexp.MustCompile(`^[A-Za-z0-9_./:@=-]*$`)

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

// Blocks JSON injection via environment variables (present in the original).
func safe(v, name string) string {
	if !safeRe.MatchString(v) {
		log.Fatalf("refusing unsafe %s: %q", name, v)
	}
	return v
}

func main() {
	tpl, err := os.ReadFile("/config.json.tpl")
	if err != nil {
		log.Fatalf("read template: %v", err)
	}

	repl := map[string]string{
		"__PROTO__":       safe(env("PROTO", "vless"), "PROTO"),
		"__USER_ID__":     safe(env("USER_ID", env("UUID", "")), "USER_ID"),
		"__WS_PATH__":     safe(env("WS_PATH", "/ws"), "WS_PATH"),
		"__NETWORK__":     "ws",
		"__PORT__":        env("PORT", "8080"),
		"__SPEED_LIMIT__": "0",
		"__HOST__":        safe(env("HOST", "localhost"), "HOST"),
		"__INBOUND_TAG__": safe(env("INBOUND_TAG", "amani-in"), "INBOUND_TAG"),
	}
	if repl["__USER_ID__"] == "" {
		log.Fatal("USER_ID is empty — refusing to start with no credential")
	}

	s := string(tpl)
	for k, v := range repl {
		s = strings.ReplaceAll(s, k, v)
	}

	// Atomic write, 0600 (the original used 0644)
	const out = "/tmp/config.json"
	if err := os.WriteFile(out+".new", []byte(s), 0600); err != nil {
		log.Fatalf("write config: %v", err)
	}
	if err := os.Rename(out+".new", out); err != nil {
		log.Fatalf("rename config: %v", err)
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	var cur *exec.Cmd
	go func() {
		<-stop
		log.Print("signal received, stopping xray")
		if cur != nil && cur.Process != nil {
			_ = cur.Process.Signal(syscall.SIGTERM)
		}
		time.Sleep(2 * time.Second)
		os.Exit(0)
	}()

	bin, err := exec.LookPath("xray")
	if err != nil {
		log.Fatalf("xray not in PATH: %v", err)
	}

	// Supervise + restart (the original leaves the service dead in silence)
	for {
		cur = exec.Command(bin, "run", "-config", out)
		cur.Stdout, cur.Stderr, cur.Stdin = os.Stdout, os.Stderr, os.Stdin
		start := time.Now()
		err := cur.Run()

		select {
		case <-stop:
			return
		default:
		}
		log.Printf("xray exited (%v), restarting", err)
		if time.Since(start) < 10*time.Second {
			time.Sleep(10 * time.Second) // backoff against a crash loop
		}
	}
}
