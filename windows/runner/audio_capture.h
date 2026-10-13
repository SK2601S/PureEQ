#ifndef RUNNER_AUDIO_CAPTURE_H_
#define RUNNER_AUDIO_CAPTURE_H_

#include <windows.h>

#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

// Captures what is playing on the default output device (WASAPI loopback)
// and turns it into a log-frequency spectrum for the visualizer.
//
// Runs on its own thread. About 30 times a second it stores a new frame of
// per-bar levels (dBFS) and posts |message| to |target| so the platform
// thread can forward it to Dart. Silence (nothing playing) produces frames
// of very low values, so the bars fall to zero.
class AudioCapture {
 public:
  // Must match the visualizer's bar count and frequency axis (Dart side).
  static constexpr int kBarCount = 128;

  AudioCapture() = default;
  ~AudioCapture();

  AudioCapture(const AudioCapture&) = delete;
  AudioCapture& operator=(const AudioCapture&) = delete;

  void Start(HWND target, UINT message);
  void Stop();

  // Latest frame (dBFS per bar), or empty if none is pending.
  std::vector<float> TakeLatest();

 private:
  void Run();
  bool CaptureSession();  // false on error → retry
  void Analyze(int sample_rate);
  void PushSample(float sample);
  void Publish(std::vector<float> bars);

  std::thread thread_;
  std::atomic<bool> running_{false};
  HWND target_ = nullptr;
  UINT message_ = 0;

  std::mutex mutex_;
  std::vector<float> latest_;
  bool pending_ = false;

  // Mono ring buffer of the most recent samples.
  static constexpr int kFftSize = 4096;
  std::vector<float> ring_ = std::vector<float>(kFftSize, 0.0f);
  int ring_pos_ = 0;
};

#endif  // RUNNER_AUDIO_CAPTURE_H_
