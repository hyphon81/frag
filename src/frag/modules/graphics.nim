import
  colors,
  events,
  strfmt

import
  bgfxdotnim as bgfx,
  bgfxdotnim/platform,
  sdl2 as sdl

import
  ../events/sdl_event,
  ../graphics/color,
  ../graphics/sdl2/version,
  ../graphics/types,
  ../graphics/window,
  ../logger,
  module,
  ../util

export
  color,
  types,
  window

when defined(windows) and not defined(android):
  type
    SysWMMsgWinObj* = object  ##  when defined(SDL_VIDEO_DRIVER_WINDOWS)
      hwnd*: pointer

    SysWMinfoKindObj* = object ##  when defined(SDL_VIDEO_DRIVER_WINDOWS)
      win*: SysWMMsgWinObj

when defined(macosx) and not defined(android):
  type
    SysWMinfoCocoaObj = object
      window: pointer

    SysWMinfoKindObj = object
      cocoa: SysWMinfoCocoaObj

when defined(linux) and not defined(android):
  import x, xlib
  type
    SysWMmsgX11Obj* = object
      display*: ptr xlib.TXDisplay
      window*: ptr x.TWindow
    SysWMinfoKindObj* = object
      x11*: SysWMMsgX11Obj

when defined(android):
  import
    android.ndk.anative_window

  type
    SysWMinfoAndroidObj* = object
      window*: ANativeWindow
      surface*: pointer

    SysWMinfoKindObj* = object
      android*: SysWMinfoAndroidObj

proc linkSDL2BGFX(window: sdl.WindowPtr): bool =
    var pd: ptr bgfx_platform_data_t = workaround_createShared[bgfx_platform_data_t]()
    var info: sdl.WMinfo
    version(info.version)

    when defined(android):
      pd.nwh = getNativeAndroidWindow()
    else:
      discard sdl.getWMInfo(window, info)
      
      case(info.subsystem):
          of SysWM_Windows:
            when defined(windows) and not defined(android):
              let info = cast[ptr SysWMinfoKindObj](addr info.padding[0])
              pd.nwh = info.win.hwnd
            pd.ndt = nil
          of SysWM_X11:
            when defined(linux) and not defined(android):
              let info = cast[ptr SysWMinfoKindObj](addr info.padding[0])
              pd.nwh = info.x11.window
              pd.ndt = info.x11.display
          of SysWM_Cocoa:
            when defined(macosx) and not defined(android):
              let info = cast[ptr SysWMinfoKindObj](addr info.padding[0])
              pd.nwh = info.cocoa.window
            pd.ndt = nil
          #of SysWM_Android:
            #when defined(android):
              #let info = cast[ptr SysWMinfoKindObj](addr info.padding[0])
              #pd.nwh = info.android.window
              #pd.nwh = getNativeAndroidWindow()
            #pd.ndt = nil
          else:
            logError "Error linking SDL2 and BGFX."
            return false

    pd.backBuffer = nil
    pd.backBufferDS = nil
    pd.context = nil
    bgfx_set_platform_data(pd)
    freeShared(pd)
    return true

proc init*(
  this: Graphics,
  rootWindowTitle: string,
  rootWindowPosX = window.posUndefined, rootWindowPosY = window.posUndefined,
  rootWindowWidth = 960, rootWindowHeight = 540,
  resetFlags: ResetFlag = ResetFlag.None,
  debugMode: uint32 = BGFX_DEBUG_NONE
): bool =
  if sdl.init(INIT_VIDEO) != SdlSuccess:
    logError "Error initializing SDL : " & $getError()
    return false

  this.rootWindow = Window()

  when defined(android):
    this.rootWindow.init(
      rootWindowTitle,
      rootWindowPosX, rootWindowPosY,
      rootWindowWidth, rootWindowHeight,
      window.WindowFlag.WindowShown.ord or window.WindowFlag.WindowFullscreen.ord
    )

  else:
    this.rootWindow.init(
      rootWindowTitle,
      rootWindowPosX, rootWindowPosY,
      rootWindowWidth, rootWindowHeight,
      window.WindowFlag.WindowShown.ord or window.WindowFlag.WindowResizable.ord
    )

  if this.rootWindow.handle.isNil:
    logError "Error creating root application window."
    return false

  if not linkSDL2BGFX(this.rootWindow.handle):
    return false

  var init: bgfx_init_t
  bgfx_init_ctor(addr(init))
  if not bgfx_init(addr(init)):
    logError("Error initializng BGFX.")

  let size = sdl.getSize(this.rootWindow.handle)
  bgfx_reset(size.x.uint32, size.y.uint32, BGFX_RESET_VSYNC, init.resolution.format)
  bgfx_set_view_rect(0, 0, 0, size.x.uint16, size.y.uint16)

  bgfx_set_debug(debugMode)

  return true
  

proc clearView*(self: Graphics, viewId: uint8, flags: uint16, rgba: colors.Color, depth: float32, stencil: uint8) =
  bgfx_set_view_clear(viewID, flags, rgba.uint32, depth, stencil)

proc drawDebugImage*(this: Graphics, image: var openarray[uint8], x, y, width, height, pitch: uint16) =
  bgfx_dbg_text_image(
    x, 
    y,
    width,
    height,
    image.addr,
    pitch
  )

proc startFrame*(this: Graphics) =
  bgfx_dbg_text_clear(0, false)

proc render*(this: Graphics) =
  var lastTime {.global.} : uint64
  let current = sdl.getPerformanceCounter()
  let frameTime = float((current - lastTime) * 1000) / float sdl.getPerformanceFrequency()
  lastTime = current

  #discard bgfx_touch(0)

  bgfx_dbg_text_printf(1, 1, 0x0f, "Frame: %7.3f[ms] FPS: %7.3f", float32(frameTime), (1.0 / frameTime) * 1000)

  discard bgfx_frame(false)

proc onWindowResize*(this: Graphics, event: sdl.Event) {.procvar.} =
  let
    width = uint16 event.window.data1
    height = uint16 event.window.data2

  when defined(android):
    discard linkSDL2BGFX(this.rootWindow.handle)

  var init: bgfx_init_t
  bgfx_init_ctor(addr(init))
  if not bgfx_init(addr(init)):
    logError("Error initializng BGFX.")

  bgfx_reset(width, height, BGFX_RESET_VSYNC, init.resolution.format)

proc onUnpause*(this: Graphics, event: sdl.Event) {.procvar.} =
  when defined(android):
    discard linkSDL2BGFX(this.rootWindow.handle)
    let size = getSize(this.rootWindow.handle)
    bgfx_reset(size.x.uint32, size.y.uint32, BGFX_RESET_VSYNC)

proc getSize*(this: Graphics): tuple =
  sdl.getSize(this.rootWindow.handle)

proc setViewRect*(this: Graphics, viewId: uint8, x, y, width, height: uint16) =
  bgfx_set_view_rect(viewId, x, y, width, height)

proc shutdown*(this: Graphics) =
  if this.rootWindow.isNil:
    return
  elif this.rootWindow.handle.isNil:
    logDebug "Shutting down SDL..."
    sdl.quit()
    logDebug "SDL shut down."
  else:
    logDebug "Shutting down BGFX..."
    bgfx_shutdown()
    logDebug "BGFX shut down."

    logDebug "Destroying root window and shutting down SDL..."
    sdl.destroyWindow(this.rootWindow.handle)
    sdl.quit()
    logDebug "SDL shut down."
