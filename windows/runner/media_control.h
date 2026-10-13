#ifndef RUNNER_MEDIA_CONTROL_H_
#define RUNNER_MEDIA_CONTROL_H_

#include <string>

// Media buttons for whatever is playing ("now playing" in Windows' media
// flyout): YouTube in Chrome/Edge, Spotify, VLC, …
//
// Uses Windows' System Media Transport Controls (SMTC) session of the
// current media app, which browsers support. Simulated media keys are only
// a fallback: they are not reliably routed to browsers when sent from our
// own window.
namespace media_control {

// command: "playPause", "play", "pause", "next", "previous", "stop".
// Runs asynchronously; returns immediately.
void Send(const std::string& command);

// For diagnostics: "<app id> | <playback status>" or "none".
std::string DescribeCurrentSession();

}  // namespace media_control

#endif  // RUNNER_MEDIA_CONTROL_H_
