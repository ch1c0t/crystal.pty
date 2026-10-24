# Checks if the full execution transcript sandwich has successfully concluded
private def command_sandwich_complete?(buffer : String, start_sentinel : String, end_sentinel : String) : Bool
  # Prefer the marker printed by the shell over the one echoed as input.
  start_idx = buffer.rindex(start_sentinel)
  end_idx = buffer.rindex(end_sentinel)

  debug_log("command_sandwich_complete? :: Sandwich Index Scan", {
    start_sentinel_index: start_idx,
    end_sentinel_index: end_idx,
    valid_chronological_order: (start_idx && end_idx ? end_idx > start_idx : false)
  })

  return false unless start_idx && end_idx && end_idx > start_idx

  suffix = buffer[end_idx + end_sentinel.bytesize..-1]
  debug_log("command_sandwich_complete? :: Trailer Sliced Suffix", {
    extracted_suffix: suffix,
    starts_with_double_underscore: suffix.starts_with?("__")
  })

  evaluation_result = extract_status_suffix(suffix)
  debug_log("command_sandwich_complete? :: Completeness Evaluation", {
    is_command_completely_finished: evaluation_result
  })

  evaluation_result
end

# Validates the "__STATUS__" wrapping envelope format without using regex
private def extract_status_suffix(suffix : String) : Bool
  return false unless suffix.starts_with?("__")

  if closing_underscore_idx = suffix.index("__", 2)
    status_digits = suffix[2...closing_underscore_idx]

    debug_log("extract_status_suffix :: Exit Token Isolated", {
      isolated_digits: status_digits,
      is_strictly_numeric: valid_status_digits?(status_digits)
    })

    return valid_status_digits?(status_digits)
  end

  false
end

# Ensures the token consists strictly of evaluated digits, ignoring the literal "__$?__" echo
private def valid_status_digits?(digits : String) : Bool
  !digits.empty? && digits.chars.all?(&.ascii_number?)
end
