package vless

import (
	xlog "github.com/xtls/xray-core/common/log"

	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// logHandler sends Xray's messages to the core's ring, where every other line
// the core writes goes and where redaction happens.
//
// Errors and warnings only. Access lines and Xray's info lines — every
// destination someone visited — never: they are the browsing history of the
// person holding the phone, and a diagnostic log is something people send to
// strangers.
type logHandler struct{}

func (logHandler) Handle(message xlog.Message) {
	general, ok := message.(*xlog.GeneralMessage)
	if !ok {
		return
	}
	switch general.Severity {
	case xlog.Severity_Error, xlog.Severity_Warning:
		diag.Logf("xray: %s", general.String())
	}
}

// Severity tells Xray what is wanted before it builds a message, so that the
// debug and info lines it would otherwise format on every connection — with
// the caller's frame, and with the destination in them — are never made.
// Warnings and errors only, verbose or not: Xray's info lines name the sites
// a person visits, which a diagnostic log is no place for.
func (logHandler) Severity() xlog.Severity { return xlog.Severity_Warning }

// installLogHandler is global in Xray, so it is global here: the last
// registration wins, and every instance makes one.
func installLogHandler() {
	xlog.RegisterHandler(logHandler{})
}
