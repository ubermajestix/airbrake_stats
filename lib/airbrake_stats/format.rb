class AirbrakeStats::Format
  class << AirbrakeStats::Format
    attr_reader :stats
    def print(stats, method)
      @stats = stats
      method_width = width(method)
      total_width = width('total')
      puts
      puts "#{method.to_s.center(method_width)} | total"
      puts "#{''.ljust(method_width + 8, '-')}"
      stats.each do |stat|
        puts "#{stat[method].to_s.ljust(method_width)} | #{stat.total.to_s.rjust(total_width)}"
      end
    end

    def width(method)
      stats.inject(0){|r,s| r = s[method].to_s.length if s[method].to_s.length > r; r} 
    end
  end
end
