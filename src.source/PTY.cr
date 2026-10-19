@[Link("util")]
lib C
  struct WinSize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end

  fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : WinSize*) : Int32
  fun kill(pid : Int32, signal : Int32) : Int32
  fun close(fd : Int32) : Int32
end

extend Run
