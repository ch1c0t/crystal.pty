# Core helper class to bridge heap allocations across raw pointers
def initialize(@value : T)
end

def value : T
  @value
end

def self.box(value : T) : Pointer(Void)
  new(value).as(Pointer(Void))
end

def self.unbox(pointer : Pointer(Void)) : T
  pointer.as(Box(T)).value
end
