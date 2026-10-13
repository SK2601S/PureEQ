#include "flutter_window.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "media_control.h"

namespace {
// Posted by the capture thread when a new spectrum frame is ready.
constexpr UINT kSpectrumFrameMessage = WM_APP + 0x51;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetUpSpectrumChannel();
  SetUpMediaChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetUpSpectrumChannel() {
  spectrum_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "skeq/spectrum",
      &flutter::StandardMethodCodec::GetInstance());
  auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        spectrum_sink_ = std::move(events);
        audio_capture_.Start(GetHandle(), kSpectrumFrameMessage);
        return nullptr;
      },
      [this](const flutter::EncodableValue*)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        audio_capture_.Stop();
        spectrum_sink_.reset();
        return nullptr;
      });
  spectrum_channel_->SetStreamHandler(std::move(handler));
}

void FlutterWindow::SetUpMediaChannel() {
  media_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "skeq/media",
      &flutter::StandardMethodCodec::GetInstance());
  media_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& name = call.method_name();
        if (name != "playPause" && name != "next" && name != "previous" && name != "stop" &&
            name != "play" && name != "pause") {
          result->NotImplemented();
          return;
        }
        // Talks to Windows' "now playing" media session (works with
        // browsers); falls back to media keys. Asynchronous.
        media_control::Send(name);
        result->Success(flutter::EncodableValue(true));
      });
}

void FlutterWindow::OnDestroy() {
  audio_capture_.Stop();
  spectrum_sink_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kSpectrumFrameMessage:
      {
        // Forward the newest frame (Float32List of dBFS per bar) to Dart.
        // Always take it, even with no listener, so "pending" is cleared.
        std::vector<float> bars = audio_capture_.TakeLatest();
        if (spectrum_sink_ && !bars.empty()) {
          spectrum_sink_->Success(flutter::EncodableValue(std::move(bars)));
        }
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
