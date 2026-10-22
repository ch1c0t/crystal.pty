# Helper A: Generates the boundary walls
private def generate_sentinels : Tuple(String, String)
  timestamp = Time.utc.to_unix_f.to_s.gsub(".", "")
  rand_id = Random.rand(100..999)

  start_sentinel = "START_MARK_#{timestamp}_#{rand_id}"
  end_sentinel   = "END_MARK_#{timestamp}_#{rand_id}"
  {start_sentinel, end_sentinel}
end
