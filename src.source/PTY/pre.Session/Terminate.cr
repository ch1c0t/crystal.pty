def terminate : Nil
  @reader_active.set(false)

  proc = @process
  process_group_id = proc.try(&.pid)

  # The PTY child starts a new session with its PID as its process-group ID.
  # Signal the whole group before closing the master descriptor, so cleanup
  # does not depend on the shell remaining alive.
  if pgid = process_group_id
    PTY::C.kill(-pgid, Signal::TERM.value)
  end

  # Close the master descriptor to unblock the reader loop.
  if io = @master_io
    begin
      io.close unless io.closed?
    rescue
    ensure
      @master_io = nil
    end
  end

  # Do not use proc.terminated? as the group-liveness check: the shell can
  # exit while a descendant in the same process group continues running.
  if pgid = process_group_id
    term_started_at = Time.instant
    while PTY::C.kill(-pgid, 0) == 0 && term_started_at.elapsed < 100.milliseconds
      sleep(5.milliseconds)
    end

    # Escalate against the group even when its original leader has exited.
    if PTY::C.kill(-pgid, 0) == 0
      PTY::C.kill(-pgid, Signal::KILL.value)
    end
  end

  Fiber.yield

  if proc
    proc.wait rescue nil
  end

  @process = nil
end
