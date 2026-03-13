package startup

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	currentTaskName         = "CordycepsAgent"
	currentBootTaskName     = "CordycepsAgentBoot"
	currentWatchdogTaskName = "CordycepsAgentWatchdog"
	currentRunKey           = "CordycepsAgent"
	launcherScriptName      = "cordyceps-agent-launcher.vbs"
)

func EnsureStartupRegistration(executablePath string) error {
	if runtime.GOOS != "windows" {
		return nil
	}

	if executablePath == "" {
		return fmt.Errorf("empty executable path")
	}

	taskCommand, err := ensureHiddenLauncher(executablePath)
	if err != nil {
		return fmt.Errorf("prepare startup launcher: %w", err)
	}
	registered := false
	registrationErrors := make([]string, 0, 4)

	if err := ensureScheduledTask(currentTaskName, taskCommand, []string{"/SC", "ONLOGON"}); err != nil {
		registrationErrors = append(registrationErrors, err.Error())
	} else {
		registered = true
	}

	if err := ensureScheduledTask(currentBootTaskName, taskCommand, []string{"/SC", "ONSTART"}); err != nil {
		registrationErrors = append(registrationErrors, err.Error())
	} else {
		registered = true
	}

	if err := ensureScheduledTask(currentWatchdogTaskName, taskCommand, []string{"/SC", "MINUTE", "/MO", "1"}); err != nil {
		registrationErrors = append(registrationErrors, err.Error())
	} else {
		registered = true
	}

	if err := ensureRunKey(executablePath); err != nil {
		registrationErrors = append(registrationErrors, err.Error())
	} else {
		registered = true
	}

	if registered {
		return nil
	}

	return fmt.Errorf("register startup launchers: %s", strings.Join(registrationErrors, "; "))
}

func ensureScheduledTask(taskName string, taskCommand string, scheduleArgs []string) error {
	args := []string{"/Create", "/TN", taskName}
	args = append(args, scheduleArgs...)
	args = append(args, "/RL", "LIMITED", "/TR", taskCommand, "/F")

	cmd := exec.Command("schtasks", args...)
	configureHiddenProcess(cmd)
	if output, err := cmd.CombinedOutput(); err != nil {
		trimmed := strings.TrimSpace(string(output))
		if trimmed == "" {
			return fmt.Errorf("register startup task %s: %w", taskName, err)
		}

		return fmt.Errorf("register startup task %s: %w: %s", taskName, err, trimmed)
	}

	return nil
}

func ensureRunKey(executablePath string) error {
	runValue, err := ensureHiddenLauncher(executablePath)
	if err != nil {
		return err
	}
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
	configureHiddenProcess(cmd)

	if output, err := cmd.CombinedOutput(); err != nil {
		trimmed := strings.TrimSpace(string(output))
		if trimmed == "" {
			return fmt.Errorf("register startup run key: %w", err)
		}

		return fmt.Errorf("register startup run key: %w: %s", err, trimmed)
	}

	return nil
}

func ensureHiddenLauncher(executablePath string) (string, error) {
	scriptPath := filepath.Join(filepath.Dir(executablePath), launcherScriptName)
	script := fmt.Sprintf(
		"Set shell = CreateObject(%s)\r\nshell.CurrentDirectory = %s\r\nshell.Run %s, 0, False\r\n",
		vbsStringLiteral("WScript.Shell"),
		vbsStringLiteral(filepath.Dir(executablePath)),
		vbsStringLiteral(fmt.Sprintf("\"%s\" --run-agent", executablePath)),
	)

	if err := os.WriteFile(scriptPath, []byte(script), 0o600); err != nil {
		return "", err
	}

	return fmt.Sprintf(`wscript.exe //B //NoLogo "%s"`, scriptPath), nil
}

func vbsStringLiteral(value string) string {
	return `"` + strings.ReplaceAll(value, `"`, `""`) + `"`
}
