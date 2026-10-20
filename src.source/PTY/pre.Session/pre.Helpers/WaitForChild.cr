private def terminate_child_group(pid : Int32) : Nil
  groups = [pid] of Int32
  if fd = @master_fd
    foreground_group = C.tcgetpgrp(fd)
    groups << foreground_group if foreground_group > 0 && foreground_group != pid
  end

  groups.each { |group| C.kill(-group, 1) }
  sleep(50.milliseconds)
  groups.each { |group| C.kill(-group, 9) }
  C.kill(pid, 9)
end
