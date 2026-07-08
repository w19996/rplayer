#include "flutter_window.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <windows.h>
#include <wrl/client.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

using Microsoft::WRL::ComPtr;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

std::vector<uint8_t> JpegBytesFromBitmap(HBITMAP bitmap) {
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    return {};
  }

  ComPtr<IWICBitmap> source;
  if (FAILED(factory->CreateBitmapFromHBITMAP(
          bitmap, nullptr, WICBitmapUsePremultipliedAlpha, &source))) {
    return {};
  }

  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(source.Get(), GUID_WICPixelFormat24bppBGR,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return {};
  }

  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    return {};
  }

  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr,
                                    &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return {};
  }

  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> properties;
  if (FAILED(encoder->CreateNewFrame(&frame, &properties)) ||
      FAILED(frame->Initialize(properties.Get()))) {
    return {};
  }

  UINT width = 0;
  UINT height = 0;
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  if (FAILED(converter->GetSize(&width, &height)) ||
      FAILED(frame->SetSize(width, height)) ||
      FAILED(frame->SetPixelFormat(&format)) ||
      FAILED(frame->WriteSource(converter.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return {};
  }

  HGLOBAL memory = nullptr;
  if (FAILED(GetHGlobalFromStream(stream.Get(), &memory))) {
    return {};
  }
  const auto size = GlobalSize(memory);
  const auto data = static_cast<uint8_t*>(GlobalLock(memory));
  if (!data || size == 0) {
    if (data) {
      GlobalUnlock(memory);
    }
    return {};
  }
  std::vector<uint8_t> bytes(data, data + size);
  GlobalUnlock(memory);
  return bytes;
}

std::vector<uint8_t> VideoThumbnail(const std::string& uri, bool remote) {
  if (uri.empty() || remote) {
    return {};
  }

  const HRESULT coinit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninit = SUCCEEDED(coinit);

  ComPtr<IShellItemImageFactory> factory;
  HBITMAP bitmap = nullptr;
  std::vector<uint8_t> bytes;
  const SIZE size = {480, 480};
  if (SUCCEEDED(SHCreateItemFromParsingName(Utf8ToWide(uri).c_str(), nullptr,
                                            IID_PPV_ARGS(&factory))) &&
      SUCCEEDED(factory->GetImage(
          size, SIIGBF_BIGGERSIZEOK | SIIGBF_THUMBNAILONLY, &bitmap))) {
    bytes = JpegBytesFromBitmap(bitmap);
  }
  if (bitmap) {
    DeleteObject(bitmap);
  }
  if (uninit) {
    CoUninitialize();
  }
  return bytes;
}

bool SetFullscreen(HWND window, bool enabled) {
  struct FullscreenState {
    bool enabled = false;
    LONG_PTR style = 0;
    WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
  };
  static FullscreenState state;

  if (!window) {
    return false;
  }

  if (state.enabled == enabled) {
    return state.enabled;
  }

  if (!enabled) {
    SetWindowLongPtr(window, GWL_STYLE, state.style);
    SetWindowPlacement(window, &state.placement);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    state.enabled = false;
    return false;
  }

  state.style = GetWindowLongPtr(window, GWL_STYLE);
  state.placement.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(window, &state.placement);
  MONITORINFO monitor_info = {sizeof(MONITORINFO)};
  if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                      &monitor_info)) {
    return false;
  }

  const RECT monitor = monitor_info.rcMonitor;
  SetWindowLongPtr(window, GWL_STYLE,
                   state.style & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW));
  SetWindowPos(window, HWND_TOP, monitor.left, monitor.top,
               monitor.right - monitor.left, monitor.bottom - monitor.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  state.enabled = true;
  return true;
}

void RegisterAppChannel(flutter::FlutterEngine* engine, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "rplayer/app",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setFullscreen") {
          bool enabled = false;
          if (const auto value = std::get_if<bool>(call.arguments())) {
            enabled = *value;
          }
          result->Success(flutter::EncodableValue(SetFullscreen(window, enabled)));
          return;
        }
        if (call.method_name() != "videoThumbnail") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Success();
          return;
        }
        std::string uri;
        bool remote = false;
        if (const auto value = args->find(flutter::EncodableValue("uri"));
            value != args->end()) {
          if (const auto text = std::get_if<std::string>(&value->second)) {
            uri = *text;
          }
        }
        if (const auto value = args->find(flutter::EncodableValue("remote"));
            value != args->end()) {
          if (const auto flag = std::get_if<bool>(&value->second)) {
            remote = *flag;
          }
        }
        auto bytes = VideoThumbnail(uri, remote);
        if (bytes.empty()) {
          result->Success();
        } else {
          result->Success(flutter::EncodableValue(bytes));
        }
      });
  static auto app_channel = std::move(channel);
}

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
  RegisterAppChannel(flutter_controller_->engine(), GetHandle());
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

void FlutterWindow::OnDestroy() {
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
