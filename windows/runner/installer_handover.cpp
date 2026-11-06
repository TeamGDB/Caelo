#include "installer_handover.h"

#include <objbase.h>
#include <sddl.h>

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <string>
#include <utility>

#include "utils.h"

InstallerHandover::InstallerHandover(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "team.gdb.caelo/windows_updates",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}

InstallerHandover::~InstallerHandover() {
  channel_->SetMethodCallHandler(nullptr);
  Release();
}

void InstallerHandover::Release() {
  if (ready_) {
    ::CloseHandle(ready_);
    ready_ = nullptr;
  }
}

void InstallerHandover::Handle(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "prepare") {
    if (ready_) {
      result->Error("update_busy", "An installer is already starting.");
      return;
    }
    GUID guid;
    wchar_t identifier[40];
    if (FAILED(::CoCreateGuid(&guid)) ||
        ::StringFromGUID2(guid, identifier, 40) == 0) {
      result->Error("event_failed", "Cannot name the installer handover event.");
      return;
    }
    const std::wstring name = std::wstring(L"Local\\Caelo.UpdateReady.") + identifier;

    // An alternate administrator entered at UAC must be able to signal the
    // event too. Other authenticated users get only EVENT_MODIFY_STATE; the
    // random name belongs to this attempt and contains no commands or paths.
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!::ConvertStringSecurityDescriptorToSecurityDescriptorW(
            L"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;OW)(A;;0x0002;;;AU)",
            SDDL_REVISION_1, &descriptor, nullptr)) {
      result->Error("event_failed", "Cannot secure the installer handover event.");
      return;
    }
    SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
    ready_ = ::CreateEventW(&attributes, TRUE, FALSE, name.c_str());
    const DWORD error = ::GetLastError();
    ::LocalFree(descriptor);
    if (!ready_ || error == ERROR_ALREADY_EXISTS) {
      Release();
      result->Error("event_failed", "Cannot create the installer handover event.");
      return;
    }
    result->Success(flutter::EncodableValue(Utf8FromUtf16(name.c_str())));
    return;
  }
  if (call.method_name() == "isReady") {
    const auto* pid = call.arguments()
                          ? std::get_if<int32_t>(call.arguments())
                          : nullptr;
    if (!ready_ || !pid || *pid <= 0) {
      result->Error("invalid_handover", "No installer handover is active.");
      return;
    }
    if (::WaitForSingleObject(ready_, 0) == WAIT_OBJECT_0) {
      result->Success(flutter::EncodableValue(true));
      return;
    }
    // The unelevated Inno loader stays alive while its elevated child runs.
    // If it exits before signalling, UAC was cancelled or setup failed early.
    HANDLE process = ::OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(*pid));
    DWORD status;
    if (process) {
      const HANDLE handles[] = {ready_, process};
      status = ::WaitForMultipleObjects(2, handles, FALSE, 0);
      ::CloseHandle(process);
    } else {
      status = ::WaitForSingleObject(ready_, 0);
      if (status != WAIT_OBJECT_0) status = WAIT_FAILED;
    }
    if (status == WAIT_OBJECT_0 || status == WAIT_TIMEOUT) {
      result->Success(flutter::EncodableValue(status == WAIT_OBJECT_0));
    } else {
      result->Error("installer_stopped", "The installer exited before it was ready.");
    }
    return;
  }
  if (call.method_name() == "release") {
    Release();
    result->Success();
    return;
  }
  result->NotImplemented();
}
