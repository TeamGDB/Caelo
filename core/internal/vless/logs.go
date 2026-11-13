package vless

import (
	xlog "github.com/xtls/xray-core/common/log"

	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// logHandler sends Xray's messages to the core's ring, where every other line
// the core writes goes and where redaction happens.
//
// Errors and warnings always; the rest only when someone asked for detail.
// Access lines — every destination someone visited — never: they are the
// browsing history of the person holding the phone, and a diagnostic log is
// something people send to strangers.
type logHandler struct{}

func (logHandler) Handle(message xlog.Message) {
	general, ok := message.(*xlog.GeneralMessage)
	if !ok {
		return
	}
	switch general.Severity {
	case xlog.Severity_Error, xlog.Severity_Warning:
	default:
		if !diag.Verbose() {
			return
		}
	}
	diag.Logf("xray: %s", general.String())
}

// installLogHandler is global in Xray, so it is global here: the last
// registration wins, and every instance makes one.
func installLogHandler() {
	xlog.RegisterHandler(logHandler{})
}
