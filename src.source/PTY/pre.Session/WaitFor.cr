class TimeoutError < Exception
end

# Blocks cleanly using message passing; immune to split-buffer fragmentation
def wait_for(target : String, timeout : Time::Span = 2.seconds) : String
  start_time = Time.instant
  local_buffer = ""

  add_queue do |queue|
    debug_log("wait_for :: Engine Initialized", {
      tracking_target: target,
      timeout_threshold: timeout,
      queue_object_id: queue.object_id
    })

    loop do
      # 1. Enforce strict timeout thresholds
      if start_time.elapsed > timeout
        raise TimeoutError.new("Timed out waiting for '#{target}'")
      end

      debug_log("wait_for :: Iteration Guard Pass", {
        elapsed_seconds: start_time.elapsed.to_f,
        reader_active_state: @reader_active.get,
        backlogged_queue_elements: queue.size
      })

      # 2. Check for unexpected upstream pipe closures
      if !@reader_active.get && queue.size == 0
        break
      end

      # 3. Block-pop the next available text chunk out of the concurrent queue
      # This cleanly suspends the current fiber without locking execution threads
      message = queue.pop
      case message
      in String
        local_buffer += message

        debug_log("wait_for :: Received Data", {
          arrived_chunk: message,
          updated_local_buffer: local_buffer,
          match_detected: local_buffer.includes?(target)
        })
        # 4. Perform the boundary scan against the rolling localized context window
        if local_buffer.includes?(target)
          break
        end
      in Symbol
        debug_log("wait_for :: Control Signal", {
          control_token: message,
          remaining_elements_to_drain: queue.size
        })

        case message
        when :session_closed && queue.size == 0
          break
        end
      end
    end
  end

  local_buffer
end
