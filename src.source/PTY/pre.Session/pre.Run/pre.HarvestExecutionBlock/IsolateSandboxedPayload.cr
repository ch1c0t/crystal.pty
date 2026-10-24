# Slices out only the text explicitly contained between the boundary walls
private def isolate_sandboxed_payload(transcript : String, start_sentinel : String, end_sentinel : String) : String?
  start_pos = transcript.rindex(start_sentinel)
  end_pos = transcript.rindex(end_sentinel)
  
  debug_log("isolate_sandboxed_payload :: Boundary Slice Mapping", {
    start_pos: start_pos,
    end_pos: end_pos
  })

  if start_pos && end_pos && end_pos > start_pos
    return transcript[start_pos + start_sentinel.bytesize...end_pos]
  end
  nil
end
