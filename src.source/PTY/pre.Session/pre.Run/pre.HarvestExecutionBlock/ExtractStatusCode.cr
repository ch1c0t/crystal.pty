# Extracts the evaluated integer return status from the tail of the transcript.
# Missing or malformed status markers are protocol failures, not successful exit code 0.
private def extract_status_code(transcript : String, end_sentinel : String) : Int32
  if end_idx = transcript.rindex(end_sentinel)
    suffix = transcript[end_idx + end_sentinel.bytesize..-1]
    if suffix.starts_with?("__") && (closing_idx = suffix.index("__", 2))
      status_digits = suffix[2...closing_idx]

      debug_log("extract_status_code :: Status Digits Extracted", {
        status_digits: status_digits,
        is_numeric: !status_digits.empty? && status_digits.chars.all?(&.ascii_number?)
      })

      if !status_digits.empty? && status_digits.chars.all?(&.ascii_number?)
        return status_digits.to_i
      end
    end
  end

  raise "Could not extract command exit status from PTY transcript (sentinel #{end_sentinel})"
end
