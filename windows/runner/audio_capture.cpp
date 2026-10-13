#include "audio_capture.h"

#include <audioclient.h>
#include <mmdeviceapi.h>

#include <algorithm>
#include <cmath>
#include <complex>
#include <string>

namespace {

constexpr double kPi = 3.14159265358979323846;

// Same axis as the Dart visualizer: 10 octaves starting half an octave
// below 31.25 Hz, so each EQ band sits in the middle of one column.
constexpr double kAxisMinHz = 31.25 / 1.4142135623730951;
constexpr double kAxisOctaves = 10.0;

// How often a new spectrum frame is produced.
constexpr ULONGLONG kFrameMs = 33;

template <typename T>
void SafeRelease(T** p) {
  if (*p) {
    (*p)->Release();
    *p = nullptr;
  }
}

// In-place iterative radix-2 FFT.
void Fft(std::vector<std::complex<double>>& a) {
  const size_t n = a.size();
  for (size_t i = 1, j = 0; i < n; ++i) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) std::swap(a[i], a[j]);
  }
  for (size_t len = 2; len <= n; len <<= 1) {
    const double angle = -2 * kPi / static_cast<double>(len);
    const std::complex<double> wlen(std::cos(angle), std::sin(angle));
    for (size_t i = 0; i < n; i += len) {
      std::complex<double> w(1);
      for (size_t k = 0; k < len / 2; ++k) {
        const auto u = a[i + k];
        const auto v = a[i + k + len / 2] * w;
        a[i + k] = u + v;
        a[i + k + len / 2] = u - v;
        w *= wlen;
      }
    }
  }
}

std::wstring DefaultDeviceId(IMMDeviceEnumerator* enumerator) {
  IMMDevice* device = nullptr;
  std::wstring id;
  if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    LPWSTR raw = nullptr;
    if (SUCCEEDED(device->GetId(&raw))) {
      id = raw;
      CoTaskMemFree(raw);
    }
    device->Release();
  }
  return id;
}

}  // namespace

AudioCapture::~AudioCapture() { Stop(); }

void AudioCapture::Start(HWND target, UINT message) {
  if (running_) return;
  target_ = target;
  message_ = message;
  running_ = true;
  thread_ = std::thread([this] { Run(); });
}

void AudioCapture::Stop() {
  running_ = false;
  if (thread_.joinable()) thread_.join();
}

std::vector<float> AudioCapture::TakeLatest() {
  std::lock_guard<std::mutex> lock(mutex_);
  pending_ = false;
  return std::move(latest_);
}

void AudioCapture::Run() {
  ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  while (running_) {
    if (!CaptureSession()) {
      // Device unplugged / audio service restarting: retry shortly.
      for (int i = 0; i < 10 && running_; ++i) ::Sleep(100);
    }
  }
  ::CoUninitialize();
}

// One capture session on the current default output device. Returns true
// when the default device changed (restart on the new one), false on error.
bool AudioCapture::CaptureSession() {
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  WAVEFORMATEX* format = nullptr;
  bool ok = false;

  do {
    if (FAILED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                  __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&enumerator)))) break;
    if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) break;
    const std::wstring device_id = DefaultDeviceId(enumerator);
    if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(&client)))) break;
    if (FAILED(client->GetMixFormat(&format))) break;
    if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                                  2000000 /* 200 ms */, 0, format, nullptr))) break;
    if (FAILED(client->GetService(__uuidof(IAudioCaptureClient),
                                  reinterpret_cast<void**>(&capture)))) break;
    if (FAILED(client->Start())) break;

    // Sample format: shared-mode mix formats are almost always 32-bit float;
    // 16/32-bit integer PCM is handled too.
    WORD tag = format->wFormatTag;
    if (tag == WAVE_FORMAT_EXTENSIBLE) {
      tag = static_cast<WORD>(reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format)->SubFormat.Data1);
    }
    const bool is_float = tag == WAVE_FORMAT_IEEE_FLOAT;
    const int bits = format->wBitsPerSample;
    const int channels = format->nChannels;
    const int rate = static_cast<int>(format->nSamplesPerSec);

    ULONGLONG last_frame = ::GetTickCount64();
    ULONGLONG last_packet = last_frame;
    ULONGLONG last_device_check = last_frame;
    ok = true;

    while (running_) {
      ::Sleep(10);
      const ULONGLONG now = ::GetTickCount64();

      UINT32 packet = 0;
      HRESULT hr = capture->GetNextPacketSize(&packet);
      if (FAILED(hr)) { ok = false; break; }
      while (packet > 0) {
        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        hr = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
        if (FAILED(hr)) { ok = false; break; }
        const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
        for (UINT32 f = 0; f < frames; ++f) {
          float mono = 0;
          if (!silent) {
            for (int c = 0; c < channels; ++c) {
              const int i = static_cast<int>(f) * channels + c;
              if (is_float && bits == 32) {
                mono += reinterpret_cast<const float*>(data)[i];
              } else if (bits == 16) {
                mono += reinterpret_cast<const int16_t*>(data)[i] / 32768.0f;
              } else if (bits == 32) {
                mono += reinterpret_cast<const int32_t*>(data)[i] / 2147483648.0f;
              }
            }
            mono /= static_cast<float>(channels);
          }
          PushSample(mono);
        }
        capture->ReleaseBuffer(frames);
        last_packet = now;
        hr = capture->GetNextPacketSize(&packet);
        if (FAILED(hr)) { ok = false; break; }
      }
      if (!ok) break;

      // Nothing playing: Windows delivers no packets at all, so feed
      // silence ourselves and let the bars fall.
      if (now - last_packet > 30) {
        const int fill = static_cast<int>(rate * 10 / 1000);
        for (int i = 0; i < fill; ++i) PushSample(0);
      }

      if (now - last_frame >= kFrameMs) {
        last_frame = now;
        Analyze(rate);
      }

      // Follow the default device (e.g. EarPods plugged in / out).
      if (now - last_device_check > 1000) {
        last_device_check = now;
        if (DefaultDeviceId(enumerator) != device_id) break;
      }
    }
    client->Stop();
  } while (false);

  if (format) ::CoTaskMemFree(format);
  SafeRelease(&capture);
  SafeRelease(&client);
  SafeRelease(&device);
  SafeRelease(&enumerator);
  return ok;
}

void AudioCapture::PushSample(float sample) {
  ring_[ring_pos_] = sample;
  ring_pos_ = (ring_pos_ + 1) % kFftSize;
}

void AudioCapture::Analyze(int sample_rate) {
  // Windowed FFT of the most recent kFftSize samples.
  std::vector<std::complex<double>> spectrum(kFftSize);
  for (int i = 0; i < kFftSize; ++i) {
    const double hann = 0.5 * (1 - std::cos(2 * kPi * i / (kFftSize - 1)));
    spectrum[i] = ring_[(ring_pos_ + i) % kFftSize] * hann;
  }
  Fft(spectrum);

  // Amplitude per bin (a full-scale sine reads ~1.0 = 0 dBFS).
  const int half = kFftSize / 2;
  std::vector<double> amp(half);
  for (int k = 0; k < half; ++k) amp[k] = std::abs(spectrum[k]) * 4.0 / kFftSize;

  const double bin_hz = static_cast<double>(sample_rate) / kFftSize;
  std::vector<float> bars(kBarCount);
  for (int j = 0; j < kBarCount; ++j) {
    const double f_lo = kAxisMinHz * std::pow(2.0, kAxisOctaves * j / kBarCount);
    const double f_hi = kAxisMinHz * std::pow(2.0, kAxisOctaves * (j + 1) / kBarCount);
    const double f_mid = std::sqrt(f_lo * f_hi);
    double value = 0;
    const double k_lo = f_lo / bin_hz;
    const double k_hi = f_hi / bin_hz;
    if (k_hi - k_lo < 1.0) {
      // Narrower than one bin (low frequencies): interpolate.
      const double k = f_mid / bin_hz;
      const int k0 = static_cast<int>(k);
      const double t = k - k0;
      if (k0 + 1 < half) value = amp[k0] * (1 - t) + amp[k0 + 1] * t;
    } else {
      for (int k = static_cast<int>(std::ceil(k_lo)); k <= static_cast<int>(k_hi) && k < half; ++k) {
        value = std::max(value, amp[k]);
      }
    }
    // dBFS, tilted +3 dB/octave around 1 kHz so typical music (which falls
    // ~3 dB/octave) looks balanced across the range, like most analyzers.
    const double db = 20.0 * std::log10(value + 1e-9) + 3.0 * std::log2(f_mid / 1000.0);
    bars[j] = static_cast<float>(db);
  }
  Publish(std::move(bars));
}

void AudioCapture::Publish(std::vector<float> bars) {
  bool notify = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    latest_ = std::move(bars);
    notify = !pending_;
    pending_ = true;
  }
  if (notify && target_) ::PostMessage(target_, message_, 0, 0);
}
