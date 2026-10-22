# Helper B: Binds the lossless real-time stream pipe hooks
private def activate_live_filter(accumulator : String -> Nil)
  @mutex.synchronize do
    @active_run_callback = ->(chunk : String) { accumulator.call(chunk) }
  end
end

private def deactivate_live_filter
  @mutex.synchronize do
    @active_run_callback = nil
  end
end
