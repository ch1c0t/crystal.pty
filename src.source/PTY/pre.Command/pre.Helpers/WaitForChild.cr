# Called after the main process exits. Descendants can inherit the slave PTY and
# keep the master readable forever, so stop the command's remaining process group.
private def terminate_child_group(pid : Int32) : Nil
  if C.kill(-pid, 1) == 0 # SIGHUP
    sleep(50.milliseconds)
    C.kill(-pid, 9) # SIGKILL
  end
end
