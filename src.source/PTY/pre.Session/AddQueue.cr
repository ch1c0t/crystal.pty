# Registers a private queue, yields it to the caller, and guarantees cleanup
private def add_queue(&block : PTY::Queue(String) -> Nil) : Int32
  my_queue = PTY::Queue(String).new
  snapshot_size = 0

  @subscribers_mutex.synchronize do
    @subscribers.add(my_queue)
    snapshot_size = output.bytesize # <- Safely captured inside the exact same lock!
  end

  begin
    yield my_queue
  ensure
    @subscribers_mutex.synchronize { @subscribers.delete(my_queue) }
  end

  snapshot_size
end
