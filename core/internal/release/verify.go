// Package release verifies that a downloaded file came from the release
// pipeline.
//
// This is not the operating system's signature check and does not replace it.
// Gatekeeper and Authenticode answer "may this run here"; this answers "did we
// produce it". They are issued by different authorities and fail independently,
// which is the point: on Windows there is no Authenticode signature at all, so
// this is the only thing standing between somebody and a substituted installer.
package release

import (
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
)

// ErrUntrusted is returned when a file is not signed by any key we trust.
//
// One error for every way of failing, deliberately. "Wrong signature", "unknown
// key" and "truncated file" are the same event from the point of view of
// somebody deciding whether to install: the file is not ours. Distinguishing
// them in the message would help whoever is trying combinations far more than it
// helps anyone else.
var ErrUntrusted = errors.New("this file was not signed by Caelo")

// Trusted is a set of public keys, any one of which may have signed a release.
//
// More than one, from the first release onwards, and that is the whole design.
// A single key cannot be replaced: adding a second one requires shipping an
// update, and shipping an update requires the key you no longer have. Whereas
// two keys can be rotated — sign with the spare, then release a build whose set
// drops the lost one and adds a fresh spare.
//
// So the second key is not a convenience. It is the difference between a lost
// key being an afternoon and being the end of updates for everyone who already
// installed.
type Trusted []ed25519.PublicKey

// ParseTrusted reads base64 public keys, as they appear in the app and in
// docs/updates.md.
func ParseTrusted(encoded []string) (Trusted, error) {
	keys := make(Trusted, 0, len(encoded))
	for _, value := range encoded {
		raw, err := base64.StdEncoding.DecodeString(value)
		if err != nil {
			return nil, fmt.Errorf("key %q is not base64: %w", value, err)
		}
		if len(raw) != ed25519.PublicKeySize {
			return nil, fmt.Errorf("key %q is %d bytes, want %d", value, len(raw), ed25519.PublicKeySize)
		}
		keys = append(keys, ed25519.PublicKey(raw))
	}
	if len(keys) == 0 {
		// An empty set would verify nothing and reject everything, which is
		// safe, or -- with one wrong `len` check elsewhere -- accept everything,
		// which is not. Refusing to build one removes the question.
		return nil, errors.New("no trusted keys")
	}
	return keys, nil
}

// VerifyFile reports whether the file at path carries a signature made by one of
// the trusted keys.
func VerifyFile(path string, signature string, keys Trusted) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()

	// Read it whole. Ed25519 is not a streaming construction: it needs the
	// message before it can say anything, and a release artifact is a file
	// somebody just downloaded, so it is already on disk and already this size.
	contents, err := io.ReadAll(file)
	if err != nil {
		return err
	}
	return Verify(contents, signature, keys)
}

// Verify reports whether message carries a signature made by one of the trusted
// keys.
func Verify(message []byte, signature string, keys Trusted) error {
	raw, err := base64.StdEncoding.DecodeString(signature)
	if err != nil {
		return ErrUntrusted
	}
	if len(raw) != ed25519.SignatureSize {
		return ErrUntrusted
	}

	// Every key is tried, and the loop does not stop early on success, so that
	// the time taken does not depend on which key matched. That leaks little
	// here -- the keys are public and the set is tiny -- but a verifier whose
	// timing describes its own state is a habit worth not forming.
	accepted := false
	for _, key := range keys {
		if ed25519.Verify(key, message, raw) {
			accepted = true
		}
	}
	if !accepted {
		return ErrUntrusted
	}
	return nil
}
