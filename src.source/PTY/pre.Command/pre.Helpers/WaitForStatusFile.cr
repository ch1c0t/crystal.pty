# Helper 4: Blocks until the status sync file has completed writing
private def wait_for_status_file : Int32
  while !File.exists?(@status_path)
    sleep(50.milliseconds)
  end

  exit_code = File.read(@status_path).strip.to_i
  File.delete(@status_path) if File.exists?(@status_path)
  exit_code
end
