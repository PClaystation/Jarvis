//go:build !windows

package main

import "fmt"

func showInfoDialog(title string, message string) {
	fmt.Printf("%s\n\n%s\n", title, message)
}

func showErrorDialog(title string, message string) {
	fmt.Printf("%s\n\n%s\n", title, message)
}

func showConfirmDialog(title string, message string) bool {
	fmt.Printf("%s\n\n%s\n", title, message)
	return true
}
