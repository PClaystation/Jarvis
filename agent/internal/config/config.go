package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type Config struct {
	DeviceID         string `json:"device_id"`
	DeviceToken      string `json:"device_token"`
	ServerBaseURL    string `json:"server_base_url"`
	WSURL            string `json:"ws_url"`
	HeartbeatSeconds int    `json:"heartbeat_seconds"`
	Version          string `json:"version"`
}

func ResolveConfigPath() (string, error) {
	override := strings.TrimSpace(os.Getenv("CORDYCEPS_AGENT_CONFIG"))
	if override != "" {
		return override, nil
	}

	path, err := DefaultConfigPath()
	if err != nil {
		return "", err
	}

	if runtime.GOOS == "windows" {
		if err := migrateLegacyWindowsConfig(path); err != nil {
			return "", err
		}
	}

	return path, nil
}

func DefaultConfigPath() (string, error) {
	if runtime.GOOS == "windows" {
		appData := strings.TrimSpace(os.Getenv("APPDATA"))
		if appData == "" {
			return "", errors.New("APPDATA is not set")
		}

		return filepath.Join(appData, "CordycepsAgent", "config.json"), nil
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}

	return filepath.Join(homeDir, ".cordyceps-agent", "config.json"), nil
}

func LegacyConfigPath() (string, error) {
	if runtime.GOOS != "windows" {
		return "", nil
	}

	appData := strings.TrimSpace(os.Getenv("APPDATA"))
	if appData == "" {
		return "", errors.New("APPDATA is not set")
	}

	return filepath.Join(appData, "JarvisAgent", "config.json"), nil
}

func migrateLegacyWindowsConfig(targetPath string) error {
	legacyPath, err := LegacyConfigPath()
	if err != nil {
		return err
	}

	targetPath = filepath.Clean(targetPath)
	legacyPath = filepath.Clean(legacyPath)
	if strings.EqualFold(targetPath, legacyPath) {
		return nil
	}

	if _, err := os.Stat(targetPath); err == nil {
		return cleanupLegacyConfigIfDuplicate(targetPath, legacyPath)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("stat current config: %w", err)
	}

	if _, err := os.Stat(legacyPath); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return fmt.Errorf("stat legacy config: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(targetPath), 0o700); err != nil {
		return fmt.Errorf("create migrated config dir: %w", err)
	}

	if err := os.Rename(legacyPath, targetPath); err != nil {
		payload, readErr := os.ReadFile(legacyPath)
		if readErr != nil {
			return fmt.Errorf("read legacy config: %w", readErr)
		}

		if writeErr := os.WriteFile(targetPath, payload, 0o600); writeErr != nil {
			return fmt.Errorf("write migrated config: %w", writeErr)
		}

		_ = os.Remove(legacyPath)
	}

	removeDirIfEmpty(filepath.Dir(legacyPath))
	return nil
}

func cleanupLegacyConfigIfDuplicate(targetPath string, legacyPath string) error {
	legacyPayload, err := os.ReadFile(legacyPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read legacy config: %w", err)
	}

	targetPayload, err := os.ReadFile(targetPath)
	if err != nil {
		return fmt.Errorf("read current config: %w", err)
	}

	if string(targetPayload) != string(legacyPayload) {
		return nil
	}

	_ = os.Remove(legacyPath)
	removeDirIfEmpty(filepath.Dir(legacyPath))
	return nil
}

func removeDirIfEmpty(path string) {
	if strings.TrimSpace(path) == "" {
		return
	}

	entries, err := os.ReadDir(path)
	if err != nil || len(entries) != 0 {
		return
	}

	_ = os.Remove(path)
}

func Load(path string) (*Config, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := json.Unmarshal(payload, &cfg); err != nil {
		return nil, fmt.Errorf("parse config file: %w", err)
	}

	cfg.DeviceID = SanitizeDeviceID(cfg.DeviceID)
	cfg.DeviceToken = strings.TrimSpace(cfg.DeviceToken)
	cfg.ServerBaseURL = strings.TrimSuffix(strings.TrimSpace(cfg.ServerBaseURL), "/")
	cfg.WSURL = strings.TrimSpace(cfg.WSURL)
	cfg.Version = strings.TrimSpace(cfg.Version)

	if cfg.HeartbeatSeconds <= 0 {
		cfg.HeartbeatSeconds = 60
	}

	if cfg.DeviceToken == "" {
		return nil, errors.New("config missing device_token")
	}

	if cfg.ServerBaseURL == "" {
		return nil, errors.New("config missing server_base_url")
	}

	return &cfg, nil
}

func Save(path string, cfg *Config) error {
	cfg.DeviceID = SanitizeDeviceID(cfg.DeviceID)
	cfg.DeviceToken = strings.TrimSpace(cfg.DeviceToken)
	cfg.ServerBaseURL = strings.TrimSuffix(strings.TrimSpace(cfg.ServerBaseURL), "/")
	cfg.WSURL = strings.TrimSpace(cfg.WSURL)
	cfg.Version = strings.TrimSpace(cfg.Version)

	if cfg.HeartbeatSeconds <= 0 {
		cfg.HeartbeatSeconds = 60
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}

	payload, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("serialize config: %w", err)
	}

	tempPath := path + ".tmp"
	if err := os.WriteFile(tempPath, payload, 0o600); err != nil {
		return fmt.Errorf("write temp config: %w", err)
	}

	if err := os.Rename(tempPath, path); err != nil {
		_ = os.Remove(tempPath)
		return fmt.Errorf("replace config: %w", err)
	}

	return nil
}

func SanitizeDeviceID(input string) string {
	normalized := strings.ToLower(strings.TrimSpace(input))
	normalized = strings.ReplaceAll(normalized, " ", "-")

	builder := strings.Builder{}
	for _, r := range normalized {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			builder.WriteRune(r)
		}
	}

	result := builder.String()
	if len(result) > 32 {
		result = result[:32]
	}

	if len(result) < 2 {
		return "m1"
	}

	return result
}
