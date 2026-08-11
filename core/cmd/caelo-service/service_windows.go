//go:build windows

package main

import (
	"fmt"
	"os"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

// serviceName is what the Service Control Manager knows us as.
const serviceName = "Caelo"

// namedPipeEventGUID identifies the trigger that fires when a client opens a
// named pipe nobody is listening on.
//
// This is the Windows analogue of systemd's socket activation, and it is what
// lets the service not exist between connections: the Service Control Manager
// watches the name, and starting the service is its job rather than the app's.
// The app therefore needs no right to start services and no elevation.
//
// {1F81D131-3FAC-4537-9E0C-7E7B0C2F4B55}
var namedPipeEventGUID = windows.GUID{
	Data1: 0x1f81d131,
	Data2: 0x3fac,
	Data3: 0x4537,
	Data4: [8]byte{0x9e, 0x0c, 0x7e, 0x7b, 0x0c, 0x2f, 0x4b, 0x55},
}

const (
	serviceConfigTriggerInfo          = 8
	serviceTriggerTypeNetworkEndpoint = 6
	serviceTriggerActionServiceStart  = 1
	serviceTriggerDataTypeString      = 2
)

type serviceTriggerSpecificDataItem struct {
	DataType uint32
	DataSize uint32
	Data     *byte
}

type serviceTrigger struct {
	TriggerType    uint32
	Action         uint32
	TriggerSubtype *windows.GUID
	DataItemsCount uint32
	DataItems      *serviceTriggerSpecificDataItem
}

type serviceTriggerInfo struct {
	TriggersCount uint32
	Triggers      *serviceTrigger
	Reserved      *byte
}

// runAsService reports whether we were started by the Service Control Manager
// rather than from a command line, and runs the service loop if so.
//
// Returning false means "carry on as an ordinary program", which is how the
// same binary is used for development.
func runAsService(work func()) (bool, error) {
	inService, err := svc.IsWindowsService()
	if err != nil || !inService {
		return false, err
	}
	return true, svc.Run(serviceName, &handler{work: work})
}

type handler struct{ work func() }

func (h *handler) Execute(_ []string, requests <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	status <- svc.Status{State: svc.StartPending}
	go h.work()
	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}

	for request := range requests {
		switch request.Cmd {
		case svc.Interrogate:
			status <- request.CurrentStatus
		case svc.Stop, svc.Shutdown:
			status <- svc.Status{State: svc.StopPending}
			// The same path a signal takes on Linux: the tunnel comes down and
			// the routing goes back before the process does. Leaving a machine
			// pointed at an adapter that is about to vanish looks exactly like
			// the network dying for no reason.
			stopEverything("the service was stopped")
			return false, 0
		}
	}
	return false, 0
}

// install registers the service and asks the Service Control Manager to start
// it when somebody opens our pipe.
func install() error {
	executable, err := os.Executable()
	if err != nil {
		return err
	}

	manager, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("opening the service manager (this needs Administrator): %w", err)
	}
	defer manager.Disconnect()

	if existing, err := manager.OpenService(serviceName); err == nil {
		existing.Close()
		return fmt.Errorf("%s is already installed", serviceName)
	}

	service, err := manager.CreateService(serviceName, executable, mgr.Config{
		DisplayName: "Caelo tunnel service",
		Description: "Creates the tunnel adapter and routes this machine through it. " +
			"Runs only while a tunnel is up.",
		// Demand start, so nothing runs at boot. The trigger below is what
		// starts it, and the service exits again once the tunnel is down.
		StartType: mgr.StartManual,
	})
	if err != nil {
		return fmt.Errorf("creating the service: %w", err)
	}
	defer service.Close()

	if err := setPipeTrigger(service.Handle); err != nil {
		// The service is left installed: it works, it just has to be started by
		// hand. Removing it here would turn a degraded installation into no
		// installation at all.
		return fmt.Errorf("the service was installed but will not start on demand: %w", err)
	}
	return nil
}

// setPipeTrigger is the ChangeServiceConfig2 call that x/sys/windows/svc/mgr
// does not wrap.
func setPipeTrigger(service windows.Handle) error {
	// The trigger names the pipe without the \\.\pipe\ prefix, as a UTF-16
	// string including its terminator.
	name, err := windows.UTF16FromString(pipeTriggerName)
	if err != nil {
		return err
	}
	nameBytes := unsafe.Slice((*byte)(unsafe.Pointer(&name[0])), len(name)*2)

	item := serviceTriggerSpecificDataItem{
		DataType: serviceTriggerDataTypeString,
		DataSize: uint32(len(nameBytes)),
		Data:     &nameBytes[0],
	}
	trigger := serviceTrigger{
		TriggerType:    serviceTriggerTypeNetworkEndpoint,
		Action:         serviceTriggerActionServiceStart,
		TriggerSubtype: &namedPipeEventGUID,
		DataItemsCount: 1,
		DataItems:      &item,
	}
	info := serviceTriggerInfo{TriggersCount: 1, Triggers: &trigger}

	return windows.ChangeServiceConfig2(service, serviceConfigTriggerInfo, (*byte)(unsafe.Pointer(&info)))
}

// uninstall removes the service, stopping it first if it is running.
func uninstall() error {
	manager, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("opening the service manager (this needs Administrator): %w", err)
	}
	defer manager.Disconnect()

	service, err := manager.OpenService(serviceName)
	if err != nil {
		return fmt.Errorf("%s is not installed", serviceName)
	}
	defer service.Close()

	// Stopping it is what restores the machine's routing. Deleting a running
	// service leaves it running until it exits on its own, which for a tunnel
	// means until somebody reboots.
	if status, err := service.Query(); err == nil && status.State != svc.Stopped {
		if _, err := service.Control(svc.Stop); err != nil {
			return fmt.Errorf("stopping the service: %w", err)
		}
	}
	return service.Delete()
}

// pipeTriggerName is the pipe as the Service Control Manager wants it named in
// a trigger: without the \\.\pipe\ prefix that clients use.
const pipeTriggerName = "caelo"

// platformCommand handles `caelo-service install` and `caelo-service
// uninstall`, which the installer runs and a person can run by hand.
func platformCommand() (bool, error) {
	if len(os.Args) < 2 {
		return false, nil
	}
	switch os.Args[1] {
	case "install":
		return true, install()
	case "uninstall":
		return true, uninstall()
	}
	return false, nil
}

// runManaged hands the main goroutine to the Service Control Manager when it
// was the Service Control Manager that started us.
func runManaged(work func()) (bool, error) {
	return runAsService(work)
}

// mustBePrivileged has nothing to check.
//
// The service runs as LocalSystem because that is what the Service Control
// Manager was told to run it as, and a process started any other way cannot
// create an adapter regardless of what this function returns. Testing for
// "am I an administrator" would refuse to run in exactly the case that works.
func mustBePrivileged() error { return nil }
