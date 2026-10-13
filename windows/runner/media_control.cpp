#include "media_control.h"

#include <windows.h>

#include <thread>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>

namespace {

using winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSession;
using winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager;
using winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;

GlobalSystemMediaTransportControlsSession CurrentSession() {
  auto manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
  return manager.GetCurrentSession();
}

// True if the current media app accepted the command.
bool SendViaSmtc(const std::string& command) {
  try {
    auto session = CurrentSession();
    if (!session) return false;
    if (command == "playPause") return session.TryTogglePlayPauseAsync().get();
    if (command == "play") return session.TryPlayAsync().get();
    // "Stop" pauses: many players end their session on Stop, after which
    // Play can no longer resume.
    if (command == "pause" || command == "stop") return session.TryPauseAsync().get();
    if (command == "next") return session.TrySkipNextAsync().get();
    if (command == "previous") return session.TrySkipPreviousAsync().get();
  } catch (...) {
    // Media service unavailable — fall back to keys below.
  }
  return false;
}

void SendKey(WORD vk) {
  INPUT inputs[2] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = vk;
  inputs[1] = inputs[0];
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  ::SendInput(2, inputs, sizeof(INPUT));
}

}  // namespace

namespace media_control {

void Send(const std::string& command) {
  // WinRT async calls must not block the UI thread: run on a worker.
  std::thread([command] {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    if (!SendViaSmtc(command)) {
      // Fallback for apps without an SMTC session. Pause/stop are skipped:
      // a toggle key could start playback instead.
      if (command == "playPause") SendKey(VK_MEDIA_PLAY_PAUSE);
      else if (command == "next") SendKey(VK_MEDIA_NEXT_TRACK);
      else if (command == "previous") SendKey(VK_MEDIA_PREV_TRACK);
    }
    winrt::uninit_apartment();
  }).detach();
}

std::string DescribeCurrentSession() {
  try {
    auto session = CurrentSession();
    if (!session) return "none";
    const auto status = session.GetPlaybackInfo().PlaybackStatus();
    const char* text = status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing ? "playing"
                       : status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Paused ? "paused"
                                                                                                    : "other";
    return winrt::to_string(session.SourceAppUserModelId()) + " | " + text;
  } catch (...) {
    return "error";
  }
}

}  // namespace media_control
