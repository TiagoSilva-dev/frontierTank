package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base32"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// TOTP (RFC 6238, the 6-digit codes of Google Authenticator, Authy, 1Password...) is the
// second factor of the staff accounts. The secret is kept encrypted: a copy of the database
// alone is not enough to produce codes.

const totpStep = 30

var totpEncoding = base32.StdEncoding.WithPadding(base32.NoPadding)

func newTOTPSecret() ([]byte, error) {
	secret := make([]byte, 20)
	_, err := rand.Read(secret)
	return secret, err
}

// hotp is RFC 4226 with 6 digits.
func hotp(secret []byte, counter int64) string {
	mac := hmac.New(sha1.New, secret)
	var buf [8]byte
	binary.BigEndian.PutUint64(buf[:], uint64(counter))
	mac.Write(buf[:])
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	value := (uint32(sum[offset])&0x7f)<<24 | uint32(sum[offset+1])<<16 | uint32(sum[offset+2])<<8 | uint32(sum[offset+3])
	return fmt.Sprintf("%06d", value%1000000)
}

// totpVerify accepts the code of the current 30 s step or the one before or after it (clock
// drift), but never a step at or before `last`: the same code is not valid twice. It returns
// the step to store.
func totpVerify(secret []byte, code string, now time.Time, last int64) (int64, bool) {
	code = strings.ReplaceAll(strings.TrimSpace(code), " ", "")
	if len(code) != 6 {
		return 0, false
	}
	current := now.Unix() / totpStep
	found := int64(0)
	for step := current - 1; step <= current+1; step++ {
		if step > last && hmac.Equal([]byte(hotp(secret, step)), []byte(code)) {
			found = step
		}
	}
	return found, found != 0
}

func totpURI(issuer, account string, secret []byte) string {
	label := url.PathEscape(issuer + ":" + account)
	query := url.Values{"secret": {totpEncoding.EncodeToString(secret)}, "issuer": {issuer}, "algorithm": {"SHA1"}, "digits": {"6"}, "period": {"30"}}
	return "otpauth://totp/" + label + "?" + query.Encode()
}

func totpKey(internalKey string) []byte {
	sum := sha256.Sum256([]byte("gustfire-admin-totp-v1:" + internalKey))
	return sum[:]
}

// sealSecret encrypts the secret for the database: "v1:" + base64(nonce + AES-GCM).
func sealSecret(key, secret []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	return "v1:" + base64.RawStdEncoding.EncodeToString(gcm.Seal(nonce, nonce, secret, nil)), nil
}

func openSecret(key []byte, sealed string) ([]byte, error) {
	data, ok := strings.CutPrefix(sealed, "v1:")
	if !ok {
		return nil, errors.New("unknown secret format")
	}
	raw, err := base64.RawStdEncoding.DecodeString(data)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(raw) < gcm.NonceSize() {
		return nil, errors.New("short secret")
	}
	return gcm.Open(nil, raw[:gcm.NonceSize()], raw[gcm.NonceSize():], nil)
}
