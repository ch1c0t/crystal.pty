# A command can exit while background descendants retain the slave terminal.
# Signal the dedicated process group, then force it down after a short grace.
private def terminate_child_group(pid : Int32) : Nil
  if C.kill(-pid, 1) == 0 # SIGHUP
    sleep(50.milliseconds)
    C.kill(-pid, 9) # SIGKILL
  end
end
