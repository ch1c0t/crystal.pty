fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
fun login_tty(fd : Int32) : Int32
fun fork : Int32
fun _exit(status : Int32) : NoReturn
fun close(fd : Int32) : Int32
fun ioctl(fd : LibC::Int, request : LibC::ULong, argp : Void*) : LibC::Int
fun kill(pid : Int32, sig : Int32) : Int32
fun execve(path : UInt8*, argv : UInt8**, envp : UInt8**) : Int32
