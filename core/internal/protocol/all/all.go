// Package all registers every protocol this build carries besides AmneziaWG.
//
// Imported for its side effect by whatever runs nodes. A new protocol is a
// line here.
package all

import (
	_ "github.com/TeamGDB/Caelo/core/internal/vless"
)
