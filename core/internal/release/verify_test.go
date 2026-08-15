package release

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func newKey(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey) {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return public, private
}

func sign(private ed25519.PrivateKey, message []byte) string {
	return base64.StdEncoding.EncodeToString(ed25519.Sign(private, message))
}

func encode(key ed25519.PublicKey) string {
	return base64.StdEncoding.EncodeToString(key)
}

// The property the whole design rests on: a build signed with the spare key is
// accepted by an installation that has never seen it used. Without this, losing
// the active key ends updates for everyone who already installed -- adding a
// second key would need an update signed with the key that is gone.
func TestEitherTrustedKeyIsAccepted(t *testing.T) {
	t.Parallel()

	activePublic, activePrivate := newKey(t)
	sparePublic, sparePrivate := newKey(t)

	keys, err := ParseTrusted([]string{encode(activePublic), encode(sparePublic)})
	if err != nil {
		t.Fatal(err)
	}

	message := []byte("a release nobody has seen yet")
	for name, private := range map[string]ed25519.PrivateKey{
		"the key in use": activePrivate,
		"the spare":      sparePrivate,
	} {
		if err := Verify(message, sign(private, message), keys); err != nil {
			t.Errorf("%s was rejected: %v", name, err)
		}
	}
}

func TestAKeyWeDoNotTrustIsRejected(t *testing.T) {
	t.Parallel()

	trustedPublic, _ := newKey(t)
	_, strangerPrivate := newKey(t)

	keys, err := ParseTrusted([]string{encode(trustedPublic)})
	if err != nil {
		t.Fatal(err)
	}

	message := []byte("a release")
	if err := Verify(message, sign(strangerPrivate, message), keys); !errors.Is(err, ErrUntrusted) {
		t.Errorf("a signature from an unknown key was accepted: %v", err)
	}
}

// The case this exists for. A signature that verifies against a file which is
// not the file we published would make the whole mechanism decorative.
func TestOneChangedByteIsRejected(t *testing.T) {
	t.Parallel()

	public, private := newKey(t)
	keys, err := ParseTrusted([]string{encode(public)})
	if err != nil {
		t.Fatal(err)
	}

	original := []byte("the installer we published")
	signature := sign(private, original)

	tampered := append([]byte(nil), original...)
	tampered[3] ^= 0x01

	if err := Verify(tampered, signature, keys); !errors.Is(err, ErrUntrusted) {
		t.Errorf("a modified file was accepted: %v", err)
	}
	if err := Verify(original, signature, keys); err != nil {
		t.Fatalf("the test is broken: the original does not verify: %v", err)
	}
}

func TestRubbishSignaturesAreRejectedRatherThanCrashing(t *testing.T) {
	t.Parallel()

	public, _ := newKey(t)
	keys, err := ParseTrusted([]string{encode(public)})
	if err != nil {
		t.Fatal(err)
	}

	// ed25519.Verify panics on a key of the wrong length; a signature of the
	// wrong length it merely rejects. Both arrive from a network, so both are
	// checked before they reach it.
	for _, signature := range []string{"", "not base64 at all!!", "c2hvcnQ=", encode(public)} {
		if err := Verify([]byte("x"), signature, keys); !errors.Is(err, ErrUntrusted) {
			t.Errorf("signature %q gave %v, want ErrUntrusted", signature, err)
		}
	}
}

func TestAnEmptyTrustSetIsRefusedRatherThanBuilt(t *testing.T) {
	t.Parallel()

	if _, err := ParseTrusted(nil); err == nil {
		t.Error("an empty set of trusted keys was accepted")
	}
	if _, err := ParseTrusted([]string{"not base64"}); err == nil {
		t.Error("a key that is not base64 was accepted")
	}
	// A key of the wrong length would make ed25519.Verify panic rather than
	// return false, so it has to be caught here and not later.
	if _, err := ParseTrusted([]string{base64.StdEncoding.EncodeToString([]byte("short"))}); err == nil {
		t.Error("a key of the wrong length was accepted")
	}
}

func TestVerifyFileReadsWhatIsOnDisk(t *testing.T) {
	t.Parallel()

	public, private := newKey(t)
	keys, err := ParseTrusted([]string{encode(public)})
	if err != nil {
		t.Fatal(err)
	}

	contents := []byte("a downloaded installer")
	path := filepath.Join(t.TempDir(), "Caelo-setup.exe")
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}

	if err := VerifyFile(path, sign(private, contents), keys); err != nil {
		t.Errorf("a file we signed was rejected: %v", err)
	}

	if err := os.WriteFile(path, append(contents, '!'), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := VerifyFile(path, sign(private, contents), keys); !errors.Is(err, ErrUntrusted) {
		t.Error("a file that changed after signing was accepted")
	}
}
