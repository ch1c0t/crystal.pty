private def wait_for_child(pid : Int32) : Int32
  loop do
    status = 0
    waited_pid = C.waitpid(pid, pointerof(status), 1) # WNOHANG

    if waited_pid == pid
      signal = status & 0x7f
      next if signal == 0x7f
      return (status >> 8) & 0xff if signal == 0
      return 128 + signal
    elsif waited_pid == 0
      sleep(10.milliseconds)
    else
      raise "waitpid failed for PTY child #{pid}"
    end
  end
end

# A command can exit while background descendants retain the slave terminal.
# Signal the dedicated process group, then force it down after a short grace.
private def terminate_child_group(pid : Int32) : Nil
  if C.kill(-pid, 1) == 0 # SIGHUP
    sleep(50.milliseconds)
    C.kill(-pid, 9) # SIGKILL
  end
end
