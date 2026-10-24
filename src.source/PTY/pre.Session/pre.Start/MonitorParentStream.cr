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

include SpawnIngestionLoop
include SpawnDistributionLoop
include ProcessNextChunk
