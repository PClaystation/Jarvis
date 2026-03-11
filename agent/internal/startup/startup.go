package startup

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	currentTaskName = "CordycepsAgent"
	legacyTaskName  = "JarvisAgent"
	currentRunKey   = "CordycepsAgent"
	legacyRunKey    = "JarvisAgent"
)

func EnsureStartupRegistration(executablePath string) error {
	if runtime.GOOS != "windows" {
		return nil
	}

	if executablePath == "" {
		return fmt.Errorf("empty executable path")
	}

	taskCommand := hiddenLaunchCommand(executablePath)
	cmd := exec.Command(
		"schtasks",
		"/Create",
		"/TN",
		currentTaskName,
		"/SC",
		"ONLOGON",
		"/RL",
		"LIMITED",
		"/TR",
		taskCommand,
		"/F",
	)

	if _, err := cmd.CombinedOutput(); err == nil {
		cleanupLegacyStartupRegistration(false)
		return nil
	}

	// Fallback that works as standard user when Task Scheduler creation is blocked.
	if err := ensureRunKey(executablePath); err != nil {
		return err
	}

	cleanupLegacyStartupRegistration(true)
	return nil
}

func ensureRunKey(executablePath string) error {
	runValue := hiddenLaunchCommand(executablePath)
	cmd := exec.Command(
		"reg",
		"add",
		`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`,
		"/v",
		currentRunKey,
		"/t",
		"REG_SZ",
		"/d",
		runValue,
		"/f",
	)

	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("register startup run key: %w: %s", err, string(output))
	}

	return nil
}

func cleanupLegacyStartupRegistration(keepCurrentRunKey bool) {
	for _, name := range []string{legacyTaskName, "T1Agent", "E1Agent", "A1Agent"} {
		deleteScheduledTask(name)
	}

	if keepCurrentRunKey {
		for _, name := range []string{legacyRunKey, "T1Agent", "E1Agent", "A1Agent"} {
			deleteRunKeyValue(name)
		}
		return
	}

	for _, name := range []string{currentRunKey, legacyRunKey, "T1Agent", "E1Agent", "A1Agent"} {
		deleteRunKeyValue(name)
	}
}

func deleteScheduledTask(name string) {
	cmd := exec.Command("schtasks", "/Delete", "/TN", name, "/F")
	_, _ = cmd.CombinedOutput()
}

func deleteRunKeyValue(name string) {
	cmd := exec.Command(
		"reg",
		"delete",
		`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`,
		"/v",
		name,
		"/f",
	)
	_, _ = cmd.CombinedOutput()
}

func hiddenLaunchCommand(executablePath string) string {
	escapedPath := strings.ReplaceAll(executablePath, "'", "''")
	escapedDir := strings.ReplaceAll(filepath.Dir(executablePath), "'", "''")
	return fmt.Sprintf(
		`powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Process -WindowStyle Hidden -WorkingDirectory '%s' -FilePath '%s' -ArgumentList '--run-agent'"`,
		escapedDir,
		escapedPath,
	)
}
