private def spawn_distribution_loop
  spawn do
    begin
      loop do
        message = @ingest_queue.pop
        case message
        in String
          process_next_chunk(message)
        in Symbol
          if message == :stream_idle
            # FAN-OUT EMIT: Broadcast the idle signal to all user listeners 
            # so they know they can safely inspect their rolling caches.
            @subscribers_mutex.synchronize do
              @subscribers.each &.push(:stream_idle)
            end
          end
        end
      end
    rescue ex : PTY::Queue::ClosedError
      # CRITICAL: Only broadcast :session_closed when the ingestion fiber 
      # explicitly closes the queue upon actual shell process termination!
      @subscribers_mutex.synchronize do
        @subscribers.each &.push(:session_closed)
      end
    ensure
      @subscribers_mutex.synchronize do
        @subscribers.clear
      end
    end
  end
end
