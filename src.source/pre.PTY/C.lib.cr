fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
fun login_tty(fd : Int32) : Int32
fun fork : Int32
fun _exit(status : Int32) : NoReturn
fun close(fd : Int32) : Int32
# Use the same variadic POSIX signature as LibC.ioctl so dependencies can
# declare this C symbol together in one Crystal program.
fun ioctl(fd : Int, request : ULong, ...) : Int
fun kill(pid : Int32, sig : Int32) : Int32
fun execve(path : UInt8*, argv : UInt8**, envp : UInt8**) : Int32
