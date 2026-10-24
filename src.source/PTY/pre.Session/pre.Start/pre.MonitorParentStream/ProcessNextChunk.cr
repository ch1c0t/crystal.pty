private def process_next_chunk(chunk : String)
  # 1. Update the inherently thread-safe atomic pointer log
  update_history_snapshot(chunk)

  # Broadcast a copy of the chunk to every active listener queue safely
  @subscribers_mutex.synchronize do
    p "in #process_next_chunk"
    # Replace raw distribution inspection with:
    debug_log("Distribution Engine Fan-Out", {
      active_subscribers: @subscribers.size,
      fanning_chunk: chunk
    })

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
