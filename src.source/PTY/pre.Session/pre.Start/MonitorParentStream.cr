private def monitor_parent_stream(master_fd : Int32)
  setup_io_handles(master_fd)
  spawn_ingestion_loop
  spawn_distribution_loop
end

private def setup_io_handles(master_fd : Int32)
  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  IO::FileDescriptor.set_blocking(master_fd, false)
  @master_io = master_io
  @reader_active.set(true)
end

private def spawn_ingestion_loop
  spawn do
    io_buffer = Bytes.new(65536)
    master_io = @master_io.not_nil!

    loop do
      break if master_io.closed?
      begin
        bytes_read = master_io.read(io_buffer)
        break if bytes_read == 0

        # Move the data instantly into our thread-safe queue
        chunk = String.new(io_buffer[0, bytes_read])
        p "in #spawn_ingestion_loop"
        p!({ingestion_chunk: chunk, bytes: bytes_read})
        @ingest_queue.push(chunk)
      rescue ex : IO::Error
        # Handle non-blocking retry signs gracefully
        next if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
        break
      end
    end
    @reader_active.set(false)
    @ingest_queue.close # ◄─ Signal completion to the consumer layer
  end
end

private def spawn_distribution_loop
  spawn do
    loop do
      begin
        # pop is guaranteed to return a strict String here, fixing the type error
        chunk = @ingest_queue.pop
        process_next_chunk(chunk)
      rescue ex : PTY::Queue::ClosedError
        break # Ingestion loop closed and queue is fully drained!
      ensure
        @subscribers_mutex.synchronize do
          @subscribers.each &.push(:session_closed)
        end
      end
    end
  end
end

private def process_next_chunk(chunk : String)
  # 1. Update the inherently thread-safe atomic pointer log
  update_history_snapshot(chunk)

  # Broadcast a copy of the chunk to every active listener queue safely
  @subscribers_mutex.synchronize do
    p "in #process_next_chunk"
    p!({distributing_chunk: chunk, current_subscribers: @subscribers.size})
    @subscribers.each &.push(chunk)
  end
end

private def update_history_snapshot(chunk : String)
  loop do
    old_ptr = @output_ptr.get
    current_string = Box(String).unbox(old_ptr)

    # Combine into a new immutable string allocation
    new_string = current_string + chunk
    new_ptr = Box(String).box(new_string)

    # Perform the lockless atomic swap
    if @output_ptr.compare_and_set(old_ptr, new_ptr)
      break
    end
  end
end
