#ifndef RUNNER_INSTALLER_HANDOVER_H_
#define RUNNER_INSTALLER_HANDOVER_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// The elevated installer signals this event before waiting for Caelo to exit.
// Keeping the loader unelevated also preserves Inno's original-user relaunch.
class InstallerHandover {
 public:
  explicit InstallerHandover(flutter::BinaryMessenger* messenger);
  ~InstallerHandover();

 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Release();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HANDLE ready_ = nullptr;
};

#endif  // RUNNER_INSTALLER_HANDOVER_H_
