class AirbrakeStats::Queue < Queue
  def to_a
    array = []
    self.size.times{array << self.pop}
    array
  end
end
