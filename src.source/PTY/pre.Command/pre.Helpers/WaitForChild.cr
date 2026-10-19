# Read a completed status file. The temporary file is renamed atomically by
# the child, so the parent never observes a partially written exit status.
private def read_status_file(status_path : String) : Int32?
  return unless File.exists?(status_path)

  contents = File.read(status_path).strip
  return if contents.empty?

  File.delete(status_path)
  contents.to_i?
end

# A command can exit while background descendants retain the slave terminal.
# Signal the dedicated process group, then force it down after a short grace.
private def terminate_child_group(pid : Int32) : Nil
  if C.kill(-pid, 1) == 0 # SIGHUP
    sleep(50.milliseconds)
    C.kill(-pid, 9) # SIGKILL
  end
end
