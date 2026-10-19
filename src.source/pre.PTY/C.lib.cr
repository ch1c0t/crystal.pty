fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
fun login_tty(fd : Int32) : Int32
fun fork : Int32
fun _exit(status : Int32) : NoReturn
fun dup2(oldfd : Int32, newfd : Int32) : Int32

struct PollFD
  fd : Int32
  events : Int16
  revents : Int16
end

fun poll(fds : PollFD*, nfds : UInt64, timeout : Int32) : Int32

struct WinSize
  ws_row : UInt16
  ws_col : UInt16
  ws_xpixel : UInt16
  ws_ypixel : UInt16
end

fun kill(pid : Int32, signal : Int32) : Int32
fun close(fd : Int32) : Int32
