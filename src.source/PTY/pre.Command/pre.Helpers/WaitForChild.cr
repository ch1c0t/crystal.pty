private def terminate_child_group(pid : Int32) : Nil
  if C.kill(-pid, 1) == 0
    sleep(50.milliseconds)
    C.kill(-pid, 9)
  end
end
