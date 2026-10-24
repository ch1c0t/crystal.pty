# Helper C: Hooks up tracking wrappers and boots background readers
private def initialize_parent_proxy(pid : Int32, slave_fd : Int32, master_fd : Int32)
  PTY::C.close(slave_fd) rescue nil
  @process = Process.new(Crystal::System::Process.new(pid))
  @started.set(true)

  if child_pid = @process.try(&.pid)
    debug_log("POSIX Fork Handshake Successful", {
      allocated_child_pid: child_pid,
      master_fd: @master_io.try(&.fd)
    })
  else
    debug_log("POSIX Fork Allocation Error - Process Refused to Boot", "")
  end

  monitor_parent_stream(master_fd)

  debug_log("Background Concurrency Workers Spawned", {
    reader_active_flag: @reader_active.get,
    ingest_queue_object_id: @ingest_queue.object_id
  })
end

include MonitorParentStream
