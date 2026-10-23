def initialize
  @deque = Deque(T).new
  @mutex = Sync::Mutex.new
  @cond = Sync::ConditionVariable.new(@mutex)
end

# Ruby's Queue#push (never blocks, wakes up waiting pops)
def push(item : T)
  @mutex.synchronize do
    @deque.push(item)
    @cond.signal # Wake up one fiber waiting in #pop
  end
end

# Ruby's Queue#pop (blocks the fiber until an item is pushed)
def pop : T
  @mutex.synchronize do
    while @deque.empty?
      # https://crystal-lang.org/api/master/Sync/ConditionVariable.html
      @cond.wait # Temporarily releases mutex and suspends fiber
    end
    @deque.shift # FIFO extraction
  end
end

def size : Int32
  @mutex.synchronize { @deque.size }
end
