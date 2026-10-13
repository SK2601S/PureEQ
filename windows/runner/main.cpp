#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// SK EQ runs as a single instance: launching it again (Start menu, desktop
// icon) brings the running window back — even when it is hidden in the
// tray — instead of starting a second copy. Two copies would fight over the
// audio settings, and an update could not replace files the other one uses.
static bool ActivateExistingInstance() {
  ::CreateMutexW(nullptr, TRUE, L"Local\\SKEQ-SingleInstance");
  const DWORD error = ::GetLastError();
  if (error != ERROR_ALREADY_EXISTS && error != ERROR_ACCESS_DENIED) {
    return false;  // We are the first instance; keep the mutex until exit.
  }
  HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"SK EQ");
  if (existing != nullptr) {
    ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
    ::SetForegroundWindow(existing);
  }
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (ActivateExistingInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SK EQ", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
