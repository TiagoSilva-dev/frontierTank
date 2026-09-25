package main

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"
)

// Passwords are stored as "pbkdf2-sha256$<rounds>$<salt>$<hash>" (base64 without padding),
// so the number of rounds can grow later without breaking old accounts.
const passwordScheme = "pbkdf2-sha256"

var b64 = base64.RawStdEncoding

func hashPassword(password string, rounds int) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, rounds, 32)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s$%d$%s$%s", passwordScheme, rounds, b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

func verifyPassword(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != passwordScheme {
		return false
	}
	rounds, err := strconv.Atoi(parts[1])
	if err != nil || rounds < 1 {
		return false
	}
	salt, err := b64.DecodeString(parts[2])
	if err != nil {
		return false
	}
	want, err := b64.DecodeString(parts[3])
	if err != nil {
		return false
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, rounds, len(want))
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare(key, want) == 1
}

func passwordRounds(encoded string) int {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 {
		return 0
	}
	rounds, _ := strconv.Atoi(parts[1])
	return rounds
}
