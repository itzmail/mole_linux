// Package main provides the mo trash command for managing the XDG Trash
// on Linux, where there is no Finder to own this responsibility.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/tw93/mole/internal/xdgtrash"
)

func humanBytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	units := "KMGTPE"
	return fmt.Sprintf("%.1f %ciB", float64(n)/float64(div), units[exp])
}

func runList(w io.Writer) error {
	items, err := xdgtrash.List()
	if err != nil {
		return err
	}
	if len(items) == 0 {
		fmt.Fprintln(w, "Trash is empty.")
		return nil
	}

	total, err := xdgtrash.TotalSize()
	if err != nil {
		return err
	}
	fmt.Fprintf(w, "Trash: %s in %d item(s)\n\n", humanBytes(total), len(items))
	for _, item := range items {
		kind := "file"
		if item.IsDir {
			kind = "dir"
		}
		fmt.Fprintf(w, "  %-30s %8s  %s  (%s, deleted %s)\n",
			item.Name, humanBytes(item.Size), item.OriginalPath, kind,
			item.DeletedAt.Format("2006-01-02 15:04"))
	}
	return nil
}

func runEmptyAll() error {
	return xdgtrash.EmptyAll()
}

func runEmptyOne(name string) error {
	return xdgtrash.EmptyOne(name)
}

func main() {
	flag.Parse()
	args := flag.Args()

	var err error
	switch {
	case len(args) == 0:
		err = runList(os.Stdout)
	case args[0] == "empty" && len(args) == 1:
		err = runEmptyAll()
		if err == nil {
			fmt.Println("Trash emptied.")
		}
	case args[0] == "empty" && len(args) == 2:
		err = runEmptyOne(args[1])
		if err == nil {
			fmt.Printf("Removed %s from trash.\n", args[1])
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: mole trash [empty [<item-name>]]")
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
