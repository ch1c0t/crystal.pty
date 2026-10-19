# Poll waitpid without blocking the Crystal scheduler that drains PTY output.
private def wait_for_child(pid : Int32) : Int32
  loop do
    status = 0
    waited_pid = PTYLibC.waitpid(pid, pointerof(status), 1)

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

# Once the command leader exits, stop descendants which inherited the slave.
# A short grace period lets ordinary SIGHUP handlers clean up before SIGKILL.
private def terminate_child_group(pid : Int32) : Nil
  if PTYLibC.kill(-pid, 1) == 0
    sleep(50.milliseconds)
    PTYLibC.kill(-pid, 9)
  end
end
