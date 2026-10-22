# Helper C: Hooks up tracking wrappers and boots background readers
private def initialize_parent_proxy(pid : Int32, slave_fd : Int32, master_fd : Int32)
  PTY::C.close(slave_fd) rescue nil
  @process = Process.new(Crystal::System::Process.new(pid))
  @started.set(true)
  monitor_parent_stream(master_fd)
end

include MonitorParentStream
