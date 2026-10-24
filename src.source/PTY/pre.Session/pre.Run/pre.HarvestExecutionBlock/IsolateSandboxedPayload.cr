# Slices out only the text explicitly contained between the boundary walls
private def isolate_sandboxed_payload(transcript : String, start_sentinel : String, end_sentinel : String) : String?
  start_pos = transcript.index(start_sentinel)
  end_pos = transcript.rindex(end_sentinel)
  
  debug_log("Harvester Boundary Slice Mapping", {
    start_pos: start_pos,
    end_pos: end_pos
  })

  if start_pos && end_pos && end_pos > start_pos
    return transcript[start_pos + start_sentinel.bytesize...end_pos]
  end
  nil
end

# private def isolate_sandboxed_payload(transcript : String, start_sentinel : String, end_sentinel : String) : String?
#   # FIX: Switch from .index to .rindex for the start sentinel!
#   # This skips past the raw shell input echo row entirely and finds where the actual output starts.
#   start_pos = transcript.rindex(start_sentinel)
#   end_pos = transcript.rindex(end_sentinel)
#
#   debug_log("Harvester Boundary Slice Mapping", {
#     start_pos: start_pos,
#     end_pos: end_pos
#   })
#
#   if start_pos && end_pos && end_pos > start_pos
#     # Slice the text starting after the end of the second (output) start sentinel
#     return transcript[start_pos + start_sentinel.bytesize...end_pos]
#   end
#   nil
# end
