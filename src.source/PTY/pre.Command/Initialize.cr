def initialize(@raw_string : String)
  @session = Session.new
end

def initialize(@raw_string : String, @session : Session)
end
