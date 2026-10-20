fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
fun login_tty(fd : Int32) : Int32
fun fork : Int32
fun _exit(status : Int32) : NoReturn
fun kill(pid : Int32, signal : Int32) : Int32
fun close(fd : Int32) : Int32
fun ioctl(fd : Int32, request : UInt64, argp : Void*) : Int32
fun tcgetpgrp(fd : Int32) : Int32
