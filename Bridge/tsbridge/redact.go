package main

// Secrets (auth keys) uit logregels filteren. Altijd toegepast, ook als debug-logging aan staat.

import (
	"regexp"
	"strings"
)

var tskeyPattern = regexp.MustCompile(`tskey-[A-Za-z0-9_-]+`)

type redactor struct {
	secrets []string
}

func newRedactor(secrets ...string) *redactor {
	r := &redactor{}
	for _, s := range secrets {
		if len(s) >= 6 {
			r.secrets = append(r.secrets, s)
		}
	}
	return r
}

func (r *redactor) redact(s string) string {
	for _, secret := range r.secrets {
		s = strings.ReplaceAll(s, secret, "***")
	}
	return tskeyPattern.ReplaceAllString(s, "tskey-***")
}
