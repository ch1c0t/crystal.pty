private def read_status_file(status_path : String) : Int32?
  return unless File.exists?(status_path)

  contents = File.read(status_path).strip
  return if contents.empty?

  File.delete(status_path)
  contents.to_i?
end

private def terminate_child_group(pid : Int32) : Nil
  if C.kill(-pid, 1) == 0
    sleep(50.milliseconds)
    C.kill(-pid, 9)
  elsif C.kill(pid, 1) == 0
    sleep(50.milliseconds)
    C.kill(pid, 9)
  end
end
