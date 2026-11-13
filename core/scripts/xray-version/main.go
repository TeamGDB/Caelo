// Command xray-version prints the Xray-core release linked into the core, as
// Xray reports it. Used by scripts/update-xray.sh to check that the commit it
// pinned is the release it was asked for.
package main

import (
	"fmt"

	"github.com/xtls/xray-core/core"
)

func main() { fmt.Println(core.Version()) }
