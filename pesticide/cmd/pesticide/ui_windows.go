//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

const (
	mbOK              = 0x00000000
	mbOKCancel        = 0x00000001
	mbIconInformation = 0x00000040
	mbIconWarning     = 0x00000030
	mbIconError       = 0x00000010
	idOK              = 1
)

var (
	user32ProcMessageBoxW = syscall.NewLazyDLL("user32.dll").NewProc("MessageBoxW")
)

func showInfoDialog(title string, message string) {
	messageBox(title, message, mbOK|mbIconInformation)
}

func showErrorDialog(title string, message string) {
	messageBox(title, message, mbOK|mbIconError)
}

func showConfirmDialog(title string, message string) bool {
	return messageBox(title, message, mbOKCancel|mbIconWarning) == idOK
}

func messageBox(title string, message string, style uintptr) uintptr {
	titlePtr := syscall.StringToUTF16Ptr(title)
	messagePtr := syscall.StringToUTF16Ptr(message)
	result, _, _ := user32ProcMessageBoxW.Call(
		0,
		uintptr(unsafe.Pointer(messagePtr)),
		uintptr(unsafe.Pointer(titlePtr)),
		style,
	)
	return result
}
