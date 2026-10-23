class TimeoutError < Exception
end

# Blocks cleanly using message passing; immune to split-buffer fragmentation
def wait_for(target : String, timeout : Time::Span = 2.seconds) : String
  start_time = Time.instant
  local_buffer = ""

  add_queue do |queue|
    loop do
      # 1. Enforce strict timeout thresholds
      if start_time.elapsed > timeout
        raise TimeoutError.new("Timed out waiting for '#{target}'")
      end

      # 2. Check for unexpected upstream pipe closures
      if !@reader_active.get && queue.size == 0
        break
      end

      # 3. Block-pop the next available text chunk out of the concurrent queue
      # This cleanly suspends the current fiber without locking execution threads
      chunk = queue.pop
      local_buffer += chunk

      # 4. Perform the boundary scan against the rolling localized context window
      if local_buffer.includes?(target)
        break
      end
    end
  end

  local_buffer
end
